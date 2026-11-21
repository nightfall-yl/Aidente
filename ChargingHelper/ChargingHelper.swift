import Foundation
import AidenteShared
import os.log
import smc_power
import IOKit
import IOKit.pwr_mgt
import Darwin
import SMCKit
import Security
import CryptoKit

private enum Constants {
    static let subsystem = "com.aidente.app.control"
    // IOMessage.h: iokit_common_msg values. The SDK's C function-like macros
    // are not imported by Swift.
    static let canSleep: UInt32 = 0xe0000270
    static let willSleep: UInt32 = 0xe0000280
    static let willNotSleep: UInt32 = 0xe0000290
    static let didWake: UInt32 = 0xe0000300
}

final class ChargingHelper: NSObject, AidenteControlProtocol {
    private var battery: SMCBattery
    private let adapter: SMCAdapter
    private let logger = Logger(
        subsystem: Constants.subsystem,
        category: "ChargingHelper"
    )
    private(set) var resetOnDisconnect = true
    private let queue = DispatchQueue(label: "com.aidente.app.control.power")
    private var policy: ChargingPowerPolicy?
    private var firmwarePolicy = FirmwarePowerPolicy()
    private var hasControlledPower = false
    private var sleeping = false
    private var clients = 0
    private var lastClientPID: pid_t?
    private var disconnectGeneration = 0
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var powerConnection: io_connect_t = 0
    private var watchdog: DispatchSourceTimer?
    private let controlDefaults = UserDefaults(suiteName: "com.aidente.app.control") ?? .standard
    private let firmwareSnapshotKey = "firmwareLimitBeforeAidente"

    init(battery: SMCBattery, adapter: SMCAdapter) {
        self.battery = battery
        self.adapter = adapter
        super.init()
        logger.info(
            "Initialized (charging=\(battery.capabilities.inhibitChargeControl), discharge=\(battery.capabilities.forceDischargeControl), magSafe=\(adapter.capabilities.magSafeControl))"
        )
        logger.notice("CONTROL_KEYS charging=\(battery.chargingControlKey, privacy: .public) discharge=\(battery.dischargeControlKey, privacy: .public)")
        startPowerMonitoring()
    }

    private func startPowerMonitoring() {
        powerConnection = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(), &notificationPort,
            { context, _, message, argument in
                guard let context else { return }
                let helper = Unmanaged<ChargingHelper>.fromOpaque(context).takeUnretainedValue()
                helper.powerEvent(message, argument: argument)
            }, &notifier
        )
        if powerConnection != 0, let notificationPort {
            IONotificationPortSetDispatchQueue(notificationPort, queue)
        } else {
            logger.error("POWER_MONITOR_REGISTRATION_FAILED")
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15, leeway: .seconds(3))
        timer.setEventHandler { [weak self] in self?.reconcile(reason: "watchdog") }
        timer.resume()
        watchdog = timer
    }

    // Runs on the same serial queue as every SMC write. Acknowledge sleep only
    // after the write and readback, not after enqueueing an asynchronous XPC call.
    private func powerEvent(_ message: UInt32, argument: UnsafeMutableRawPointer?) {
        switch message {
        case Constants.canSleep:
            IOAllowPowerChange(powerConnection, Int(bitPattern: argument))
        case Constants.willSleep:
            sleeping = true
            policy?.sleeping = true
            reconcile(reason: "willSleep")
            IOAllowPowerChange(powerConnection, Int(bitPattern: argument))
        case Constants.didWake, Constants.willNotSleep:
            sleeping = false
            // Keep the sleep hold until the app submits a fresh policy. A dark
            // wake must not resume charging from a stale pre-sleep percentage.
            do { battery = try SMCBattery.probe() }
            catch { logger.error("Wake capability probe failed: \(error.localizedDescription, privacy: .public)") }
            reconcile(reason: "didWake")
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.reconcile(reason: "wakeRecheck")
            }
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.resetAfterDisconnectIfNeeded()
            }
        default: break
        }
    }

    func clientConnected(pid: pid_t) {
        queue.sync {
            clients += 1
            disconnectGeneration += 1
            lastClientPID = pid
        }
    }

    func clientDisconnected() {
        queue.async {
            self.clients = max(0, self.clients - 1)
            self.disconnectGeneration += 1
            let generation = self.disconnectGeneration
            self.queue.asyncAfter(deadline: .now() + 5) {
                guard self.clients == 0, generation == self.disconnectGeneration else { return }
                // A transient XPC interruption at sleep must not undo the hold.
                self.resetAfterDisconnectIfNeeded()
            }
        }
    }

    private func resetAfterDisconnectIfNeeded() {
        guard clients == 0, resetOnDisconnect, !sleeping, hasControlledPower else { return }
        if let pid = lastClientPID, kill(pid, 0) == 0 || errno == EPERM {
            return // The GUI is alive but suspended or reconnecting.
        }
        resetOnQueue()
    }

    func applyPowerPolicy(charging: Bool, adapter: Bool, managed: Bool,
                          stopWhileSleeping: Bool, resetOnDisconnect: Bool,
                          chargeCeiling: Int, rechargeBelow: Int,
                          reply: @escaping @Sendable (Bool, String?) -> Void) {
        queue.async {
            guard (1...100).contains(chargeCeiling), rechargeBelow >= 0,
                  rechargeBelow < chargeCeiling else {
                reply(false, "Invalid firmware charge interval")
                return
            }
            var request = ChargingPowerPolicy()
            request.charging = charging
            request.adapter = adapter
            request.managed = managed
            request.stopWhileSleeping = stopWhileSleeping
            request.sleeping = self.sleeping
            request.chargeCeiling = chargeCeiling
            request.rechargeBelow = rechargeBelow
            self.policy = request
            self.hasControlledPower = true
            self.resetOnDisconnect = resetOnDisconnect
            do {
                if managed && stopWhileSleeping && self.powerConnection == 0 {
                    throw NSError(domain: "AidenteControl", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "无法注册系统睡眠通知，请重启 Aidente 重新授权后台控制服务"
                    ])
                }
                try self.applyEffectivePolicy()
                reply(true, nil)
            } catch {
                self.logger.error("POWER_POLICY_FAILED \(error.localizedDescription, privacy: .public)")
                if case SMCError.notPrivileged = error {
                    reply(false, "FIRMWARE_ACCESS_DENIED: system firmware denied charge-control access")
                } else {
                    reply(false, error.localizedDescription)
                }
            }
        }
    }

    private func applyEffectivePolicy() throws {
        guard let policy else { return }
        let target = policy.effective
        if battery.usesFirmwareChargeLimit {
            let controller = FirmwareChargeLimitController(registers: SMCFirmwareLimitRegisters())
            if target.adapter, battery.capabilities.forceDischargeControl,
               try battery.getForceDischarging() {
                try battery.setForceDischarging(false)
            }
            if policy.managed {
                // A root-owned preference survives daemon upgrades and crashes;
                // turning management off must restore the user's original limit.
                if controlDefaults.data(forKey: firmwareSnapshotKey) == nil {
                    let snapshot = try JSONEncoder().encode(controller.read())
                    controlDefaults.set(snapshot, forKey: firmwareSnapshotKey)
                    guard controlDefaults.synchronize() else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
                let percentage = try SMCBattery.firmwarePercentageExact()
                let externalConnected = try SMCBattery.externalPowerConnected()
                let previous = try controller.read()
                switch firmwarePolicy.target(policy: policy, percentage: percentage,
                                             externalConnected: externalConnected) {
                case .unlimited:
                    var unlimited = previous
                    unlimited.activation = 0
                    try controller.replace(with: unlimited)
                case .interval(let lower, let upper):
                    try controller.set(lower: lower, upper: upper)
                }
                let applied = try controller.read()
                if applied != previous {
                    let rawPercentage = String(format: "%.4f", percentage)
                    logger.notice("FIRMWARE_INTERVAL_APPLIED raw=\(rawPercentage, privacy: .public) lower=\(applied.lower) upper=\(applied.upper) activation=\(applied.activation) sleeping=\(policy.sleeping) chargingRequested=\(target.charging) externalConnected=\(externalConnected)")
                }
            } else {
                try restoreFirmwareLimit()
            }
            if battery.capabilities.forceDischargeControl {
                if try battery.getForceDischarging() == target.adapter {
                    try battery.setForceDischarging(!target.adapter)
                }
                guard try battery.getForceDischarging() == !target.adapter else {
                    throw SMCBatteryError.stateVerificationFailed
                }
            } else if !target.adapter {
                throw SMCBatteryError.unsupportedCapability
            }
        } else {
            try battery.applyPowerState(charging: target.charging, adapter: target.adapter)
        }
    }

    private func restoreFirmwareLimit() throws {
        guard let data = controlDefaults.data(forKey: firmwareSnapshotKey) else { return }
        let original = try JSONDecoder().decode(FirmwareChargeLimitState.self, from: data)
        try FirmwareChargeLimitController(registers: SMCFirmwareLimitRegisters()).replace(with: original)
        controlDefaults.removeObject(forKey: firmwareSnapshotKey)
        controlDefaults.synchronize()
    }

    private func reconcile(reason: String) {
        guard let policy else { return }
        do {
            try applyEffectivePolicy()
            if reason != "watchdog" {
                logger.notice("POWER_EVENT \(reason, privacy: .public) charging=\(policy.effective.charging) adapter=\(policy.effective.adapter)")
            }
        } catch {
            logger.error("POWER_RECONCILE_FAILED \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func ping(reply: @escaping @Sendable (Bool, String?) -> Void) {
        reply(true, nil)
    }

    // MARK: - Update-time client pin refresh (方案 C)
    //
    // The updater replaces /Applications/Aidente.app with a new ad-hoc build,
    // so the client cdhash changes and the pinned manifest would reject the
    // relaunched app. Only the *currently authorized* app can announce the
    // update over its already-pinned connection; the daemon then watches for
    // the swap and re-pins itself — but only after re-validating the new
    // bundle. Any failure keeps the old pin, and the next launch falls back to
    // the normal re-authorization prompt.

    private let pinRefreshQueue = DispatchQueue(label: "com.aidente.app.control.pinrefresh", qos: .utility)
    private var pinRefreshGeneration = 0

    func schedulePinRefresh(expectedVersion: String, reply: @escaping @Sendable (Bool, String?) -> Void) {
        pinRefreshGeneration += 1
        let generation = pinRefreshGeneration
        logger.notice("PIN_REFRESH_SCHEDULED \(expectedVersion, privacy: .public)")
        pinLog("SCHEDULED expectedVersion=\(expectedVersion) generation=\(pinRefreshGeneration)")
        pinRefreshQueue.async { [weak self] in
            self?.watchForClientSwap(expectedVersion: expectedVersion, generation: generation)
        }
        reply(true, nil)
    }

    /// File-based trace for the pin-refresh watcher: the unified log is not
    /// readable in every environment, so keep a small plain-text trail next to
    /// the manifest (truncated past 64 KB).
    private func pinLog(_ message: String) {
        let url = URL(fileURLWithPath: LocalControlIdentity.directory)
            .appendingPathComponent("pinrefresh.log")
        let line = "\(Date()) \(message)\n"
        if let data = try? Data(contentsOf: url), data.count > 64 * 1024 {
            try? data.write(to: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line.data(using: .utf8)!)
        } else {
            try? line.data(using: .utf8)?.write(to: url)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: url.path
            )
        }
    }

    private func watchForClientSwap(expectedVersion: String, generation: Int) {
        let clientPath = LocalControlIdentity.clientPath
        // The bundle directory, NOT clientPath (that is the executable; reading
        // "<executable>/Contents/Info.plist" is why version checks read nil).
        let bundleURL = URL(fileURLWithPath: LocalControlIdentity.clientBundle, isDirectory: true)
        let manifestURL = URL(fileURLWithPath: LocalControlIdentity.manifest)
        // 240 × 0.5 s = 120 s: enough for the updater's 60 s parent-exit window
        // plus the swap itself. The idle poll is a cheap stat + static-signature
        // read; the expensive codesign verify only runs once the cdhash moved.
        // Expiring without a swap (failed update, user rollback) is a no-op —
        // the old pin stays valid.
        for tick in 0..<240 {
            guard pinRefreshGeneration == generation else {
                pinLog("SUPERSEDED generation=\(generation)")
                return
            }
            guard let pinned = clientPinnedIdentity() else {
                logger.error("PIN_REFRESH_NO_MANIFEST")
                pinLog("NO_MANIFEST")
                return
            }
            guard FileManager.default.fileExists(atPath: clientPath) else {
                usleep(500_000)
                continue
            }
            guard let candidate = codeIdentity(at: bundleURL) else {
                logger.notice("PIN_REFRESH_CANDIDATE_UNREADABLE")
                pinLog("tick=\(tick) CANDIDATE_UNREADABLE")
                usleep(500_000)
                continue
            }
            if candidate.cdHash == pinned.cdHash {
                usleep(500_000) // not swapped yet (or rolled back)
                continue
            }
            pinLog("tick=\(tick) SWAP_DETECTED new=\(candidate.cdHash) id=\(candidate.identifier ?? "nil") ver=\(candidate.version ?? "nil")")
            // The cdhash moved — validate the replacement before re-pinning.
            // Strict (non-deep) is sufficient here: the updater already ran a
            // full --deep --strict on the staged bundle before the swap, and
            // this daemon only needs to reject a post-swap tamper attempt.
            guard candidate.identifier == "com.aidente.app",
                  candidate.version == expectedVersion,
                  verifyCodeSignature(at: bundleURL),
                  let sha = fileSHA256(at: URL(fileURLWithPath: clientPath))
            else {
                logger.error("PIN_REFRESH_VALIDATION_FAILED")
                pinLog("VALIDATION_FAILED id=\(candidate.identifier ?? "nil") ver=\(candidate.version ?? "nil") expected=\(expectedVersion)")
                return
            }
            guard updateClientPin(cdHash: candidate.cdHash, sha256: sha, manifestURL: manifestURL) else {
                logger.error("PIN_REFRESH_WRITE_FAILED")
                pinLog("WRITE_FAILED")
                return
            }
            logger.notice("PIN_REFRESHED \(candidate.cdHash, privacy: .public) version=\(expectedVersion, privacy: .public)")
            pinLog("PIN_REFRESHED new=\(candidate.cdHash)")
            // Restart so the listener re-reads the manifest: exiting releases
            // the mach port and launchd starts a fresh daemon on demand with
            // the new pin in effect.
            Thread.sleep(forTimeInterval: 0.5)
            exit(0)
        }
        logger.notice("PIN_REFRESH_EXPIRED")
        pinLog("EXPIRED no swap within window")
    }

    private struct CodeIdentity {
        let cdHash: String
        let identifier: String?
        let version: String?
    }

    private func codeIdentity(at bundleURL: URL) -> CodeIdentity? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let code = staticCode
        else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let details = information as? [String: Any],
              let cdHashData = details[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        let cdHash = cdHashData.map { String(format: "%02x", $0) }.joined()
        // Read the version straight from Info.plist: Bundle(url:) has been
        // observed returning nil info values for a freshly swapped bundle
        // inside the root daemon (no UI session), which failed validation.
        let info = NSDictionary(contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist"))
        let version = info?["CFBundleShortVersionString"] as? String
        return CodeIdentity(cdHash: cdHash, identifier: details[kSecCodeInfoIdentifier as String] as? String, version: version)
    }

    private func verifyCodeSignature(at bundleURL: URL) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--strict", bundleURL.path]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func fileSHA256(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func clientPinnedIdentity() -> (cdHash: String, sha256: String)? {
        guard let manifest = NSDictionary(contentsOfFile: LocalControlIdentity.manifest),
              let cdHash = manifest["clientCDHash"] as? String,
              let sha256 = manifest["clientSHA256"] as? String
        else { return nil }
        return (cdHash, sha256)
    }

    private func updateClientPin(cdHash: String, sha256: String, manifestURL: URL) -> Bool {
        guard let manifest = NSDictionary(contentsOfFile: manifestURL.path) as? [String: Any] else {
            return false
        }
        var updated = manifest
        updated["clientCDHash"] = cdHash
        updated["clientSHA256"] = sha256
        let plist = NSDictionary(dictionary: updated)
        return plist.write(to: manifestURL, atomically: true)
    }

    func manageBatteryCharging(enabled: Bool, reply: @escaping @Sendable (Bool, String?) -> Void) {
        queue.sync {
        hasControlledPower = true
        do {
            guard battery.capabilities.inhibitChargeControl else {
                reply(false, "当前设备不支持充电控制")
                return
            }
            let currentlyInhibited = try battery.getChargingInhibited()
            if currentlyInhibited != !enabled {
                try battery.setChargingInhibited(!enabled)
                logger.debug("SMC set charging inhibited to: \(!enabled)")
            }
            let appliedValue = try battery.getChargingInhibited()
            guard appliedValue == !enabled else {
                reply(false, "SMC 没有接受充电暂停状态")
                return
            }
            reply(true, nil)
        } catch {
            logger.error("manageBatteryCharging failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
        }
    }

    func manageExternalPower(enabled: Bool, reply: @escaping @Sendable (Bool, String?) -> Void) {
        queue.sync {
        hasControlledPower = true
        do {
            guard battery.capabilities.forceDischargeControl else {
                reply(false, "当前设备不支持适配器控制")
                return
            }
            let currentlyDischarging = try battery.getForceDischarging()
            if currentlyDischarging != !enabled {
                try battery.setForceDischarging(!enabled)
                logger.debug("SMC set force discharging to: \(!enabled)")
            }
            let appliedValue = try battery.getForceDischarging()
            guard appliedValue == !enabled else {
                reply(false, "SMC 没有接受适配器控制状态")
                return
            }
            reply(true, nil)
        } catch {
            logger.error("manageExternalPower failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
        }
    }

    func manageMagsafeLED(target: UInt8, reply: @escaping @Sendable (Bool, String?) -> Void) {
        queue.sync {
        do {
            guard adapter.capabilities.magSafeControl else {
                reply(false, "当前设备不支持 MagSafe 指示灯控制")
                return
            }
            guard let ledState = MagSafeLEDState(rawValue: target) else {
                reply(false, "无效的 MagSafe 指示灯状态：\(target)")
                return
            }
            let currentState = try adapter.getMagSafeLEDState()
            if currentState != ledState {
                try adapter.setMagSafeLEDState(ledState)
                logger.debug("SMC MagSafe LED set to: \(ledState.rawValue)")
            }
            reply(true, nil)
        } catch {
            logger.error("manageMagsafeLED failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
        }
    }

    func setLowPowerMode(enabled: Bool, reply: @escaping @Sendable (Bool, String?) -> Void) {
        queue.sync {
        // Low Power Mode has no public API; pmset is the only interface and
        // needs root. `-b` scopes the write to the battery power profile so an
        // AC-side user setting is never touched.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-b", "lowpowermode", enabled ? "1" : "0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                logger.error("pmset lowpowermode failed: \(message, privacy: .public)")
                reply(false, message.isEmpty ? "pmset 退出状态 \(process.terminationStatus)" : message)
                return
            }
            logger.info("pmset battery lowpowermode set to \(enabled)")
            reply(true, nil)
        } catch {
            logger.error("setLowPowerMode failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
        }
    }

    func setResetOnDisconnect(_ enabled: Bool) {
        queue.sync {
        resetOnDisconnect = enabled
        logger.info("Reset on disconnect: \(enabled)")
        }
    }

    func restoreDefaults(reply: @escaping @Sendable (Bool, String?) -> Void) {
        queue.async {
            do {
                try self.restoreOnQueue()
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    private func resetOnQueue() {
        do { try restoreOnQueue() }
        catch { logger.error("reset after disconnect failed: \(error.localizedDescription)") }
    }

    private func restoreOnQueue() throws {
        policy = nil
        firmwarePolicy.reset()
        if battery.capabilities.forceDischargeControl {
            try battery.setForceDischarging(false)
        }
        if battery.usesFirmwareChargeLimit {
            try restoreFirmwareLimit()
        } else if controlDefaults.data(forKey: firmwareSnapshotKey) != nil {
            throw SMCBatteryError.unsupportedCapability
        } else if battery.capabilities.inhibitChargeControl {
            try battery.setChargingInhibited(false)
        }
        if adapter.capabilities.magSafeControl {
            do { try adapter.setMagSafeLEDState(.reset) }
            catch { logger.warning("LED reset failed after restoring power: \(error.localizedDescription)") }
        }
        logger.info("SMC keys reset to defaults")
        hasControlledPower = false
    }
}

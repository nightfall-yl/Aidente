import AppKit
import Defaults
import Foundation
import Observation

@MainActor
@Observable
class MenuViewModel {
    private let batteryService: BatteryService
    private let chargeManager: ChargeManager
    private let batteryHistoryService: BatteryHistoryService

    var batteryTemperatureText: String = "0°C"
    var adapterElectricalText: String = "0V · 0A"
    var batteryElectricalText: String = "0V · 0A"
    var cycleCountText: String = "0"
    var batteryHealthText: String = "0.0%"
    var currentCapacityText: String = "—"
    var estimatedFullCapacityText: String = "—"
    var designCapacityText: String = "—"
    var batteryCapacityHistory: [BatteryCapacitySample] = []
    var batteryHistoryTrackingText: String = AidenteL10n.t("每日记录 · 今天开始")
    var chargerDisplayName: String = AidenteL10n.t("未连接电源", "No Power Source")

    var displayPercentage: Int = 0
    var chargingMode: ChargingMode = .discharging
    var batteryPower: Double = 0
    var adapterPower: Double = 0
    var systemPower: Double = 0
    var powerSource: PowerSource = .battery
    var isCharging: Bool = false
    var isLowPowerModeEnabled: Bool = false
    /// 仪表盘「高能耗应用」唯一展示项：经过阈值 + 迟滞筛选，可能为空。
    var highlightedEnergyApp: AppEnergyUsageSnapshot?

    /// 高功耗判定：绝对门槛 25%（约一个核心 1/4 负载）+ 相对优势 1.5×；
    /// 连续 2 次采样（约 8 秒）达标才显示，跌破 12% 连续 3 次才撤下。
    private enum EnergyHighlightPolicy {
        static let showThreshold = 25.0
        static let hideThreshold = 12.0
        static let relativeAdvantage = 1.5
        static let samplesToShow = 2
        static let samplesToHide = 3
    }
    private var energyCandidateID: String?
    private var energyCandidateCount = 0
    private var energyMissCount = EnergyHighlightPolicy.samplesToHide

    var chargeLimitOverrideActive: Bool { chargeManager.chargeLimitOverrideActive }
    var forceDischargeActive: Bool { chargeManager.forceDischargeActive }
    var lowPowerOverrideActive: Bool { chargeManager.lowPowerOverrideActive }
    var manualPauseActive: Bool { chargeManager.manualPauseActive }
    var calibrationActive: Bool { chargeManager.calibrationStage != .idle }
    var operationStatusText: String { chargeManager.operationStatusTitle }
    var canQuickRepair: Bool { chargeManager.canQuickRepair }
    func quickRepair() async { await chargeManager.attemptQuickRepair() }
    var hasControlError: Bool { chargeManager.controlError != nil }
    var adapterConnected: Bool = false

    private var metricsObservation: Task<Void, Never>?
    private var historyObservation: Task<Void, Never>?
    private var settingsObservation: Task<Void, Never>?
    private var powerModeObserver: NSObjectProtocol?
    private var energyUsageTask: Task<Void, Never>?

    init(
        batteryService: BatteryService,
        chargeManager: ChargeManager,
        batteryHistoryService: BatteryHistoryService
    ) {
        self.batteryService = batteryService
        self.chargeManager = chargeManager
        self.batteryHistoryService = batteryHistoryService
        startObservingMetrics()
        startObservingHistory()
        startObservingSettings()
        startObservingPowerMode()
    }

    private func startObservingMetrics() {
        metricsObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.updateFormattedValues(
                    from: self.batteryService.metrics,
                    adapter: self.batteryService.adapterMetrics
                )
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.batteryService.metrics
                        _ = self.batteryService.adapterMetrics
                    } onChange: {
                        Task { @MainActor in
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    private func startObservingSettings() {
        settingsObservation = Task { [weak self] in
            for await _ in Defaults.updates(
                [.useHardwarePercentage, .appLanguage],
                initial: false
            ) {
                guard let self else { return }
                self.updateFormattedValues(
                    from: self.batteryService.metrics,
                    adapter: self.batteryService.adapterMetrics
                )
            }
        }
    }

    private func startObservingHistory() {
        historyObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.batteryCapacityHistory = self.batteryHistoryService.samples
                self.batteryHistoryTrackingText = self.formatHistoryTrackingText(
                    self.batteryHistoryService.trackingStartedAt
                )
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.batteryHistoryService.samples
                        _ = self.batteryHistoryService.trackingStartedAt
                    } onChange: {
                        Task { @MainActor in
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    private func startObservingPowerMode() {
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

        powerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: ProcessInfo.processInfo,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    func toggleChargeLimitOverride() {
        chargeManager.toggleChargeLimitOverride()
    }

    func toggleForceDischarge() {
        chargeManager.toggleForceDischarge()
    }

    func toggleLowPowerOverride() {
        chargeManager.toggleLowPowerOverride()
    }

    func toggleManualPause() {
        if manualPauseActive {
            chargeManager.resumeNormalManagement()
        } else {
            chargeManager.pauseCharging()
        }
    }

    func toggleCalibration() {
        if calibrationActive {
            chargeManager.cancelCalibration()
        } else {
            chargeManager.startCalibration()
        }
    }

    private func updateFormattedValues(from metrics: BatteryMetrics, adapter: AdapterMetrics) {
        let useHardware = Defaults[.useHardwarePercentage]
        let percentage =
            useHardware
            ? metrics.hardwareBatteryPercentage : metrics.batteryPercentage
        displayPercentage = percentage
        chargerDisplayName = ChargerInfoProvider.displayName(adapter: adapter)

        let derivedPowerSource = derivePowerSource(battery: metrics, adapter: adapter)

        if derivedPowerSource == .acAdapter {
            if metrics.isCharging {
                chargingMode = .charging
            } else {
                chargingMode = .pluggedIn
            }
        } else {
            chargingMode = .discharging
        }

        batteryTemperatureText =
            "\(metrics.batteryTemperature.formatted(.number.precision(.fractionLength(1))))°C"

        let voltageFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        let currentFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))

        adapterElectricalText =
            "\(abs(adapter.adapterVoltage).formatted(voltageFormat))V · \(abs(adapter.adapterCurrent).formatted(currentFormat))A"
        batteryElectricalText =
            "\(abs(metrics.batteryVoltage).formatted(voltageFormat))V · \(abs(metrics.batteryCurrent).formatted(currentFormat))A"

        batteryPower = metrics.batteryPower
        adapterPower = adapter.adapterPower
        systemPower = adapter.adapterPower - metrics.batteryPower
        powerSource = derivedPowerSource
        isCharging = metrics.isCharging
        adapterConnected = adapter.adapterConnected

        cycleCountText = "\(metrics.cycleCount)"
        batteryHealthText = String(format: "%.1f%%", metrics.batteryHealth)
        currentCapacityText = formatCapacity(metrics.currentCapacityMilliampHours)
        estimatedFullCapacityText = formatCapacity(
            metrics.estimatedFullChargeCapacityMilliampHours
        )
        designCapacityText = formatCapacity(metrics.designCapacityMilliampHours)
    }

    private func derivePowerSource(battery: BatteryMetrics, adapter: AdapterMetrics) -> PowerSource {
        guard adapter.adapterConnected else { return .battery }

        if adapter.adapterPower == 0 {
            return .battery
        } else if battery.batteryPower >= 0 {
            return .acAdapter
        } else {
            return .both
        }
    }

    private func startEnergyUsageTimer() {
        guard energyUsageTask == nil else { return }

        energyUsageTask = Task { [weak self] in
            while !Task.isCancelled {
                let snapshots = await Task.detached(priority: .utility) {
                    AppEnergyUsageService.readTopApps()
                }.value

                guard !Task.isCancelled else { return }
                self?.applyEnergyUsageSnapshots(snapshots)

                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    private func stopEnergyUsageTimer() {
        energyUsageTask?.cancel()
        energyUsageTask = nil
    }

    private func refreshEnergyUsage() {
        Task { [weak self] in
            let snapshots = await Task.detached(priority: .utility) {
                AppEnergyUsageService.readTopApps()
            }.value
            guard !Task.isCancelled else { return }
            self?.applyEnergyUsageSnapshots(snapshots)
        }
    }

    /// 统一入口：仪表盘展示项按阈值 + 迟滞收敛为至多一个 App。
    private func applyEnergyUsageSnapshots(_ snapshots: [AppEnergyUsageSnapshot]) {
        guard let leader = snapshots.first else {
            energyCandidateID = nil
            energyCandidateCount = 0
            energyMissCount += 1
            if energyMissCount >= EnergyHighlightPolicy.samplesToHide {
                highlightedEnergyApp = nil
            }
            return
        }

        let runnerUp = snapshots.dropFirst().first?.cpuUsage ?? 0
        let qualifies = leader.cpuUsage >= EnergyHighlightPolicy.showThreshold
            && leader.cpuUsage >= runnerUp * EnergyHighlightPolicy.relativeAdvantage

        if qualifies {
            energyMissCount = 0
            if energyCandidateID == leader.id {
                energyCandidateCount += 1
            } else {
                energyCandidateID = leader.id
                energyCandidateCount = 1
            }
            if energyCandidateCount >= EnergyHighlightPolicy.samplesToShow {
                highlightedEnergyApp = leader
            }
        } else {
            energyCandidateID = nil
            energyCandidateCount = 0
            if leader.cpuUsage < EnergyHighlightPolicy.hideThreshold {
                energyMissCount += 1
            } else {
                // 介于两档之间：保持当前展示但不再累积撤下计数。
                energyMissCount = 0
            }
            if energyMissCount >= EnergyHighlightPolicy.samplesToHide {
                highlightedEnergyApp = nil
            }
        }
    }

    func menuWillOpen() {
        batteryHistoryService.captureCurrent()
        startEnergyUsageTimer()
        batteryService.enableFastPolling()
    }

    func menuDidClose() {
        stopEnergyUsageTimer()
        batteryService.disableFastPolling()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func formatCapacity(_ milliampHours: Int) -> String {
        guard milliampHours > 0 else { return "—" }
        return "\(milliampHours) mAh"
    }

    // Cached per language: DateFormatter construction is expensive and this
    // runs on every history sample refresh.
    private static let trackingDateFormatterEn: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    private static let trackingDateFormatterZh: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func formatHistoryTrackingText(_ startDate: Date) -> String {
        let dateText = AidenteL10n.isEnglish
            ? Self.trackingDateFormatterEn.string(from: startDate)
            : Self.trackingDateFormatterZh.string(from: startDate)
        return AidenteL10n.t(
            "自 \(dateText) 开始记录 · 每天 1 个数据点",
            "Tracking since \(dateText) · 1 point per day"
        )
    }

    deinit {
        MainActor.assumeIsolated {
            metricsObservation?.cancel()
            historyObservation?.cancel()
            settingsObservation?.cancel()
            if let powerModeObserver {
                NotificationCenter.default.removeObserver(powerModeObserver)
            }
            energyUsageTask?.cancel()
        }
    }
}

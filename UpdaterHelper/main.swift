import Darwin
import Foundation

// MARK: - Parent-process exit detection
//
// `waitForParentToExit` waits for the launching Aidente process to disappear so
// this helper can safely move the staged replacement over it. `kill(pid, 0)`
// only reports ESRCH once the PID is fully reaped; a process that has exited
// but is not yet reaped still answers "exists" (it is a zombie). We therefore
// also treat a zombie as gone — it is no longer running, so replacing its
// on-disk bundle is safe.

private let bsdInfoFlavor: Int32 = 3          // PROC_PIDTBSDINFO
private let processStateZombie: UInt32 = 5    // SZOMB

private func parentProcessIsGone(_ pid: pid_t) -> Bool {
    // Fully reaped: kill(pid, 0) fails with ESRCH.
    if kill(pid, 0) != 0, errno == ESRCH {
        return true
    }
    // Exited but not yet reaped (zombie): no longer running, safe to replace.
    if processIsZombie(pid) {
        return true
    }
    return false
}

private func processIsZombie(_ pid: pid_t) -> Bool {
    guard pid > 1 else { return false }
    // proc_bsdinfo lays out pbsd_pid(0:4), pbsd_ppid(4:8), pbsd_pgid(8:12),
    // pbsd_status(12:16); SZOMB (zombie) == 5. Read the status word at
    // byte offset 12 — not 4, which is pbsd_ppid.
    var buffer = [UInt8](repeating: 0, count: 64)
    let count = Int32(buffer.count)
    let ret = buffer.withUnsafeMutableBytes { raw in
        proc_pidinfo(pid, bsdInfoFlavor, UInt64(0), raw.baseAddress!, count)
    }
    guard ret >= 16 else { return false }
    let status = UInt32(buffer[12]) | UInt32(buffer[13]) << 8
        | UInt32(buffer[14]) << 16 | UInt32(buffer[15]) << 24
    return status == processStateZombie
}

private struct InstallResult: Codable {
    let succeeded: Bool
    let version: String
    let message: String
    let backupPath: String?
}

private enum UpdaterError: LocalizedError {
    case invalidArguments
    case parentDidNotExit
    case unsafePath
    case invalidReplacement
    case invalidSignature(String)
    case replacementFailed(String)
    case relaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments: "Invalid updater arguments."
        case .parentDidNotExit: "Aidente did not quit before the update timeout."
        case .unsafePath: "The requested update paths are not safe."
        case .invalidReplacement: "The replacement is not the expected Aidente version."
        case .invalidSignature(let detail): "The replacement signature is invalid: \(detail)"
        case .replacementFailed(let detail): "Unable to replace Aidente: \(detail)"
        case .relaunchFailed(let detail): "Unable to relaunch Aidente: \(detail)"
        }
    }
}

private struct Arguments {
    let parentPID: pid_t
    let targetURL: URL
    let replacementURL: URL
    let version: String
    let resultURL: URL
    let skipRelaunchForTest: Bool
    let allowTestLocation: Bool

    init?(_ values: [String]) {
        func value(after flag: String) -> String? {
            guard let index = values.firstIndex(of: flag), values.indices.contains(index + 1) else {
                return nil
            }
            return values[index + 1]
        }

        guard let pidText = value(after: "--parent-pid"),
            let pid = Int32(pidText),
            let target = value(after: "--target"),
            let replacement = value(after: "--replacement"),
            let version = value(after: "--version"),
            let result = value(after: "--result")
        else {
            return nil
        }

        parentPID = pid
        targetURL = URL(fileURLWithPath: target).standardizedFileURL
        replacementURL = URL(fileURLWithPath: replacement).standardizedFileURL
        self.version = version
        resultURL = URL(fileURLWithPath: result).standardizedFileURL
        skipRelaunchForTest = values.contains("--skip-relaunch-for-test")
        allowTestLocation = values.contains("--allow-test-location")
    }
}

private func runProcess(
    executable: URL,
    arguments: [String]
) -> (status: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    } catch {
        return (-1, error.localizedDescription)
    }
}

private func waitForParentToExit(_ pid: pid_t) -> Bool {
    guard pid > 1 else { return false }
    // 600 × 100 ms = 60 s. Generous window so a slow teardown or a lingering
    // zombie (reaped late by the parent) does not abort the update.
    for _ in 0..<600 {
        if parentProcessIsGone(pid) {
            return true
        }
        usleep(100_000)
    }
    return false
}

private func validatePaths(_ arguments: Arguments) throws {
    let targetParent = arguments.targetURL.deletingLastPathComponent()
    let replacementParent = arguments.replacementURL.deletingLastPathComponent()
    let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        .standardizedFileURL
    let userApplications = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications", isDirectory: true)
        .standardizedFileURL

    let approvedParent = targetParent == systemApplications
        || targetParent == userApplications
        || (arguments.skipRelaunchForTest && arguments.allowTestLocation)

    guard arguments.targetURL.pathExtension == "app",
        arguments.replacementURL.pathExtension == "app",
        targetParent == replacementParent,
        approvedParent,
        arguments.replacementURL.lastPathComponent.hasPrefix(".Aidente.update-")
    else {
        throw UpdaterError.unsafePath
    }
}

private func validateReplacement(_ arguments: Arguments) throws {
    guard let bundle = Bundle(url: arguments.replacementURL),
        bundle.bundleIdentifier == "com.aidente.app",
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            == arguments.version
    else {
        throw UpdaterError.invalidReplacement
    }

    let signature = runProcess(
        executable: URL(fileURLWithPath: "/usr/bin/codesign"),
        arguments: ["--verify", "--deep", "--strict", arguments.replacementURL.path]
    )
    guard signature.status == 0 else {
        throw UpdaterError.invalidSignature(signature.output)
    }
}

private func writeResult(
    _ result: InstallResult,
    to url: URL
) {
    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(result)
        try data.write(to: url, options: .atomic)
    } catch {
        // The updater cannot present UI. Relaunch still proceeds so Aidente can
        // continue operating even when the result file cannot be written.
    }
}

private func relaunch(_ applicationURL: URL) throws {
    let result = runProcess(
        executable: URL(fileURLWithPath: "/usr/bin/open"),
        arguments: ["-n", applicationURL.path]
    )
    guard result.status == 0 else {
        throw UpdaterError.relaunchFailed(result.output)
    }
}

guard let arguments = Arguments(Array(CommandLine.arguments.dropFirst())) else {
    exit(2)
}

let fileManager = FileManager.default
let backupURL = arguments.targetURL.deletingLastPathComponent()
    .appendingPathComponent(
        ".Aidente.backup-\(UUID().uuidString).app",
        isDirectory: true
    )
var targetWasMoved = false
var replacementWasMoved = false

do {
    try validatePaths(arguments)
    try validateReplacement(arguments)
    guard waitForParentToExit(arguments.parentPID) else {
        throw UpdaterError.parentDidNotExit
    }

    do {
        try fileManager.moveItem(at: arguments.targetURL, to: backupURL)
        targetWasMoved = true
        try fileManager.moveItem(at: arguments.replacementURL, to: arguments.targetURL)
        replacementWasMoved = true
    } catch {
        throw UpdaterError.replacementFailed(error.localizedDescription)
    }

    writeResult(
        InstallResult(
            succeeded: true,
            version: arguments.version,
            message: "Aidente was updated successfully.",
            backupPath: backupURL.path
        ),
        to: arguments.resultURL
    )

    if !arguments.skipRelaunchForTest {
        try relaunch(arguments.targetURL)
    }
    exit(0)
} catch {
    if replacementWasMoved, fileManager.fileExists(atPath: arguments.targetURL.path) {
        try? fileManager.removeItem(at: arguments.targetURL)
    }
    if targetWasMoved, fileManager.fileExists(atPath: backupURL.path) {
        try? fileManager.moveItem(at: backupURL, to: arguments.targetURL)
    }
    if fileManager.fileExists(atPath: arguments.replacementURL.path) {
        try? fileManager.removeItem(at: arguments.replacementURL)
    }

    let message = error.localizedDescription
    writeResult(
        InstallResult(
            succeeded: false,
            version: arguments.version,
            message: message,
            backupPath: nil
        ),
        to: arguments.resultURL
    )

    if !arguments.skipRelaunchForTest,
        fileManager.fileExists(atPath: arguments.targetURL.path)
    {
        try? relaunch(arguments.targetURL)
    }
    exit(1)
}

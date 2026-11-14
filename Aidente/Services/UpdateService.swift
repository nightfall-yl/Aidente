import AppKit
import CryptoKit
import Defaults
import Foundation
import Observation

struct AidenteUpdateRelease: Equatable, Sendable {
    let version: String
    let name: String
    let notes: String
    let pageURL: URL
    let assetName: String
    let assetURL: URL
    let assetSize: Int
    let sha256: String
}

enum AidenteUpdatePhase: Equatable {
    case idle
    case checking
    case upToDate
    case available(AidenteUpdateRelease)
    case downloading(AidenteUpdateRelease)
    case preparing(AidenteUpdateRelease)
    case installing(AidenteUpdateRelease)
    case installed(String)
    case failed(String)
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let state: String
    let contentType: String
    let size: Int
    let digest: String?
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case state
        case contentType = "content_type"
        case size
        case digest
        case browserDownloadURL = "browser_download_url"
    }
}

private struct UpdateInstallResult: Codable {
    let succeeded: Bool
    let version: String
    let message: String
    let backupPath: String?
}

private enum InstallResultOutcome {
    case none
    case succeeded(String)
    case failed(String)
}

private enum AidenteUpdateError: LocalizedError {
    case invalidResponse
    case invalidRelease
    case missingAsset(String)
    case missingDigest
    case invalidDownloadURL
    case invalidDownload
    case oversizedAsset
    case checksumMismatch
    case extractionFailed(String)
    case invalidBundle
    case wrongBundleIdentifier
    case wrongBundleVersion
    case invalidSignature(String)
    case unsupportedArchitecture
    case runningFromDiskImage
    case unsupportedInstallLocation
    case installLocationNotWritable
    case missingUpdater
    case updaterLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            AidenteL10n.t(
                "GitHub 返回了无法识别的更新信息。",
                "GitHub returned an unrecognized update response."
            )
        case .invalidRelease:
            AidenteL10n.t(
                "最新发行版不是可安装的正式版本。",
                "The latest release is not an installable stable version."
            )
        case .missingAsset(let name):
            AidenteL10n.t(
                "发行版缺少安装包：\(name)",
                "The release is missing the update package: \(name)"
            )
        case .missingDigest:
            AidenteL10n.t(
                "发行版没有提供 SHA-256 校验值，已拒绝安装。",
                "The release does not provide a SHA-256 digest, so installation was refused."
            )
        case .invalidDownloadURL:
            AidenteL10n.t(
                "更新包不是来自 Aidente 官方 GitHub Release。",
                "The update package is not from the official Aidente GitHub Release."
            )
        case .invalidDownload:
            AidenteL10n.t(
                "更新包下载失败或返回内容无效。",
                "The update download failed or returned invalid content."
            )
        case .oversizedAsset:
            AidenteL10n.t(
                "更新包大小异常，已停止下载。",
                "The update package size is unexpected, so the download was stopped."
            )
        case .checksumMismatch:
            AidenteL10n.t(
                "更新包 SHA-256 校验失败，原应用未被修改。",
                "The update package failed SHA-256 verification. The installed app was not changed."
            )
        case .extractionFailed(let detail):
            AidenteL10n.t(
                "无法解压更新包：\(detail)",
                "Unable to extract the update package: \(detail)"
            )
        case .invalidBundle:
            AidenteL10n.t(
                "更新包中没有有效的 Aidente.app。",
                "The update package does not contain a valid Aidente.app."
            )
        case .wrongBundleIdentifier:
            AidenteL10n.t(
                "更新应用的身份与 Aidente 不一致，已拒绝安装。",
                "The update app identity does not match Aidente, so installation was refused."
            )
        case .wrongBundleVersion:
            AidenteL10n.t(
                "更新应用的版本与 GitHub 发行版不一致。",
                "The update app version does not match the GitHub release."
            )
        case .invalidSignature(let detail):
            AidenteL10n.t(
                "更新应用签名校验失败：\(detail)",
                "The update app failed signature verification: \(detail)"
            )
        case .unsupportedArchitecture:
            AidenteL10n.t(
                "更新包不是适用于 Apple 芯片的 arm64 应用。",
                "The update package is not an arm64 app for Apple silicon."
            )
        case .runningFromDiskImage:
            AidenteL10n.t(
                "当前正从磁盘映像运行。请先把 Aidente 拖入“应用程序”文件夹。",
                "Aidente is running from a disk image. Move it to Applications first."
            )
        case .unsupportedInstallLocation:
            AidenteL10n.t(
                "自动更新仅支持“应用程序”文件夹中的 Aidente。",
                "Automatic updates are supported only for Aidente in an Applications folder."
            )
        case .installLocationNotWritable:
            AidenteL10n.t(
                "无法写入当前“应用程序”文件夹。请从 GitHub 手动安装本次更新。",
                "The current Applications folder is not writable. Install this update manually from GitHub."
            )
        case .missingUpdater:
            AidenteL10n.t(
                "应用内缺少更新安装程序。",
                "The updater executable is missing from the app."
            )
        case .updaterLaunchFailed(let detail):
            AidenteL10n.t(
                "无法启动更新安装程序：\(detail)",
                "Unable to start the updater: \(detail)"
            )
        }
    }
}

@MainActor
@Observable
final class UpdateService {
    static let shared = UpdateService()

    static let releasesPageURL = URL(
        string: "https://github.com/nightfall-yl/Aidente/releases"
    )!

    private static let latestReleaseAPIURL = URL(
        string: "https://api.github.com/repos/nightfall-yl/Aidente/releases/latest"
    )!
    private static let latestReleasePageURL = URL(
        string: "https://github.com/nightfall-yl/Aidente/releases/latest"
    )!
    private static let maximumAssetSize = 200 * 1_024 * 1_024
    private static let automaticCheckInterval: Duration = .seconds(6 * 60 * 60)

    private(set) var phase: AidenteUpdatePhase = .idle
    private(set) var lastCheckedAt: Date?

    private var automaticCheckTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?

    /// Set by AppDelegate before `start()`. After a successful post-update
    /// re-authorization the active ChargeManager re-evaluates charging control
    /// immediately instead of waiting for the next SMC poll.
    var controlRetryHandler: (() -> Void)?

    /// Nil when the running process has no usable Info.plist version (previews,
    /// unit-test hosts, bare executables, or a malformed plist value).
    private var verifiedBundleVersion: String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else { return nil }
        return Self.isStableNumericVersion(value) ? value : nil
    }

    var currentVersion: String {
        verifiedBundleVersion ?? "development"
    }

    var availableRelease: AidenteUpdateRelease? {
        switch phase {
        case .available(let release), .downloading(let release),
            .preparing(let release), .installing(let release):
            release
        default:
            nil
        }
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .preparing, .installing:
            true
        default:
            false
        }
    }

    var statusIcon: String {
        switch phase {
        case .checking: "arrow.triangle.2.circlepath"
        case .available: "arrow.down.circle.fill"
        case .downloading: "icloud.and.arrow.down.fill"
        case .preparing: "checkmark.shield.fill"
        case .installing: "arrow.clockwise.circle.fill"
        case .upToDate, .installed: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .idle: "sparkles"
        }
    }

    var statusColor: NSColor {
        switch phase {
        case .available, .downloading, .preparing, .installing:
            .systemOrange
        case .upToDate, .installed:
            .systemGreen
        case .failed:
            .systemRed
        default:
            .systemTeal
        }
    }

    var statusTitle: String {
        switch phase {
        case .idle:
            AidenteL10n.t("等待检查更新", "Ready to Check")
        case .checking:
            AidenteL10n.t("正在检查更新…", "Checking for Updates…")
        case .upToDate:
            AidenteL10n.t("当前已是最新版", "Aidente Is Up to Date")
        case .available(let release):
            AidenteL10n.t(
                "发现新版本 \(release.version)",
                "Version \(release.version) Is Available"
            )
        case .downloading(let release):
            AidenteL10n.t(
                "正在后台下载 \(release.version)…",
                "Downloading \(release.version) in the Background…"
            )
        case .preparing:
            AidenteL10n.t("正在校验更新包…", "Verifying the Update…")
        case .installing:
            AidenteL10n.t("正在准备重新启动…", "Preparing to Restart…")
        case .installed(let version):
            AidenteL10n.t(
                "已更新至 \(version)",
                "Updated to \(version)"
            )
        case .failed:
            AidenteL10n.t("更新未完成", "Update Not Completed")
        }
    }

    var statusDetail: String {
        switch phase {
        case .idle:
            return AidenteL10n.t(
                "更新来源：GitHub 正式发行版",
                "Update source: stable GitHub Releases"
            )
        case .checking:
            return AidenteL10n.t(
                "正在连接 nightfall-yl/Aidente",
                "Connecting to nightfall-yl/Aidente"
            )
        case .upToDate:
            return checkedTimeDescription
        case .available(let release):
            let detail = AidenteL10n.t(
                "点击后将自动下载、校验、安装并重新启动 Aidente。",
                "Aidente will download, verify, install, and restart automatically."
            )
            if release.assetSize > 0 {
                return detail + " · \(formattedFileSize(release.assetSize))"
            }
            return detail
        case .downloading:
            return AidenteL10n.t(
                "可以继续使用 Aidente，下载完成后才会重新启动。",
                "You can keep using Aidente until the download is ready."
            )
        case .preparing:
            return AidenteL10n.t(
                "正在核对 SHA-256、签名、版本与 arm64 架构。",
                "Checking SHA-256, signature, version, and arm64 architecture."
            )
        case .installing:
            return AidenteL10n.t(
                "原应用会保留到新版本成功启动后。",
                "The old app is retained until the new version launches successfully."
            )
        case .installed:
            return AidenteL10n.t(
                "新版本已成功启动。",
                "The new version launched successfully."
            )
        case .failed(let message):
            return message
        }
    }

    var primaryActionTitle: String {
        if availableRelease != nil {
            return AidenteL10n.t("立即更新", "Update Now")
        }
        return AidenteL10n.t("检查更新", "Check for Updates")
    }

    private init() {}

    /// Runs one launch-time authorization check no matter how the bundle was
    /// replaced. Automatic updates leave an install-result file; manually
    /// copying a new bundle into /Applications does not, but both change the
    /// binary the helper pins its client identity to.
    func checkControlAuthorizationOnLaunch() {
        let outcome = consumeInstallResultIfNeeded()
        guard !AidenteRuntime.isUIPreview,
            !CommandLine.arguments.contains("--update-preview")
        else { return }

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self else { return }
            switch outcome {
            case .failed(let message):
                self.presentErrorAlert(message)
            case .none:
                self.presentLaunchAuthorizationState(updatedVersion: nil)
            case .succeeded(let version):
                self.presentLaunchAuthorizationState(updatedVersion: version)
            }
        }
    }

    func start() {
        if CommandLine.arguments.contains("--update-preview") {
            phase = .available(Self.previewRelease)
            return
        }

        guard Defaults[.automaticallyCheckForUpdates] else { return }
        automaticCheckTask?.cancel()
        automaticCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await self?.performCheck(manual: false)

            while !Task.isCancelled {
                try? await Task.sleep(for: Self.automaticCheckInterval)
                guard !Task.isCancelled else { return }
                await self?.performCheck(manual: false)
            }
        }
    }

    func stop() {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
    }

    func automaticCheckPreferenceChanged() {
        if Defaults[.automaticallyCheckForUpdates] {
            start()
        } else {
            stop()
        }
    }

    func performPrimaryAction() {
        guard !isBusy else { return }
        if availableRelease != nil {
            installAvailableUpdate()
        } else {
            checkForUpdates()
        }
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        Task { [weak self] in
            await self?.performCheck(manual: true)
        }
    }

    func installAvailableUpdate() {
        guard case .available(let release) = phase else { return }
        guard !AidenteRuntime.isUIPreview else { return }

        installTask = Task { [weak self] in
            await self?.performInstall(release)
            self?.installTask = nil
        }
    }

    /// Cancel an in-flight download or verification. The installation stage
    /// (`.installing`) has already handed off to the external updater and
    /// cannot be interrupted, so this is a no-op once that stage begins.
    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
    }

    /// "Skip This Version" in the update sheet. The choice persists across
    /// launches; the next release with a different version is still offered.
    func skipVersion(_ version: String) {
        Defaults[.skippedUpdateVersion] = version
        phase = .idle
    }

    /// Preview builds open the update sheet on the "available" state instead
    /// of showing a standalone alert.
    func presentPreviewAlertIfRequested() {
        guard AidenteRuntime.isUIPreview,
            CommandLine.arguments.contains("--update-preview"),
            CommandLine.arguments.contains("--show-update-alert-preview")
        else {
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.phase = .available(Self.previewRelease)
        }
    }

    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = versionComponents(candidate)
        let currentParts = versionComponents(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }

    nonisolated static func runVersionSelfTest() -> Bool {
        isVersion("6.0.1", newerThan: "6.0")
            && !isVersion("6.0.1", newerThan: "6.0.1")
            && isVersion("v6.0.10", newerThan: "6.0.2")
            && !isVersion("6.0", newerThan: "6.0.1")
            && isVersion("6.1", newerThan: "6.0.2")
            && !isVersion("6.1", newerThan: "6.1.0")
            && !isVersion("6.0.99", newerThan: "6.1")
            && isVersion("7", newerThan: "6.99.99")
    }

    private func performCheck(manual: Bool) async {
        if CommandLine.arguments.contains("--update-preview") {
            // The update sheet presents the preview release from `phase`.
            phase = .available(Self.previewRelease)
            return
        }

        guard !isBusy else { return }

        // A non-bundle host has no numeric version. Comparing against the
        // "development" placeholder would parse it as 0 and report every
        // release as newer, so skip the check instead of guessing.
        guard let localVersion = verifiedBundleVersion else {
            if manual {
                let message = AidenteL10n.t(
                    "无法读取当前应用版本，已跳过更新检查。",
                    "The current app version is unavailable, so the update check was skipped."
                )
                phase = .failed(message)
            }
            return
        }

        phase = .checking

        do {
            let release = try await fetchLatestRelease()
            lastCheckedAt = Date()
            // A skipped release is ignored until a newer one is published;
            // the sheet then reports "up to date" instead of prompting again.
            let skipped = Defaults[.skippedUpdateVersion]
            if Self.isVersion(release.version, newerThan: localVersion),
                release.version != skipped {
                phase = .available(release)
            } else {
                phase = .upToDate
            }
        } catch {
            // The settings sheet presents the failure reason from `phase`.
            phase = .failed(error.localizedDescription)
        }
    }

    private func fetchLatestRelease() async throws -> AidenteUpdateRelease {
        do {
            return try await fetchLatestReleaseFromAPI()
        } catch {
            return try await fetchLatestReleaseFromWebRedirect()
        }
    }

    private func fetchLatestReleaseFromAPI() async throws -> AidenteUpdateRelease {
        var request = URLRequest(url: Self.latestReleaseAPIURL)
        request.timeoutInterval = 25
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Aidente/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw AidenteUpdateError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
        guard !decoded.draft, !decoded.prerelease else {
            throw AidenteUpdateError.invalidRelease
        }

        let version = Self.normalizedVersion(decoded.tagName)
        guard !version.isEmpty else { throw AidenteUpdateError.invalidRelease }
        let expectedAssetName = "Aidente-\(version)-macOS-arm64.zip"
        guard let asset = decoded.assets.first(where: {
            $0.name == expectedAssetName && $0.state == "uploaded"
        }) else {
            throw AidenteUpdateError.missingAsset(expectedAssetName)
        }
        guard asset.size > 0, asset.size <= Self.maximumAssetSize else {
            throw AidenteUpdateError.oversizedAsset
        }
        guard Self.isOfficialDownloadURL(asset.browserDownloadURL) else {
            throw AidenteUpdateError.invalidDownloadURL
        }
        guard let digest = asset.digest?.lowercased(),
            digest.hasPrefix("sha256:"), digest.count == 71
        else {
            throw AidenteUpdateError.missingDigest
        }

        return AidenteUpdateRelease(
            version: version,
            name: decoded.name ?? "Aidente \(version)",
            notes: decoded.body ?? "",
            pageURL: decoded.htmlURL,
            assetName: asset.name,
            assetURL: asset.browserDownloadURL,
            assetSize: asset.size,
            sha256: String(digest.dropFirst("sha256:".count))
        )
    }

    private func fetchLatestReleaseFromWebRedirect() async throws -> AidenteUpdateRelease {
        var request = URLRequest(url: Self.latestReleasePageURL)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Aidente/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            let finalURL = httpResponse.url,
            finalURL.scheme == "https",
            finalURL.host?.lowercased() == "github.com",
            finalURL.path.hasPrefix("/nightfall-yl/Aidente/releases/tag/")
        else {
            throw AidenteUpdateError.invalidResponse
        }

        let tag = finalURL.lastPathComponent
        let version = Self.normalizedVersion(tag)
        guard Self.isStableNumericVersion(version) else {
            throw AidenteUpdateError.invalidRelease
        }

        let assetName = "Aidente-\(version)-macOS-arm64.zip"
        let checksumName = "SHA256SUMS-\(version).txt"
        guard let assetURL = URL(
            string: "https://github.com/nightfall-yl/Aidente/releases/download/\(tag)/\(assetName)"
        ), let checksumURL = URL(
            string: "https://github.com/nightfall-yl/Aidente/releases/download/\(tag)/\(checksumName)"
        ), Self.isOfficialDownloadURL(assetURL), Self.isOfficialDownloadURL(checksumURL)
        else {
            throw AidenteUpdateError.invalidDownloadURL
        }

        var checksumRequest = URLRequest(url: checksumURL)
        checksumRequest.timeoutInterval = 25
        checksumRequest.setValue("text/plain", forHTTPHeaderField: "Accept")
        checksumRequest.setValue("Aidente/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (checksumData, checksumResponse) = try await URLSession.shared.data(
            for: checksumRequest
        )
        guard let checksumHTTPResponse = checksumResponse as? HTTPURLResponse,
            checksumHTTPResponse.statusCode == 200,
            let checksumFinalURL = checksumHTTPResponse.url,
            Self.isAllowedDownloadResponseURL(checksumFinalURL),
            checksumData.count <= 64 * 1_024,
            let checksumText = String(data: checksumData, encoding: .utf8),
            let sha256 = Self.sha256(for: assetName, in: checksumText)
        else {
            throw AidenteUpdateError.missingDigest
        }

        return AidenteUpdateRelease(
            version: version,
            name: "Aidente \(version)",
            notes: "",
            pageURL: finalURL,
            assetName: assetName,
            assetURL: assetURL,
            assetSize: 0,
            sha256: sha256
        )
    }

    private func performInstall(_ release: AidenteUpdateRelease) async {
        var stagedApplicationURL: URL?
        var workingDirectory: URL?

        do {
            let installLocation = try Self.validatedInstallLocation()
            phase = .downloading(release)
            let download = try await download(release)
            workingDirectory = download.workingDirectory

            phase = .preparing(release)
            let staged = try await Task.detached(priority: .userInitiated) {
                try Self.verifyExtractAndStage(
                    archiveURL: download.archiveURL,
                    workingDirectory: download.workingDirectory,
                    release: release,
                    installedApplicationURL: installLocation
                )
            }.value
            stagedApplicationURL = staged
            try? FileManager.default.removeItem(at: download.workingDirectory)
            workingDirectory = nil

            phase = .installing(release)
            try launchUpdater(
                release: release,
                installedApplicationURL: installLocation,
                stagedApplicationURL: staged
            )

            // Brief grace so the update sheet (dismissed when phase becomes
            // .installing) fully ends its modal session before we terminate.
            try? await Task.sleep(for: .milliseconds(800))
            NSApplication.shared.terminate(nil)
        } catch is CancellationError {
            // User cancelled before installation began. Return to idle so the
            // sheet does not re-present the "available" prompt on next open.
            phase = .idle
        } catch {
            if let workingDirectory {
                try? FileManager.default.removeItem(at: workingDirectory)
            }
            if let stagedApplicationURL {
                try? FileManager.default.removeItem(at: stagedApplicationURL)
            }
            // The open settings sheet switches to its failure state via `phase`.
            phase = .failed(error.localizedDescription)
        }
    }

    private func download(
        _ release: AidenteUpdateRelease
    ) async throws -> (archiveURL: URL, workingDirectory: URL) {
        let root = try Self.updatesDirectory()
        let workingDirectory = root.appendingPathComponent(
            "download-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )

        var request = URLRequest(url: release.assetURL)
        request.timeoutInterval = 180
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Aidente/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200,
                let finalURL = httpResponse.url,
                Self.isAllowedDownloadResponseURL(finalURL)
            else {
                throw AidenteUpdateError.invalidDownload
            }

            let archiveURL = workingDirectory.appendingPathComponent(release.assetName)
            try FileManager.default.moveItem(at: temporaryURL, to: archiveURL)
            let downloadedSize = try archiveURL.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize ?? 0
            guard downloadedSize > 0, downloadedSize <= Self.maximumAssetSize else {
                throw AidenteUpdateError.oversizedAsset
            }
            return (archiveURL, workingDirectory)
        } catch {
            try? FileManager.default.removeItem(at: workingDirectory)
            throw error
        }
    }

    private func launchUpdater(
        release: AidenteUpdateRelease,
        installedApplicationURL: URL,
        stagedApplicationURL: URL
    ) throws {
        guard let updaterURL = Bundle.main.url(
            forResource: "AidenteUpdater",
            withExtension: nil
        ), FileManager.default.isExecutableFile(atPath: updaterURL.path)
        else {
            throw AidenteUpdateError.missingUpdater
        }

        let resultURL = try Self.updateResultURL()
        let process = Process()
        process.executableURL = updaterURL
        process.arguments = [
            "--parent-pid", "\(ProcessInfo.processInfo.processIdentifier)",
            "--target", installedApplicationURL.path,
            "--replacement", stagedApplicationURL.path,
            "--version", release.version,
            "--result", resultURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw AidenteUpdateError.updaterLaunchFailed(error.localizedDescription)
        }
    }

    private func presentErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AidenteL10n.t(
            "无法完成更新",
            "Unable to Complete the Update"
        )
        alert.informativeText = message
        alert.addButton(withTitle: AidenteL10n.t("好", "OK"))
        alert.addButton(withTitle: AidenteL10n.t("打开 GitHub", "Open GitHub"))
        present(alert) { response in
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(Self.releasesPageURL)
            }
        }
    }

    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        completion(alert.runModal())
    }

    private func consumeInstallResultIfNeeded() -> InstallResultOutcome {
        guard let resultURL = try? Self.updateResultURL(),
            let data = try? Data(contentsOf: resultURL),
            let result = try? JSONDecoder().decode(UpdateInstallResult.self, from: data)
        else {
            return .none
        }

        try? FileManager.default.removeItem(at: resultURL)
        if result.succeeded {
            phase = .installed(result.version)
            removeValidatedBackupIfPresent(result.backupPath)
            return .succeeded(result.version)
        } else {
            phase = .failed(result.message)
            return .failed(result.message)
        }
    }

    /// One prompt per launch. Automatic updates carry a version string; a
    /// manual /Applications replacement has no result file, so the copy is
    /// phrased around the changed app instead of a specific version.
    private func presentLaunchAuthorizationState(updatedVersion: String?) {
        let helper = ChargingHelperManager.shared
        helper.refreshStatus()

        guard !helper.isInstalled, Defaults[.manageCharging] else {
            if let updatedVersion {
                presentSuccessfulUpdateAlert(version: updatedVersion)
            }
            return
        }

        let title: String
        let englishTitle: String
        if let updatedVersion {
            title = "Aidente 已更新至 \(updatedVersion)，需要重新授权一次"
            englishTitle = "Aidente Was Updated to \(updatedVersion) — Re-authorization Needed"
        } else {
            title = "需要重新授权后台控制服务"
            englishTitle = "Background Control Service Needs Re-authorization"
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AidenteL10n.t(title, englishTitle)
        alert.informativeText = AidenteL10n.t(
            "主程序已改变，后台控制服务登记的身份不再匹配，充电管理暂时不可用。点击「立即重新授权」，通过 macOS 管理员弹窗重新登记即可恢复；无需开发者账号。",
            "The app changed, so the helper's pinned identity no longer matches and charging control is paused. Click Re-authorize Now to re-register through the macOS administrator prompt — no developer account needed."
        )
        alert.addButton(withTitle: AidenteL10n.t("立即重新授权", "Re-authorize Now"))
        alert.addButton(withTitle: AidenteL10n.t("稍后", "Later"))
        present(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in
                await self?.performReauthorization()
            }
        }
    }

    private func performReauthorization() async {
        do {
            try await ChargingHelperManager.shared.repair()
            controlRetryHandler?()
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = AidenteL10n.t("重新授权完成", "Re-authorization Complete")
            alert.informativeText = AidenteL10n.t(
                "后台控制服务已与当前 Aidente 重新匹配，充电管理已恢复。",
                "The helper now matches this Aidente build; charging control is available again."
            )
            alert.addButton(withTitle: AidenteL10n.t("好", "OK"))
            present(alert) { _ in }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = AidenteL10n.t("重新授权未完成", "Re-authorization Failed")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: AidenteL10n.t("好", "OK"))
            present(alert) { _ in }
        }
    }

    private func presentSuccessfulUpdateAlert(version: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AidenteL10n.t(
            "Aidente 已更新至 \(version)",
            "Aidente Was Updated to \(version)"
        )
        alert.informativeText = AidenteL10n.t(
            "新版本已成功启动，原版本备份已安全清理。",
            "The new version launched successfully and the old backup was safely removed."
        )
        alert.addButton(withTitle: AidenteL10n.t("好", "OK"))
        present(alert) { _ in }
    }

    private func removeValidatedBackupIfPresent(_ path: String?) {
        guard let path else { return }
        let backupURL = URL(fileURLWithPath: path).standardizedFileURL
        let applicationURL = Bundle.main.bundleURL.standardizedFileURL
        guard backupURL.deletingLastPathComponent() == applicationURL.deletingLastPathComponent(),
            backupURL.lastPathComponent.hasPrefix(".Aidente.backup-"),
            backupURL.pathExtension == "app"
        else {
            return
        }
        try? FileManager.default.removeItem(at: backupURL)
    }

    private var checkedTimeDescription: String {
        guard let lastCheckedAt else {
            return AidenteL10n.t("刚刚完成检查", "Checked just now")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AidenteL10n.isEnglish ? "en_US" : "zh_CN")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return AidenteL10n.t(
            "上次检查：\(formatter.string(from: lastCheckedAt))",
            "Last checked: \(formatter.string(from: lastCheckedAt))"
        )
    }

    private func formattedFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    nonisolated private static func verifyExtractAndStage(
        archiveURL: URL,
        workingDirectory: URL,
        release: AidenteUpdateRelease,
        installedApplicationURL: URL
    ) throws -> URL {
        let data = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        let actualDigest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualDigest == release.sha256 else {
            throw AidenteUpdateError.checksumMismatch
        }

        let extractionURL = workingDirectory.appendingPathComponent(
            "Extracted",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: extractionURL,
            withIntermediateDirectories: true
        )
        let extraction = runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archiveURL.path, extractionURL.path]
        )
        guard extraction.status == 0 else {
            throw AidenteUpdateError.extractionFailed(extraction.output)
        }

        let candidateURL = extractionURL.appendingPathComponent(
            "Aidente.app",
            isDirectory: true
        )
        guard let bundle = Bundle(url: candidateURL),
            FileManager.default.fileExists(atPath: candidateURL.path)
        else {
            throw AidenteUpdateError.invalidBundle
        }
        guard bundle.bundleIdentifier == "com.aidente.app" else {
            throw AidenteUpdateError.wrongBundleIdentifier
        }
        let bundleVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        guard bundleVersion == release.version else {
            throw AidenteUpdateError.wrongBundleVersion
        }

        let signature = runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--deep", "--strict", candidateURL.path]
        )
        guard signature.status == 0 else {
            throw AidenteUpdateError.invalidSignature(signature.output)
        }

        let executableURL = candidateURL.appendingPathComponent("Contents/MacOS/Aidente")
        let architecture = runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/lipo"),
            arguments: ["-archs", executableURL.path]
        )
        let architectures = architecture.output
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard architecture.status == 0, architectures.contains("arm64") else {
            throw AidenteUpdateError.unsupportedArchitecture
        }

        let parentURL = installedApplicationURL.deletingLastPathComponent()
        let stagedURL = parentURL.appendingPathComponent(
            ".Aidente.update-\(UUID().uuidString).app",
            isDirectory: true
        )
        try FileManager.default.copyItem(at: candidateURL, to: stagedURL)
        return stagedURL
    }

    private static func validatedInstallLocation() throws -> URL {
        let applicationURL = Bundle.main.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        if applicationURL.path.hasPrefix("/Volumes/") {
            throw AidenteUpdateError.runningFromDiskImage
        }

        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .standardizedFileURL
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
        let parent = applicationURL.deletingLastPathComponent()
        guard parent == systemApplications || parent == userApplications else {
            throw AidenteUpdateError.unsupportedInstallLocation
        }
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw AidenteUpdateError.installLocationNotWritable
        }
        return applicationURL
    }

    private static func updatesDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AidenteUpdateError.invalidDownload
        }
        let directory = applicationSupport
            .appendingPathComponent("Aidente", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func updateResultURL() throws -> URL {
        try updatesDirectory().appendingPathComponent("last-install-result.json")
    }

    nonisolated private static func normalizedVersion(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("v") {
            normalized.removeFirst()
        }
        return normalized
    }

    nonisolated private static func versionComponents(_ value: String) -> [Int] {
        normalizedVersion(value)
            .split(separator: ".")
            .map { component in
                let numericPrefix = component.prefix(while: { $0.isNumber })
                return Int(numericPrefix) ?? 0
            }
    }

    nonisolated private static func isStableNumericVersion(_ value: String) -> Bool {
        !value.isEmpty
            && value.range(
                of: #"^[0-9]+(?:\.[0-9]+)*$"#,
                options: .regularExpression
            ) != nil
    }

    nonisolated private static func sha256(
        for assetName: String,
        in checksumText: String
    ) -> String? {
        for line in checksumText.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, String(fields.last!) == assetName else {
                continue
            }
            let digest = String(fields[0]).lowercased()
            guard digest.count == 64,
                digest.allSatisfy({ $0.isHexDigit })
            else {
                return nil
            }
            return digest
        }
        return nil
    }

    nonisolated private static func isOfficialDownloadURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix(
                "/nightfall-yl/Aidente/releases/download/"
            )
    }

    nonisolated private static func isAllowedDownloadResponseURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "github.com"
            || host == "objects.githubusercontent.com"
            || host == "release-assets.githubusercontent.com"
    }

    nonisolated private static func runProcess(
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

    private static let previewRelease = AidenteUpdateRelease(
        version: "6.1",
        name: "Aidente 6.1",
        notes: "Update preview",
        pageURL: URL(
            string: "https://github.com/nightfall-yl/Aidente/releases/tag/v6.1"
        )!,
        assetName: "Aidente-6.1-macOS-arm64.zip",
        assetURL: URL(
            string: "https://github.com/nightfall-yl/Aidente/releases/download/v6.1/Aidente-6.1-macOS-arm64.zip"
        )!,
        assetSize: 2_500_000,
        sha256: String(repeating: "0", count: 64)
    )
}

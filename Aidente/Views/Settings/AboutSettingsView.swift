import AppKit
import Defaults
import SwiftUI

struct AboutSettingsView: View {
    @Default(.automaticallyCheckForUpdates) private var automaticallyCheckForUpdates

    let updateService: UpdateService

    /// Legal documents are read from the project's own GitHub repository so
    /// the text always matches the published source, not a bundled snapshot.
    private static let licenseURL = URL(
        string: "https://github.com/nightfall-yl/Aidente/blob/main/LICENSE"
    )!
    private static let thirdPartyNoticesURL = URL(
        string: "https://github.com/nightfall-yl/Aidente/blob/main/THIRD_PARTY_NOTICES.md"
    )!

    @State private var updateSheetTrigger: UpdateSheetTrigger?
    @State private var didCheckInitialPhase = false

    /// Read from the running bundle so the row always shows the real version.
    private var versionText: String {
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return "v\(updateService.currentVersion) (Build \(build))"
    }

    /// One sheet carries the whole flow: checking, no update, new release,
    /// download / verify / install, completion and failure. The settings card
    /// itself never grows a status row.
    private static func shouldPresentUpdateSheet(
        for phase: AidenteUpdatePhase
    ) -> Bool {
        if case .idle = phase { return false }
        return true
    }

    /// States reached before this page existed (launch install result, or an
    /// automatic check that found a release) are replayed once on appear. A
    /// stale "up to date" result must not pop up every time the tab opens.
    private static func shouldPresentOnAppear(
        for phase: AidenteUpdatePhase
    ) -> Bool {
        switch phase {
        case .available, .installed, .failed:
            true
        default:
            false
        }
    }

    /// While the sheet is open the trigger stays non-nil, so phase changes
    /// update its content live instead of re-presenting the window.
    private func presentUpdateSheet(for phase: AidenteUpdatePhase) {
        guard updateSheetTrigger == nil,
            Self.shouldPresentUpdateSheet(for: phase) else { return }
        updateSheetTrigger = UpdateSheetTrigger()
    }

    private struct UpdateSheetTrigger: Identifiable {
        let id = UUID()
    }

    var body: some View {
        AidenteSettingsPage {
            AidenteCard(
                "软件更新",
                subtitle: AidenteL10n.t(
                    "从 Aidente 官方 GitHub 发行版安全获取更新。",
                    "Get updates safely from Aidente's official GitHub Releases."
                ),
                icon: "arrow.triangle.2.circlepath.circle.fill",
                colors: AidenteTheme.permissionColors,
                subtitleLink: AidenteCardSubtitleLink(
                    phrase: "GitHub 发行版",
                    englishPhrase: "GitHub Releases",
                    url: UpdateService.releasesPageURL
                )
            ) {
                AidenteControlRow(
                    AidenteL10n.t("当前版本", "Current Version"),
                    subtitle: versionText,
                    icon: "number.circle.fill",
                    colors: AidenteTheme.permissionColors
                ) {
                    Button {
                        updateService.performPrimaryAction()
                    } label: {
                        Label(
                            updateService.primaryActionTitle,
                            systemImage: updateService.availableRelease == nil
                                ? "arrow.clockwise"
                                : "arrow.down.app.fill"
                        )
                    }
                    .buttonStyle(
                        AidenteActionButtonStyle(colors: AidenteTheme.permissionColors)
                    )
                    .disabled(updateService.isBusy)
                }

                AidenteRowDivider()

                AidenteSettingToggle(
                    "自动检查更新",
                    subtitle: "启动后检查，并每隔六小时检查一次正式发行版。",
                    icon: "clock.arrow.2.circlepath",
                    colors: AidenteTheme.permissionColors,
                    isOn: $automaticallyCheckForUpdates
                )
            }

            AidenteCard(
                "法律与开源",
                subtitle: "开源许可、商标与安全声明。",
                icon: "shield",
                colors: AidenteTheme.generalColors
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    legalBlock(
                        title: AidenteL10n.t("安全说明"),
                        body: AidenteL10n.t(
                            "Aidente 会调整底层电池充电控制。设备不支持某项能力时，软件会自动退回只读监测模式。你可以随时关闭“管理充电”，恢复系统默认充电状态。"
                        )
                    )

                    AidenteRowDivider()

                    legalBlock(
                        title: AidenteL10n.t("商标声明"),
                        body: AidenteL10n.t(
                            "Aidente 是独立项目，与 AppHouseKitchen 不存在隶属、授权或分发关系。AlDente 是其各自权利人的商标。"
                        )
                    )

                    AidenteRowDivider()

                    legalBlock(
                        title: AidenteL10n.t("开放源代码"),
                        body: AidenteL10n.t(
                            "Aidente 是基于开源 Stasis 项目修改的 GPL-3.0 软件，并使用 SMCKit 与 Defaults 开源组件。"
                        )
                    )

                    HStack(spacing: 10) {
                        Button {
                            NSWorkspace.shared.open(Self.licenseURL)
                        } label: {
                            Label(
                                AidenteL10n.t("查看开源许可证"),
                                systemImage: "doc.text.fill"
                            )
                        }
                        .buttonStyle(
                            AidenteActionButtonStyle(colors: AidenteTheme.generalColors)
                        )

                        Button {
                            NSWorkspace.shared.open(Self.thirdPartyNoticesURL)
                        } label: {
                            Label(
                                AidenteL10n.t("查看第三方声明", "View Third-Party Notices"),
                                systemImage: "doc.plaintext.fill"
                            )
                        }
                        .buttonStyle(
                            AidenteActionButtonStyle(colors: AidenteTheme.generalColors)
                        )
                    }
                    .padding(.top, 4)
                }
            }
        }
        .onAppear {
            guard !didCheckInitialPhase else { return }
            didCheckInitialPhase = true
            let phase = updateService.phase
            guard Self.shouldPresentOnAppear(for: phase) else { return }
            presentUpdateSheet(for: phase)
        }
        .onChange(of: automaticallyCheckForUpdates) { _, _ in
            updateService.automaticCheckPreferenceChanged()
        }
        .onChange(of: updateService.phase) { _, newPhase in
            if case .installing = newPhase {
                // The app is handing off to the external updater and will call
                // NSApplication.terminate. A presented sheet keeps a modal
                // session alive that blocks termination, so dismiss it first.
                updateSheetTrigger = nil
            } else {
                presentUpdateSheet(for: newPhase)
            }
        }
        .sheet(item: $updateSheetTrigger) { _ in
            UpdateProgressSheet(updateService: updateService)
        }
    }

    private func legalBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Every update state lives in one sheet. It reads `UpdateService.phase` live,
/// so a check result replaces "checking" without re-presenting the window.
/// The panel shows only the current state: icon, title, one line of detail and
/// (for results) a version capsule — no header row, stage list, progress bar
/// or status notice.
private struct UpdateProgressSheet: View {
    @Environment(\.dismiss) private var dismiss

    let updateService: UpdateService

    private var tint: Color {
        AidenteTheme.permissionColors.first ?? AidenteTheme.ocean
    }

    private var phase: AidenteUpdatePhase { updateService.phase }

    private var subtitle: String {
        switch phase {
        case .idle:
            "Aidente"
        case .checking:
            AidenteL10n.t(
                "正在连接 nightfall-yl/Aidente",
                "Connecting to nightfall-yl/Aidente"
            )
        case .upToDate:
            "Aidente \(updateService.currentVersion) · "
                + AidenteL10n.t("检查完成", "Check Complete")
        case .available(let release):
            "Aidente \(release.version) · "
                + AidenteL10n.t("可更新", "Update Available")
        case .downloading(let release), .preparing(let release),
            .installing(let release):
            "Aidente \(release.version) · "
                + AidenteL10n.t("正在后台更新", "Updating in the Background")
        case .installed(let version):
            "Aidente \(version) · "
                + AidenteL10n.t("更新完成", "Update Complete")
        case .failed:
            "Aidente · " + AidenteL10n.t("更新未完成", "Update Not Completed")
        }
    }

    private var versionBadge: String? {
        switch phase {
        case .upToDate: "v\(updateService.currentVersion)"
        case .available(let release): "v\(release.version)"
        default: nil
        }
    }

    private enum SheetAction {
        case available(String)
        case failed
        case done
        case background
        case cancellable
    }

    private var action: SheetAction {
        switch phase {
        case .available(let release): .available(release.version)
        case .failed: .failed
        case .upToDate, .installed: .done
        case .downloading, .preparing: .cancellable
        case .installing: .background
        default: .background
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AidenteIconBadge(
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    colors: AidenteTheme.permissionColors,
                    size: 34
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(AidenteL10n.t("软件更新", "Software Update"))
                        .font(.system(size: 17, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            AidenteInsetPanel {
                HStack(spacing: 12) {
                    AidenteIconBadge(
                        icon: updateService.statusIcon,
                        colors: AidenteTheme.permissionColors,
                        size: 28
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(updateService.statusTitle)
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(updateService.statusDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if let versionBadge {
                        Text(versionBadge)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(tint.opacity(0.12)))
                    }
                }
                .padding(5)
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                actionButtons
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch action {
        case .available(let version):
            secondaryButton(
                AidenteL10n.t("跳过这个版本", "Skip This Version")
            ) {
                dismiss()
                updateService.skipVersion(version)
            }

            Button {
                updateService.installAvailableUpdate()
            } label: {
                Label(
                    AidenteL10n.t("立即更新", "Update Now"),
                    systemImage: "arrow.down.app.fill"
                )
            }
            .buttonStyle(
                AidenteActionButtonStyle(colors: AidenteTheme.permissionColors)
            )

        case .failed:
            secondaryButton(AidenteL10n.t("关闭", "Close")) {
                dismiss()
            }

            Button {
                dismiss()
                updateService.checkForUpdates()
            } label: {
                Label(
                    AidenteL10n.t("重试", "Retry"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(
                AidenteActionButtonStyle(colors: AidenteTheme.permissionColors)
            )

        case .done:
            Button {
                dismiss()
            } label: {
                Label(
                    AidenteL10n.t("完成", "Done"),
                    systemImage: "checkmark"
                )
            }
            .buttonStyle(
                AidenteActionButtonStyle(colors: AidenteTheme.permissionColors)
            )

        case .cancellable:
            secondaryButton(
                AidenteL10n.t("取消更新", "Cancel Update")
            ) {
                dismiss()
                updateService.cancelInstall()
            }

            Button {
                dismiss()
            } label: {
                Label(
                    AidenteL10n.t("后台继续", "Continue in Background"),
                    systemImage: "arrow.right"
                )
            }
            .buttonStyle(
                AidenteActionButtonStyle(colors: AidenteTheme.permissionColors)
            )

        case .background:
            Button {
                dismiss()
            } label: {
                Label(
                    AidenteL10n.t("后台继续", "Continue in Background"),
                    systemImage: "arrow.right"
                )
            }
            .buttonStyle(
                AidenteActionButtonStyle(colors: AidenteTheme.permissionColors)
            )
        }
    }

    private func secondaryButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}

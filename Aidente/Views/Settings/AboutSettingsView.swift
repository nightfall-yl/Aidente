import AppKit
import Defaults
import SwiftUI

struct AboutSettingsView: View {
    @Default(.automaticallyCheckForUpdates) private var automaticallyCheckForUpdates

    let updateService: UpdateService

    /// One card = one color pair: the status panel, toggle, version readout
    /// and action buttons all use the Software Update card's own tint.
    private var updateTint: Color {
        AidenteTheme.permissionColors.first ?? AidenteTheme.ocean
    }

    var body: some View {
        AidenteSettingsPage {
            AidenteCard(
                "软件更新",
                subtitle: "从 Aidente 官方 GitHub 发行版安全获取更新。",
                icon: "arrow.triangle.2.circlepath.circle.fill",
                colors: AidenteTheme.permissionColors
            ) {
                // The status panel only appears once a check has run. In the
                // idle phase it would just repeat the card subtitle ("waiting
                // to check", "source: GitHub Releases") above the auto-check
                // toggle, so the card opens with just the toggle and buttons.
                if updateService.phase != .idle {
                    AidenteInsetPanel {
                        HStack(spacing: 12) {
                            Image(systemName: updateService.statusIcon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(updateTint)
                                .frame(width: 34, height: 34)
                                .background(
                                    updateTint.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(updateService.statusTitle)
                                    .font(.system(size: 13.5, weight: .semibold))
                                Text(updateService.statusDetail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 12)

                            Text("v\(updateService.currentVersion)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(updateTint)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(updateTint.opacity(0.12))
                                )
                        }

                        if updateService.isBusy {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(updateTint)
                        }
                    }
                }

                AidenteSettingToggle(
                    "自动检查更新",
                    subtitle: "启动后检查，并每隔六小时检查一次正式发行版。",
                    icon: "clock.arrow.2.circlepath",
                    colors: AidenteTheme.permissionColors,
                    isOn: $automaticallyCheckForUpdates
                )

                AidenteRowDivider()

                HStack(spacing: 10) {
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

                    Button {
                        updateService.openReleasePage()
                    } label: {
                        Label(
                            AidenteL10n.t("查看 GitHub 发行版", "View GitHub Releases"),
                            systemImage: "safari.fill"
                        )
                    }
                    .buttonStyle(
                        AidenteActionButtonStyle(colors: AidenteTheme.permissionColors)
                    )
                }
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
                            openBundledDocument(named: "LICENSE", extension: "txt")
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
                            openBundledDocument(named: "THIRD_PARTY_NOTICES", extension: "md")
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
        .onChange(of: automaticallyCheckForUpdates) { _, _ in
            updateService.automaticCheckPreferenceChanged()
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

    /// Opens a resource shipped in the app bundle; missing files fail
    /// silently instead of crashing the About page.
    private func openBundledDocument(named name: String, extension ext: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

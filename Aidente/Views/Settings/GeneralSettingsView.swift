import Defaults
import SwiftUI
import smc_power

struct GeneralSettingsView: View {
    @Default(.appLanguage) var appLanguage
    @Default(.launchAtLogin) var launchAtLogin
    @Default(.batteryPercentageDisplayLocation) var batteryPercentageDisplayLocation
    @Default(.menuBarReadoutStyle) var menuBarReadoutStyle
    @Default(.showBatteryStateInStatusIcon) var showBatteryStateInStatusIcon
    @Default(.useHardwarePercentage) var useHardwarePercentage
    @Default(.forceOpaqueBackground) var forceOpaqueBackground
    @Default(.appAppearance) var appAppearance
    @Default(.manageMagSafeLED) var manageMagSafeLED
    @Default(.heatProtectionMagSafeLEDState) var heatProtectionMagSafeLEDState
    @Default(.enableHeatProtectionMode) var enableHeatProtectionMode
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let capabilities: DeviceCapabilities

    init(capabilities: DeviceCapabilities) {
        self.capabilities = capabilities
    }

    /// The card reports the app-wide policy, not the settings window's own
    /// container capability. That window always renders an opaque baseline
    /// because it cannot sample a backdrop; the explanation still describes
    /// what the system would supply on a capable surface.
    private var resolution: AidenteReadabilityResolution {
        AidenteReadability.resolve(
            reduceTransparency: reduceTransparency,
            forceOpaque: forceOpaqueBackground,
            canSampleBackdrop: true
        )
    }

    var body: some View {
        AidenteSettingsPage {
            AidenteCard(
                "语言",
                subtitle: "切换菜单栏和设置界面的显示语言。",
                icon: "character.bubble.fill",
                colors: AidenteTheme.generalColors
            ) {
                Picker(AidenteL10n.t("语言"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title)
                            .tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .id(appLanguage)
            }

            AidenteCard(
                "外观",
                subtitle: resolution.strategy.detail,
                icon: "paintbrush.fill",
                colors: AidenteTheme.generalColors
            ) {
                Picker(AidenteL10n.t("外观模式"), selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .id(appLanguage)

                AidenteRowDivider()

                AidenteSettingToggle(
                    "始终使用不透明背景",
                    subtitle: "系统「降低透明度」开启时，无论此开关状态如何，都会强制使用不透明背景。",
                    icon: "rectangle.inset.filled",
                    colors: AidenteTheme.dashboardColors,
                    isOn: $forceOpaqueBackground
                )
            }

            AidenteCard(
                "启动",
                subtitle: "让电池保护在登录后自动开始工作。",
                icon: "power.circle.fill",
                colors: AidenteTheme.generalColors
            ) {
                AidenteSettingToggle(
                    "登录时启动 Aidente",
                    subtitle: "登录后自动启动，并在菜单栏显示图标",
                    icon: "arrow.up.forward.app.fill",
                    colors: AidenteTheme.generalColors,
                    isOn: $launchAtLogin
                )
            }

            AidenteCard(
                "菜单栏实时读数",
                subtitle: "在电量、功率或两者同时显示之间切换。",
                icon: "gauge.with.dots.needle.67percent",
                colors: AidenteTheme.chargingColors
            ) {
                Picker(AidenteL10n.t("菜单栏显示内容"), selection: $menuBarReadoutStyle) {
                    ForEach(MenuBarReadoutStyle.allCases) { style in
                        Label(style.title, systemImage: style.icon)
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .id(appLanguage)

                if menuBarReadoutStyle == .batteryPercentage {
                    AidenteRowDivider()

                    AidenteControlRow(
                        "电量数字位置",
                        icon: "percent",
                        colors: AidenteTheme.chargingColors
                    ) {
                        Picker("", selection: $batteryPercentageDisplayLocation) {
                            Text(AidenteL10n.t("不显示")).tag(PercentageDisplayLocation.hidden)
                            Text(AidenteL10n.t("图标旁")).tag(PercentageDisplayLocation.nextToIcon)
                            Text(AidenteL10n.t("图标内")).tag(PercentageDisplayLocation.insideIcon)
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }

                AidenteRowDivider()

                AidenteSettingToggle(
                    "使用颜色显示电池状态",
                    subtitle: "充电、接通电源、低电量使用不同颜色",
                    icon: "paintpalette.fill",
                    colors: AidenteTheme.chargingColors,
                    isOn: $showBatteryStateInStatusIcon
                )

                AidenteRowDivider()

                // Moved from the charging page's "电量读取方式" card; the row
                // inherits this card's charging colors via the card environment.
                AidenteSettingToggle(
                    "使用硬件电量百分比",
                    subtitle: "直接读取电池管理系统的原始数值，而不是 macOS 校准后的显示值",
                    icon: "battery.100.bolt",
                    colors: AidenteTheme.chargingColors,
                    isOn: $useHardwarePercentage
                )

                AidenteNotice(
                    text: "硬件电量通常会与菜单栏中的 macOS 电量相差几个百分点。切换后，所有充电策略都将使用所选读数。",
                    icon: "info.circle.fill",
                    colors: AidenteTheme.chargingColors
                )
            }

            // Moved from the charging page; still gated by the device's
            // MagSafe capability, and the heat-protection row follows the
            // heat-protection preference owned by the charging page.
            if capabilities.hasMagSafe {
                AidenteCard(
                    "MagSafe 指示灯",
                    subtitle: "在受支持机型上用颜色显示充电、暂停和保护状态。",
                    icon: "lightbulb.led.fill",
                    colors: AidenteTheme.automationColors
                ) {
                    AidenteSettingToggle(
                        "由 Aidente 控制指示灯",
                        icon: "lightbulb.fill",
                        colors: AidenteTheme.automationColors,
                        isOn: $manageMagSafeLED
                    )
                    .disabled(!capabilities.magsafeLEDControl)
                    .opacity(capabilities.magsafeLEDControl ? 1 : 0.5)

                    if manageMagSafeLED && enableHeatProtectionMode {
                        AidenteRowDivider()
                        AidenteControlRow(
                            "高温保护时的灯光",
                            icon: "lightspectrum.horizontal",
                            colors: AidenteTheme.automationColors
                        ) {
                            Picker("", selection: $heatProtectionMagSafeLEDState) {
                                Text(AidenteL10n.t("关闭")).tag(MagSafeLEDState.off)
                                Text(AidenteL10n.t("绿色")).tag(MagSafeLEDState.green)
                                Text(AidenteL10n.t("橙色")).tag(MagSafeLEDState.orange)
                                Text(AidenteL10n.t("橙色慢闪"))
                                    .tag(MagSafeLEDState.blinkOrangeSlow)
                                Text(AidenteL10n.t("橙色快闪"))
                                    .tag(MagSafeLEDState.blinkOrangeFast)
                            }
                            .labelsHidden()
                            .frame(width: 140)
                        }
                    }

                    if !capabilities.magsafeLEDControl {
                        AidenteNotice(text: "当前设备不支持 MagSafe 指示灯控制。")
                    }
                }
            }
        }
        .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLoginService.shared.setLaunchAtLogin(newValue)
        }
        .animation(.default, value: manageMagSafeLED)
    }
}

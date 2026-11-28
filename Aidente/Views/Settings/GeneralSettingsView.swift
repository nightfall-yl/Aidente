import AppKit
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
    @Default(.appAppearance) var appAppearance

    private let capabilities: DeviceCapabilities

    init(capabilities: DeviceCapabilities) {
        self.capabilities = capabilities
    }

    var body: some View {
        AidenteSettingsPage {
            // 2026-11-18 用户指令：语言 / 外观合并为一张卡，卡头外置只有标题、无徽章。
            AidenteCard(
                "语言与外观",
                icon: "character.bubble.fill",
                colors: AidenteTheme.generalColors,
                headerOutside: true,
                showsHeaderBadge: false
            ) {
                AidenteControlRow(
                    "语言",
                    subtitle: "切换菜单栏和设置界面的显示语言。",
                    icon: "character.bubble.fill",
                    colors: AidenteTheme.generalColors
                ) {
                    AidenteMenuPicker(
                        options: AidenteMenuOption<AppLanguage>.options(for: \.title),
                        selection: $appLanguage
                    )
                }

                AidenteRowDivider()

                AidenteControlRow(
                    "外观",
                    subtitle: "选择浅色、深色，或跟随系统。",
                    icon: "paintbrush.fill",
                    colors: AidenteTheme.generalColors
                ) {
                    AidenteMenuPicker(
                        options: AidenteMenuOption<AppAppearance>.options(for: \.title),
                        selection: $appAppearance
                    )
                }
            }

            // 2026-11-18 用户指令：菜单栏提前到第二张。
            // v2: the card is titled "菜单栏"; the old title/subtitle became
            // the first setting row, with the same popup-list control language.
            AidenteCard(
                "菜单栏",
                icon: "gauge.with.dots.needle.67percent",
                colors: AidenteTheme.chargingColors,
                headerOutside: true,
                showsHeaderBadge: false
            ) {
                AidenteControlRow(
                    "菜单栏实时读数",
                    icon: "gauge.with.dots.needle.67percent",
                    colors: AidenteTheme.chargingColors
                ) {
                    AidenteMenuPicker(
                        options: AidenteMenuOption<MenuBarReadoutStyle>.options(for: \.title),
                        selection: $menuBarReadoutStyle
                    )
                }

                if menuBarReadoutStyle == .batteryPercentage {
                    AidenteRowDivider()

                    AidenteControlRow(
                        "电量数字位置",
                        icon: "percent",
                        colors: AidenteTheme.chargingColors
                    ) {
                        AidenteMenuPicker(
                            options: [
                                AidenteMenuOption<PercentageDisplayLocation>(
                                    title: AidenteL10n.t("不显示", "Hidden"),
                                    value: PercentageDisplayLocation.hidden
                                ),
                                AidenteMenuOption<PercentageDisplayLocation>(
                                    title: AidenteL10n.t("图标旁", "Next to Icon"),
                                    value: PercentageDisplayLocation.nextToIcon
                                ),
                                AidenteMenuOption<PercentageDisplayLocation>(
                                    title: AidenteL10n.t("图标内", "Inside Icon"),
                                    value: PercentageDisplayLocation.insideIcon
                                ),
                            ],
                            selection: $batteryPercentageDisplayLocation
                        )
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

            // 2026-11-18 用户定：登录时启动改用 amber/gold（automation 色对），启动语义。
            AidenteCard(
                "登录时启动",
                icon: "power.circle.fill",
                colors: AidenteTheme.automationColors,
                headerOutside: true,
                showsHeaderBadge: false
            ) {
                AidenteSettingToggle(
                    "登录时启动 Aidente",
                    subtitle: "登录后自动启动，并在菜单栏显示图标",
                    icon: "arrow.up.forward.app.fill",
                    colors: AidenteTheme.automationColors,
                    isOn: $launchAtLogin
                )
            }

            // 2026-11-27：从「仪表盘」tab 原样搬移（headless，无卡头）。
            AidenteCard(
                "访问仪表盘",
                icon: "macwindow.on.rectangle",
                colors: AidenteTheme.automationColors,
                headless: true
            ) {
                AidenteControlRow(
                    "访问仪表盘",
                    subtitle: "菜单栏图标被系统折叠时，仍然可以打开完整仪表盘。",
                    icon: "macwindow.on.rectangle",
                    colors: AidenteTheme.automationColors
                ) {
                    Button {
                        if let url = URL(string: "aidente://dashboard") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label(AidenteL10n.t("打开仪表盘"), systemImage: "macwindow")
                    }
                    .buttonStyle(
                        AidenteActionButtonStyle(colors: AidenteTheme.automationColors)
                    )
                }
            }
        }
        .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLoginService.shared.setLaunchAtLogin(newValue)
        }
    }
}

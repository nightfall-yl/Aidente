import AppKit
import Defaults
import SwiftUI

struct DashboardSettingsView: View {
    @Default(.appLanguage) private var appLanguage

    @Default(.showPowerSource) var showPowerSource
    @Default(.showTimeTillDischarge) var showTimeTillDischarge
    @Default(.showUptime) var showUptime
    @Default(.showInternalPower) var showInternalPower
    @Default(.showExternalPower) var showExternalPower

    var body: some View {
        AidenteSettingsPage {
            AidenteCard(
                "访问仪表盘",
                subtitle: "菜单栏图标被系统折叠时，仍然可以打开完整仪表盘。",
                icon: "macwindow.on.rectangle",
                colors: AidenteTheme.dashboardColors
            ) {
                AidenteNotice(
                    text: "双击“应用程序”文件夹、启动台或聚焦搜索中的 Aidente 图标，即可打开独立仪表盘窗口。",
                    icon: "cursorarrow.click.2",
                    colors: AidenteTheme.dashboardColors
                )

                Button {
                    if let url = URL(string: "aidente://dashboard") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(AidenteL10n.t("打开仪表盘"), systemImage: "macwindow")
                }
                .buttonStyle(AidenteActionButtonStyle(colors: AidenteTheme.dashboardColors))
            }

            AidenteCard(
                "状态信息",
                subtitle: "选择仪表盘顶部显示的系统与电池时间信息。",
                icon: "gauge.with.dots.needle.67percent",
                colors: AidenteTheme.dashboardColors
            ) {
                AidenteSettingToggle(
                    "系统运行时间",
                    icon: "clock.fill",
                    colors: [AidenteTheme.violet, AidenteTheme.pink],
                    isOn: $showUptime
                )
                AidenteRowDivider()
                AidenteSettingToggle(
                    "电池剩余时间",
                    icon: "hourglass.bottomhalf.filled",
                    colors: AidenteTheme.automationColors,
                    isOn: $showTimeTillDischarge
                )
            }

            AidenteCard(
                "实时功率",
                subtitle: "显示电池与电源适配器的电压、电流和功率。",
                icon: "waveform.path.ecg.rectangle.fill",
                colors: AidenteTheme.generalColors
            ) {
                AidenteSettingToggle(
                    "电源来源",
                    icon: "powerplug.fill",
                    colors: [AidenteTheme.ocean, AidenteTheme.sky],
                    isOn: $showPowerSource
                )
                AidenteRowDivider()
                AidenteSettingToggle(
                    "电池功率数据",
                    icon: "battery.50percent",
                    colors: AidenteTheme.chargingColors,
                    isOn: $showInternalPower
                )
                AidenteRowDivider()
                AidenteSettingToggle(
                    "适配器功率数据",
                    icon: "powerplug.fill",
                    colors: AidenteTheme.generalColors,
                    isOn: $showExternalPower
                )
            }
        }
    }
}

import AppKit
import Defaults
import SwiftUI

struct DashboardSettingsView: View {
    @Default(.showPowerSourceTitle) var showPowerSourceTitle
    @Default(.showPowerElectricalSubtitle) var showPowerElectricalSubtitle
    @Default(.showPowerFlowSheen) var showPowerFlowSheen

    var body: some View {
        AidenteSettingsPage {
            AidenteCard(
                "控制面板",
                icon: "gauge.with.dots.needle.67percent",
                colors: AidenteTheme.chargingColors,
                headerOutside: true,
                showsHeaderBadge: false
            ) {
                // 2026-11-24 用户定：流动光效放第三行
                AidenteSettingToggle(
                    "电源适配器",
                    icon: "powerplug.fill",
                    colors: AidenteTheme.dashboardColors,
                    isOn: $showPowerSourceTitle
                )
                AidenteRowDivider()
                AidenteSettingToggle(
                    "电压与电流",
                    icon: "bolt.horizontal.circle.fill",
                    colors: AidenteTheme.dashboardColors,
                    isOn: $showPowerElectricalSubtitle
                )
                AidenteRowDivider()
                AidenteSettingToggle(
                    "流动光效",
                    icon: "sparkles",
                    colors: AidenteTheme.dashboardColors,
                    isOn: $showPowerFlowSheen
                )
            }

            // v2: no header. The title is a setting row (13pt) and the action
            // button sits at that row's trailing edge.
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
    }
}

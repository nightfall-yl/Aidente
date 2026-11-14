import AppKit
import Defaults
import SwiftUI

struct DashboardSettingsView: View {
    @Default(.showTimeTillDischarge) var showTimeTillDischarge
    @Default(.showUptime) var showUptime

    var body: some View {
        AidenteSettingsPage {
            AidenteCard(
                "状态信息",
                subtitle: "选择仪表盘顶部显示的系统与电池时间信息。",
                icon: "gauge.with.dots.needle.67percent",
                colors: AidenteTheme.dashboardColors
            ) {
                AidenteSettingToggle(
                    "系统运行时间",
                    icon: "clock.fill",
                    colors: AidenteTheme.dashboardColors,
                    isOn: $showUptime
                )
                AidenteRowDivider()
                AidenteSettingToggle(
                    "电池剩余时间",
                    icon: "hourglass.bottomhalf.filled",
                    colors: AidenteTheme.dashboardColors,
                    isOn: $showTimeTillDischarge
                )
            }

            /* The notice repeated the subtitle, so the card is header-only:
               no content rows and no header divider; the action button sits
               to the right of the title. */
            AidenteCard(
                "访问仪表盘",
                subtitle: "菜单栏图标被系统折叠时，仍然可以打开完整仪表盘。",
                icon: "macwindow.on.rectangle",
                colors: AidenteTheme.automationColors,
                showDivider: false,
                headerAccessory: {
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
            ) {
                EmptyView()
            }
        }
    }
}

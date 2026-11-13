import Defaults
import SwiftUI
import smc_power

struct PermissionsSettingsView: View {
    @Default(.disableSleepUntilChargeLimit) var disableSleepUntilChargeLimit
    @Default(.stopChargingWhenAppClosed) var stopChargingWhenAppClosed
    @Default(.stopChargingWhileSleeping) var stopChargingWhileSleeping

    private let capabilities: DeviceCapabilities

    init(capabilities: DeviceCapabilities) {
        self.capabilities = capabilities
    }

    private var hasChargingControl: Bool {
        capabilities.chargingControl
    }

    var body: some View {
        AidenteSettingsPage {
            // 自「充电管理」页移入并更名（2026-11-12）；本页首卡，颜色与
            // 页标题（advanced 靛，与仪表盘互换后）一致。
            AidenteCard(
                "睡眠行为",
                subtitle: "决定 Mac 睡眠以及 Aidente 未运行时如何保持充电状态。",
                icon: "moon.stars.fill",
                colors: AidenteTheme.advancedColors
            ) {
                AidenteSettingToggle(
                    "达到上限前阻止睡眠",
                    subtitle: "仅阻止因长时间无操作而自动睡眠，合盖仍会睡眠。",
                    icon: "moon.zzz.fill",
                    colors: AidenteTheme.dashboardColors,
                    isOn: $disableSleepUntilChargeLimit
                )
                .disabled(!hasChargingControl)
                .opacity(hasChargingControl ? 1 : 0.5)

                AidenteRowDivider()
                AidenteSettingToggle(
                    "睡眠时暂停充电",
                    subtitle: "进入睡眠（含合盖）时暂停充电。",
                    icon: "bed.double.fill",
                    colors: [AidenteTheme.ocean, AidenteTheme.violet],
                    isOn: $stopChargingWhileSleeping
                )
                .disabled(!hasChargingControl)
                .opacity(hasChargingControl ? 1 : 0.5)

                AidenteRowDivider()
                AidenteSettingToggle(
                    "退出 Aidente 后保持暂停",
                    subtitle: "退出后保持充电受控状态。",
                    icon: "door.left.hand.closed",
                    colors: [AidenteTheme.coral, AidenteTheme.amber],
                    isOn: $stopChargingWhenAppClosed
                )
                .disabled(!hasChargingControl)
                .opacity(hasChargingControl ? 1 : 0.5)
            }
        }
    }
}

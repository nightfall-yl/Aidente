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

    var body: some View {
        AidenteSettingsPage {
            // 自「充电管理」页移入并更名（2026-11-12）；本页首卡，颜色与
            // 页标题（dashboard 紫，2026-11-27 由 advanced 靛改来）一致。
            // v2: this page has a single card, so the header is removed and
            // only the card body remains (headless).
            AidenteCard(
                "睡眠行为",
                icon: "moon.stars.fill",
                colors: AidenteTheme.dashboardColors,
                headless: true
            ) {
                AidenteSettingToggle(
                    "达到上限前阻止睡眠",
                    subtitle: "仅阻止因长时间无操作而自动睡眠，合盖仍会睡眠。",
                    icon: "moon.zzz.fill",
                    colors: AidenteTheme.dashboardColors,
                    isOn: $disableSleepUntilChargeLimit
                )
                .aidenteGated(capabilities.chargingControl)

                AidenteRowDivider()
                AidenteSettingToggle(
                    "睡眠时暂停充电",
                    subtitle: "进入睡眠（含合盖）时暂停充电。",
                    icon: "bed.double.fill",
                    colors: [AidenteTheme.ocean, AidenteTheme.violet],
                    isOn: $stopChargingWhileSleeping
                )
                .aidenteGated(capabilities.chargingControl)

                AidenteRowDivider()
                AidenteSettingToggle(
                    "退出 Aidente 后保持暂停",
                    subtitle: "退出后保持充电受控状态。",
                    icon: "door.left.hand.closed",
                    colors: [AidenteTheme.coral, AidenteTheme.amber],
                    isOn: $stopChargingWhenAppClosed
                )
                .aidenteGated(capabilities.chargingControl)
            }
        }
    }
}

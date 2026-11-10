import Foundation

/// 充电器统一显示名。数据来自 `AdapterMetrics`（由 `IOKitService` 从 IOKit
/// `AppleSmartBattery.AdapterDetails` 读取，并随插拔事件自动刷新），本文件只负责把其中的
/// 制造商 / 是否 Apple / 功率 / PD 协议信息翻译成本地化显示名，不再单独读取 IOKit。
///
/// 显示名五态（统一使用「电源适配器」一词，英文 "Power Adapter"，避免中英混搭）：
/// - 未连接电源                          → 未连接电源 / No Power Source
/// - 接电但无 PD 元数据（协议名非 USB PD）→ USB 电源适配器 / USB Power Adapter
/// - Apple（manufacturer 含 "Apple"）     → XXW Apple 电源适配器
/// - 第三方有制造商                       → XXW {制造商} 电源适配器
/// - 第三方无制造商                       → XXW PD 电源适配器
enum ChargerInfoProvider {
    static func displayName(adapter: AdapterMetrics) -> String {
        guard adapter.adapterConnected else {
            return AidenteL10n.t("未连接电源", "No Power Source")
        }

        let isPD = !adapter.powerProfiles.isEmpty || adapter.protocolName == "USB PD"
        guard isPD else {
            return AidenteL10n.t("USB 电源适配器", "USB Power Adapter")
        }

        let wattPrefix: String
        if adapter.maximumSupportedPower > 0 {
            wattPrefix = "\(Int(adapter.maximumSupportedPower.rounded()))W "
        } else {
            wattPrefix = ""
        }

        if adapter.isApple {
            return AidenteL10n.t(
                "\(wattPrefix)Apple 电源适配器",
                "\(wattPrefix)Apple Power Adapter"
            )
        }
        if let maker = adapter.manufacturer, !maker.isEmpty {
            return AidenteL10n.t(
                "\(wattPrefix)\(maker) 电源适配器",
                "\(wattPrefix)\(maker) Power Adapter"
            )
        }
        return AidenteL10n.t(
            "\(wattPrefix)PD 电源适配器",
            "\(wattPrefix)PD Power Adapter"
        )
    }
}

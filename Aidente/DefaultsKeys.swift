import Defaults
import Foundation
import smc_power

enum AidenteRuntime {
    static let isUIPreview = CommandLine.arguments.contains("--ui-preview")
}

enum AidenteMigration {
    private static let legacyBundleIdentifier = "com.iadente.app"
    private static let migrationMarker = "didMigrateLegacyPreferencesV1"

    static func migrateLegacyPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationMarker) else { return }

        let currentBundleIdentifier =
            Bundle.main.bundleIdentifier ?? "com.aidente.app"
        let currentValues =
            defaults.persistentDomain(forName: currentBundleIdentifier) ?? [:]

        if let legacyValues = defaults.persistentDomain(
            forName: legacyBundleIdentifier
        ) {
            for (key, value) in legacyValues where currentValues[key] == nil {
                defaults.set(value, forKey: key)
            }
        }

        defaults.set(true, forKey: migrationMarker)
    }
}

extension MagSafeLEDState: Defaults.Serializable {}

enum AppLanguage: String, Defaults.Serializable, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: AidenteL10n.t("跟随系统", "System")
        case .simplifiedChinese: AidenteL10n.t("中文", "Chinese")
        case .english: AidenteL10n.t("英语", "English")
        }
    }
}

enum AppAppearance: String, Defaults.Serializable, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: AidenteL10n.t("自动", "Auto")
        case .light: AidenteL10n.t("浅色", "Light")
        case .dark: AidenteL10n.t("深色", "Dark")
        }
    }
}

enum PercentageDisplayLocation: String, Defaults.Serializable, CaseIterable, Identifiable {
    case hidden
    case nextToIcon
    case insideIcon

    var id: String { rawValue }
}

enum MenuBarReadoutStyle: String, Defaults.Serializable, CaseIterable, Identifiable {
    case batteryPercentage
    case systemPower
    case batteryAndPower

    var id: String { rawValue }

    var title: String {
        switch self {
        case .batteryPercentage: AidenteL10n.t("电量", "Battery")
        case .systemPower: AidenteL10n.t("功率", "Power")
        case .batteryAndPower: AidenteL10n.t("电量 + 功率", "Battery + Power")
        }
    }
}

// The four-way interface material picker has been retired. macOS supplies
// the material and the app follows the system's readability settings.

extension Defaults.Keys {
    // General
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)
    static let appAppearance = Key<AppAppearance>("appAppearance", default: .dark)
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let automaticallyCheckForUpdates = Key<Bool>(
        "automaticallyCheckForUpdates", default: true)
    /// Version the user chose to skip from the update sheet. Empty means none;
    /// a newer release still surfaces normally.
    static let skippedUpdateVersion = Key<String>(
        "skippedUpdateVersion", default: "")

    // Status Icon
    static let batteryPercentageDisplayLocation = Key<PercentageDisplayLocation>(
        "batteryPercentageDisplayLocation", default: .nextToIcon)
    static let menuBarReadoutStyle = Key<MenuBarReadoutStyle>(
        "menuBarReadoutStyle", default: .batteryPercentage)
    static let showBatteryStateInStatusIcon = Key<Bool>(
        "showBatteryStateInStatusIcon", default: true)

    // Menu Dashboard
    // 仪表盘顶部两行：电源适配器名 / 电压电流（2026-11-19 由时间信息开关改义）
    static let showPowerSourceTitle = Key<Bool>("showPowerSourceTitle", default: true)
    static let showPowerElectricalSubtitle = Key<Bool>("showPowerElectricalSubtitle", default: true)
    // 功率桑基图的白色流动光效（只关动效层，保留彩色信息层）
    static let showPowerFlowSheen = Key<Bool>("showPowerFlowSheen", default: true)
    static let showPowerDistribution = Key<Bool>("showPowerDistribution", default: true)
    static let showCapacityHistory = Key<Bool>("showCapacityHistory", default: true)
    static let showEnergyAppRanking = Key<Bool>("showEnergyAppRanking", default: true)
    static let showCareActions = Key<Bool>("showCareActions", default: true)
    /// Controls the whole battery-metrics card.
    static let showBatteryHealthCard = Key<Bool>("showBatteryHealthCard", default: true)
    /// Comma-separated order of the editable dashboard cards. Missing
    /// identifiers are inserted at their default positions, so adding a card
    /// does not move it to the end for users with a saved order.
    static let dashboardCardOrder = Key<String>(
        "dashboardCardOrder",
        default: "batteryHealth,colorEnergyFlow,energyAppRanking,capacityHistory,careActions"
    )

    // Charging
    static let manageCharging = Key<Bool>("manageCharging", default: false)
    static let chargeLimit = Key<Int>("chargeLimit", default: 80)
    static let sailingMode = Key<Bool>("sailingMode", default: true)
    static let sailingModeLimit = Key<Int>("sailingModeLimit", default: 5)
    static let automaticDischarge = Key<Bool>("automaticDischarge", default: false)
    static let disableSleepUntilChargeLimit = Key<Bool>("disableSleepUntilChargeLimit", default: true)

    // Charging - Heat Protection
    static let enableHeatProtectionMode = Key<Bool>(
        "enableHeatProtectionMode", default: true)
    static let heatProtectionLimit = Key<Int>("heatProtectionLimit", default: 40)

    // Charging - MagSafe LED Control
    static let manageMagSafeLED = Key<Bool>("manageMagSafeLED", default: true)
    static let heatProtectionMagSafeLEDState = Key<MagSafeLEDState>(
        "heatProtectionMagSafeLEDState", default: MagSafeLEDState.blinkOrangeSlow)

    // Charging - Advanced workflows
    static let stopChargingWhenAppClosed = Key<Bool>(
        "stopChargingWhenAppClosed", default: true)
    static let stopChargingWhileSleeping = Key<Bool>(
        "stopChargingWhileSleeping", default: false)
    static let topUpActive = Key<Bool>("topUpActive", default: false)
    static let manualPauseActive = Key<Bool>("manualPauseActive", default: false)
    static let forcedDischargeTarget = Key<Int>("forcedDischargeTarget", default: 80)
    static let calibrationStage = Key<String>("calibrationStage", default: "idle")
    static let calibrationOriginalLimit = Key<Int>(
        "calibrationOriginalLimit", default: 80)
    static let calibrationLowLevel = Key<Int>("calibrationLowLevel", default: 10)
    static let calibrationHoldMinutes = Key<Int>("calibrationHoldMinutes", default: 60)
    static let calibrationHoldUntil = Key<Double>("calibrationHoldUntil", default: 0)

    // Automation
    static let scheduleTasksData = Key<Data>("scheduleTasksData", default: Data())

    // Advanced
    static let useHardwarePercentage = Key<Bool>("useHardwarePercentage", default: false)

    // Diagnostics
    static let diagnosticSessionStartedAt = Key<Double>(
        "diagnosticSessionStartedAt", default: 0)
    static let diagnosticSessionID = Key<String>(
        "diagnosticSessionID", default: "")
}

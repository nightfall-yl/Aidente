import Foundation

@objc public protocol AidenteReaderProtocol {
    func readBatteryMetrics(
        reply: @escaping @Sendable (Double, Double, Double) -> Void
    )
    func readAdapterMetrics(
        reply: @escaping @Sendable (Double, Double, Double) -> Void
    )
    func getCapabilities(
        reply: @escaping @Sendable (Bool, Bool, Bool, Bool) -> Void
    )
}

@objc public protocol AidenteControlProtocol {
    func applyPowerPolicy(charging: Bool, adapter: Bool, managed: Bool,
                          stopWhileSleeping: Bool, resetOnDisconnect: Bool,
                          chargeCeiling: Int, rechargeBelow: Int,
                          reply: @escaping @Sendable (Bool, String?) -> Void)
    func ping(
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
    func manageBatteryCharging(
        enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
    func manageExternalPower(
        enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
    func manageMagsafeLED(
        target: UInt8,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
    func setResetOnDisconnect(_ enabled: Bool)
    func resetToDefaults()
    func restoreDefaults(reply: @escaping @Sendable (Bool, String?) -> Void)
    /// Announces a self-update so the daemon can re-pin the client manifest
    /// after the updater swaps /Applications (new ad-hoc build → new cdhash),
    /// sparing the user a re-authorization. Only honored over an already-pinned
    /// connection; the replacement bundle is re-validated before any write.
    func schedulePinRefresh(
        expectedVersion: String,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
}

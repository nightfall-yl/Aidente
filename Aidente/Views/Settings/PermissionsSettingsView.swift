import Defaults
import SwiftUI
import os.log

struct PermissionsSettingsView: View {
    @Default(.manageCharging) private var manageCharging

    private let helperManager = ChargingHelperManager.shared
    @State private var installError: String?
    @State private var hasCheckedStatus = false

    private let chargeManager: ChargeManager

    private let logger = Logger(
        subsystem: "com.aidente.app",
        category: "PermissionsSettingsView"
    )

    init(chargeManager: ChargeManager) {
        self.chargeManager = chargeManager
    }

    var body: some View {
        AidenteSettingsPage {
            AidenteCard(
                AidenteL10n.t("检查后台服务状态", "Check Background Service Status"),
                subtitle: AidenteL10n.t(
                    "检查后台控制服务是否已安装，以及身份是否与当前 Aidente 匹配。",
                    "Check whether the helper is installed and its identity matches this Aidente build."
                ),
                icon: "person.badge.shield.checkmark.fill",
                colors: AidenteTheme.permissionColors
            ) {
                if hasCheckedStatus {
                    AidenteNotice(
                        text: serviceStatusText,
                        icon: helperManager.isInstalled
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill",
                        colors: helperManager.isInstalled
                            ? [AidenteTheme.jade, AidenteTheme.mint]
                            : [AidenteTheme.coral, AidenteTheme.amber]
                    )
                } else {
                    AidenteNotice(
                        text: AidenteL10n.t(
                            "点击下方按钮读取当前状态；若服务缺失或身份不匹配，请用下方「修复控制服务」重新授权安装。",
                            "Tap the button to read the current status. If the helper is missing or mismatched, use Repair Control Service below to re-install it."
                        ),
                        icon: "info.circle.fill",
                        colors: AidenteTheme.permissionColors
                    )
                }

                Button {
                    checkServiceStatus()
                } label: {
                    Label(
                        AidenteL10n.t("检查状态", "Check Status"),
                        systemImage: "arrow.clockwise.circle.fill"
                    )
                }
                .buttonStyle(AidenteActionButtonStyle(colors: AidenteTheme.permissionColors))
            }

            AidenteCard(
                "修复控制服务",
                subtitle: AidenteL10n.t(
                    "升级后主程序或后台控制程序改变、身份不匹配导致控制失效时，重新登记授权。",
                    "After an update changes the main app or the helper binary, re-register authorization when identities no longer match."
                ),
                icon: "wrench.and.screwdriver.fill",
                colors: AidenteTheme.aboutColors
            ) {
                AidenteNotice(
                    text: AidenteL10n.t(
                        "后台控制服务身份不匹配或已损坏时，点击修复将重新通过 macOS 管理员授权安装服务，无需开发者账号。",
                        "When the helper service identity is mismatched or damaged, Repair re-installs it through macOS administrator authorization — no developer account needed."
                    ),
                    icon: "info.circle.fill",
                    colors: AidenteTheme.aboutColors
                )

                Button {
                    repairControlService()
                } label: {
                    Label(
                        helperManager.isBusy
                            ? AidenteL10n.t("正在修复…", "Repairing…")
                            : AidenteL10n.t("修复控制服务", "Repair Control Service"),
                        systemImage: helperManager.isBusy
                            ? "hourglass.bottomhalf.filled"
                            : "wrench.and.screwdriver.fill"
                    )
                }
                .buttonStyle(AidenteActionButtonStyle(colors: AidenteTheme.aboutColors))
                .disabled(helperManager.isRunningFromDiskImage || helperManager.isBusy)
            }
        }
        .aidenteInstallErrorAlert($installError)
    }

    private var serviceStatusText: String {
        if helperManager.isInstalled {
            return AidenteL10n.t(
                "后台服务已安装，且与当前 Aidente 身份匹配，可以正常控制充电。",
                "The helper is installed and matches this Aidente build; charging control is available."
            )
        }
        return AidenteL10n.t(
            "后台服务未安装，或身份与当前 Aidente 不匹配；请点击下方「修复控制服务」重新授权安装。",
            "The helper is missing or does not match this Aidente build. Use Repair Control Service below to re-install it."
        )
    }

    private func checkServiceStatus() {
        helperManager.refreshStatus()
        hasCheckedStatus = true
    }

    private func repairControlService() {
        Task {
            do {
                try await helperManager.repair()
                if helperManager.helperStatus == .installed {
                    manageCharging = true
                    chargeManager.retryControlAfterRepair()
                }
            } catch {
                logger.error("Failed to repair charging helper: \(error)")
                installError = error.localizedDescription
            }
            // Refresh the status card so a successful repair turns the
            // previously red status notice green without a manual re-check.
            helperManager.refreshStatus()
            hasCheckedStatus = true
        }
    }
}

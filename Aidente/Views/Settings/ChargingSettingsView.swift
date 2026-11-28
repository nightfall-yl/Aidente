import Defaults
import SwiftUI
import os.log
import smc_power

struct ChargingSettingsView: View {
    @Default(.manageCharging) var manageCharging
    @Default(.chargeLimit) var chargeLimit
    @Default(.sailingMode) var sailingMode
    @Default(.sailingModeLimit) var sailingModeLimit
    @Default(.automaticDischarge) var automaticDischarge
    @Default(.enableHeatProtectionMode) var enableHeatProtectionMode
    @Default(.heatProtectionLimit) var heatProtectionLimit
    @Default(.calibrationLowLevel) var calibrationLowLevel
    @Default(.calibrationHoldMinutes) var calibrationHoldMinutes
    // 2026-11-18 用户指令：「MagSafe 指示灯」卡由通用页移入本页（电池校准之后）
    @Default(.manageMagSafeLED) var manageMagSafeLED
    @Default(.heatProtectionMagSafeLEDState) var heatProtectionMagSafeLEDState
    private let helperManager = ChargingHelperManager.shared
    @State private var installError: String?

    private let capabilities: DeviceCapabilities
    private let chargeManager: ChargeManager

    private let logger = Logger(
        subsystem: "com.aidente.app",
        category: "ChargingSettingsView"
    )

    init(capabilities: DeviceCapabilities, chargeManager: ChargeManager) {
        self.capabilities = capabilities
        self.chargeManager = chargeManager
    }

    private var hasChargingControl: Bool {
        capabilities.chargingControl
    }

    private var hasAdapterControl: Bool {
        capabilities.adapterControl
    }

    private var hasAnyControl: Bool {
        hasChargingControl || hasAdapterControl
    }

    private var chargingStatusNotice: String {
        let sailing = sailingMode ? "已开启" : "当前关闭"
        let sailingEn = sailingMode ? "on" : "off"
        // 原型定稿：一个状态框内两行——第一行是原「设置充电上限」副标题的说明，
        // 第二行是实时状态。Swift 保留 chargeLimit / sailingMode 的插值。
        return AidenteL10n.t(
            "达到上限后由适配器供电；巡航使用巡航范围。\n正在以 \(Int(chargeLimit))% 上限管理充电；电池巡航\(sailing)。",
            "Use adapter power at the limit; sailing uses the sailing range.\nManaging charging at an \(Int(chargeLimit))% limit; Battery Sailing is \(sailingEn)."
        )
    }

    var body: some View {
        AidenteSettingsPage {
            AidenteCard(
                "充电管理",
                icon: "battery.75percent",
                colors: AidenteTheme.chargingColors,
                headerOutside: true,
                showsHeaderBadge: false
            ) {
                AidenteSettingToggle(
                    "启用充电管理",
                    subtitle: AidenteL10n.t("首次启用需管理员授权安装后台服务", "Administrator authorization is required to install the background service on first enable"),
                    icon: "switch.2",
                    colors: AidenteTheme.chargingColors,
                    isOn: Binding(
                        get: { manageCharging },
                        set: { toggleManageCharging($0) }
                    )
                )
                .disabled(!hasAnyControl || helperManager.isBusy)
                .opacity(
                    (!hasAnyControl || helperManager.helperStatus == .requiresApproval)
                        ? 0.50 : 1
                )

                if helperManager.isRunningFromDiskImage {
                    AidenteNotice(
                        text: "当前正从安装磁盘映像运行，后台控制服务无法可靠启动。请退出 Aidente，将应用拖入“应用程序”文件夹后重新打开。",
                        icon: "externaldrive.badge.exclamationmark",
                        colors: [AidenteTheme.coral, AidenteTheme.amber]
                    )
                }

                if manageCharging, !helperManager.isInstalled,
                   let registrationError = helperManager.registrationError {
                    AidenteNotice(
                        text: AidenteL10n.t(
                            "后台控制服务登记失败：\(registrationError)",
                            "Background control service registration failed: \(registrationError)"
                        ),
                        icon: "person.badge.shield.exclamationmark.fill",
                        colors: [AidenteTheme.coral, AidenteTheme.amber]
                    )
                }

                if !hasAnyControl {
                    AidenteNotice(
                        text: "当前设备不支持充电管理；Aidente 将继续提供只读电池监测。",
                        icon: "laptopcomputer.trianglebadge.exclamationmark",
                        colors: [AidenteTheme.coral, AidenteTheme.amber]
                    )
                }

                AidenteNotice(
                    text: AidenteL10n.t("部分新固件在电量高于上限时会使用电池，不能保证仅由充电器供电；临时暂停使用当时电量的固件上限，允许小幅波动。", "Some newer firmware uses battery power above the limit. Temporary pause sets a firmware ceiling at the current level and may allow small fluctuations."),
                    icon: "info.circle", colors: AidenteTheme.chargingColors
                )

                if manageCharging {
                    AidenteRowDivider()
                    AidenteControlRow(
                        "设置充电上限",
                        icon: "target",
                        colors: AidenteTheme.chargingColors
                    ) {
                        InlineSliderRow(
                            value: chargeLimit,
                            range: 20...100,
                            step: 5,
                            suffix: "%",
                            sliderWidth: 190,
                            valueWidth: 48,
                        ) { chargeLimit = $0 }
                    }

                    AidenteNotice(
                        text: chargingStatusNotice,
                        icon: "battery.100percent.bolt",
                        colors: AidenteTheme.chargingColors
                    )

                    AidenteRowDivider()

                    AidenteSettingToggle(
                        "启用自动放电",
                        subtitle: "到达目标后自动恢复适配器供电",
                        icon: "battery.25percent",
                        colors: AidenteTheme.chargingColors,
                        isOn: $automaticDischarge
                    )
                    .disabled(!hasAdapterControl)
                    .opacity(hasAdapterControl ? 1 : 0.5)

                    if !hasAdapterControl {
                        AidenteNotice(text: "当前设备不支持适配器控制。")
                    }
                }
            }

            if manageCharging {
                // 2026-11-28：徽章配色改用「语言与外观」的 generalColors 蓝
                // （原 permissionColors → 2026-11-27 一度改 dashboardColors 紫）。
                AidenteCard(
                    "电池巡航",
                    subtitle: "允许电量在上限附近自然浮动，减少频繁微量补电。",
                    icon: "sailboat.fill",
                    colors: AidenteTheme.generalColors,
                    headerOutside: true,
                    showsHeaderBadge: false
                ) {
                    AidenteSettingToggle(
                        "启用电池巡航",
                        icon: "water.waves",
                        colors: AidenteTheme.permissionColors,
                        isOn: $sailingMode
                    )
                    .aidenteGated(hasChargingControl)

                    if sailingMode {
                        AidenteRowDivider()
                        AidenteControlRow(
                            "低于上限多少时恢复充电",
                            icon: "arrow.down.right",
                            colors: AidenteTheme.permissionColors
                        ) {
                            InlineSliderRow(
                                value: sailingModeLimit,
                                range: 1...20,
                                step: 1,
                                suffix: "%",
                                sliderWidth: 150,
                                valueWidth: 44
                            ) { sailingModeLimit = $0 }
                        }
                    }
                }

                AidenteCard(
                    "高温保护",
                    subtitle: "温度超过阈值时暂停充电，并通过约五分钟的延迟避免频繁切换。",
                    icon: "thermometer.high",
                    colors: [AidenteTheme.amber, AidenteTheme.coral],
                    headerOutside: true,
                    showsHeaderBadge: false
                ) {
                    AidenteSettingToggle(
                        "启用高温保护",
                        icon: "flame.fill",
                        colors: [AidenteTheme.amber, AidenteTheme.coral],
                        isOn: $enableHeatProtectionMode
                    )
                    .aidenteGated(hasChargingControl)

                    if enableHeatProtectionMode {
                        AidenteRowDivider()
                        AidenteControlRow(
                            "温度上限",
                            icon: "thermometer.medium",
                            colors: [AidenteTheme.amber, AidenteTheme.coral]
                        ) {
                            InlineSliderRow(
                                value: heatProtectionLimit,
                                range: 30...50,
                                step: 1,
                                suffix: "°C",
                                sliderWidth: 160,
                                valueWidth: 50
                            ) { heatProtectionLimit = $0 }
                        }
                    }
                }

                AidenteCard(
                    "电池校准",
                    subtitle: "充至 100% → 放电 → 再充满 → 满电保持 → 恢复原上限。",
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    colors: AidenteTheme.automationColors,
                    headerOutside: true,
                    showsHeaderBadge: false
                ) {
                    // 与诊断页「诊断记录未启动」同款控件行：左侧状态文字，
                    // 右侧内联按钮。校准是一次性完整 loop，不是持续开关——
                    // 按钮开 = startCalibration()，loop 中 = 停止校准。
                    // 与仪表盘 / 菜单快捷开关同源（calibrationStage）。
                    AidenteControlRow(
                        chargeManager.calibrationStage == .idle
                            ? AidenteL10n.t("电池校准未启动", "Battery Calibration Is Off")
                            : chargeManager.calibrationStage.title,
                        subtitle: chargeManager.calibrationStage == .idle
                            ? AidenteL10n.t(
                                "执行一次完整的充放电校准流程",
                                "Run one full charge–discharge calibration cycle"
                            )
                            : nil,
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        colors: AidenteTheme.automationColors
                    ) {
                        Button {
                            if chargeManager.calibrationStage == .idle {
                                chargeManager.startCalibration()
                            } else {
                                chargeManager.cancelCalibration()
                            }
                        } label: {
                            Label(
                                chargeManager.calibrationStage == .idle
                                    ? AidenteL10n.t("开始电池校准")
                                    : AidenteL10n.t("停止校准", "Stop Calibration"),
                                systemImage: chargeManager.calibrationStage == .idle
                                    ? "play.fill" : "stop.fill"
                            )
                        }
                        .buttonStyle(AidenteActionButtonStyle(colors: AidenteTheme.automationColors))
                        .aidenteGated(hasChargingControl)
                    }

                    AidenteRowDivider()

                    AidenteControlRow(
                        "放电目标",
                        icon: "arrow.down.to.line.compact",
                        colors: AidenteTheme.dashboardColors
                    ) {
                        InlineSliderRow(
                            value: calibrationLowLevel,
                            range: 5...20,
                            step: 1,
                            suffix: "%",
                            sliderWidth: 170
                        ) { calibrationLowLevel = $0 }
                    }

                    AidenteRowDivider()

                    AidenteControlRow(
                        "满电保持时间",
                        icon: "timer",
                        colors: AidenteTheme.automationColors
                    ) {
                        Stepper(
                            AidenteL10n.t(
                                "\(calibrationHoldMinutes) 分钟",
                                "\(calibrationHoldMinutes) min"
                            ),
                            value: $calibrationHoldMinutes,
                            in: 15...120,
                            step: 15
                        )
                    }
                }
            }

            // 2026-11-18 用户指令：由通用页移入；与电池校准 / 巡航 / 高温保护同族——
            // LED 是充电状态机的可视化外设（写入走同一 root helper），充电管理关闭时
            // 整卡隐藏，与其它充电状态卡的门控一致。
            if manageCharging && capabilities.hasMagSafe {
                AidenteCard(
                    "MagSafe 指示灯",
                    subtitle: "在受支持机型上用颜色显示充电、暂停和保护状态。",
                    icon: "lightbulb.led.fill",
                    colors: AidenteTheme.automationColors,
                    headerOutside: true,
                    showsHeaderBadge: false
                ) {
                    AidenteSettingToggle(
                        "由 Aidente 控制指示灯",
                        icon: "lightbulb.fill",
                        colors: AidenteTheme.automationColors,
                        isOn: $manageMagSafeLED
                    )
                    .disabled(!capabilities.magsafeLEDControl)
                    .opacity(capabilities.magsafeLEDControl ? 1 : 0.5)

                    if manageMagSafeLED && enableHeatProtectionMode {
                        AidenteRowDivider()
                        AidenteControlRow(
                            "高温保护时的灯光",
                            icon: "lightspectrum.horizontal",
                            colors: AidenteTheme.automationColors
                        ) {
                            AidenteMenuPicker(
                                options: [
                                    AidenteMenuOption<MagSafeLEDState>(
                                        title: AidenteL10n.t("关闭", "Off"),
                                        value: MagSafeLEDState.off
                                    ),
                                    AidenteMenuOption<MagSafeLEDState>(
                                        title: AidenteL10n.t("绿色", "Green"),
                                        value: MagSafeLEDState.green
                                    ),
                                    AidenteMenuOption<MagSafeLEDState>(
                                        title: AidenteL10n.t("橙色", "Orange"),
                                        value: MagSafeLEDState.orange
                                    ),
                                    AidenteMenuOption<MagSafeLEDState>(
                                        title: AidenteL10n.t("橙色慢闪", "Slow Orange Blink"),
                                        value: MagSafeLEDState.blinkOrangeSlow
                                    ),
                                    AidenteMenuOption<MagSafeLEDState>(
                                        title: AidenteL10n.t("橙色快闪", "Fast Orange Blink"),
                                        value: MagSafeLEDState.blinkOrangeFast
                                    ),
                                ],
                                selection: $heatProtectionMagSafeLEDState
                            )
                        }
                    }

                    if !capabilities.magsafeLEDControl {
                        AidenteNotice(text: "当前设备不支持 MagSafe 指示灯控制。")
                    }
                }
            }
        }
        .animation(.default, value: manageCharging)
        .animation(.default, value: sailingMode)
        .animation(.default, value: enableHeatProtectionMode)
        .animation(.default, value: manageMagSafeLED)
        .animation(.default, value: helperManager.helperStatus)
        .aidenteInstallErrorAlert($installError)
    }

    private func toggleManageCharging(_ enabled: Bool) {
        Task {
            do {
                if enabled {
                    try await helperManager.enableForUser()
                    manageCharging = true
                } else {
                    try await chargeManager.disableChargingManagement()
                }
            } catch {
                logger.error("Failed to \(enabled ? "install" : "uninstall") charging helper: \(error)")
                installError = error.localizedDescription
            }
        }
    }
}

/// Slider + trailing value readout, shared by the numeric controls on the
/// charging page (charge limit, calibration target, sailing range, heat limit).
private struct InlineSliderRow: View {
    let value: Int
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    var sliderWidth: CGFloat = 170
    var valueWidth: CGFloat = 45
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 9) {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0)) }
                ),
                in: range,
                step: step
            )
            .frame(width: sliderWidth)

            Text("\(value)\(suffix)")
                .font(.body.monospacedDigit())
                // 数值字号统一为 body 等宽，颜色一律用系统文字色，不随卡色变化
                .foregroundStyle(Color.primary)
                .frame(width: valueWidth, alignment: .trailing)
        }
    }
}

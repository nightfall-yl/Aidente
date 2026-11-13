import Defaults
import SwiftUI

struct DiagnosticsSettingsView: View {
    @Bindable var diagnosticCenter: DiagnosticCenter

    var body: some View {
        AidenteSettingsPage {
            // 问题记录 / 导出诊断包 / 隐私保护 三卡整合后的单卡：诊断记录
            // 控件行置顶，编号行不再展示（对齐 HTML 原型）。
            AidenteCard(
                "诊断与导出",
                subtitle: "诊断信息始终由用户决定是否生成和发送。",
                icon: "square.and.arrow.up.on.square.fill",
                colors: AidenteTheme.aboutColors
            ) {
                AidenteControlRow(
                    diagnosticCenter.isRecording
                        ? AidenteL10n.t("正在记录问题", "Recording Issue")
                        : AidenteL10n.t("诊断记录未启动", "Diagnostic Recording Is Off"),
                    subtitle: diagnosticCenter.isRecording
                        ? nil
                        : AidenteL10n.t(
                            "平时不会增加高频采样或后台负担",
                            "No extra high-frequency sampling runs while idle"
                        ),
                    icon: diagnosticCenter.isRecording
                        ? "record.circle.fill" : "checkmark.shield.fill",
                    colors: AidenteTheme.advancedColors
                ) {
                    HStack(spacing: 10) {
                        if diagnosticCenter.isRecording {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(
                                    elapsedText(
                                        from: diagnosticCenter.recordingStartedAt ?? .now,
                                        to: context.date
                                    )
                                )
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            if diagnosticCenter.isRecording {
                                diagnosticCenter.stopRecording()
                            } else {
                                diagnosticCenter.startRecording()
                            }
                        } label: {
                            Label(
                                diagnosticCenter.isRecording
                                    ? AidenteL10n.t("停止记录", "Stop Recording")
                                    : AidenteL10n.t("开始问题记录", "Start Recording"),
                                systemImage: diagnosticCenter.isRecording
                                    ? "stop.fill" : "record.circle"
                            )
                        }
                        .buttonStyle(AidenteActionButtonStyle(colors: AidenteTheme.aboutColors))
                    }
                }

                AidenteRowDivider()

                AidenteSettingToggle(
                    "包含最近的崩溃报告",
                    subtitle: "最多收集最近七天内的 5 份 Aidente 报告，并自动脱敏",
                    icon: "exclamationmark.triangle.fill",
                    colors: AidenteTheme.advancedColors,
                    isOn: $diagnosticCenter.includeCrashReports
                )

                AidenteRowDivider()

                AidenteSettingToggle(
                    "包含耗电 App 名称",
                    subtitle: "默认关闭；开启后仅记录导出时的 App 名称与活动估算",
                    icon: "bolt.horizontal.circle.fill",
                    colors: AidenteTheme.chargingColors,
                    isOn: $diagnosticCenter.includeEnergyAppNames
                )

                AidenteInsetPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AidenteL10n.t("导出内容预览"))
                            .font(.system(size: 12.5, weight: .semibold))

                        diagnosticItem("Aidente 统一日志（最近 1 小时或本次记录）")
                        diagnosticItem("软件、macOS、机型与后台服务状态")
                        diagnosticItem("电池、适配器及充电控制快照")
                        diagnosticItem("用户名、路径、网络地址、序列号自动脱敏")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await diagnosticCenter.exportDiagnostics()
                        }
                    } label: {
                        if diagnosticCenter.isExporting {
                            HStack(spacing: 7) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(AidenteL10n.t("正在导出…", "Exporting…"))
                            }
                        } else {
                            Label(
                                AidenteL10n.t("导出诊断包"),
                                systemImage: "shippingbox.and.arrow.backward.fill"
                            )
                        }
                    }
                    .buttonStyle(AidenteActionButtonStyle(colors: AidenteTheme.aboutColors))
                    .disabled(diagnosticCenter.isExporting)

                    if diagnosticCenter.lastExportURL != nil {
                        Button {
                            diagnosticCenter.revealLastExport()
                        } label: {
                            Label(AidenteL10n.t("在访达中显示"), systemImage: "folder.fill")
                        }
                        .buttonStyle(AidenteActionButtonStyle(colors: AidenteTheme.aboutColors))
                    }

                    Spacer()
                }
            }

            AidenteCard(
                "可选 CLI",
                subtitle: "高级用户可以从终端查看状态或触发操作，CLI 不会常驻后台。",
                icon: "terminal.fill",
                colors: AidenteTheme.permissionColors
            ) {
                AidenteInsetPanel {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("aidente status")
                        Text("aidente limit 80")
                        Text("aidente pause · aidente resume")
                        Text("aidente diagnostics")
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button {
                        diagnosticCenter.copyCLIPath()
                    } label: {
                        Label(AidenteL10n.t("复制 CLI 完整路径"), systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(AidenteActionButtonStyle(colors: AidenteTheme.permissionColors))

                    Spacer()

                    Text(
                        AidenteL10n.t(
                            "随应用提供，不会自动修改系统 PATH",
                            "Bundled with the app; it does not modify PATH"
                        )
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                }
            }

            // Page-level feedback: statusMessage is shared by copy actions and
            // exports, so the notice lives below all cards instead of inside
            // the export card.
            if let statusMessage = diagnosticCenter.statusMessage {
                AidenteNotice(
                    text: statusMessage,
                    icon: "checkmark.circle.fill",
                    colors: AidenteTheme.generalColors
                )
            }

            if let errorMessage = diagnosticCenter.errorMessage {
                AidenteNotice(
                    text: errorMessage,
                    icon: "xmark.octagon.fill",
                    colors: [AidenteTheme.coral, AidenteTheme.amber]
                )
            }
        }
    }

    private func diagnosticItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AidenteTheme.aboutColors.first ?? AidenteTheme.coral)
            Text(AidenteL10n.t(text))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func elapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return AidenteL10n.t(
            String(format: "已记录 %02d:%02d", minutes, remainder),
            String(format: "Recorded %02d:%02d", minutes, remainder)
        )
    }
}

import AppKit
import Defaults
import SwiftUI
import smc_power

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case dashboard = "Dashboard"
    case charging = "Charging"
    case permissions = "Permissions"
    case automation = "Automation"
    case diagnostics = "Diagnostics"
    case about = "About"

    var id: String { rawValue }

    init?(urlValue: String) {
        guard let tab = Self.allCases.first(where: {
            $0.rawValue.lowercased() == urlValue.lowercased()
        }) else {
            return nil
        }
        self = tab
    }

    var title: String {
        switch self {
        case .general: AidenteL10n.t("通用")
        case .dashboard: AidenteL10n.t("仪表盘")
        case .charging: AidenteL10n.t("充电管理")
        case .permissions: AidenteL10n.t("权限管理")
        case .automation: AidenteL10n.t("计划与自动化")
        case .diagnostics: AidenteL10n.t("诊断")
        case .about: AidenteL10n.t("关于")
        }
    }

    var icon: String {
        switch self {
        case .general:
            return "gearshape.fill"
        case .dashboard:
            return "gauge.with.dots.needle.67percent"
        case .charging:
            return "battery.100.bolt"
        case .permissions:
            return "person.badge.shield.checkmark.fill"
        case .automation:
            return "calendar.badge.clock"
        case .diagnostics:
            return "waveform.badge.magnifyingglass"
        case .about:
            return "heart.text.square.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .general: AidenteTheme.generalColors
        case .dashboard: AidenteTheme.dashboardColors
        case .charging: AidenteTheme.chargingColors
        // Unique hue pairs per tab: permissions get an ocean→violet guard
        // feel instead of reusing general's blue; diagnostics switch to the
        // deeper indigo pair so neither collides with its neighbors.
        case .permissions: AidenteTheme.permissionColors
        case .automation: AidenteTheme.automationColors
        case .diagnostics: AidenteTheme.advancedColors
        case .about: AidenteTheme.aboutColors
        }
    }

    var detailSubtitle: String {
        switch self {
        case .general: AidenteL10n.t(
            "语言、外观、启动与通知等全局基础偏好。",
            "Global basics: language, appearance, startup and notifications."
        )
        case .dashboard: AidenteL10n.t(
            "配置仪表盘顶部的时间信息与打开方式。",
            "Configure the dashboard's time readouts and how to open it."
        )
        case .charging: AidenteL10n.t(
            "设定充电上限、巡航与高温保护，养护电池。",
            "Set the charge limit, sailing mode and heat protection to care for the battery."
        )
        case .permissions: AidenteL10n.t(
            "查看并重发控制服务的系统授权。",
            "Review and re-issue the system authorization for the control service."
        )
        case .automation: AidenteL10n.t(
            "按计划自动执行充电任务，或接入快捷指令。",
            "Run charging tasks on a schedule, or wire up Shortcuts."
        )
        case .diagnostics: AidenteL10n.t(
            "记录问题、导出诊断包，并查看隐私与命令行。",
            "Record issues, export a diagnostics package, and review privacy and the CLI."
        )
        case .about: AidenteL10n.t(
            "软件更新、版本信息与法律开源声明。",
            "Software updates, version info, and legal & open-source notices."
        )
        }
    }
}

struct SettingsView: View {
    @Default(.appLanguage) private var appLanguage
    @Default(.appAppearance) private var appAppearance
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var systemAppearanceMonitor = SystemAppearanceMonitor()
    @State private var selectedTab: SettingsTab

    private let capabilities: DeviceCapabilities
    private let chargeManager: ChargeManager
    private let diagnosticCenter: DiagnosticCenter
    private let updateService: UpdateService

    /// AppKit paints no title bar for a transparent `.fullSizeContentView`
    /// window. This independent chrome layer sits above the scrolling detail
    /// pane so cards are clipped beneath it, like the prototype. 28pt is the
    /// system height of a hidden-title title bar.
    private let titlebarMaskHeight: CGFloat = 28

    /// Both panes' headers share this fixed content height so the sidebar app
    /// icon and the detail badge land on the same horizontal center line,
    /// regardless of text height in either pane's header. The text column can
    /// exceed 34pt (title + subtitle); centering it in this fixed frame keeps
    /// the 34pt badges' geometric centers aligned on both sides.
    private let headerContentHeight: CGFloat = 46

    init(
        capabilities: DeviceCapabilities,
        chargeManager: ChargeManager,
        diagnosticCenter: DiagnosticCenter,
        updateService: UpdateService,
        initialTab: SettingsTab = .general
    ) {
        self.capabilities = capabilities
        self.chargeManager = chargeManager
        self.diagnosticCenter = diagnosticCenter
        self.updateService = updateService
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            AidenteWindowBackdrop()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 236)

                Divider()

                detailPane
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                AidenteChromeBar()
                    .frame(height: titlebarMaskHeight)
                Rectangle()
                    .fill(AidenteSurfaceTokens.stroke(scheme: colorScheme))
                    .frame(height: 1)
            }
            .frame(maxWidth: .infinity)
            .offset(y: -titlebarMaskHeight)
            .allowsHitTesting(false)
        }
        .tint(AidenteTheme.jade)
        .environment(\.aidenteCanSampleBackdrop, false)
        .frame(minWidth: 960, minHeight: 640)
        .preferredColorScheme(resolvedPreferredScheme)
        .onAppear {
            updateWindowTitle()
        }
        .onChange(of: appLanguage) { _, _ in
            updateWindowTitle()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                // App icon, matching the running Aidente app icon. Scaled up
                // ~18% so the icon's built-in safe-area padding is cropped and
                // the rounded square fills the 34pt frame, matching the visual
                // weight of the functional-area badges.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                    .scaleEffect(1.18)
                    .clipped()
                Text("Aidente")
                    .font(.system(size: 20, weight: .bold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            // Fixed content height keeps the icon's center on the shared
            // header center line with the detail pane's badge.
            .frame(height: headerContentHeight)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        sidebarRow(tab)
                    }
                }
                .padding(.horizontal, 10)
                // Line the first sidebar row up with the first detail card:
                // both headers are the same height, then the detail pane adds
                // a 1pt divider and the settings page's 20pt top padding.
                .padding(.top, 21)
                .padding(.bottom, 14)
            }
        }
        .background(AidenteChromeBar())
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        let selected = tab == selectedTab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: tab.colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: tab.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)

                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : Color.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? sidebarAccent : Color.clear)
            )
            // Plain buttons only hit-test opaque content. Declare the whole
            // row (trailing Spacer and padding included) as the hit area so a
            // click anywhere on the row switches tabs, like System Settings.
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sidebarAccent: Color {
        // macOS 15 System Blue at ~80% — light #007AFF, dark #0A84FF.
        colorScheme == .dark
            ? Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.80)
            : Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.80)
    }

    private var detailPane: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    AidenteIconBadge(
                        icon: selectedTab.icon,
                        colors: selectedTab.colors,
                        size: 34
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selectedTab.title)
                            .font(.system(size: 20, weight: .bold))
                        Text(selectedTab.detailSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                // Same fixed content height as the sidebar header: the 34pt
                // badge centers on the shared horizontal line even when the
                // title + subtitle column is taller than 34pt.
                .frame(height: headerContentHeight)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()
                    .padding(.horizontal, 20)

                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView()
                    case .dashboard:
                        DashboardSettingsView()
                    case .charging:
                        ChargingSettingsView(
                            capabilities: capabilities,
                            chargeManager: chargeManager
                        )
                    case .permissions:
                        PermissionsSettingsView(chargeManager: chargeManager)
                    case .automation:
                        AutomationSettingsView()
                    case .diagnostics:
                        DiagnosticsSettingsView(diagnosticCenter: diagnosticCenter)
                    case .about:
                        AboutSettingsView(updateService: updateService)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    /// Always returns an explicit scheme: 「自动」resolves to the current system
    /// appearance. Never nil — `.preferredColorScheme(nil)` is sticky in the
    /// AppKit-hosted hierarchy and would not clear a previous override.
    private var resolvedPreferredScheme: ColorScheme {
        switch appAppearance {
        case .light: return .light
        case .dark: return .dark
        case .auto: return systemAppearanceMonitor.isDark ? .dark : .light
        }
    }

    private func updateWindowTitle() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.title = AidenteL10n.t(
                "Aidente 设置",
                "Aidente Settings"
            )
        }
    }
}

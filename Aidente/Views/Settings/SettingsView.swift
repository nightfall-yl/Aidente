import AppKit
import Defaults
import SwiftUI
import smc_power

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
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
        case .charging: AidenteL10n.t("充电管理")
        case .permissions: AidenteL10n.t("睡眠行为", "Sleep Behavior")
        case .automation: AidenteL10n.t("自动化")
        case .diagnostics: AidenteL10n.t("诊断")
        case .about: AidenteL10n.t("关于")
        }
    }

    var icon: String {
        switch self {
        case .general:
            return "gearshape.fill"
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
        // 6 个 tab：蓝 → 绿 → 紫 → 橙 → 橙红 → 蓝紫（2026-11-27 调整）。
        // 仪表盘 tab 删除后，充电管理改回 chargingColors 绿，
        // 睡眠行为改用 dashboardColors 紫（原 advancedColors 靛）。
        case .general: AidenteTheme.generalColors
        case .charging: AidenteTheme.chargingColors
        case .permissions: AidenteTheme.dashboardColors
        case .automation: AidenteTheme.automationColors
        case .diagnostics: AidenteTheme.aboutColors
        case .about: AidenteTheme.permissionColors
        }
    }
}

struct SettingsView: View {
    @Default(.appLanguage) private var appLanguage
    @Default(.appAppearance) private var appAppearance
    @StateObject private var systemAppearanceMonitor = SystemAppearanceMonitor()

    /// `.preferredColorScheme` is applied *below* this view, so an
    /// `@Environment(\.colorScheme)` read here still reflects the window's
    /// NSAppearance captured at creation. Surfaces painted directly in this
    /// body — the pane divider, the detail background, the sidebar accent —
    /// would otherwise keep the old theme after an in-app appearance switch.
    /// Derive the scheme from the same source as the modifier instead.
    private var colorScheme: ColorScheme { resolvedPreferredScheme }
    @State private var selectedTab: SettingsTab
    /// Tab navigation history for the header back / forward buttons
    /// (prototype `nav-btns`). `navIndex` points into `navHistory`; sidebar
    /// taps push and truncate, back / forward only move the pointer. Reset to
    /// the initial tab on every window creation — both buttons start dimmed.
    @State private var navHistory: [SettingsTab]
    @State private var navIndex: Int = 0
    @State private var backHovered = false
    @State private var forwardHovered = false

    private let capabilities: DeviceCapabilities
    private let chargeManager: ChargeManager
    private let diagnosticCenter: DiagnosticCenter
    private let updateService: UpdateService

    /// Sidebar-only: fixed frame height so the app badge and "Aidente" label
    /// are vertically centered as one header block. It has no relationship to
    /// the nav rows below, which flow naturally after the header.
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
        _navHistory = State(initialValue: [initialTab])
    }

    var body: some View {
        // Prototype frame: `.window > .body > sidebar | vdiv | detail`. There
        // is NO full-width layer — no title bar, no window-wide backdrop. Both
        // panes and the divider paint from the very top edge all the way down,
        // and the AppKit traffic lights float inside the sidebar's top-left.
        ZStack {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 214)

                // The 1pt pane divider must be opaque: this window has no
                // full-width backdrop and `backgroundColor = .clear`, so a
                // translucent line shows the desktop through it and reads as
                // a black seam. Paint an opaque window-token base first,
                // then the neutral stroke on top.
                ZStack {
                    detailPaneColor
                    AidenteSurfaceTokens.stroke(scheme: colorScheme)
                }
                .frame(width: 1)

                detailPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
        }
        .ignoresSafeArea(.container, edges: .top)
        // Dark-mode-only outer light ring, matching macOS System Settings'
        // hairline window outline. strokeBorder keeps the 1pt line fully
        // inside the contentView's 12pt-corner clip, so it hugs the rounded
        // edge exactly. Light mode stays clear — the window already has its
        // natural edge highlight there and doubling it looks muddy.
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.20)
                        : .clear,
                    lineWidth: 1
                )
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
        }
        .tint(AidenteTheme.jade)
        .environment(\.aidenteCanSampleBackdrop, false)
        // Settings cards use a dimmer light-mode fill than the global L2 token
        // so they don't read as pure white on the grey detail pane. Injected
        // here (not on .card itself) so dashboard / menu cards keep #FCFCFC.
        // Sheets presented from settings inherit this and stay consistent.
        .environment(\.aidenteUsesSettingsCardFill, true)
        .frame(
            minWidth: 750, idealWidth: 750, maxWidth: 750,
            minHeight: 475, maxHeight: 960
        )
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
                // Settings-specific 34pt badge: full-bleed artwork, no glass
                // rim or inner glow, so the small size stays clean. Falls back
                // to the app icon if the bundled resource is missing.
                if let badgeURL = Bundle.main.url(forResource: "SettingsBadge", withExtension: "png"),
                   let badgeImage = NSImage(contentsOf: badgeURL) {
                    Image(nsImage: badgeImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                } else {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                }
                Text("Aidente")
                    .font(.system(size: 18, weight: .bold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            // Fixed header height; the detail pane no longer aligns with it.
            .frame(height: headerContentHeight)
            // Sidebar-only clearance for the AppKit traffic lights floating
            // at the window's top-left. 54 + 46/2 = 77pt header center, i.e.
            // 47pt below the traffic-light center at y=30pt.
            .padding(.top, 54)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        sidebarRow(tab)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
        }
        .background { AidenteSettingsSidebarSurface() }
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        let selected = tab == selectedTab
        return Button {
            selectFromSidebar(tab)
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

    /// Settings-only detail pane fill. Light sits a little greyer than the
    /// global `.window` token (which the dashboard still uses), closer to the
    /// macOS System Settings content pane. Dark keeps the global token.
    private var detailPaneColor: Color {
        colorScheme == .dark
            ? AidenteSurfaceTokens.color(.window, scheme: .dark)
            : Color(red: 237 / 255, green: 238 / 255, blue: 240 / 255)
    }

    private var sidebarAccent: Color {
        // macOS 15 System Blue at ~80% — light #007AFF, dark #0A84FF.
        colorScheme == .dark
            ? Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.80)
            : Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.80)
    }

    // MARK: Header back / forward navigation (settings-prototype.html)

    private var canGoBack: Bool { navIndex > 0 }
    private var canGoForward: Bool { navIndex < navHistory.count - 1 }

    /// Sidebar tap = a fresh forward navigation: truncate any forward branch
    /// and push. Tapping the already-current tab is a no-op (no duplicate).
    private func selectFromSidebar(_ tab: SettingsTab) {
        guard navHistory[navIndex] != tab else { return }
        navHistory = Array(navHistory[0...navIndex]) + [tab]
        navIndex = navHistory.count - 1
        selectedTab = tab
    }

    private func goBack() {
        guard canGoBack else { return }
        navIndex -= 1
        selectedTab = navHistory[navIndex]
    }

    private func goForward() {
        guard canGoForward else { return }
        navIndex += 1
        selectedTab = navHistory[navIndex]
    }

    /// Available = darker chevron, no fill until hover (hover shows the
    /// card-colored rounded chip). Unavailable = light chevron, no feedback.
    /// Matches the prototype: NOT the system-blue accent, no borders/shadows.
    private var navIconEnabled: Color {
        colorScheme == .dark
            ? Color(red: 242 / 255, green: 242 / 255, blue: 247 / 255)
            : Color(red: 83 / 255, green: 83 / 255, blue: 83 / 255)
    }

    private var navIconDisabled: Color {
        colorScheme == .dark
            ? Color(red: 150 / 255, green: 150 / 255, blue: 157 / 255)
            : Color(red: 115 / 255, green: 115 / 255, blue: 120 / 255)
    }

    private func navChevronButton(
        systemImage: String,
        isEnabled: Bool,
        isHovered: Bool,
        setHovered: @escaping (Bool) -> Void,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background {
                    if isEnabled && isHovered {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(AidenteSurfaceTokens.settingsCardColor(scheme: colorScheme))
                    }
                }
                .foregroundStyle(isEnabled ? navIconEnabled : navIconDisabled)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { setHovered($0) }
        .accessibilityLabel(accessibilityLabel)
    }

    private var detailPane: some View {
        // Right pane = Reduce Transparency always ON: an opaque window-token
        // backdrop, with the page header pinned above the scrolling cards.
        VStack(spacing: 0) {
            // Fixed page header: the title's center sits 32pt from the window
            // top, and the hairline below it is another 32pt down. Not part of
            // the ScrollView, so it never scrolls; its opaque fill and higher
            // z-order clip cards passing beneath it. Back / forward chevrons
            // sit left of the title (~88pt title inset), per the prototype.
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        navChevronButton(
                            systemImage: "chevron.left",
                            isEnabled: canGoBack,
                            isHovered: backHovered,
                            setHovered: { backHovered = $0 },
                            accessibilityLabel: AidenteL10n.t("后退", "Back")
                        ) { goBack() }
                        navChevronButton(
                            systemImage: "chevron.right",
                            isEnabled: canGoForward,
                            isHovered: forwardHovered,
                            setHovered: { forwardHovered = $0 },
                            accessibilityLabel: AidenteL10n.t("前进", "Forward")
                        ) { goForward() }
                    }
                    Text(selectedTab.title)
                        .font(.system(size: 16, weight: .bold))
                        // Clicks pass through to the drag layer below.
                        .allowsHitTesting(false)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .frame(height: 60)

                // y = 60pt, i.e. 30pt below the title center. Cards keep
                // their own top spacing and no longer line up with the
                // sidebar's first nav row.
                Divider()
                    .padding(.horizontal, 20)
                    .allowsHitTesting(false)
            }
            // Drag layer sits BELOW the content (was an overlay above it): the
            // buttons must stay clickable, while the title / hairline and empty
            // areas opt out of hit-testing so window dragging still works there.
            .background {
                AidenteWindowDragHandle()
            }
            .background(detailPaneColor)
            .zIndex(2)

            ScrollView {
                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView(capabilities: capabilities)
                    case .charging:
                        ChargingSettingsView(
                            capabilities: capabilities,
                            chargeManager: chargeManager
                        )
                    case .permissions:
                        PermissionsSettingsView(capabilities: capabilities)
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
        .background(detailPaneColor)
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

/// Settings-only sidebar material. Mirrors the prototype's split: the left
/// pane keeps Reduce Transparency permanently OFF and samples the desktop
/// behind the window, while the right pane stays on the opaque window token
/// (permanently ON). Kept local to the settings view so the dashboard's
/// frozen L0-L3 scale is untouched. The solid chrome token underneath is a
/// paint-order fallback for containers where no backdrop can be sampled.
private struct AidenteSettingsSidebarSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AidenteSurfaceTokens.color(.chrome, scheme: colorScheme)
            AidenteBackdropMaterial()
            sidebarTint
            AidenteSurfaceTokens.glassTint(scheme: colorScheme)
        }
        .allowsHitTesting(false)
    }

    /// Mirrors the prototype's side-fill: a darker translucent wash over the
    /// live glass so the sidebar reads one step deeper than the content pane.
    private var sidebarTint: Color {
        colorScheme == .dark
            ? Color(red: 52 / 255, green: 52 / 255, blue: 56 / 255).opacity(0.50)
            : Color(red: 236 / 255, green: 236 / 255, blue: 238 / 255).opacity(0.60)
    }
}

/// Makes the pinned settings page header draggable. With a hidden transparent
/// title bar, AppKit only lets the traffic-light strip move the window; turning
/// on `isMovableByWindowBackground` would also steal drags from the card
/// ScrollView, so the drag handle is scoped to the header instead.
private struct AidenteWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> AidenteWindowDragNSView {
        AidenteWindowDragNSView()
    }

    func updateNSView(_ nsView: AidenteWindowDragNSView, context: Context) {}
}

private final class AidenteWindowDragNSView: NSView {
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

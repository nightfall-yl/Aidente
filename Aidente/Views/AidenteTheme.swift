import AppKit
import Defaults
import SwiftUI

enum AidenteTheme {
    static let jade = Color(red: 0.18, green: 0.84, blue: 0.50)
    static let mint = Color(red: 0.40, green: 0.92, blue: 0.68)
    static let ocean = Color(red: 0.24, green: 0.56, blue: 0.98)
    static let sky = Color(red: 0.36, green: 0.74, blue: 0.98)
    static let violet = Color(red: 0.55, green: 0.42, blue: 0.98)
    static let pink = Color(red: 0.90, green: 0.38, blue: 0.86)
    static let amber = Color(red: 1.00, green: 0.59, blue: 0.18)
    static let gold = Color(red: 1.00, green: 0.76, blue: 0.27)
    static let coral = Color(red: 0.98, green: 0.34, blue: 0.30)
    static let graphite = Color(red: 0.11, green: 0.12, blue: 0.14)
    static let panel = Color(red: 0.13, green: 0.13, blue: 0.14)

    static let generalColors = [ocean, sky]
    static let dashboardColors = [violet, pink]
    static let chargingColors = [jade, mint]
    static let automationColors = [amber, gold]
    static let advancedColors = [Color.indigo, violet]
    static let aboutColors = [coral, amber]

    /// Settings sidebar "Permissions" tab identity: ocean→violet, distinct
    /// from General's pure blue pair.
    static let permissionColors = [ocean, violet]
}

// MARK: - New Glass surface system (`gross-glass.html`, plan A + B + L4)

/// macOS supplies the glass on surfaces that can sample a backdrop; the app
/// owns one fixed neutral level scale and one readability promise.
/// L0 window / L1 chrome / L2 card / L3 emphasis. L4 controls carry only a
/// hairline fill and are drawn by their own views.
enum AidenteSurfaceLevel {
    case window
    case chrome
    case card
    case emphasis
}

enum AidenteSurfaceTokens {
    /// Fixed values from `gross-glass.html`: light #F4F5F6 / #F8F8F8 /
    /// #FCFCFC, dark #232326 / #28282B / #2D2D31. L1 > L0 and L2 > L0 stay
    /// constant across appearance, container and system state.
    static func color(
        _ level: AidenteSurfaceLevel,
        scheme: ColorScheme
    ) -> Color {
        let light = scheme != .dark
        switch level {
        case .window: return light ? rgb(244, 245, 246) : rgb(35, 35, 38)
        case .chrome: return light ? rgb(248, 248, 248) : rgb(40, 40, 43)
        case .card: return light ? rgb(252, 252, 252) : rgb(45, 45, 49)
        case .emphasis: return light ? rgb(233, 246, 239) : rgb(26, 46, 36)
        }
    }

    private static func rgb(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat
    ) -> Color {
        Color(
            nsColor: NSColor(
                calibratedRed: red / 255,
                green: green / 255,
                blue: blue / 255,
                alpha: 1
            )
        )
    }

    /// One 1pt neutral stroke is the only hierarchy signal on a card.
    static func stroke(scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.09)
    }

    /// L4 controls: a barely-there fill so the 1pt border stays legible on
    /// top of live glass. Values from `gross-glass.html`.
    static func controlFill(scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.055)
            : Color.white.opacity(0.24)
    }

    /// A light tint over the live backdrop material. Values are the frozen
    /// defaults from `liquid-glass-proposal.html`: light white 0.14, dark
    /// rgb(30,30,34) 0.24. AppKit's `.popover` material carries its own tint,
    /// so this stays a small correction on top of the sampled backdrop.
    static func glassTint(scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 30 / 255, green: 30 / 255, blue: 34 / 255).opacity(0.24)
            : Color.white.opacity(0.14)
    }
}

/// Frozen parameters of the "方案 A" glass prototype. The rim-light alpha is
/// the one master knob; every other layer scales off it with the same fixed
/// coefficients as the prototype CSS. The user confirmed the coupling
/// (rim thickness follows rim light) should stay as-is.
private enum AidenteGlassTokens {
    static let rimLightAlpha: CGFloat = 0.20
    static let rimWidth: CGFloat = 40
    static let rimAlphaScale: CGFloat = 0.55
    static let topHighlightScale: CGFloat = 0.30
    static let innerGlowScale: CGFloat = 0.07
    static let bottomRightScale: CGFloat = 0.55
    static let darkRimLightScale: CGFloat = 0.38
    static let darkBottomRightScale: CGFloat = 0.18
    static let darkTopHighlightScale: CGFloat = 0.12
    static let darkEdgeShadeScale: CGFloat = 0.34
    static let lightEdgeShadeScale: CGFloat = 0.16
}

/// Static glass approximation: rim thickness, inset glow, top highlight and a
/// 1pt corner-to-corner gradient stroke. Everything is SwiftUI drawing, so it
/// needs no backdrop bitmap and works from macOS 14 on. This corresponds to
/// layers 3 / 5 and the 1pt stroke of the glasswork material; blur, saturation
/// and brightness stay with the system `NSVisualEffectView`, and dispersion
/// (layer 2 of the lens) is deliberately not implemented.
private struct AidenteGlassOverlay: View {
    let shape: RoundedRectangle
    let scheme: ColorScheme

    private var dark: Bool { scheme == .dark }
    private var light: CGFloat { AidenteGlassTokens.rimLightAlpha }
    private var rim: CGFloat { AidenteGlassTokens.rimWidth }
    private var rimAlpha: CGFloat { light * AidenteGlassTokens.rimAlphaScale }

    var body: some View {
        let topLeft = light * (dark ? AidenteGlassTokens.darkRimLightScale : 1)
        let bottomRight = light * (dark
            ? AidenteGlassTokens.darkBottomRightScale
            : AidenteGlassTokens.bottomRightScale)
        let topHighlight = light * (dark
            ? AidenteGlassTokens.darkTopHighlightScale
            : AidenteGlassTokens.topHighlightScale)
        let edgeShade = rimAlpha * (dark
            ? AidenteGlassTokens.darkEdgeShadeScale
            : AidenteGlassTokens.lightEdgeShadeScale)

        ZStack {
            // 3 - rim thickness: clear in the middle, shaded toward the edge.
            shape.fill(
                RadialGradient(
                    colors: [.clear, Color.black.opacity(edgeShade)],
                    center: .center,
                    startRadius: 0,
                    endRadius: rim * 2
                )
            )
            // 5a - soft inset glow.
            shape.strokeBorder(
                Color.white.opacity(light * AidenteGlassTokens.innerGlowScale),
                lineWidth: rim / 8
            )
            // 5b - top highlight.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(topHighlight), location: 0),
                        .init(color: .clear, location: 0.16)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // 5c - top-left / bottom-right rim light as a 1pt gradient stroke.
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(topLeft), location: 0),
                        .init(color: .clear, location: 0.26),
                        .init(color: .clear, location: 0.70),
                        .init(color: Color.white.opacity(bottomRight), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
    }
}

/// Real backdrop-sampling material for macOS 15 and earlier. On macOS 26+
/// `glassEffect` replaces it; that version branch lives in
/// `AidenteLevelSurface` only.
struct AidenteBackdropMaterial: NSViewRepresentable {
    @Default(.appAppearance) private var appAppearance

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = appAppearance.nsAppearance
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = appAppearance.nsAppearance
    }
}

extension AppAppearance {
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Observes the **system** appearance so「自动」can be resolved to a concrete
/// ColorScheme. Needed because `.preferredColorScheme(nil)` is sticky in an
/// AppKit-hosted SwiftUI hierarchy: switching from an explicit value back to
/// nil does not clear the previous override, so「自动」must be re-applied as an
/// explicit value derived from the system appearance instead.
@MainActor
final class SystemAppearanceMonitor: ObservableObject {
    @Published var isDark: Bool

    private var observation: NSKeyValueObservation?

    init() {
        isDark = Self.currentSystemIsDark()
        observation = NSApp.observe(\.effectiveAppearance) { [weak self] app, _ in
            let dark = Self.isDark(app.effectiveAppearance)
            Task { @MainActor in
                self?.isDark = dark
            }
        }
    }

    deinit {
        observation?.invalidate()
    }

    nonisolated private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Called only from `init()`, which is on the main actor, so this inherits
    /// the class isolation and may read `NSApp.effectiveAppearance` directly.
    /// `isDark(_:)` stays nonisolated because the KVO callback needs it.
    private static func currentSystemIsDark() -> Bool {
        isDark(NSApp.effectiveAppearance)
    }
}

enum AidenteAppearanceResolver {
    /// Concrete NSAppearance for a user setting. 「自动」resolves to the current
    /// system appearance (aqua / darkAqua) instead of returning nil, so windows
    /// always receive a real appearance change and can never stay pinned to
    /// the value captured when they were created.
    @MainActor
    static func resolved(_ setting: AppAppearance) -> NSAppearance? {
        switch setting {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .auto:
            let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSAppearance(named: systemIsDark ? .darkAqua : .aqua)
        }
    }
}

private struct AidenteBackdropSamplingKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the hosting AppKit container can sample the content behind it.
    /// An `NSPopover` can; the transparent settings `NSWindow`, the
    /// standalone dashboard `NSWindow` and the preview `NSPanel` cannot.
    var aidenteCanSampleBackdrop: Bool {
        get { self[AidenteBackdropSamplingKey.self] }
        set { self[AidenteBackdropSamplingKey.self] = newValue }
    }
}

enum AidenteReadabilityStrategy: String {
    case systemMaterial
    case compatible
    case opaque

    var badge: String {
        switch self {
        case .systemMaterial:
            return AidenteL10n.t("系统材质", "System Material")
        case .compatible:
            return AidenteL10n.t("兼容材质", "Compatible Material")
        case .opaque:
            return AidenteL10n.t("不透明", "Opaque")
        }
    }

    var detail: String {
        switch self {
        case .systemMaterial:
            return AidenteL10n.t(
                "界面材质由系统提供，并在受支持的界面上自动使用系统液态玻璃材质。",
                "macOS supplies the material and automatically uses system Liquid Glass on supported surfaces."
            )
        case .compatible:
            return AidenteL10n.t(
                "macOS 26 以前的系统，仪表盘使用类液态玻璃材质；升级到 macOS 26+，自动使用系统液态玻璃材质。",
                "On macOS versions earlier than 26, the dashboard uses a liquid-glass-like material. Upgrading to macOS 26 or later adopts the system Liquid Glass automatically."
            )
        case .opaque:
            return AidenteL10n.t(
                "当前使用不透明背景，所有界面层均为实体，文字对比度最高。",
                "An opaque background is active. Every surface is solid for maximum text contrast."
            )
        }
    }
}

enum AidenteReadabilitySource: String {
    case followSystem
    case systemReduceTransparency
    case appOverride
    case containerFallback
}

struct AidenteReadabilityResolution {
    let strategy: AidenteReadabilityStrategy
    let source: AidenteReadabilitySource
}

enum AidenteReadability {
    /// The only version branch in the app. On macOS 26+ `glassEffect` is the
    /// system material; older systems use `NSVisualEffectView(.popover)`,
    /// which is also real backdrop-sampling glass, not a solid fallback.
    static var supportsSystemMaterial: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// Priority: system Reduce Transparency > app override > container
    /// capability > follow system.
    static func resolve(
        reduceTransparency: Bool,
        forceOpaque: Bool,
        canSampleBackdrop: Bool
    ) -> AidenteReadabilityResolution {
        if reduceTransparency {
            return AidenteReadabilityResolution(
                strategy: .opaque, source: .systemReduceTransparency)
        }
        if forceOpaque {
            return AidenteReadabilityResolution(
                strategy: .opaque, source: .appOverride)
        }
        if !canSampleBackdrop {
            return AidenteReadabilityResolution(
                strategy: .opaque, source: .containerFallback)
        }
        return AidenteReadabilityResolution(
            strategy: supportsSystemMaterial ? .systemMaterial : .compatible,
            source: .followSystem
        )
    }
}

/// The single painting outlet. No other view owns a material, gradient,
/// blur or overall opacity.
struct AidenteLevelSurface: View {
    @Default(.forceOpaqueBackground) private var forceOpaque
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.aidenteCanSampleBackdrop) private var canSampleBackdrop

    let level: AidenteSurfaceLevel
    var cornerRadius: CGFloat = 0

    private var resolution: AidenteReadabilityResolution {
        AidenteReadability.resolve(
            reduceTransparency: reduceTransparency,
            forceOpaque: forceOpaque,
            canSampleBackdrop: canSampleBackdrop
        )
    }

    /// Only L0 can carry live glass, and only on a container that can sample
    /// a backdrop when neither the system nor the user asked for opacity.
    /// macOS 26+ uses `glassEffect`; macOS 15 and earlier use the real
    /// `.popover` / `.behindWindow` material. L1/L2/L3 stay on the authored
    /// tokens so their fixed offsets remain measurable.
    private var usesBackdropMaterial: Bool {
        resolution.strategy != .opaque && level == .window
    }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
        let base = AidenteSurfaceTokens.color(level, scheme: colorScheme)

        ZStack {
            if usesBackdropMaterial {
                if #available(macOS 26, *) {
                    Color.clear
                        .glassEffect(.regular, in: shape)
                } else {
                    AidenteBackdropMaterial()
                }
                shape.fill(AidenteSurfaceTokens.glassTint(scheme: colorScheme))
                // macOS 26+ owns the highlight and refraction already; adding
                // the drawn approximation there would double the glass.
                if !AidenteReadability.supportsSystemMaterial {
                    AidenteGlassOverlay(shape: shape, scheme: colorScheme)
                }
            } else {
                shape.fill(base)
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

struct AidenteWindowBackdrop: View {
    var body: some View {
        AidenteLevelSurface(level: .window)
            .ignoresSafeArea()
    }
}

struct AidenteChromeBar: View {
    var body: some View {
        AidenteLevelSurface(level: .chrome)
    }
}

struct AidenteMaterialLayer: View {
    var cornerRadius: CGFloat = 0

    var body: some View {
        AidenteLevelSurface(level: .card, cornerRadius: cornerRadius)
    }
}

/// Hover-only hint band below the dashboard cards. The dashboard never draws
/// this itself: the gradient and its hairline edge live here with the other
/// painting outlets, so the fixed L0–L3 level scale stays measurable.
struct AidenteFooterHintSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    private var tintAlpha: Double {
        colorScheme == .dark ? 0.16 : 0.09
    }

    private var edgeAlpha: Double {
        colorScheme == .dark ? 0.34 : 0.25
    }

    var body: some View {
        LinearGradient(
            colors: [
                Color.clear,
                AidenteTheme.ocean.opacity(tintAlpha),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AidenteTheme.ocean.opacity(edgeAlpha))
                .frame(height: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The settings window and its sheets cannot sample a backdrop. Force the
/// capability flag here instead of relying on environment inheritance.
struct AidenteSettingsBackground: View {
    var body: some View {
        AidenteWindowBackdrop()
            .environment(\.aidenteCanSampleBackdrop, false)
    }
}

struct AidenteIconBadge: View {
    let icon: String
    let colors: [Color]
    var size: CGFloat = 36
    var cornerRadius: CGFloat? = nil

    private var tint: Color { colors.first ?? AidenteTheme.jade }
    private var iconTint: Color { colors.last ?? tint }

    var body: some View {
        let radius = cornerRadius ?? max(7, size * 0.27)

        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tint.opacity(0.16))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(tint.opacity(0.34), lineWidth: 1)
            Image(systemName: icon)
                .font(.system(size: size * 0.46, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconTint)
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(0.16), radius: 4, y: 2)
    }
}

struct AidenteSectionHeader: View {
    @Default(.appLanguage) private var appLanguage

    let title: String
    let subtitle: String?
    let icon: String
    let colors: [Color]

    init(
        _ title: String,
        subtitle: String? = nil,
        icon: String,
        colors: [Color]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.colors = colors
    }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            AidenteIconBadge(icon: icon, colors: colors, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(AidenteL10n.t(title))
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(AidenteL10n.t(subtitle))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

struct AidenteCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String?
    let icon: String
    let colors: [Color]
    let showDivider: Bool
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        icon: String,
        colors: [Color],
        showDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.colors = colors
        self.showDivider = showDivider
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AidenteSectionHeader(
                title,
                subtitle: subtitle,
                icon: icon,
                colors: colors
            )

            if showDivider {
                Rectangle()
                    .fill(.primary.opacity(0.10))
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 11) {
                content
            }
        }
        .padding(16)
        .background {
            AidenteMaterialLayer(cornerRadius: 15)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(
                    AidenteSurfaceTokens.stroke(scheme: colorScheme),
                    lineWidth: 1
                )
        }
    }
}

struct AidenteSettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// The settings detail pane owns the ScrollView so its page header scrolls
    /// away together with the cards. Keep this container free of a nested
    /// ScrollView, otherwise the header and the cards scroll independently.
    var body: some View {
        LazyVStack(spacing: 14) {
            content
        }
        .padding(20)
        .frame(maxWidth: 740)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .tint(AidenteTheme.jade)
    }
}

struct AidenteSettingToggle: View {
    @Default(.appLanguage) private var appLanguage

    let title: String
    let subtitle: String?
    let icon: String
    let colors: [Color]
    @Binding var isOn: Bool

    init(
        _ title: String,
        subtitle: String? = nil,
        icon: String,
        colors: [Color],
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.colors = colors
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 10) {
            AidenteIconBadge(icon: icon, colors: colors, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(AidenteL10n.t(title))
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(AidenteL10n.t(subtitle))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(colors.first ?? AidenteTheme.jade)
        }
        .padding(.vertical, 2)
    }
}

struct AidenteControlRow<Trailing: View>: View {
    @Default(.appLanguage) private var appLanguage

    let title: String
    let subtitle: String?
    let icon: String
    let colors: [Color]
    @ViewBuilder let trailing: Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        icon: String,
        colors: [Color],
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.colors = colors
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            AidenteIconBadge(icon: icon, colors: colors, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(AidenteL10n.t(title))
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(AidenteL10n.t(subtitle))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 2)
    }
}

struct AidenteRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.09))
            .frame(height: 1)
    }
}

struct AidenteNotice: View {
    @Default(.appLanguage) private var appLanguage

    let text: String
    var icon = "exclamationmark.triangle.fill"
    var colors = [AidenteTheme.amber, AidenteTheme.gold]

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            AidenteIconBadge(icon: icon, colors: colors, size: 26)
            Text(AidenteL10n.t(text))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill((colors.first ?? AidenteTheme.amber).opacity(0.075))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder((colors.first ?? AidenteTheme.amber).opacity(0.20))
        )
    }
}

struct AidenteActionButtonStyle: ButtonStyle {
    let colors: [Color]

    private var tint: Color { colors.first ?? AidenteTheme.ocean }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.13 : 0.20))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(tint.opacity(0.34), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct AidenteInsetPanel<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.primary.opacity(0.09), lineWidth: 1)
            }
    }
}

/// Shared "helper install/repair failed" alert used by both the Charging and
/// Permissions settings pages, so the wording and dismiss behavior stay in
/// one place.
private struct AidenteInstallErrorAlert: ViewModifier {
    @Binding var error: String?

    func body(content: Content) -> some View {
        content.alert(
            AidenteL10n.t("无法启用充电控制服务", "Cannot Enable Charging Control Service"),
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )
        ) {
            Button(AidenteL10n.t("好", "OK")) { error = nil }
        } message: {
            if let error {
                Text(error)
            }
        }
    }
}

extension View {
    func aidenteInstallErrorAlert(_ error: Binding<String?>) -> some View {
        modifier(AidenteInstallErrorAlert(error: error))
    }
}

extension ScheduleActionKind {
    /// Icon badge and color pair for UI rows, kept with the other shared
    /// theme components (the model file stays SwiftUI-free).
    var icon: String {
        switch self {
        case .setChargeLimit: "battery.75percent"
        case .startCalibration: "arrow.triangle.2.circlepath.circle.fill"
        case .topUp: "bolt.circle.fill"
        case .pauseCharging: "pause.circle.fill"
        case .dischargeTo: "arrow.down.circle.fill"
        case .resumeCharging: "play.circle.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .setChargeLimit: AidenteTheme.chargingColors
        case .startCalibration: AidenteTheme.dashboardColors
        case .topUp: AidenteTheme.automationColors
        case .pauseCharging: [AidenteTheme.coral, AidenteTheme.amber]
        case .dischargeTo: AidenteTheme.generalColors
        case .resumeCharging: AidenteTheme.generalColors
        }
    }
}

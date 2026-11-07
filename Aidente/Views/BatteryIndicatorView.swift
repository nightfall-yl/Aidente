import SwiftUI

/// Shared geometry keeps the menu-bar allocation aligned with the rendered icon.
enum BatteryIndicatorLayout {
    static let bodyWidth: CGFloat = 19
    static let bodyHeight: CGFloat = 11
    static let insideBodyWidth: CGFloat = 24
    static let insideBodyHeight: CGFloat = 13
    static let terminalWidth: CGFloat = 2
    static let terminalHeight: CGFloat = 4
    static let terminalSpacing: CGFloat = 1
    static let outsideTextSpacing: CGFloat = 2
    static let statusInset: CGFloat = 1
    /// Also used by StatusBarManager to measure the menu-bar slot width.
    static let percentageFontSize: CGFloat = 12

    static func width(insidePercentage: Bool) -> CGFloat {
        (insidePercentage ? insideBodyWidth : bodyWidth) + terminalSpacing + terminalWidth
    }
}

struct BatteryIndicatorView: View {
    let batteryLevel: Int
    let chargingMode: ChargingMode
    var isLowPowerModeEnabled: Bool = false
    var percentageDisplayLocation: PercentageDisplayLocation = .hidden
    var showState: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var shouldShowInsidePercentage: Bool {
        percentageDisplayLocation == .insideIcon
    }

    private var shouldShowOutsidePercentage: Bool {
        percentageDisplayLocation == .nextToIcon
    }

    private var isCritical: Bool {
        showState && batteryLevel <= 20
    }

    /// macOS 15 draws the menu-bar battery as a monochrome template image: the
    /// outline, the level fill and the terminal all use the menu-bar foreground
    /// colour. Only the two system warnings are tinted (low battery, Low Power
    /// Mode); charging is communicated by the bolt glyph instead of a colour.
    private var fillColor: Color {
        if isCritical { return AidenteTheme.coral }
        if isLowPowerModeEnabled { return AidenteTheme.gold }
        return .primary
    }

    /// Numerals and glyphs sit on top of the solid fill, so they need the
    /// opposite of the menu-bar foreground colour in both appearances.
    private var inverseColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private enum Layout {
        static let cornerRadius: CGFloat = 2.5
        static let strokeWidth: CGFloat = 1
        static let inset: CGFloat = 1.5
        static let contentCornerRadius: CGFloat = 1.2
        static let glyphBackingCornerRadius: CGFloat = 1
        static var percentageFontSize: CGFloat { BatteryIndicatorLayout.percentageFontSize }
        static let insideFontSize: CGFloat = 9.5
        static let insideFullFontSize: CGFloat = 8.8
        static let levelAnimation: Animation = .easeInOut(duration: 0.25)
    }

    var body: some View {
        HStack(spacing: BatteryIndicatorLayout.outsideTextSpacing) {
            if shouldShowOutsidePercentage {
                Text("\(batteryLevel)%")
                    .font(.system(size: Layout.percentageFontSize))
                    .monospacedDigit()
            }

            HStack(spacing: BatteryIndicatorLayout.terminalSpacing) {
                batteryBody
                BatteryTerminal(
                    width: BatteryIndicatorLayout.terminalWidth,
                    height: BatteryIndicatorLayout.terminalHeight,
                    cornerRadius: 0.75
                )
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = [
            AidenteL10n.t(
                "电池电量 \(batteryLevel)%",
                "Battery level \(batteryLevel)%"
            )
        ]
        switch chargingMode {
        case .charging: parts.append(AidenteL10n.t("正在充电"))
        case .pluggedIn: parts.append(AidenteL10n.t("已接通电源", "Plugged In"))
        case .discharging: break
        }
        if isLowPowerModeEnabled {
            parts.append(AidenteL10n.t("低电量模式", "Low Power Mode"))
        }
        return parts.joined(separator: "，")
    }

    private var batteryBody: some View {
        ZStack {
            // macOS 15: a crisp single-colour outline over a transparent
            // interior. There is no tinted "track" behind the level fill.
            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .strokeBorder(.primary, lineWidth: Layout.strokeWidth)

            if shouldShowInsidePercentage {
                // When the percentage lives inside the icon the cell is filled
                // solid, with the numerals knocked out in the inverse colour.
                RoundedRectangle(cornerRadius: Layout.contentCornerRadius)
                    .fill(fillColor)
                    .padding(Layout.inset)
            } else {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: Layout.contentCornerRadius)
                        .fill(fillColor)
                        .frame(width: fillWidth(usableWidth: geo.size.width))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(Layout.levelAnimation, value: batteryLevel)
                }
                .padding(Layout.inset)
            }

            if shouldShowInsidePercentage {
                insideContent
            } else {
                chargingGlyph
            }
        }
        .frame(
            width: shouldShowInsidePercentage ? BatteryIndicatorLayout.insideBodyWidth : BatteryIndicatorLayout.bodyWidth,
            height: shouldShowInsidePercentage ? BatteryIndicatorLayout.insideBodyHeight : BatteryIndicatorLayout.bodyHeight
        )
    }

    private func fillWidth(usableWidth: CGFloat) -> CGFloat {
        usableWidth * CGFloat(min(100, max(0, batteryLevel))) / 100
    }

    private var insideContent: some View {
        HStack(spacing: 0.5) {
            Text(verbatim: "\(batteryLevel)")
                .font(.system(
                    size: batteryLevel >= 100
                        ? Layout.insideFullFontSize : Layout.insideFontSize,
                    weight: .semibold
                ))
                .monospacedDigit()
                .fixedSize()
            chargingGlyph
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(inverseColor)
    }

    /// A small filled backing keeps the bolt/plug legible whether it lands on
    /// the level fill or on the transparent part of the cell at low charge.
    @ViewBuilder
    private var chargingGlyph: some View {
        if chargingMode != .discharging {
            Image(systemName: chargingMode == .charging ? "bolt.fill" : "powerplug.fill")
                .resizable()
                .scaledToFit()
                .frame(
                    width: chargingMode == .charging ? 4 : 4.6,
                    height: 7
                )
                .foregroundStyle(inverseColor)
                .padding(0.4)
                .background(
                    fillColor,
                    in: RoundedRectangle(cornerRadius: Layout.glyphBackingCornerRadius)
                )
        }
    }
}

struct BatteryTerminal: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: cornerRadius
        )
        .fill(.primary)
        .frame(width: width, height: height)
        .opacity(0.9)
    }
}

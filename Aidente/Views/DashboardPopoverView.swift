import AppKit
import CoreGraphics
import Defaults
import SwiftUI

/// Shared geometry for the dashboard presentation. Keep the width in one
/// place so the popover, standalone window and preview panel stay in sync;
/// the height is an upper bound only — the real height is measured from the
/// visible content and reported to AppKit.
enum DashboardLayout {
    static let width: CGFloat = 400
    static let maxHeight: CGFloat = 800
    static let dividerHeight: CGFloat = 1
}

/// The six cards that can be toggled and reordered from the dashboard itself.
/// Raw values are persisted in `dashboardCardOrder`, so keep them stable;
/// `allCases` doubles as the canonical order for newly added cards.
private enum DashboardEditableCard: String, CaseIterable, Identifiable {
    case colorEnergyFlow
    case batteryHealth
    case capacityHistory
    case energyAppRanking
    case careActions
    case automaticProtection

    var id: String { rawValue }

    /// Reuse the existing wording so the dock and the card always agree in
    /// both languages — no hand-written English labels here.
    var title: String {
        switch self {
        case .colorEnergyFlow: AidenteL10n.t("彩色能量流")
        case .batteryHealth: AidenteL10n.t("电池健康")
        case .capacityHistory: AidenteL10n.t("容量与寿命趋势")
        case .energyAppRanking: AidenteL10n.t("当前耗电 App")
        case .careActions: AidenteL10n.t("快捷养护")
        case .automaticProtection: AidenteL10n.t("自动保护")
        }
    }

    var icon: String {
        switch self {
        case .colorEnergyFlow: "point.3.connected.trianglepath.dotted"
        case .batteryHealth: "heart.text.square.fill"
        case .capacityHistory: "chart.xyaxis.line"
        case .energyAppRanking: "bolt.horizontal.circle.fill"
        case .careActions: "leaf.fill"
        case .automaticProtection: "shield.lefthalf.filled"
        }
    }
}

private enum DashboardFooterMetrics {
    static let hoverHeight: CGFloat = 20
    static let barHeight: CGFloat = 34
    static let dockHeight: CGFloat = 46
    /// Keep footer controls on the same 8pt continuous corner as the three
    /// `ProtectionPill` buttons in the Automatic Protection card.
    static let buttonCornerRadius: CGFloat = 8
}

/// Hit area shared by card-wide long-press (idle) and card-wide reorder drag
/// (edit mode). The 14pt continuous corner matches `PopoverCardBackground`;
/// the outer 2pt stays inert so the card edge cannot trigger either gesture.
private enum DashboardCardHitArea {
    static let cornerRadius: CGFloat = 14
    static let edgeInset: CGFloat = 2
}

/// Card frames in the `dashboardCards` coordinate space. Reordering uses a
/// plain DragGesture on a handle plus these frames, so it no longer depends on
/// NSItemProvider / UTI matching or competes with buttons inside the cards.
private struct DashboardCardFrameKey: PreferenceKey {
    static let defaultValue: [DashboardEditableCard: CGRect] = [:]

    static func reduce(
        value: inout [DashboardEditableCard: CGRect],
        nextValue: () -> [DashboardEditableCard: CGRect]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct DashboardHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DashboardContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct DashboardPopoverView: View {
    let viewModel: MenuViewModel
    let onOpenSettings: (SettingsTab) -> Void
    let onQuit: () -> Void

    @Default(.chargeLimit) private var chargeLimit
    @Default(.manageCharging) private var manageCharging
    @Default(.enableHeatProtectionMode) private var heatProtectionEnabled
    @Default(.stopChargingWhileSleeping) private var sleepPauseEnabled
    @Default(.sailingMode) private var sailingModeEnabled
    @Default(.appLanguage) private var appLanguage
    @Default(.showPowerSource) private var showPowerSource
    @Default(.showTimeTillDischarge) private var showTimeTillDischarge
    @Default(.showUptime) private var showUptime
    @Default(.showInternalPower) private var showInternalPower
    @Default(.showExternalPower) private var showExternalPower
    @Default(.showPowerDistribution) private var showPowerDistribution
    @Default(.showCapacityHistory) private var showCapacityHistory
    @Default(.showEnergyAppRanking) private var showEnergyAppRanking
    @Default(.showCareActions) private var showCareActions
    @Default(.showAutomaticProtection) private var showAutomaticProtection
    @Default(.showBatteryHealthCard) private var showBatteryHealthCard
    @Default(.dashboardCardOrder) private var dashboardCardOrder
    @Default(.appAppearance) private var appAppearance
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var systemAppearanceMonitor = SystemAppearanceMonitor()

    /// Called whenever the measured content height changes so AppKit can
    /// resize the popover / standalone window / preview panel.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var chargeLimitDraft: Double = 80
    @State private var isAdjustingChargeLimit = false
    @State private var capacityHistoryRange: CapacityHistoryRange = .all
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var isEditingCards = false
    @State private var isFooterHovering = false
    @State private var draggingCard: DashboardEditableCard?
    @State private var dropTarget: DashboardEditableCard?
    @State private var cardFrames: [DashboardEditableCard: CGRect] = [:]

    /// Always explicit;「自动」resolves to the current system appearance (see
    /// SettingsView.resolvedPreferredScheme — nil is sticky in AppKit hosting).
    private var resolvedPreferredScheme: ColorScheme {
        switch appAppearance {
        case .light: return .light
        case .dark: return .dark
        case .auto: return systemAppearanceMonitor.isDark ? .dark : .light
        }
    }

    private var footerHeight: CGFloat {
        guard isEditingCards else { return DashboardFooterMetrics.hoverHeight }
        return DashboardFooterMetrics.barHeight
            + (hiddenCards.isEmpty ? 0 : DashboardFooterMetrics.dockHeight)
    }

    private var scrollHeight: CGFloat {
        let available =
            DashboardLayout.maxHeight
            - headerHeight
            - DashboardLayout.dividerHeight
            - footerHeight
        return max(0, min(contentHeight, available))
    }

    private var totalHeight: CGFloat {
        headerHeight + DashboardLayout.dividerHeight + scrollHeight + footerHeight
    }

    var body: some View {
        ZStack {
            AidenteWindowBackdrop()

            VStack(spacing: 0) {
                // Plan A + B: the dashboard chrome is transparent so the
                // L0 glass shows through; only a 1pt neutral rule remains.
                header
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: DashboardHeaderHeightKey.self,
                            value: geo.size.height
                        )
                    })
                    .zIndex(1)

                Rectangle()
                    .fill(AidenteSurfaceTokens.stroke(scheme: colorScheme))
                    .frame(height: DashboardLayout.dividerHeight)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        // The hero is the only pinned card: always rendered and
                        // never part of edit mode.
                        statusHero
                        ForEach(visibleCards) { card in
                            editableCard(card)
                        }
                    }
                    .coordinateSpace(name: "dashboardCards")
                    .padding(.horizontal, 14)
                    .padding(.top, 11)
                    // 2pt to the hover hint; keep the old 11pt in edit mode so
                    // the dock is not glued to the last card.
                    .padding(.bottom, isEditingCards ? 11 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: DashboardContentHeightKey.self,
                            value: geo.size.height
                        )
                    })
                }
                .scrollIndicators(.never)
                .frame(height: scrollHeight)

                dashboardFooter
                    .frame(height: footerHeight)
            }
        }
        .frame(width: DashboardLayout.width, height: totalHeight)
        .preferredColorScheme(resolvedPreferredScheme)
        .tint(AidenteTheme.jade)
        .onPreferenceChange(DashboardHeaderHeightKey.self) { headerHeight = $0 }
        .onPreferenceChange(DashboardContentHeightKey.self) { contentHeight = $0 }
        .onPreferenceChange(DashboardCardFrameKey.self) { cardFrames = $0 }
        .onChange(of: totalHeight) { _, newValue in
            guard newValue > 0 else { return }
            onHeightChange(newValue)
        }
        .onAppear {
            chargeLimitDraft = Double(chargeLimit)
        }
        .onChange(of: chargeLimit) { _, newValue in
            guard !isAdjustingChargeLimit else { return }
            chargeLimitDraft = Double(newValue)
        }
    }

    // MARK: - Editable dashboard cards

    private var orderedCards: [DashboardEditableCard] {
        var result: [DashboardEditableCard] = []
        for raw in dashboardCardOrder.split(separator: ",") {
            if let card = DashboardEditableCard(rawValue: String(raw)),
               !result.contains(card) {
                result.append(card)
            }
        }
        // Insert newly added cards at their canonical position instead of
        // appending: a saved 4-card order keeps its relative order and the
        // battery card lands back where the metrics strip used to be.
        let canonical = DashboardEditableCard.allCases
        for card in canonical where !result.contains(card) {
            let canonicalIndex = canonical.firstIndex(of: card) ?? 0
            if let next = result.first(where: { candidate in
                (canonical.firstIndex(of: candidate) ?? 0) > canonicalIndex
            }), let insertAt = result.firstIndex(of: next) {
                result.insert(card, at: insertAt)
            } else {
                result.append(card)
            }
        }
        return result
    }

    private var visibleCards: [DashboardEditableCard] {
        orderedCards.filter { isCardVisible($0) }
    }

    private var hiddenCards: [DashboardEditableCard] {
        orderedCards.filter { !isCardVisible($0) }
    }

    private func isCardVisible(_ card: DashboardEditableCard) -> Bool {
        switch card {
        case .colorEnergyFlow: showPowerDistribution
        case .batteryHealth: showBatteryHealthCard
        case .capacityHistory: showCapacityHistory
        case .energyAppRanking: showEnergyAppRanking
        case .careActions: showCareActions
        case .automaticProtection: showAutomaticProtection
        }
    }

    private func setCardVisible(_ card: DashboardEditableCard, _ visible: Bool) {
        switch card {
        case .colorEnergyFlow: showPowerDistribution = visible
        case .batteryHealth: showBatteryHealthCard = visible
        case .capacityHistory: showCapacityHistory = visible
        case .energyAppRanking: showEnergyAppRanking = visible
        case .careActions: showCareActions = visible
        case .automaticProtection: showAutomaticProtection = visible
        }
    }

    private func enterCardEditMode() {
        isFooterHovering = false
        withAnimation(.easeInOut(duration: 0.18)) {
            isEditingCards = true
        }
    }

    @ViewBuilder
    private func cardView(_ card: DashboardEditableCard) -> some View {
        switch card {
        case .colorEnergyFlow: powerSummary
        case .batteryHealth: batterySummary
        case .capacityHistory: capacityHistory
        case .energyAppRanking: energyAppRanking
        case .careActions: careActions
        case .automaticProtection: automaticProtection
        }
    }

    @ViewBuilder
    private func editableCard(_ card: DashboardEditableCard) -> some View {
        if isEditingCards {
            cardView(card)
                .opacity(draggingCard == card ? 0.6 : 1)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: DashboardCardFrameKey.self,
                            value: [card: geo.frame(in: .named("dashboardCards"))]
                        )
                    }
                }
                // A transparent layer over the whole card owns the press, so
                // buttons / pickers inside the card cannot steal the drag.
                // The inset keeps the outer 2pt edge inert, matching the idle
                // long-press below.
                .overlay {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: DashboardCardHitArea.cornerRadius,
                                style: .continuous
                            )
                            .inset(by: DashboardCardHitArea.edgeInset)
                        )
                        .gesture(reorderGesture(card))
                }
                .overlay(alignment: .top) {
                    if draggingCard != nil, draggingCard != card, dropTarget == card {
                        Rectangle()
                            .fill(AidenteTheme.ocean)
                            .frame(height: 2)
                            .allowsHitTesting(false)
                    }
                }
                // Added last so the remove badge stays above the drag layer.
                .overlay(alignment: .topLeading) { removeBadge(card) }
        } else {
            // Without an explicit content shape, transparent areas (the header
            // Spacer, VStack spacing, the 13pt card padding) do not participate
            // in hit testing, so a parent long-press only fires over real
            // subviews. Shape the whole card instead, with a 2pt inert edge.
            // Every non-pinned card goes through this branch.
            cardView(card)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: DashboardCardHitArea.cornerRadius,
                        style: .continuous
                    )
                    .inset(by: DashboardCardHitArea.edgeInset)
                )
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.5, maximumDistance: 24)
                        .onEnded { _ in enterCardEditMode() }
                )
        }
    }

    private func removeBadge(_ card: DashboardEditableCard) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                setCardVisible(card, false)
            }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(AidenteTheme.coral))
        }
        .buttonStyle(.plain)
        .offset(x: -7, y: -7)
        .accessibilityLabel(
            AidenteL10n.t("移出仪表盘", "Remove from dashboard")
        )
    }

    /// Attached to the full-card transparent layer in edit mode. No handle:
    /// pressing anywhere on the card and dragging reorders it.
    private func reorderGesture(_ card: DashboardEditableCard) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("dashboardCards"))
            .onChanged { value in
                draggingCard = card
                dropTarget = targetCard(at: value.location, excluding: card)
            }
            .onEnded { value in
                if let target = targetCard(at: value.location, excluding: card) {
                    commitReorder(card, onto: target)
                }
                resetDragState()
            }
    }

    private func targetCard(
        at point: CGPoint,
        excluding card: DashboardEditableCard
    ) -> DashboardEditableCard? {
        for candidate in visibleCards where candidate != card {
            if let frame = cardFrames[candidate], frame.contains(point) {
                return candidate
            }
        }
        return nil
    }

    private func commitReorder(
        _ dragged: DashboardEditableCard,
        onto target: DashboardEditableCard
    ) {
        var order = orderedCards
        guard let from = order.firstIndex(of: dragged),
              let originalTargetIndex = order.firstIndex(of: target) else { return }
        order.remove(at: from)
        guard let targetIndex = order.firstIndex(of: target) else { return }
        let insertAt = targetIndex + (from < originalTargetIndex ? 1 : 0)
        order.insert(dragged, at: min(insertAt, order.count))
        dashboardCardOrder = order.map(\.rawValue).joined(separator: ",")
    }

    private func resetDragState() {
        draggingCard = nil
        dropTarget = nil
    }

    // MARK: - Footer (hover hint / edit dock)

    @ViewBuilder
    private var dashboardFooter: some View {
        if isEditingCards {
            VStack(spacing: 0) {
                if !hiddenCards.isEmpty { dockRow }
                editingBar
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AidenteSurfaceTokens.stroke(scheme: colorScheme))
                    .frame(height: DashboardLayout.dividerHeight)
            }
        } else {
            hoverHint
        }
    }

    private var hoverHint: some View {
        // Keep the hint vertically centred between the last card's bottom
        // edge and the panel's bottom edge; `AidenteFooterHintSurface` still
        // fills the whole 20pt hover strip via its own max-size frame.
        ZStack {
            if isFooterHovering {
                AidenteFooterHintSurface()
                    .transition(.opacity)
                Text(AidenteL10n.t("长按进入编辑模式", "Long-press to enter edit mode"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: DashboardFooterMetrics.hoverHeight)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isFooterHovering = hovering
            }
        }
        .onLongPressGesture(
            minimumDuration: 0.5,
            maximumDistance: 24,
            perform: enterCardEditMode
        )
    }

    private var dockRow: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(hiddenCards) { card in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                setCardVisible(card, true)
                            }
                        } label: {
                            Label(card.title, systemImage: card.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            // Solid ocean is the leading colour of the hero
                            // charge bar at 0%; the label stays white.
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: DashboardFooterMetrics.buttonCornerRadius,
                                    style: .continuous
                                )
                                .fill(AidenteTheme.ocean)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            AidenteL10n.t("添加到仪表盘：", "Add to dashboard: ") + card.title
                        )
                    }
                }
                // Let the row keep its intrinsic width: titles never collapse and
                // the dock scrolls right instead of squeezing everything in.
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                // When only a few capsules remain they are narrower than the
                // panel: give the row a minimum width equal to the visible dock
                // area so the capsules centre instead of pinning to the leading
                // edge. Once they exceed that width the intrinsic width wins and
                // the row scrolls right exactly as before.
                // `alignment` only has an effect when the frame is larger than
                // its content, so reserve vertical space too — otherwise the
                // capsules stay pinned to the top of the 46pt dock row and all
                // the leftover space collects underneath them.
                .frame(
                    minWidth: proxy.size.width,
                    minHeight: proxy.size.height,
                    alignment: .center
                )
            }
        }
        .frame(height: DashboardFooterMetrics.dockHeight)
    }

    private var editingBar: some View {
        HStack(spacing: 8) {
            Text(
                hiddenCards.isEmpty
                    ? AidenteL10n.t("通过拖放重新排列卡片。", "Drag to reorder cards.")
                    : AidenteL10n.t(
                        "通过拖放重新排列卡片，或点按上方图标添加。",
                        "Drag to reorder cards, or click an icon above to add one."
                    )
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Spacer(minLength: 6)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isEditingCards = false
                    isFooterHovering = false
                    resetDragState()
                }
            } label: {
                Text(AidenteL10n.t("已完成", "Done"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(
                            cornerRadius: DashboardFooterMetrics.buttonCornerRadius,
                            style: .continuous
                        )
                        .fill(AidenteSurfaceTokens.controlFill(scheme: colorScheme))
                    }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .frame(height: DashboardFooterMetrics.barHeight)
        .padding(.horizontal, 14)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(viewModel.batteryModeText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                Spacer()

                HStack(spacing: 6) {
                    HeaderButton(icon: "arrow.clockwise", label: AidenteL10n.t("刷新")) { viewModel.refresh() }
                    HeaderButton(icon: "gearshape.fill", label: AidenteL10n.t("设置")) { onOpenSettings(.general) }
                    HeaderButton(icon: "power", label: AidenteL10n.t("退出")) { onQuit() }
                }
            }

            if showUptime || showTimeTillDischarge {
                VStack(alignment: .leading, spacing: 2) {
                    if showUptime {
                        Text(AidenteL10n.t("系统运行时间：") + viewModel.uptimeText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if showTimeTillDischarge {
                        Text(AidenteL10n.t("电池剩余时间：") + viewModel.timeRemainingText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var statusHero: some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                Image(
                    systemName: viewModel.adapterConnected
                        ? (viewModel.isCharging ? "bolt.fill" : "powerplug.fill")
                        : "battery.75percent"
                )
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? Color.white : heroTint)
                .frame(width: 39, height: 39)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(heroTint.opacity(0.17))
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.operationStatusText)
                        .font(.system(size: 15, weight: .bold))
                }

                Spacer()
            }

            BatteryChargeLimitControl(
                batteryLevel: viewModel.displayPercentage,
                chargeLimitDraft: $chargeLimitDraft,
                tint: heroTint
            ) { editing in
                isAdjustingChargeLimit = editing
                if !editing {
                    chargeLimit = displayedChargeLimit
                }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(manageCharging ? heroTint : warningTint)
                    .frame(width: 6, height: 6)
                    .shadow(
                        color: manageCharging ? heroTint : warningTint,
                        radius: 4
                    )
                Text(
                    manageCharging
                        ? AidenteL10n.t(
                            "达到 \(displayedChargeLimit)% 后自动暂停充电",
                            "Charging pauses automatically at \(displayedChargeLimit)%"
                        )
                        : AidenteL10n.t(
                            "只读监测 · 上限会在启用充电管理后生效",
                            "Read-only monitoring · Enable charging control to apply the limit"
                        )
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                Color(red: 0.115, green: 0.145, blue: 0.18).opacity(0.95),
                                Color(red: 0.065, green: 0.075, blue: 0.09).opacity(0.92),
                            ]
                            : [
                                Color.white.opacity(0.97),
                                heroTint.opacity(0.14),
                            ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(heroTint)
                .frame(width: 2)
                .shadow(color: heroTint, radius: 8)
                .padding(.vertical, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : heroTint.opacity(0.28),
                    lineWidth: 1
                )
        }
        .shadow(color: heroTint.opacity(0.12), radius: 10, y: 4)
        // The hero now follows the system appearance like the rest of the
        // dashboard, so .primary/.secondary resolve correctly on its surface.
    }

    /// All three metrics are always on: the settings page no longer exposes
    /// per-metric switches, so this card no longer reads those preferences.
    private var batterySummary: some View {
        let metrics: [(title: String, value: String, tint: Color, compact: Bool)] = [
            ("电池健康", viewModel.batteryHealthText, AidenteTheme.jade, false),
            ("循环次数", viewModel.cycleCountText, AidenteTheme.violet, false),
            ("电池温度", viewModel.batteryTemperatureText, AidenteTheme.amber, false),
        ]

        return PopoverCompactCard {
            HStack(spacing: 0) {
                ForEach(0..<metrics.count, id: \.self) { index in
                    if index > 0 {
                        CompactDivider()
                    }
                    let metric = metrics[index]
                    CompactMetric(
                        title: metric.title,
                        value: metric.value,
                        tint: metric.tint,
                        compact: metric.compact
                    )
                }
            }
        }
    }

    private var powerSummary: some View {
        PopoverCompactCard {
            VStack(spacing: 8) {
                HStack {
                    Label(
                        AidenteL10n.t("彩色能量流"),
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if showPowerSource {
                        Text(viewModel.powerSourceText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                CompactPowerFlowDiagram(
                    powerSource: viewModel.powerSource,
                    isCharging: viewModel.isCharging,
                    adapterPower: viewModel.adapterPower,
                    systemPower: viewModel.systemPower,
                    batteryPower: viewModel.batteryPower,
                    adapterElectricalText: viewModel.adapterElectricalText,
                    batteryElectricalText: viewModel.batteryElectricalText
                )

                if showInternalPower || showExternalPower {
                    HStack(spacing: 12) {
                        if showInternalPower {
                            Label(
                                viewModel.internalInputText,
                                systemImage: "battery.50percent"
                            )
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                        if showExternalPower {
                            Label(
                                viewModel.externalInputText,
                                systemImage: "powerplug.fill"
                            )
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var capacityHistory: some View {
        PopoverCompactCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(
                        AidenteL10n.t("容量与寿命趋势"),
                        systemImage: "chart.xyaxis.line"
                    )
                    .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    Picker("", selection: $capacityHistoryRange) {
                        ForEach(CapacityHistoryRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .frame(width: 146)
                }

                Label(
                    viewModel.batteryHistoryTrackingText,
                    systemImage: "calendar.badge.clock"
                )
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    CompactMetric(
                        title: "当前容量",
                        value: viewModel.currentCapacityText,
                        tint: AidenteTheme.jade,
                        compact: true
                    )
                    CompactDivider()
                    CompactMetric(
                        title: "估算满充",
                        value: viewModel.estimatedFullCapacityText,
                        tint: AidenteTheme.ocean,
                        compact: true
                    )
                    CompactDivider()
                    CompactMetric(
                        title: "设计容量",
                        value: viewModel.designCapacityText,
                        tint: AidenteTheme.violet,
                        compact: true
                    )
                }

                BatteryCapacityChartView(
                    samples: viewModel.batteryCapacityHistory,
                    range: capacityHistoryRange
                )

                HStack(spacing: 12) {
                    CapacityLegend(title: "当前容量", tint: AidenteTheme.jade)
                    CapacityLegend(title: "估算满充", tint: AidenteTheme.ocean)
                    CapacityLegend(
                        title: "设计容量",
                        tint: AidenteTheme.violet,
                        dashed: true
                    )
                    Spacer(minLength: 0)
                }

                Text(
                    AidenteL10n.t(
                        "容量数据由 macOS 根据充放电状态估算，仅供电池养护参考。",
                        "Capacity values are estimated by macOS from charge and discharge data and are for battery-care reference only."
                    )
                )
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var energyAppRanking: some View {
        PopoverCompactCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        AidenteL10n.t("当前耗电 App"),
                        systemImage: "bolt.horizontal.circle.fill"
                    )
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(AidenteL10n.t("按处理器活动实时估算"))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                if !viewModel.hasEnergyUsageSample {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(AidenteL10n.t("正在采样当前应用活动…"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } else if viewModel.topEnergyApps.isEmpty {
                    Text(AidenteL10n.t("当前没有检测到明显耗电的前台应用"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    let maximum = max(
                        viewModel.topEnergyApps.map(\.cpuUsage).max() ?? 1,
                        1
                    )
                    ForEach(
                        Array(viewModel.topEnergyApps.prefix(3).enumerated()),
                        id: \.element.id
                    ) { item in
                        EnergyAppRow(
                            rank: item.offset + 1,
                            app: item.element,
                            maximumCPUUsage: maximum,
                            tint: energyTint(for: item.offset)
                        )
                    }
                }
            }
        }
    }

    private var careActions: some View {
        PopoverCompactCard {
            VStack(spacing: 10) {
                HStack {
                    Label(AidenteL10n.t("快捷养护"), systemImage: "leaf.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(viewModel.operationStatusText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(statusTint)
                }

                CompactActionRow(
                    title: "暂停充电",
                    subtitle: viewModel.manualPauseActive
                        ? "当前已暂停，点击恢复管理"
                        : "保持适配器供电，停止电池充入",
                    icon: viewModel.manualPauseActive ? "pause.fill" : "pause.circle",
                    tint: AidenteTheme.coral,
                    isOn: viewModel.manualPauseActive,
                    action: viewModel.toggleManualPause
                )

                CompactActionRow(
                    title: "临时充至 100%",
                    subtitle: AidenteL10n.t(
                        "完成后恢复 \(displayedChargeLimit)% 充电上限",
                        "Restore the \(displayedChargeLimit)% charge limit when complete"
                    ),
                    icon: "bolt.fill",
                    tint: AidenteTheme.amber,
                    isOn: viewModel.chargeLimitOverrideActive,
                    action: viewModel.toggleChargeLimitOverride
                )

                CompactActionRow(
                    title: "放电至充电上限",
                    subtitle: AidenteL10n.t(
                        "使用电池降低至 \(displayedChargeLimit)%",
                        "Use the battery until it reaches \(displayedChargeLimit)%"
                    ),
                    icon: "arrow.down.circle.fill",
                    tint: AidenteTheme.ocean,
                    isOn: viewModel.forceDischargeActive,
                    action: viewModel.toggleForceDischarge
                )

                CompactActionRow(
                    title: "电池校准",
                    subtitle: "执行完整充放电校准流程",
                    icon: "arrow.triangle.2.circlepath",
                    tint: AidenteTheme.violet,
                    isOn: viewModel.calibrationActive,
                    action: viewModel.toggleCalibration
                )
            }
        }
    }

    private var automaticProtection: some View {
        PopoverCompactCard {
            VStack(alignment: .leading, spacing: 9) {
                Label(AidenteL10n.t("自动保护"), systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 7) {
                    ProtectionPill(
                        title: "高温",
                        isEnabled: heatProtectionEnabled,
                        action: { heatProtectionEnabled.toggle() }
                    )
                    ProtectionPill(
                        title: "睡眠暂停",
                        isEnabled: sleepPauseEnabled,
                        action: { sleepPauseEnabled.toggle() }
                    )
                    ProtectionPill(
                        title: "巡航",
                        isEnabled: sailingModeEnabled,
                        action: { sailingModeEnabled.toggle() }
                    )
                }
            }
        }
    }

    private var displayedChargeLimit: Int {
        min(max(Int(chargeLimitDraft.rounded()), 20), 100)
    }

    private var statusTint: Color {
        if viewModel.hasControlError { return AidenteTheme.coral }
        if viewModel.isCharging { return AidenteTheme.amber }
        return AidenteTheme.jade
    }

    /// The regular accents are tuned for dark surfaces and wash out on white.
    /// The hero card is light in light mode, so use deeper variants there.
    private var heroTint: Color {
        guard colorScheme == .light else { return statusTint }
        if viewModel.hasControlError {
            return Color(red: 0.80, green: 0.16, blue: 0.14)
        }
        if viewModel.isCharging {
            return Color(red: 0.78, green: 0.40, blue: 0.04)
        }
        return Color(red: 0.05, green: 0.52, blue: 0.28)
    }

    private var warningTint: Color {
        colorScheme == .dark
            ? AidenteTheme.amber
            : Color(red: 0.78, green: 0.40, blue: 0.04)
    }

    private func energyTint(for index: Int) -> Color {
        switch index {
        case 0: AidenteTheme.amber
        case 1: AidenteTheme.ocean
        default: AidenteTheme.violet
        }
    }
}

private struct BatteryChargeLimitControl: View {
    @Default(.appLanguage) private var appLanguage
    @Environment(\.colorScheme) private var colorScheme

    let batteryLevel: Int
    @Binding var chargeLimitDraft: Double
    let tint: Color
    let onEditingChanged: (Bool) -> Void

    private var chargeLimit: Int {
        min(max(Int(chargeLimitDraft.rounded()), 20), 100)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("\(batteryLevel)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    Text(AidenteL10n.t("实时电量"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(AidenteL10n.t("上限"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(chargeLimit)%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let safeBattery = min(max(batteryLevel, 0), 100)
                let batteryWidth = width * CGFloat(safeBattery) / 100
                let limitX = width * CGFloat(chargeLimit) / 100

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.085)
                                : Color.black.opacity(0.08)
                        )
                        .frame(height: 10)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AidenteTheme.ocean, tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(5, batteryWidth), height: 10)
                        .shadow(color: tint.opacity(0.35), radius: 5)

                    ForEach(1..<10, id: \.self) { tick in
                        Rectangle()
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(tick % 2 == 0 ? 0.24 : 0.13)
                                    : Color.black.opacity(tick % 2 == 0 ? 0.20 : 0.10)
                            )
                            .frame(width: 1, height: tick % 2 == 0 ? 7 : 5)
                            .offset(x: width * CGFloat(tick) / 10)
                    }

                    ZStack {
                        Capsule()
                            .fill(.white.opacity(0.96))
                            .frame(width: 3, height: 20)
                            .shadow(color: .black.opacity(0.70), radius: 2)

                        Circle()
                            .fill(.white)
                            .frame(width: 13, height: 13)
                            .overlay {
                                Circle()
                                    .strokeBorder(tint.opacity(0.85), lineWidth: 2)
                            }
                            .shadow(color: tint.opacity(0.45), radius: 5)
                    }
                    .frame(width: 18, height: 24)
                    .offset(x: min(max(limitX - 9, 0), width - 18))
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onEditingChanged(true)
                            updateLimit(at: value.location.x, width: width)
                        }
                        .onEnded { value in
                            updateLimit(at: value.location.x, width: width)
                            onEditingChanged(false)
                        }
                )
            }
            .frame(height: 24)

            HStack {
                Text("0%")
                Spacer()
                Text(AidenteL10n.t("拖动白色标记调整上限"))
                Spacer()
                Text("100%")
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AidenteL10n.t("电池电量与充电上限", "Battery Level and Charge Limit")
        )
        .accessibilityValue(
            AidenteL10n.t(
                "实时电量 \(batteryLevel)%，充电上限 \(chargeLimit)%",
                "Battery level \(batteryLevel)%, charge limit \(chargeLimit)%"
            )
        )
        .accessibilityHint(
            AidenteL10n.t(
                "拖动或调整数值来修改充电上限",
                "Drag or adjust the value to change the charge limit"
            )
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                chargeLimitDraft = min(100, chargeLimitDraft + 1)
            case .decrement:
                chargeLimitDraft = max(20, chargeLimitDraft - 1)
            @unknown default:
                return
            }
            onEditingChanged(false)
        }
    }

    private func updateLimit(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let percentage = (x / width * 100).rounded()
        chargeLimitDraft = min(max(Double(percentage), 20), 100)
    }
}

private struct CompactPowerFlowDiagram: View {
    @Default(.appLanguage) private var appLanguage

    let powerSource: PowerSource
    let isCharging: Bool
    let adapterPower: Double
    let systemPower: Double
    let batteryPower: Double
    let adapterElectricalText: String
    let batteryElectricalText: String

    private let nodeWidth: CGFloat = 124
    private let nodeHeight: CGFloat = 54
    /// Cap the distance between the two node columns so a wider panel does
    /// not stretch the flow line all the way out to both edges.
    private let maxNodeGap: CGFloat = 72
    /// Keep wire ends clear of the node cards: their background is now
    /// semi-transparent, and round line caps extend past the endpoint.
    private let flowEndInset: CGFloat = 6

    private var diagramHeight: CGFloat {
        switch diagramMode {
        case .adapterSplit, .sourcesMerge:
            136
        case .adapterOnly, .batteryOnly:
            68
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let availableGap = max(0, geometry.size.width - nodeWidth * 2)
            let gap = min(availableGap, maxNodeGap)
            let leading = (geometry.size.width - nodeWidth * 2 - gap) / 2
            let leftX = leading + nodeWidth / 2
            let rightX = leftX + nodeWidth + gap
            // Shrink the inset on very narrow panels so the wire never folds
            // back on itself.
            let wireInset = min(flowEndInset, gap / 4)
            let topY: CGFloat = nodeHeight / 2
            let middleY = diagramHeight / 2
            let bottomY = diagramHeight - nodeHeight / 2

            ZStack {
                Canvas { context, _ in
                    drawFlows(
                        context: context,
                        leftX: leftX + nodeWidth / 2 + wireInset,
                        rightX: rightX - nodeWidth / 2 - wireInset,
                        arrowTipX: rightX - nodeWidth / 2,
                        topY: topY,
                        middleY: middleY,
                        bottomY: bottomY
                    )
                }
                .clipped()

                switch diagramMode {
                case .adapterSplit:
                    PowerFlowNode(
                        title: "适配器",
                        icon: "powerplug.fill",
                        power: adapterPower,
                        electricalText: adapterElectricalText,
                        tint: AidenteTheme.amber
                    )
                    .position(x: leftX, y: middleY)

                    PowerFlowNode(
                        title: "电池充入",
                        icon: isCharging ? "battery.100.bolt" : "battery.100",
                        power: batteryPower,
                        electricalText: batteryElectricalText,
                        tint: AidenteTheme.jade
                    )
                    .position(x: rightX, y: topY)

                    PowerFlowNode(
                        title: "系统使用",
                        icon: "laptopcomputer",
                        power: systemPower,
                        electricalText: nil,
                        tint: AidenteTheme.ocean
                    )
                    .position(x: rightX, y: bottomY)

                case .sourcesMerge:
                    PowerFlowNode(
                        title: "电池输出",
                        icon: "battery.100",
                        power: batteryPower,
                        electricalText: batteryElectricalText,
                        tint: AidenteTheme.jade
                    )
                    .position(x: leftX, y: topY)

                    PowerFlowNode(
                        title: "适配器",
                        icon: "powerplug.fill",
                        power: adapterPower,
                        electricalText: adapterElectricalText,
                        tint: AidenteTheme.amber
                    )
                    .position(x: leftX, y: bottomY)

                    PowerFlowNode(
                        title: "系统使用",
                        icon: "laptopcomputer",
                        power: systemPower,
                        electricalText: nil,
                        tint: AidenteTheme.ocean
                    )
                    .position(x: rightX, y: middleY)

                case .adapterOnly:
                    PowerFlowNode(
                        title: "适配器",
                        icon: "powerplug.fill",
                        power: adapterPower,
                        electricalText: adapterElectricalText,
                        tint: AidenteTheme.amber
                    )
                    .position(x: leftX, y: middleY)

                    PowerFlowNode(
                        title: "系统使用",
                        icon: "laptopcomputer",
                        power: systemPower,
                        electricalText: nil,
                        tint: AidenteTheme.ocean
                    )
                    .position(x: rightX, y: middleY)

                case .batteryOnly:
                    PowerFlowNode(
                        title: "电池输出",
                        icon: "battery.100",
                        power: batteryPower,
                        electricalText: batteryElectricalText,
                        tint: AidenteTheme.jade
                    )
                    .position(x: leftX, y: middleY)

                    PowerFlowNode(
                        title: "系统使用",
                        icon: "laptopcomputer",
                        power: systemPower,
                        electricalText: nil,
                        tint: AidenteTheme.ocean
                    )
                    .position(x: rightX, y: middleY)
                }
            }
        }
        .frame(height: diagramHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AidenteL10n.t("实时功率分流图", "Live Power Flow Diagram"))
        .accessibilityValue(
            AidenteL10n.t(
                "适配器 \(formatted(adapterPower))，\(adapterElectricalText)；系统 \(formatted(systemPower))；电池 \(formatted(batteryPower))，\(batteryElectricalText)",
                "Adapter \(formatted(adapterPower)), \(adapterElectricalText); system \(formatted(systemPower)); battery \(formatted(batteryPower)), \(batteryElectricalText)"
            )
        )
    }

    private enum DiagramMode {
        case adapterSplit
        case sourcesMerge
        case adapterOnly
        case batteryOnly
    }

    private var diagramMode: DiagramMode {
        switch powerSource {
        case .acAdapter:
            batteryPower > 0.05 ? .adapterSplit : .adapterOnly
        case .both:
            .sourcesMerge
        case .battery:
            .batteryOnly
        }
    }

    private func drawFlows(
        context: GraphicsContext,
        leftX: CGFloat,
        rightX: CGFloat,
        arrowTipX: CGFloat,
        topY: CGFloat,
        middleY: CGFloat,
        bottomY: CGFloat
    ) {
        switch diagramMode {
        case .adapterSplit:
            drawFlow(
                context: context,
                from: CGPoint(x: leftX, y: middleY),
                to: CGPoint(x: rightX, y: topY),
                power: batteryPower,
                startColor: AidenteTheme.amber,
                endColor: AidenteTheme.jade,
                arrowTipX: arrowTipX
            )
            drawFlow(
                context: context,
                from: CGPoint(x: leftX, y: middleY),
                to: CGPoint(x: rightX, y: bottomY),
                power: systemPower,
                startColor: AidenteTheme.amber,
                endColor: AidenteTheme.ocean,
                arrowTipX: arrowTipX
            )

        case .sourcesMerge:
            drawFlow(
                context: context,
                from: CGPoint(x: leftX, y: topY),
                to: CGPoint(x: rightX, y: middleY),
                power: batteryPower,
                startColor: AidenteTheme.jade,
                endColor: AidenteTheme.ocean,
                arrowTipX: arrowTipX
            )
            drawFlow(
                context: context,
                from: CGPoint(x: leftX, y: bottomY),
                to: CGPoint(x: rightX, y: middleY),
                power: adapterPower,
                startColor: AidenteTheme.amber,
                endColor: AidenteTheme.ocean,
                arrowTipX: arrowTipX
            )

        case .adapterOnly:
            drawFlow(
                context: context,
                from: CGPoint(x: leftX, y: middleY),
                to: CGPoint(x: rightX, y: middleY),
                power: adapterPower,
                startColor: AidenteTheme.amber,
                endColor: AidenteTheme.ocean,
                arrowTipX: arrowTipX
            )

        case .batteryOnly:
            drawFlow(
                context: context,
                from: CGPoint(x: leftX, y: middleY),
                to: CGPoint(x: rightX, y: middleY),
                power: systemPower,
                startColor: AidenteTheme.jade,
                endColor: AidenteTheme.ocean,
                arrowTipX: arrowTipX
            )
        }
    }

    private func drawFlow(
        context: GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        power: Double,
        startColor: Color,
        endColor: Color,
        arrowTipX: CGFloat
    ) {
        let controlX = start.x + (end.x - start.x) * 0.50
        let path = Path { path in
            path.move(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(x: controlX, y: start.y),
                control2: CGPoint(x: controlX, y: end.y)
            )
        }
        let width = min(max(CGFloat(sqrt(abs(power))) * 1.15, 3), 8)

        context.stroke(
            path,
            with: .color(.black.opacity(0.24)),
            style: StrokeStyle(lineWidth: width + 3, lineCap: .round)
        )
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    startColor.opacity(0.82),
                    endColor.opacity(0.88),
                ]),
                startPoint: start,
                endPoint: end
            ),
            style: StrokeStyle(lineWidth: width, lineCap: .round)
        )

        // The wire stops short of the node card, but the arrow should still
        // point at its leading edge instead of hanging in the gap.
        var arrow = Path()
        arrow.move(to: CGPoint(x: arrowTipX, y: end.y))
        arrow.addLine(to: CGPoint(x: arrowTipX - 7, y: end.y - 5))
        arrow.addLine(to: CGPoint(x: arrowTipX - 7, y: end.y + 5))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(endColor.opacity(0.95)))
    }

    private func formatted(_ power: Double) -> String {
        String(format: "%.2f W", abs(power))
    }
}

private struct PowerFlowNode: View {
    @Default(.appLanguage) private var appLanguage
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let icon: String
    let power: Double
    let electricalText: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 23, height: 23)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(AidenteL10n.t(title))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(String(format: "%.2f W", abs(power)))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let electricalText {
                    Text(electricalText)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: 124, height: 54)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.black.opacity(0.19)
                        : tint.opacity(0.07)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            tint.opacity(colorScheme == .dark ? 0.30 : 0.32),
                            lineWidth: 1
                        )
                }
        }
        .shadow(color: tint.opacity(0.12), radius: 5, y: 2)
    }
}

private struct PopoverCompactCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(13)
            .background {
                PopoverCardBackground()
            }
    }
}

private struct PopoverCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AidenteLevelSurface(level: .card, cornerRadius: 14)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        AidenteSurfaceTokens.stroke(scheme: colorScheme),
                        lineWidth: 1
                    )
            }
    }
}

private struct CompactDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.11))
            .frame(width: 1, height: 34)
    }
}

private struct CompactMetric: View {
    @Default(.appLanguage) private var appLanguage

    let title: String
    let value: String
    let tint: Color
    var compact = false

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(
                    .system(
                        size: compact ? 12 : 16,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(AidenteL10n.t(title))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CapacityLegend: View {
    @Default(.appLanguage) private var appLanguage

    let title: String
    let tint: Color
    var dashed = false

    var body: some View {
        HStack(spacing: 4) {
            if dashed {
                HStack(spacing: 2) {
                    Rectangle().frame(width: 4, height: 2)
                    Rectangle().frame(width: 4, height: 2)
                }
                .foregroundStyle(tint)
            } else {
                Capsule()
                    .fill(tint)
                    .frame(width: 10, height: 3)
            }
            Text(AidenteL10n.t(title))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct CompactActionRow: View {
    @Default(.appLanguage) private var appLanguage

    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(AidenteL10n.t(title))
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(AidenteL10n.t(subtitle))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(AidenteL10n.t(isOn ? "开启" : "关闭"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isOn ? tint : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((isOn ? tint : Color.secondary).opacity(0.12))
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EnergyAppRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let rank: Int
    let app: AppEnergyUsageSnapshot
    let maximumCPUUsage: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(rank)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(width: 13)
                    Text(app.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f%%", app.cpuUsage))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.07)
                                    : Color.black.opacity(0.08)
                            )
                        Capsule()
                            .fill(tint)
                            .frame(
                                width: max(
                                    3,
                                    geometry.size.width
                                        * min(app.cpuUsage / maximumCPUUsage, 1)
                                )
                            )
                    }
                }
                .frame(height: 3)
            }
        }
    }
}

private struct ProtectionPill: View {
    @Default(.appLanguage) private var appLanguage

    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isEnabled ? AidenteTheme.jade : Color.secondary)
                Text(AidenteL10n.t(title))
                    .font(.system(size: 10.5, weight: .medium))
                Text(AidenteL10n.t(isEnabled ? "开" : "关"))
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(isEnabled ? AidenteTheme.jade : .secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        (isEnabled ? AidenteTheme.jade : Color.secondary)
                            .opacity(isEnabled ? 0.10 : 0.04)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        (isEnabled ? AidenteTheme.jade : Color.secondary).opacity(0.20),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AidenteL10n.t(title))
        .accessibilityValue(AidenteL10n.t(isEnabled ? "开启" : "关闭"))
        .accessibilityHint(AidenteL10n.t("点击切换", "Click to toggle"))
    }
}

private struct HeaderButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 25, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AidenteSurfaceTokens.controlFill(scheme: colorScheme))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    AidenteSurfaceTokens.stroke(scheme: colorScheme),
                                    lineWidth: 1
                                )
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .overlay(alignment: .top) {
            if isHovering {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(white: 0.16, opacity: 0.96))
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(y: 30)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

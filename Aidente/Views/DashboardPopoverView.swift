import AppKit
import CoreGraphics
import QuartzCore
import Defaults
import SwiftUI

/// Shared geometry for the dashboard presentation. Keep the width in one
/// place so the popover, standalone window and preview panel stay in sync;
/// the height is an upper bound only — the real height is measured from the
/// visible content and reported to AppKit.
enum DashboardLayout {
    static let width: CGFloat = 360
    static let maxHeight: CGFloat = 800
    static let dividerHeight: CGFloat = 1
    /// 卡片内文字到卡片左右边缘的距离（hero / 普通卡 / 规格卡统一）。
    static let cardTextInset: CGFloat = 12
}

/// The six cards that can be toggled and reordered from the dashboard itself.
/// Raw values are persisted in `dashboardCardOrder`, so keep them stable;
/// `allCases` doubles as the canonical order for newly added cards.
private enum DashboardEditableCard: String, CaseIterable, Identifiable {
    // 默认顺序（2026-11-23 用户定）：规格 → 功率桑基图 → 高能耗应用 → 电池健康 → 捷径。
    // hero 卡单独常驻渲染，不在此列。rawValue 已持久化，勿改动其字符串。
    case batteryHealth
    case colorEnergyFlow
    case energyAppRanking
    case capacityHistory
    case careActions

    var id: String { rawValue }

    /// Resolve a saved comma-separated order into the full canonical card
    /// list. Memoized on the last key: the dashboard body re-evaluates
    /// frequently and re-splitting the string each time was pure waste.
    private static var orderCache: (key: String, cards: [DashboardEditableCard])?
    static func resolvedOrder(_ raw: String) -> [DashboardEditableCard] {
        if let cache = orderCache, cache.key == raw { return cache.cards }
        var result: [DashboardEditableCard] = []
        for part in raw.split(separator: ",") {
            if let card = DashboardEditableCard(rawValue: String(part)),
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
        orderCache = (raw, result)
        return result
    }

    /// Reuse the existing wording so the dock and the card always agree in
    /// both languages — no hand-written English labels here.
    var title: String {
        switch self {
        case .colorEnergyFlow: AidenteL10n.t("功率桑基图")
        case .batteryHealth: AidenteL10n.t("规格")
        case .capacityHistory: AidenteL10n.t("电池健康")
        case .energyAppRanking: AidenteL10n.t("高能耗应用")
        case .careActions: AidenteL10n.t("捷径")
        }
    }

    var icon: String {
        switch self {
        case .colorEnergyFlow: "point.3.connected.trianglepath.dotted"
        case .batteryHealth: "heart.text.square.fill"
        case .capacityHistory: "chart.xyaxis.line"
        case .energyAppRanking: "bolt.horizontal.circle.fill"
        case .careActions: "leaf.fill"
        }
    }
}

private enum DashboardFooterMetrics {
    static let hotZoneHeight: CGFloat = 11
    static let barHeight: CGFloat = 34
    static let dockHeight: CGFloat = 46
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
    @Default(.sailingMode) private var sailingModeEnabled
    @Default(.sailingModeLimit) private var sailingModeLimit
    @Default(.appLanguage) private var appLanguage
    @Default(.showPowerSourceTitle) private var showPowerSourceTitle
    @Default(.showPowerElectricalSubtitle) private var showPowerElectricalSubtitle
    @Default(.showPowerFlowSheen) private var showPowerFlowSheen
    @Default(.showPowerDistribution) private var showPowerDistribution
    @Default(.showCapacityHistory) private var showCapacityHistory
    @Default(.showEnergyAppRanking) private var showEnergyAppRanking
    @Default(.showCareActions) private var showCareActions
    @Default(.showBatteryHealthCard) private var showBatteryHealthCard
    @Default(.dashboardCardOrder) private var dashboardCardOrder
    @Default(.appAppearance) private var appAppearance
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.aidenteCanSampleBackdrop) private var canSampleBackdrop
    @StateObject private var systemAppearanceMonitor = SystemAppearanceMonitor()

    /// Hero card fill alpha, shared with the compact-card surface. The hero
    /// paints its own gradient, so it applies the same readability-gated alpha
    /// directly: 0.3 light / 0.4 dark over live L0 glass, 1 under any opaque
    /// strategy.
    private var heroCardFillAlpha: CGFloat {
        AidenteReadability.dashboardCardAlpha(
            reduceTransparency: reduceTransparency,
            canSampleBackdrop: canSampleBackdrop,
            scheme: colorScheme
        )
    }

    /// Called whenever the measured content height changes so AppKit can
    /// resize the popover / standalone window / preview panel.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var chargeLimitDraft: Double = 80
    @State private var isAdjustingChargeLimit = false
    @State private var capacityHistoryRange: CapacityHistoryRange = .all
    @State private var contentHeight: CGFloat = 0
    @State private var isEditingCards = false
    @State private var isFooterHovering = false
    /// 编辑态 footer 高度动画进度（0 = 常态 hover 条，1 = 编辑态完整 footer）。
    /// 由 CADisplayLink 逐帧推进，SwiftUI 布局与 AppKit 面板 resize 在同一帧
    /// 内由同一数值同步更新，从结构上消除两套系统各自插值的错位（方案 B）。
    @StateObject private var footerProgress = FooterProgressDriver()
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
        // 常态无 footer 条（提示浮在卡片上，2026-11-21）；编辑态按 progress
        // 从 0 平滑长高到编辑栏（+隐藏卡 dock），面板向下伸展、卡片零位移。
        let editing = DashboardFooterMetrics.barHeight
            + (hiddenCards.isEmpty ? 0 : DashboardFooterMetrics.dockHeight)
        return editing * footerProgress.progress
    }

    /// Screen space below the menu bar. Lets the panel grow while editing
    /// (footer 0 → 34/80) without ever exceeding the visible frame.
    private var panelHeightCeiling: CGFloat {
        NSScreen.main?.visibleFrame.height ?? DashboardLayout.maxHeight
    }

    private var scrollHeight: CGFloat {
        // Card area is capped by the panel maximum only: normal mode has no
        // footer strip any more, so the whole height budget belongs to the
        // cards. The edit-mode footer grows downward via totalHeight instead,
        // keeping every card at exactly the same position.
        let base = max(0, min(contentHeight, DashboardLayout.maxHeight))
        // Screen clamp: if the expanded footer would push the panel past the
        // visible frame, hand the excess back to the scroll area. Only bites
        // on short screens or with very tall content.
        let excess = max(0, base + footerHeight - panelHeightCeiling)
        return max(0, base - excess)
    }

    private var totalHeight: CGFloat {
        scrollHeight + footerHeight
    }

    var body: some View {
        ZStack {
            AidenteWindowBackdrop()

            VStack(spacing: 0) {
                // B1 整合（2026-11-20）：header 区块取消——标题并入 hero 卡内、
                // 电源信息并入电池健康卡、设置/退出悬浮 hero 右上角。
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
                    .padding(.horizontal, 11)
                    .padding(.top, 11)
                    .fixedSize(horizontal: false, vertical: true)
                    // 11pt bottom padding matches the top (2026-11-21 v2 定稿);
                    // the hint text lives in this gap, anchored to the panel
                    // bottom — not to the card.
                    .padding(.bottom, 11)
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
                    .frame(height: footerHeight, alignment: .top)
            }
            // 底部间隔带（v2 定稿）：hover 时 ocean 渐变面色 + 提示文字。
            // 文字放 11pt 间隔带内（上距卡片 0.5pt、下距面板底边 0.5pt，
            // 不以卡片为参照系、锚定面板底边）；热区 = 间隔带本身，左右
            // 铺满面板宽度，编辑态让位给编辑栏。热区最后挂（最上层）
            // 独占 hover 跟踪，面色与文字在下面透出。
            .overlay(alignment: .bottom) { footerHintSurface }
            .overlay(alignment: .bottom) { footerHintText }
            .overlay(alignment: .bottom) { footerHotZone }
        }
        // alignment .top：面板顶部锚定，内容在 hosting 边界内的纵向位置恒定
        // 于顶部——尺寸动画期间任何瞬时错位都表现为底部裁切而非卡片位移
        // （center 对齐会把错位变成卡片垂直弹跳，2026-11-21 曾实测复现）。
        .frame(width: DashboardLayout.width, height: totalHeight, alignment: .top)
        .preferredColorScheme(resolvedPreferredScheme)
        .tint(AidenteTheme.jade)
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
        DashboardEditableCard.resolvedOrder(dashboardCardOrder)
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
        }
    }

    private func setCardVisible(_ card: DashboardEditableCard, _ visible: Bool) {
        switch card {
        case .colorEnergyFlow: showPowerDistribution = visible
        case .batteryHealth: showBatteryHealthCard = visible
        case .capacityHistory: showCapacityHistory = visible
        case .energyAppRanking: showEnergyAppRanking = visible
        case .careActions: showCareActions = visible
        }
    }

    private func enterCardEditMode() {
        isFooterHovering = false
        // 切换即时生效，footer 高度/淡入由 driver 逐帧推进（方案 B）。
        isEditingCards = true
        footerProgress.animate(to: 1)
    }

    @ViewBuilder
    private func cardView(_ card: DashboardEditableCard) -> some View {
        switch card {
        case .colorEnergyFlow: powerSummary
        case .batteryHealth: batterySummary
        case .capacityHistory: capacityHistory
        case .energyAppRanking: energyAppRanking
        case .careActions: careActions
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
        // 内容挂载绑 progress 而非 isEditingCards（2026-11-21 弹跳排查定案）：
        // 逐帧几何实测面板 anchor 恒定、AppKit 无跳变，弹跳来自退出时
        // 编辑栏瞬时卸载——底部 80pt 闪空一帧再收回。挂载绑 progress 后，
        // 编辑栏瞬时卸载——底部 80pt 闪空一帧再收回。挂载绑 progress 后，
        // 退出与进入完全对称：编辑栏随高度收回渐隐。
        Group {
            if footerProgress.progress > 0.001 {
                VStack(spacing: 0) {
                    if !hiddenCards.isEmpty { dockRow }
                    editingBar
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AidenteSurfaceTokens.stroke(scheme: colorScheme))
                        .frame(height: DashboardLayout.dividerHeight)
                }
                .opacity(footerProgress.progress)
            }
        }
    }

    /// hover 时 11pt 间隔带的 ocean 渐变面色（复用旧 footer 条的绘制组件）。
    /// 淡入淡出用视图级 .animation(value:)，不用 withAnimation（进出路径禁
    /// withAnimation，见 footerHotZone 注释）。可见条件绑 progress < 0.001：
    /// 退出动画期间不闪现，面板完全关闭后才允许出现。
    @ViewBuilder
    private var footerHintSurface: some View {
        AidenteFooterHintSurface()
            .frame(height: DashboardFooterMetrics.hotZoneHeight)
            .opacity(isFooterHovering && footerProgress.progress < 0.001 ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isFooterHovering)
    }

    /// 「长按进入编辑模式」提示文字：10pt 高，放在卡片与面板底边之间的
    /// 11pt 间隔带里——上距卡片 0.5pt、下距面板底边 0.5pt，水平居中，
    /// 锚定面板底边（v2 定稿：不以卡片为参照系）。
    @ViewBuilder
    private var footerHintText: some View {
        Text(AidenteL10n.t("长按进入编辑模式", "Long-press to enter edit mode"))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(height: 10)
            .padding(.bottom, 0.5)
            .opacity(isFooterHovering && footerProgress.progress < 0.001 ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isFooterHovering)
    }

    /// 底部透明热区：高 11pt = 间隔带本身，左右铺满面板宽度；hover 显隐
    /// 提示文字、长按进入编辑态。可见条件绑 progress < 0.001——退出动画
    /// 期间不重挂载（避免光标下 mouseEntered 闪现面色），面板关闭后才出现。
    private var footerHotZone: some View {
        Group {
            if footerProgress.progress < 0.001 {
                Color.clear
                    .frame(height: DashboardFooterMetrics.hotZoneHeight)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isFooterHovering = hovering
                    }
                    .onLongPressGesture(
                        minimumDuration: 0.5,
                        maximumDistance: 24,
                        perform: enterCardEditMode
                    )
            }
        }
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
                .padding(.horizontal, 11)
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
                // 与进入态对称：分支即时切换，footer 高度收回由 driver
                // 逐帧推进，totalHeight/面板每帧同步，无弹跳。
                isEditingCards = false
                isFooterHovering = false
                resetDragState()
                footerProgress.animate(to: 0)
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
        .padding(.horizontal, 11)
    }

    // B1 整合（2026-11-20）：原 header 区块取消——
    // 标题由 statusHero 卡内标题行承担（信息源与横幅统一为 operationStatusText），
    // 电源信息迁入电池健康卡上半，三按钮悬浮 hero 右上角。

    private var statusHero: some View {
        VStack(spacing: 13) {
            // B 方案 + B1 整合（2026-11-20）：常态标题行与异常/临时横幅同一信息源
            // （operationStatusText = ChargeManager.operationStatusTitle），二者互斥——
            // 常态显示标题行，异常（控制未生效）或临时动作（暂停充电、临时充至
            // 100%、放电至上限、电池校准）生效中切换为横幅。
            if showsStatusBanner {
                HStack(spacing: 12) {
                    Image(systemName: statusBannerIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? Color.white : bannerTintInk)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(bannerTint.opacity(0.17))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        // 点击修复期间文案保持「充电控制未生效 / 点击修复充电控制」不变，
                        // 不切换为「修复中…」短暂态（2026-11-20 用户定：该中间态多余）。
                        Text(viewModel.operationStatusText)
                            .font(.system(size: 15, weight: .bold))
                        if viewModel.canQuickRepair {
                            Text(AidenteL10n.t("点击修复充电控制", "Tap to repair charging control"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard viewModel.canQuickRepair else { return }
                    Task { await viewModel.quickRepair() }
                }
                .help(viewModel.canQuickRepair
                      ? AidenteL10n.t("点击修复充电控制", "Tap to repair charging control")
                      : "")
            } else {
                // 常态标题行：与横幅同源，颜色随 hero tint。
                // 固定 20pt 行高 = 悬浮按钮高度，使标题中心与右上角按钮中心同在 y = 24（14 padding + 10）。
                HStack {
                    Text(viewModel.operationStatusText)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(heroTint)
                        .lineLimit(1)
                    Spacer()
                }
                .frame(height: 20)
                .padding(.trailing, 84)
            }

            BatteryChargeLimitControl(
                batteryLevel: viewModel.displayPercentage,
                chargeLimitDraft: $chargeLimitDraft,
                tint: heroTint,
                sailingFloor: sailingFloor
            ) { editing in
                isAdjustingChargeLimit = editing
                if !editing {
                    chargeLimit = displayedChargeLimit
                }
            }
        }
        .padding(.horizontal, DashboardLayout.cardTextInset)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                    .opacity(heroCardFillAlpha)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : heroTint.opacity(0.28),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .topTrailing) {
            // B1 整合：设置 / 退出悬浮 hero 右上角（半透明小圆钮）。
            // top 14 = hero 顶 padding，按钮 20pt 高 → 中心 y = 24，与标题行中心对齐。
            HStack(spacing: 6) {
                HeaderButton(icon: "gearshape.fill", label: AidenteL10n.t("设置")) { onOpenSettings(.general) }
                HeaderButton(icon: "power", label: AidenteL10n.t("退出")) { onQuit() }
            }
            .opacity(0.85)
            .padding(.top, 14)
            .padding(.trailing, 12)
        }
        .shadow(color: heroTint.opacity(0.12), radius: 10, y: 4)
        // The hero now follows the system appearance like the rest of the
        // dashboard, so .primary/.secondary resolve correctly on its surface.
    }

    /// All three metrics are always on: the settings page no longer exposes
    /// per-metric switches, so this card no longer reads those preferences.
    private var batterySummary: some View {
        let metrics: [(title: String, value: String, tint: Color, compact: Bool)] = [
            ("健康度", viewModel.batteryHealthText, AidenteTheme.jade, false),
            ("循环数", viewModel.cycleCountText, AidenteTheme.violet, false),
            ("温度", viewModel.batteryTemperatureText, AidenteTheme.amber, false),
        ]

        return PopoverCompactCard {
            VStack(spacing: 0) {
                // 上半：当前供电来源单行（左来源名 / 右 V@A 居右），受「电源适配器」「电压与电流」开关控制。
                // 两者均 11pt medium 次要色（2026-11-20 用户定：升 11pt 但颜色保持次要色，不升 primary）。
                if showPowerSourceTitle || showPowerElectricalSubtitle {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if showPowerSourceTitle {
                            Text(powerSourceName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if showPowerElectricalSubtitle {
                            Text(powerSourceVAText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .padding(.bottom, 10)

                    Rectangle()
                        .fill(AidenteSurfaceTokens.stroke(scheme: colorScheme))
                        .frame(height: 1)
                        // 横线与内容同宽、不贴卡边（与三格之间的竖向分割线一致）
                        .padding(.bottom, 11)
                }

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
    }

    private var powerSummary: some View {
        PopoverCompactCard {
            // 标题与副标题已移到仪表盘顶部（由两个开关控制），本卡只保留桑基图。
            CompactPowerFlowDiagram(
                powerSource: viewModel.powerSource,
                isCharging: viewModel.isCharging,
                adapterPower: viewModel.adapterPower,
                systemPower: viewModel.systemPower,
                batteryPower: viewModel.batteryPower,
                adapterElectricalText: viewModel.adapterElectricalText,
                batteryElectricalText: viewModel.batteryElectricalText,
                showsSheen: showPowerFlowSheen
            )
        }
    }

    /// B1 整合（2026-11-20）：电源信息迁入电池健康卡上半——单行、单源：
    /// 适配器供电 = 适配器名 + 适配器 V@A；电池供电 = 「电池供电」+ 电池 V@A。
    private var powerSourceName: String {
        viewModel.powerSource == .battery
            ? AidenteL10n.t("电池供电", "Battery Power")
            : viewModel.chargerDisplayName
    }

    private var powerSourceVAText: String {
        let raw = viewModel.powerSource == .battery
            ? viewModel.batteryElectricalText
            : viewModel.adapterElectricalText
        return raw.replacingOccurrences(of: " · ", with: " @ ")
    }

    private var capacityHistory: some View {
        PopoverCompactCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(
                        AidenteL10n.t("电池健康"),
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
                if let app = viewModel.highlightedEnergyApp {
                    EnergyAppRow(app: app, tint: AidenteTheme.amber)
                } else {
                    Text(AidenteL10n.t("当前无高功耗应用", "No high-power app right now"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
                }
            }
        }
    }

    private var careActions: some View {
        PopoverCompactCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(AidenteL10n.t("捷径"), systemImage: "leaf.fill")
                    .font(.system(size: 13, weight: .semibold))

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
                    title: "恢复正常模式",
                    subtitle: lowPowerRowSubtitle,
                    icon: "speedometer",
                    tint: AidenteTheme.ocean,
                    isOn: viewModel.lowPowerOverrideActive,
                    action: viewModel.toggleLowPowerOverride
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

    private var displayedChargeLimit: Int {
        min(max(Int(chargeLimitDraft.rounded()), 20), 100)
    }

    /// 「恢复正常模式」副标题：生效中说明恢复条件；不可用时说明前提。
    private var lowPowerRowSubtitle: String {
        if viewModel.lowPowerOverrideActive {
            return AidenteL10n.t(
                "低电量模式已临时关闭，接通电源自动恢复",
                "Low Power Mode is temporarily off and will be restored on AC power"
            )
        }
        if viewModel.adapterConnected || !viewModel.isLowPowerModeEnabled {
            return AidenteL10n.t(
                "电池供电且系统低电量模式开启时可用",
                "Available on battery power while Low Power Mode is on"
            )
        }
        return AidenteL10n.t(
            "电池供电时关闭低电量模式，接通电源自动恢复",
            "Turn off Low Power Mode on battery; restores automatically on AC power"
        )
    }

    private var statusTint: Color {
        if viewModel.hasControlError { return AidenteTheme.coral }
        if viewModel.isCharging { return AidenteTheme.amber }
        return AidenteTheme.jade
    }

    // MARK: Hero 状态行（B 方案：仅异常 / 用户主动触发的临时动作生效中显示）

    /// 异常（充电控制未生效）或临时动作（暂停充电、临时充至 100%、
    /// 恢复正常模式、电池校准）生效中；常态由 header 标题承担。
    private var showsStatusBanner: Bool {
        viewModel.hasControlError
            || viewModel.manualPauseActive
            || viewModel.chargeLimitOverrideActive
            || viewModel.lowPowerOverrideActive
            || viewModel.calibrationActive
    }

    /// 异常 = coral 警示；临时动作 = amber（与捷径四个动作行色调一致）。
    private var bannerTint: Color {
        viewModel.hasControlError ? AidenteTheme.coral : AidenteTheme.amber
    }

    /// 亮色 hero 浅底上用 ink 深色变体保证对比（同 heroTint 的补偿逻辑）。
    private var bannerTintInk: Color {
        viewModel.hasControlError ? AidenteTheme.coralInk : AidenteTheme.amberInk
    }

    private var statusBannerIcon: String {
        if viewModel.hasControlError { return "exclamationmark.triangle.fill" }
        if viewModel.manualPauseActive { return "pause.fill" }
        if viewModel.chargeLimitOverrideActive { return "bolt.fill" }
        if viewModel.lowPowerOverrideActive { return "speedometer" }
        return "arrow.triangle.2.circlepath"   // 电池校准
    }

    /// 巡航下限虚线位置（上限 − sailingModeLimit）：仅适配器供电且开启巡航时显示，
    /// 电池供电不适用巡航。只展示设置值，不参与手势。
    private var sailingFloor: Int? {
        guard sailingModeEnabled, viewModel.powerSource != .battery else { return nil }
        return max(displayedChargeLimit - sailingModeLimit, 20)
    }

    /// The regular accents are tuned for dark surfaces and wash out on white.
    /// The hero card is light in light mode, so use deeper variants there —
    /// shared ink tokens so foreground compensation stays in one place.
    private var heroTint: Color {
        guard colorScheme == .light else { return statusTint }
        if viewModel.hasControlError { return AidenteTheme.coralInk }
        if viewModel.isCharging { return AidenteTheme.amberInk }
        return AidenteTheme.jadeInk
    }

}

private struct BatteryChargeLimitControl: View {
    @Default(.appLanguage) private var appLanguage
    @Environment(\.colorScheme) private var colorScheme

    let batteryLevel: Int
    @Binding var chargeLimitDraft: Double
    let tint: Color
    /// 巡航下限虚线（上限 − sailingModeLimit）；nil = 不显示（电池供电 / 未开启巡航）。
    let sailingFloor: Int?
    let onEditingChanged: (Bool) -> Void

    private var chargeLimit: Int {
        min(max(Int(chargeLimitDraft.rounded()), 20), 100)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("\(batteryLevel)%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
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
                        .font(.system(size: 18, weight: .bold, design: .rounded))
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

                    // 巡航下限虚线：只展示设置项「电池巡航」的上限 − sailingModeLimit，
                    // 不可拖、不参与手势；随上限拖动实时移动。
                    if let sailingFloor {
                        let floorX = width * CGFloat(min(max(sailingFloor, 20), 100)) / 100
                        Path { path in
                            path.move(to: CGPoint(x: floorX, y: 3))
                            path.addLine(to: CGPoint(x: floorX, y: 21))
                        }
                        .stroke(
                            tint.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let powerSource: PowerSource
    let isCharging: Bool
    let adapterPower: Double
    let systemPower: Double
    let batteryPower: Double
    let adapterElectricalText: String
    let batteryElectricalText: String
    /// 「流动光效」开关：关闭时只保留彩色信息层、隐藏白色光带动效层，并暂停时间线（无每帧开销）。
    let showsSheen: Bool

    private let nodeWidth: CGFloat = 60
    private let flowInset: CGFloat = 5
    private let fullNodeHeight: CGFloat = 120
    private let nodeGap: CGFloat = 20
    private let nodeRadius: CGFloat = 16
    /// 流管四角与节点内侧相接处的小圆角（对齐 v2 原型，5pt）。
    private let flowCornerRadius: CGFloat = 5
    // 充电动效：扫描 2.5s + 出框停顿 1.5s = 周期 4s（对齐 v2 原型）
    private let animationPeriod: Double = 4.0
    private let sheenScanFraction: Double = 2.5 / 4.0

    // 信息层三色渐变的中间过渡色（方案 B，去脏色），对齐 v2 原型
    private let midAmberJade = Color(red: 0.714, green: 0.769, blue: 0.306)   // #b6c44e
    private let midAmberOcean = Color(red: 0.494, green: 0.576, blue: 0.722)  // #7e93b8
    private let midJadeOcean = Color(red: 0.345, green: 0.694, blue: 0.776)   // #58b1c6

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

    private var diagramHeight: CGFloat {
        switch diagramMode {
        case .adapterSplit, .sourcesMerge:
            fullNodeHeight + nodeGap
        case .adapterOnly, .batteryOnly:
            fullNodeHeight
        }
    }

    private var upperNodeHeight: CGFloat {
        // 上节点按「上 : 下」两股功率的贡献占比分配：
        // 适配器分流时右侧 = 电池 : 系统（适配器输入 = 电池 + 系统）；
        // 双源汇流时左侧 = 电池 : 适配器。
        let upper: Double
        let lower: Double
        switch diagramMode {
        case .adapterSplit:
            upper = abs(batteryPower)
            lower = abs(systemPower)
        case .sourcesMerge:
            upper = abs(batteryPower)
            lower = abs(adapterPower)
        case .adapterOnly, .batteryOnly:
            return fullNodeHeight
        }
        let total = max(upper + lower, 0.1)
        let fraction = min(max(upper / total, 0.15), 0.85)
        return fullNodeHeight * fraction
    }

    var body: some View {
        // 时间线：减弱动态效果、或「流动光效」开关关闭时暂停（date 冻结，无每帧重绘开销）
        TimelineView<AnimationTimelineSchedule, AnyView>(
            .animation(minimumInterval: nil, paused: !showsSheen || reduceMotion)
        ) { timeline in
            AnyView(
                GeometryReader { geometry in
                let width = geometry.size.width
                let flowStart = nodeWidth + flowInset
                let flowEnd = width - nodeWidth - flowInset
                let leftX = nodeWidth / 2
                let rightX = width - nodeWidth / 2
                let nodeTop = (diagramHeight - fullNodeHeight) / 2
                let phase = reduceMotion
                    ? 0
                    : timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: animationPeriod) / animationPeriod
                // 移动高光：扫描段 0→sheenScanFraction 光带从左侧框外移到右侧框外；
                // 其余时间光带停在右框外作为循环间隔，彩色渐变（信息层）全程常驻。
                let scan = reduceMotion ? 1 : min(phase / sheenScanFraction, 1)
                let flowSpan = flowEnd - flowStart
                let sheenWidth = flowSpan * 0.16          // 光带总跨度（柔光底）
                let sheenCenter = flowStart - sheenWidth + scan * (flowSpan + 2 * sheenWidth)

                ZStack {
                    let bands = flowBands(
                        flowStart: flowStart,
                        flowEnd: flowEnd,
                        nodeTop: nodeTop
                    )

                    // ① 无色底管常驻
                    Canvas { context, _ in
                        for band in bands {
                            context.fill(band.path, with: .color(Color.primary.opacity(0.15)))
                        }
                    }

                    // ② 彩色渐变常驻 = 信息层（功率分配 / 方向 / 三色语义），不随动效淡入淡出
                    Canvas { context, _ in
                        for band in bands {
                            context.fill(
                                band.path,
                                with: .linearGradient(
                                    Gradient(stops: [
                                        .init(color: band.start.opacity(0.32), location: 0),
                                        .init(color: band.mid.opacity(0.30), location: 0.5),
                                        .init(color: band.end.opacity(0.28), location: 1),
                                    ]),
                                    startPoint: CGPoint(x: flowStart, y: 0),
                                    endPoint: CGPoint(x: flowEnd, y: 0)
                                )
                            )
                        }
                    }

                    // ③ 白色光带平移 = 动效层：柔光底 + 亮芯两层。
                    // 「流动光效」开关关闭、减弱动态效果、或循环间隔（光带已停在右框外不可见）时不绘制，省去每帧开销。
                    if showsSheen && !reduceMotion && phase < sheenScanFraction {
                        Canvas { context, _ in
                            let start = CGPoint(x: sheenCenter - sheenWidth / 2, y: 0)
                            let end = CGPoint(x: sheenCenter + sheenWidth / 2, y: 0)
                            // 光带透明度分主题：白色光带在浅色卡片上对比度低，亮色用更浓的值（对齐 v2 原型）。
                            let glowEdge1 = colorScheme == .dark ? 0.009 : 0.02
                            let glowEdge2 = colorScheme == .dark ? 0.029 : 0.06
                            let glowPeak = colorScheme == .dark ? 0.069 : 0.144
                            let coreEdge = colorScheme == .dark ? 0.025 : 0.048
                            let corePeak = colorScheme == .dark ? 0.172 : 0.36
                            let glow = Gradient(stops: [
                                .init(color: .white.opacity(0), location: 0),
                                .init(color: .white.opacity(glowEdge1), location: 0.219),
                                .init(color: .white.opacity(glowEdge2), location: 0.375),
                                .init(color: .white.opacity(glowPeak), location: 0.5),
                                .init(color: .white.opacity(glowEdge2), location: 0.625),
                                .init(color: .white.opacity(glowEdge1), location: 0.781),
                                .init(color: .white.opacity(0), location: 1),
                            ])
                            let core = Gradient(stops: [
                                .init(color: .white.opacity(0), location: 0),
                                .init(color: .white.opacity(coreEdge), location: 0.25),
                                .init(color: .white.opacity(corePeak), location: 0.5),
                                .init(color: .white.opacity(coreEdge), location: 0.75),
                                .init(color: .white.opacity(0), location: 1),
                            ])
                            for band in bands {
                                context.fill(band.path, with: .linearGradient(glow, startPoint: start, endPoint: end))
                                context.fill(band.path, with: .linearGradient(core, startPoint: start, endPoint: end))
                            }
                        }
                    }

                    flowNodes(leftX: leftX, rightX: rightX, nodeTop: nodeTop)

                    flowLabels(flowStart: flowStart, flowEnd: flowEnd, nodeTop: nodeTop)
                }
                }
            )
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

    private struct FlowBand {
        let path: Path
        let start: Color
        let mid: Color
        let end: Color
        let label: String?
        let labelY: CGFloat
    }

    private func flowBands(
        flowStart: CGFloat,
        flowEnd: CGFloat,
        nodeTop: CGFloat
    ) -> [FlowBand] {
        /// 需要做小圆角的角。相接（分叉 / 汇流）角保持直角，
        /// 外侧自由角圆角——对齐 v2 原型终态。
        struct FlowCorners: OptionSet {
            let rawValue: Int
            static let leftTop = FlowCorners(rawValue: 1 << 0)
            static let leftBottom = FlowCorners(rawValue: 1 << 1)
            static let rightTop = FlowCorners(rawValue: 1 << 2)
            static let rightBottom = FlowCorners(rawValue: 1 << 3)
            static let all: FlowCorners = [.leftTop, .leftBottom, .rightTop, .rightBottom]
        }

        func path(
            _ leftTop: CGFloat, _ leftBottom: CGFloat,
            _ rightTop: CGFloat, _ rightBottom: CGFloat,
            round: FlowCorners
        ) -> Path {
            let r = flowCornerRadius
            let control = flowStart + (flowEnd - flowStart) * 0.5
            // 圆角角沿切线内缩 r（角点处切线水平 / 垂直），直角角就是角点本身
            let topStartX = round.contains(.leftTop) ? flowStart + r : flowStart
            let topEndX = round.contains(.rightTop) ? flowEnd - r : flowEnd
            let bottomStartX = round.contains(.rightBottom) ? flowEnd - r : flowEnd
            let bottomEndX = round.contains(.leftBottom) ? flowStart + r : flowStart
            let leftStartY = round.contains(.leftTop) ? leftTop + r : leftTop
            let leftEndY = round.contains(.leftBottom) ? leftBottom - r : leftBottom
            let rightStartY = round.contains(.rightTop) ? rightTop + r : rightTop
            let rightEndY = round.contains(.rightBottom) ? rightBottom - r : rightBottom
            return Path { p in
                p.move(to: CGPoint(x: flowStart, y: leftStartY))
                if round.contains(.leftTop) {
                    p.addQuadCurve(
                        to: CGPoint(x: topStartX, y: leftTop),
                        control: CGPoint(x: flowStart, y: leftTop)
                    )
                }
                p.addCurve(
                    to: CGPoint(x: topEndX, y: rightTop),
                    control1: CGPoint(x: control, y: leftTop),
                    control2: CGPoint(x: control, y: rightTop)
                )
                if round.contains(.rightTop) {
                    p.addQuadCurve(
                        to: CGPoint(x: flowEnd, y: rightStartY),
                        control: CGPoint(x: flowEnd, y: rightTop)
                    )
                }
                p.addLine(to: CGPoint(x: flowEnd, y: rightEndY))
                if round.contains(.rightBottom) {
                    p.addQuadCurve(
                        to: CGPoint(x: bottomStartX, y: rightBottom),
                        control: CGPoint(x: flowEnd, y: rightBottom)
                    )
                }
                p.addCurve(
                    to: CGPoint(x: bottomEndX, y: leftBottom),
                    control1: CGPoint(x: control, y: rightBottom),
                    control2: CGPoint(x: control, y: leftBottom)
                )
                if round.contains(.leftBottom) {
                    p.addQuadCurve(
                        to: CGPoint(x: flowStart, y: leftEndY),
                        control: CGPoint(x: flowStart, y: leftBottom)
                    )
                }
                p.closeSubpath()
            }
        }

        switch diagramMode {
        case .adapterSplit:
            let leftSplit = nodeTop + upperNodeHeight
            return [
                FlowBand(
                    path: path(nodeTop, leftSplit, 0, upperNodeHeight,
                               round: [.leftTop, .rightTop, .rightBottom]),
                    start: AidenteTheme.amber, mid: midAmberJade, end: AidenteTheme.jade,
                    label: formatted(batteryPower),
                    labelY: ((nodeTop + leftSplit) / 2 + upperNodeHeight / 2) / 2
                ),
                FlowBand(
                    path: path(leftSplit, nodeTop + fullNodeHeight,
                               upperNodeHeight + nodeGap, diagramHeight,
                               round: [.leftBottom, .rightTop, .rightBottom]),
                    start: AidenteTheme.amber, mid: midAmberOcean, end: AidenteTheme.ocean,
                    label: formatted(systemPower),
                    labelY: ((leftSplit + nodeTop + fullNodeHeight) / 2
                             + (upperNodeHeight + nodeGap + diagramHeight) / 2) / 2
                ),
            ]
        case .sourcesMerge:
            let leftSplit = nodeTop + upperNodeHeight
            let rightMiddle = nodeTop + fullNodeHeight / 2
            return [
                FlowBand(
                    path: path(nodeTop, leftSplit, nodeTop, rightMiddle,
                               round: [.leftTop, .leftBottom, .rightTop]),
                    start: AidenteTheme.jade, mid: midJadeOcean, end: AidenteTheme.ocean,
                    label: formatted(batteryPower),
                    labelY: ((nodeTop + leftSplit) / 2 + (nodeTop + rightMiddle) / 2) / 2
                ),
                FlowBand(
                    path: path(leftSplit + nodeGap, nodeTop + fullNodeHeight,
                               rightMiddle, nodeTop + fullNodeHeight,
                               round: [.leftTop, .leftBottom, .rightBottom]),
                    start: AidenteTheme.amber, mid: midAmberOcean, end: AidenteTheme.ocean,
                    label: formatted(adapterPower),
                    labelY: ((leftSplit + nodeGap + nodeTop + fullNodeHeight) / 2
                             + (rightMiddle + nodeTop + fullNodeHeight) / 2) / 2
                ),
            ]
        case .adapterOnly:
            return [FlowBand(
                path: path(nodeTop, nodeTop + fullNodeHeight,
                           nodeTop, nodeTop + fullNodeHeight, round: .all),
                start: AidenteTheme.amber, mid: midAmberOcean, end: AidenteTheme.ocean,
                label: formatted(adapterPower),
                labelY: nodeTop + fullNodeHeight / 2
            )]
        case .batteryOnly:
            return [FlowBand(
                path: path(nodeTop, nodeTop + fullNodeHeight,
                           nodeTop, nodeTop + fullNodeHeight, round: .all),
                start: AidenteTheme.jade, mid: midJadeOcean, end: AidenteTheme.ocean,
                label: formatted(systemPower),
                labelY: nodeTop + fullNodeHeight / 2
            )]
        }
    }

    @ViewBuilder
    private func flowNodes(leftX: CGFloat, rightX: CGFloat, nodeTop: CGFloat) -> some View {
        switch diagramMode {
        case .adapterSplit:
            FlowNodeView(
                icon: viewModelIcon(isAdapter: true, isCharging: isCharging),
                tint: AidenteTheme.amber,
                height: fullNodeHeight,
                side: .left,
                powerText: formattedWhole(adapterPower),
                colorScheme: colorScheme
            )
            .position(x: leftX, y: nodeTop + fullNodeHeight / 2)

            VStack(spacing: nodeGap) {
                FlowNodeView(
                    icon: isCharging ? "battery.100.bolt" : "battery.100",
                    tint: AidenteTheme.jade,
                    height: upperNodeHeight,
                    side: .right,
                    powerText: nil,
                    colorScheme: colorScheme
                )
                FlowNodeView(
                    icon: "laptopcomputer",
                    tint: AidenteTheme.ocean,
                    height: fullNodeHeight - upperNodeHeight,
                    side: .right,
                    powerText: nil,
                    colorScheme: colorScheme
                )
            }
            .position(x: rightX, y: diagramHeight / 2)

        case .sourcesMerge:
            VStack(spacing: nodeGap) {
                FlowNodeView(
                    icon: "battery.100",
                    tint: AidenteTheme.jade,
                    height: upperNodeHeight,
                    side: .left,
                    powerText: nil,
                    colorScheme: colorScheme
                )
                FlowNodeView(
                    icon: "powerplug.fill",
                    tint: AidenteTheme.amber,
                    height: fullNodeHeight - upperNodeHeight,
                    side: .left,
                    powerText: nil,
                    colorScheme: colorScheme
                )
            }
            .position(x: leftX, y: diagramHeight / 2)

            FlowNodeView(
                icon: "laptopcomputer",
                tint: AidenteTheme.ocean,
                height: fullNodeHeight,
                side: .right,
                powerText: nil,
                colorScheme: colorScheme
            )
            .position(x: rightX, y: nodeTop + fullNodeHeight / 2)

        case .adapterOnly:
            FlowNodeView(
                icon: "powerplug.fill",
                tint: AidenteTheme.amber,
                height: fullNodeHeight,
                side: .left,
                powerText: nil,
                colorScheme: colorScheme
            )
            .position(x: leftX, y: nodeTop + fullNodeHeight / 2)
            FlowNodeView(
                icon: "laptopcomputer",
                tint: AidenteTheme.ocean,
                height: fullNodeHeight,
                side: .right,
                powerText: nil,
                colorScheme: colorScheme
            )
            .position(x: rightX, y: nodeTop + fullNodeHeight / 2)

        case .batteryOnly:
            FlowNodeView(
                icon: "battery.100",
                tint: AidenteTheme.jade,
                height: fullNodeHeight,
                side: .left,
                powerText: nil,
                colorScheme: colorScheme
            )
            .position(x: leftX, y: nodeTop + fullNodeHeight / 2)
            FlowNodeView(
                icon: "laptopcomputer",
                tint: AidenteTheme.ocean,
                height: fullNodeHeight,
                side: .right,
                powerText: nil,
                colorScheme: colorScheme
            )
            .position(x: rightX, y: nodeTop + fullNodeHeight / 2)
        }
    }

    private func viewModelIcon(isAdapter: Bool, isCharging: Bool) -> String {
        isAdapter ? (isCharging ? "bolt.fill" : "powerplug.fill") : "battery.75percent"
    }

    @ViewBuilder
    private func flowLabels(flowStart: CGFloat, flowEnd: CGFloat, nodeTop: CGFloat) -> some View {
        let bands = flowBands(
            flowStart: flowStart, flowEnd: flowEnd, nodeTop: nodeTop
        )
        ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
            if let label = band.label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary)
                    .position(x: (flowStart + flowEnd) / 2, y: band.labelY)
            }
        }
    }

    /// 流管中的功率文字：保留两位小数。
    private func formatted(_ power: Double) -> String {
        String(format: "%.2f W", abs(power))
    }

    /// 节点徽章中的功率文字：只显示整数。
    private func formattedWhole(_ power: Double) -> String {
        String(format: "%.0f W", abs(power))
    }
}

private struct FlowNodeView: View {
    let icon: String
    let tint: Color
    let height: CGFloat
    let side: FlowNodeSide
    let powerText: String?
    let colorScheme: ColorScheme

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: side == .left ? nodeRadius : innerRadius,
            bottomLeadingRadius: side == .left ? nodeRadius : innerRadius,
            bottomTrailingRadius: side == .right ? nodeRadius : innerRadius,
            topTrailingRadius: side == .right ? nodeRadius : innerRadius,
            style: .continuous
        )
        ZStack {
            shape.fill(tint.opacity(0.14))
            shape.strokeBorder(tint.opacity(0.34), lineWidth: 1)

            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(AidenteTheme.legibleTextTint(tint, scheme: colorScheme))
                if let powerText {
                    Text(powerText)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(AidenteTheme.legibleTextTint(tint, scheme: colorScheme))
                }
            }
        }
        .frame(width: 60, height: height)
    }

    private var nodeRadius: CGFloat { 16 }

    /// 节点与流管相接一侧的小圆角（对齐 v2 原型，5pt）。
    private let innerRadius: CGFloat = 5
}

/// 编辑态 footer 高度动画驱动器（方案 B，2026-11-21）。
///
/// 此前所有失败方案（withAnimation、NSAnimationContext setFrame、
/// sizingOptions=[]）的共同根因：SwiftUI 布局插值与 AppKit `setContentSize`
/// 一次性 resize 互不感知，中间态必然错位。本驱动用 120Hz Timer 逐帧推进
/// progress，`footerHeight` / `totalHeight` / footer 内容 opacity 全部由这一个
/// 数值每帧重算，`onChange(of: totalHeight)` 每帧把同一高度同步给 AppKit——
/// 两个系统共享同一数据源，不存在独立的插值路径，结构上不可能错位。
/// （CADisplayLink 在 macOS SDK 标记 API_UNAVAILABLE，故用 Timer。）
private final class FooterProgressDriver: ObservableObject {
    @Published private(set) var progress: CGFloat = 0

    private var timer: Timer?
    private var startTime: CFTimeInterval = 0
    private var fromValue: CGFloat = 0
    private var target: CGFloat = 0

    private static let duration: CFTimeInterval = 0.18
    private static let tickInterval: TimeInterval = 1.0 / 120.0

    /// easeInOutQuad，观感对齐此前 0.18s `.easeInOut`。
    private static func eased(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    func animate(to newTarget: CGFloat) {
        guard newTarget != progress else { return }
        fromValue = progress
        target = newTarget
        startTime = CACurrentMediaTime()
        if timer == nil {
            let tick = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                self?.step()
            }
            RunLoop.main.add(tick, forMode: .common)
            timer = tick
        }
    }

    private func step() {
        let t = min(1, (CACurrentMediaTime() - startTime) / Self.duration)
        progress = fromValue + (target - fromValue) * CGFloat(Self.eased(t))
        if t >= 1 {
            progress = target
            timer?.invalidate()
            timer = nil
        }
    }

    deinit {
        timer?.invalidate()
        timer = nil
    }
}

private enum FlowNodeSide: Equatable {
    case left
    case right
}

private struct PopoverCompactCard<Content: View>: View {
    @ViewBuilder let content: Content
    /// 卡片内文字到左右边缘的距离，统一 12pt（2026-11-22 定）。
    var horizontalPadding: CGFloat = DashboardLayout.cardTextInset

    init(
        horizontalPadding: CGFloat = DashboardLayout.cardTextInset,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 13)
            .background {
                PopoverCardBackground()
            }
    }
}

private struct PopoverCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Dashboard cards let the L0 glass show through (alpha 0.3 light /
        // 0.4 dark). The surface falls back to opaque under Reduce Transparency
        // or non-sampling containers, so text contrast is preserved.
        AidenteLevelSurface(level: .card, cornerRadius: 14, translucentCard: true)
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
    @Environment(\.colorScheme) private var colorScheme

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
                .foregroundStyle(AidenteTheme.legibleTextTint(tint, scheme: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(AidenteL10n.t(title))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
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
    @Environment(\.colorScheme) private var colorScheme

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
                    .foregroundStyle(AidenteTheme.legibleTextTint(tint, scheme: colorScheme))
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
                    .foregroundStyle(
                        isOn ? AidenteTheme.legibleTextTint(tint, scheme: colorScheme) : .secondary
                    )
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

    let app: AppEnergyUsageSnapshot
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
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
                            // 单条展示：进度按 100% 一个核心刻度，不再按榜首归一（否则恒满格）
                            .frame(
                                width: max(
                                    3,
                                    geometry.size.width
                                        * min(app.cpuUsage / 100, 1)
                                )
                            )
                    }
                }
                .frame(height: 3)
            }
        }
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

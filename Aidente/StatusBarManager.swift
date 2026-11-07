import AppKit
import Defaults
import SwiftUI

@MainActor
final class StatusBarManager: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let viewModel: MenuViewModel
    private let settingsWindowController: SettingsWindowController
    /// Borderless panel that replaces NSPopover for the menu-bar dropdown.
    /// NSPopover draws an unavoidable arrow on some macOS builds even with
    /// `hasFullSizeContent`, so the dashboard is presented in a custom panel
    /// anchored under the status item — guaranteed arrow-free.
    private var menuPanel: NSPanel?
    private var outsideClickMonitors: [Any] = []
    /// Top edge (screen Y) the panel is anchored to, so height changes keep the
    /// top fixed and grow the panel downward instead of upward.
    private var menuPanelAnchorTopY: CGFloat = 0
    private var displayObservation: Task<Void, Never>?
    private var powerWidthObservation: Task<Void, Never>?
    private var appearanceObservation: Task<Void, Never>?
    private var systemAppearanceObservation: NSKeyValueObservation?
    private var previewWindow: NSWindow?
    private var dashboardWindow: NSWindow?
    /// True while a menu-panel show/close transition is in flight, to drop
    /// re-entrant status-bar clicks that would otherwise double-toggle.
    private var isPresenting = false

    init(
        viewModel: MenuViewModel,
        settingsWindowController: SettingsWindowController
    ) {
        self.viewModel = viewModel
        self.settingsWindowController = settingsWindowController
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()

        setupPersistentHostingView()
        startDisplayObservation()
        startAppearanceObservation()
    }

    /// Resolves the user's appearance choice into the AppKit appearance used by
    /// the menu panel and the standalone menu windows, so the menu-bar surface
    /// matches the "Appearance" setting in the settings page.
    private var appearanceForSetting: NSAppearance? {
        Defaults[.appAppearance].nsAppearance
    }

    private func makeDashboardRootView(
        canSampleBackdrop: Bool = true
    ) -> some View {
        DashboardPopoverView(
            viewModel: viewModel,
            onOpenSettings: { [weak self] tab in
                guard let self else { return }
                self.closeMenuPanel()
                self.previewWindow?.close()
                self.dashboardWindow?.close()
                self.settingsWindowController.showSettings(tab: tab)
            },
            onQuit: { [weak self] in
                self?.viewModel.quit()
            },
            onHeightChange: { [weak self] height in
                self?.applyContentHeight(height)
            }
        )
        .environment(\.aidenteCanSampleBackdrop, canSampleBackdrop)
    }

    /// Keep every presentation container in sync with the measured SwiftUI
    /// content height, so hiding cards shrinks the panel instead of leaving
    /// an empty area at the bottom.
    private func applyContentHeight(_ height: CGFloat) {
        let size = NSSize(width: DashboardLayout.width, height: height)
        if let menuPanel {
            menuPanel.setContentSize(size)
            // Re-anchor: keep the top fixed just below the status item and let
            // the panel grow downward as content height changes.
            menuPanel.setFrameOrigin(NSPoint(
                x: menuPanel.frame.origin.x,
                y: menuPanelAnchorTopY - size.height
            ))
        }
        if let dashboardWindow { dashboardWindow.setContentSize(size) }
        if let previewWindow { previewWindow.setContentSize(size) }
    }

    private func setupPersistentHostingView() {
        guard let button = statusItem.button else { return }

        let rootView = StatusBarContentView(viewModel: viewModel)
            .allowsHitTesting(false)
        let hosting = NSHostingView(rootView: rootView)

        button.subviews.forEach { $0.removeFromSuperview() }
        button.title = ""
        // An empty placeholder image makes the system treat this item as a
        // standard status item, so macOS applies its inactive-display dimming
        // to the hosted SwiftUI view on secondary monitors. With `nil` the
        // custom view stays fully bright when another screen has focus.
        button.image = NSImage()
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: button.topAnchor, constant: 1),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1),
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: BatteryIndicatorLayout.statusInset),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -BatteryIndicatorLayout.statusInset),
        ])
    }

    private func startDisplayObservation() {
        displayObservation = Task { [weak self] in
            for await _ in Defaults.updates(
                [.menuBarReadoutStyle, .batteryPercentageDisplayLocation],
                initial: true
            ) {
                self?.updateStatusItemLength()
            }
        }
        powerWidthObservation = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                updateStatusItemLength()
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.viewModel.systemPower
                        _ = self.viewModel.displayPercentage
                    } onChange: {
                        Task { @MainActor in continuation.resume() }
                    }
                }
            }
        }
    }

    /// Keeps the appearance of every open dashboard container in sync with the
    /// "Appearance" setting. Without this, switching to「自动」leaves windows
    /// pinned to the NSAppearance captured at creation time (dark stays dark,
    /// light stays light) because `.preferredColorScheme(nil)` falls back to
    /// the stale window environment.
    private func startAppearanceObservation() {
        appearanceObservation = Task { [weak self] in
            for await _ in Defaults.updates([.appAppearance], initial: false) {
                self?.applyAppearanceToOpenContainers()
            }
        }
        // While「自动」is selected (resolved to a concrete appearance), follow
        // live system appearance flips.
        systemAppearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                self?.applyAppearanceToOpenContainers()
            }
        }
    }

    private func applyAppearanceToOpenContainers() {
        let appearance = AidenteAppearanceResolver.resolved(Defaults[.appAppearance])
        menuPanel?.appearance = appearance
        dashboardWindow?.appearance = appearance
        previewWindow?.appearance = appearance
    }

    private func updateStatusItemLength() {
        let power = String(format: "%.2fW", abs(viewModel.systemPower))
        let powerWidth = ceil((power as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        ]).width) + 3
        let outerWidth = BatteryIndicatorLayout.statusInset * 2
        let iconWidth = BatteryIndicatorLayout.width(insidePercentage: false) + outerWidth
        let percentageIconWidth = BatteryIndicatorLayout.width(insidePercentage: true) + outerWidth
        switch Defaults[.menuBarReadoutStyle] {
        case .batteryPercentage:
            switch Defaults[.batteryPercentageDisplayLocation] {
            case .hidden:
                statusItem.length = iconWidth
            case .insideIcon:
                statusItem.length = percentageIconWidth
            case .nextToIcon:
                let textWidth = ceil(("\(viewModel.displayPercentage)%" as NSString).size(withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: BatteryIndicatorLayout.percentageFontSize,
                        weight: .regular
                    )
                ]).width)
                statusItem.length = textWidth + iconWidth + BatteryIndicatorLayout.outsideTextSpacing
            }
        case .systemPower:
            statusItem.length = iconWidth + powerWidth
        case .batteryAndPower:
            statusItem.length = percentageIconWidth + powerWidth
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        // Drop clicks that arrive while a show/close transition is in flight, so
        // rapid clicks cannot double-toggle the menu panel.
        if isPresenting { return }

        if let menuPanel, menuPanel.isVisible {
            closeMenuPanel()
            return
        }

        if let dashboardWindow, dashboardWindow.isVisible {
            dashboardWindow.close()
            isPresenting = true
            Task { [weak self] in
                await Task.yield()
                guard let self else { return }
                self.isPresenting = false
                self.presentMenuPanel(relativeTo: sender)
            }
            return
        }

        presentMenuPanel(relativeTo: sender)
    }

    /// Presents the dashboard in a borderless panel anchored beneath the status
    /// item. Replaces NSPopover so there is no arrow on any macOS build.
    private func presentMenuPanel(relativeTo sender: NSStatusBarButton?) {
        isPresenting = true
        if menuPanel == nil {
            let hostingController = NSHostingController(
                rootView: makeDashboardRootView(canSampleBackdrop: true)
            )
            let panel = AidentePreviewPanel(contentViewController: hostingController)
            panel.styleMask = [.borderless]
            panel.appearance = appearanceForSetting
            panel.setContentSize(NSSize(
                width: DashboardLayout.width,
                height: DashboardLayout.maxHeight
            ))
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.cornerRadius = 15
            hostingController.view.layer?.masksToBounds = true
            menuPanel = panel
        } else {
            menuPanel?.appearance = appearanceForSetting
        }
        positionMenuPanel(relativeTo: sender)
        viewModel.menuWillOpen()
        NSApp.activate(ignoringOtherApps: true)
        menuPanel?.makeKeyAndOrderFront(nil)
        menuPanel?.orderFrontRegardless()
        installOutsideClickMonitor()
        isPresenting = false
    }

    /// Anchors the menu panel directly beneath the status-item button (no arrow,
    /// unlike NSPopover). Falls back to centering on the primary screen when the
    /// button is unavailable.
    private func positionMenuPanel(relativeTo button: NSStatusBarButton?) {
        guard let panel = menuPanel else { return }
        let size = panel.frame.size
        if let button, let window = button.window {
            let buttonFrameInWindow = button.convert(button.bounds, to: nil)
            let buttonFrameInScreen = window.convertToScreen(buttonFrameInWindow)
            let xPos = buttonFrameInScreen.midX - size.width / 2
            let topY = buttonFrameInScreen.minY - 4
            menuPanelAnchorTopY = topY
            let yPos = topY - size.height
            panel.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        } else if let screen = NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            menuPanelAnchorTopY = visibleFrame.minY + visibleFrame.height
            panel.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            ))
        }
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitors.isEmpty else { return }
        // Local monitor catches clicks inside our app (desktop, other windows);
        // the global monitor catches clicks on other apps. The status-item
        // button rectangle is excluded so the toggle action handles it instead
        // of being treated as an outside click (avoids a close→reopen flip).
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleOutsideClick(event)
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleOutsideClick(event)
        }
        if let local { outsideClickMonitors.append(local) }
        if let global { outsideClickMonitors.append(global) }
    }

    private func handleOutsideClick(_ event: NSEvent) {
        guard let panel = menuPanel, panel.isVisible else { return }
        let screenPoint: NSPoint
        if let window = event.window {
            screenPoint = window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        } else {
            screenPoint = event.locationInWindow
        }
        if panel.frame.contains(screenPoint) { return }
        if let button = statusItem.button, let buttonWindow = button.window {
            let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonFrame.contains(screenPoint) { return }
        }
        closeMenuPanel()
    }

    func closeMenuPanel() {
        removeOutsideClickMonitor()
        menuPanel?.close()
    }

    private func removeOutsideClickMonitor() {
        for monitor in outsideClickMonitors {
            NSEvent.removeMonitor(monitor)
        }
        outsideClickMonitors.removeAll()
    }

    func showDashboardWindow() {
        if let dashboardWindow {
            NSApp.activate(ignoringOtherApps: true)
            dashboardWindow.appearance = appearanceForSetting
            dashboardWindow.makeKeyAndOrderFront(nil)
            dashboardWindow.orderFrontRegardless()
            return
        }

        if let menuPanel, menuPanel.isVisible {
            closeMenuPanel()
            Task { [weak self] in
                await Task.yield()
                self?.presentDashboardWindow()
            }
            return
        }

        presentDashboardWindow()
    }

    private func presentDashboardWindow() {
        guard dashboardWindow == nil else { return }

        let hostingController = NSHostingController(
            rootView: makeDashboardRootView(canSampleBackdrop: true)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = AidenteL10n.t("Aidente 主菜单", "Aidente Dashboard")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.appearance = appearanceForSetting
        window.setContentSize(NSSize(
            width: DashboardLayout.width,
            height: DashboardLayout.maxHeight
        ))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 15
        hostingController.view.layer?.masksToBounds = true

        dashboardWindow = window
        viewModel.menuWillOpen()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func showPopoverForPreview() {
        guard let button = statusItem.button, menuPanel?.isVisible != true, !isPresenting else { return }
        presentMenuPanel(relativeTo: button)
    }

    func showWindowForPreview() {
        guard previewWindow == nil else { return }

        let hostingController = NSHostingController(
            rootView: makeDashboardRootView(canSampleBackdrop: true)
        )
        let panel = AidentePreviewPanel(contentViewController: hostingController)
        panel.styleMask = [.borderless]
        panel.appearance = appearanceForSetting
        panel.setContentSize(NSSize(
            width: DashboardLayout.width,
            height: DashboardLayout.maxHeight
        ))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        if let screen = NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.midX - DashboardLayout.width / 2,
                    y: visibleFrame.midY - DashboardLayout.maxHeight / 2
                )
            )
        } else {
            panel.center()
        }

        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 15
        hostingController.view.layer?.masksToBounds = true

        previewWindow = panel
        viewModel.menuWillOpen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let closedWindow = notification.object as? NSWindow else { return }
            if closedWindow === dashboardWindow {
                dashboardWindow = nil
                viewModel.menuDidClose()
            } else if closedWindow === previewWindow {
                previewWindow = nil
                viewModel.menuDidClose()
            } else if closedWindow === menuPanel {
                menuPanel = nil
                removeOutsideClickMonitor()
                viewModel.menuDidClose()
            }
        }
    }

    deinit {
        displayObservation?.cancel()
        powerWidthObservation?.cancel()
        appearanceObservation?.cancel()
        systemAppearanceObservation?.invalidate()
    }
}

private final class AidentePreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct StatusBarContentView: View {
    let viewModel: MenuViewModel
    @Default(.batteryPercentageDisplayLocation) var percentageDisplayLocation
    @Default(.menuBarReadoutStyle) var readoutStyle
    @Default(.showBatteryStateInStatusIcon) var showState

    var body: some View {
        HStack(spacing: 3) {
            BatteryIndicatorView(
                batteryLevel: viewModel.displayPercentage,
                chargingMode: viewModel.chargingMode,
                isLowPowerModeEnabled: viewModel.isLowPowerModeEnabled,
                percentageDisplayLocation: batteryIndicatorLocation,
                showState: showState
            )

            switch readoutStyle {
            case .batteryPercentage:
                EmptyView()
            case .systemPower:
                Text(formattedPower)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            case .batteryAndPower:
                Text(formattedPower)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .fixedSize()
        .lineLimit(1)
        .help(AidenteL10n.t(
            "电量 \(viewModel.displayPercentage)% · 系统功率 \(formattedPower)",
            "Battery \(viewModel.displayPercentage)% · System power \(formattedPower)"
        ))
    }

    private var batteryIndicatorLocation: PercentageDisplayLocation {
        switch readoutStyle {
        case .batteryPercentage: percentageDisplayLocation
        case .systemPower: .hidden
        case .batteryAndPower: .insideIcon
        }
    }

    private var formattedPower: String {
        String(format: "%.2fW", abs(viewModel.systemPower))
    }
}

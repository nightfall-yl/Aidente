import AppKit
import SwiftUI
import Defaults
import smc_power

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// Live-syncs the open settings window with the「Appearance」setting.
    /// Without this, switching to「自动」(`.preferredColorScheme(nil)`) falls
    /// back to the NSAppearance captured at window creation and the page
    /// stops refreshing (dark stays dark, light stays light).
    private var appearanceObservation: Task<Void, Never>?
    /// Language switches rewrite the window title (`SettingsView.updateWindowTitle`),
    /// and AppKit re-tiles the titlebar on `setTitle`, snapping the traffic
    /// lights back to the stock position with no resize/becomeKey callback.
    /// This observation re-applies the custom position after that relayout.
    private var languageObservation: Task<Void, Never>?
    private var systemAppearanceObservation: NSKeyValueObservation?
    private let capabilities: DeviceCapabilities
    private let chargeManager: ChargeManager
    private let diagnosticCenter: DiagnosticCenter
    private let updateService: UpdateService

    /// AppKit parks the traffic lights at ~16pt under a hidden transparent
    /// title bar. Move their centers to 30pt so they line up with the detail
    /// pane's title, and shift the row right to the 20pt left inset used by
    /// the detail title. AppKit re-lays them out on resize / appearance
    /// changes, so the delegate callbacks below re-apply this.
    private static let trafficLightInset: CGFloat = 30
    private static let trafficLightLeftInset: CGFloat = 20
    /// The buttons' superview (the titlebar container) is only ~28pt tall by
    /// default. Moving the buttons down to a 30pt center yields a negative y
    /// in that container, pushing them outside its hit-test bounds — clicks
    /// land on the SwiftUI content instead. A transparent bottom accessory
    /// grows the container to this height so `positionTrafficLights()` keeps
    /// the buttons inside it and their click targets stay alive.
    private static let targetTitlebarHeight: CGFloat = 60
    private var titlebarAccessory: NSTitlebarAccessoryViewController?

    init(
        capabilities: DeviceCapabilities,
        chargeManager: ChargeManager,
        diagnosticCenter: DiagnosticCenter,
        updateService: UpdateService
    ) {
        self.capabilities = capabilities
        self.chargeManager = chargeManager
        self.diagnosticCenter = diagnosticCenter
        self.updateService = updateService
        super.init()

        appearanceObservation = Task { [weak self] in
            for await _ in Defaults.updates([.appAppearance], initial: false) {
                self?.applyAppearance()
            }
        }
        languageObservation = Task { [weak self] in
            for await _ in Defaults.updates([.appLanguage], initial: false) {
                await self?.repositionAfterTitleRelayout()
            }
        }
        // While「自动」is selected, follow live system appearance flips.
        systemAppearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                self?.applyAppearance()
            }
        }
    }

    /// The title change lands one async hop later (`DispatchQueue.main.async`
    /// in `updateWindowTitle`), and AppKit's titlebar re-tile follows it.
    /// Yield a few main-queue hops so the re-tile has finished before the
    /// buttons are moved back; the recompute-from-current-x logic in
    /// `positionTrafficLights()` makes repeated calls converge, not drift.
    private func repositionAfterTitleRelayout() async {
        guard window != nil else { return }
        for _ in 0..<3 {
            await MainActor.run { }
        }
        positionTrafficLights()
    }

    private func applyAppearance() {
        window?.appearance = AidenteAppearanceResolver.resolved(Defaults[.appAppearance])
        positionTrafficLights()
    }

    /// Grow the titlebar container with a transparent bottom accessory. The
    /// stock container is ~28pt tall, so a 32pt-centered button needs a
    /// negative y and falls outside its hit-test bounds (clicks hit the
    /// SwiftUI view instead). Adding the accessory once grows the container
    /// to `targetTitlebarHeight`; `positionTrafficLights()` then computes a
    /// positive in-bounds y and clicks reach the buttons again.
    private func installTitlebarAccessory() {
        guard titlebarAccessory == nil,
              let window,
              let button = window.standardWindowButton(.closeButton),
              let container = button.superview else { return }
        let extra = max(0, Self.targetTitlebarHeight - container.bounds.height)
        guard extra > 0 else { return }
        let accessory = NSTitlebarAccessoryViewController()
        let spacer = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: extra))
        spacer.wantsLayer = false
        accessory.view = spacer
        accessory.layoutAttribute = .bottom
        window.addTitlebarAccessoryViewController(accessory)
        titlebarAccessory = accessory
    }

    private func positionTrafficLights() {
        guard let window else { return }
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        // Delta is recomputed from the current (possibly AppKit-reset) x, so
        // repeated calls converge on the target inset without drifting.
        let dx: CGFloat
        if let first = window.standardWindowButton(.closeButton) {
            dx = Self.trafficLightLeftInset - first.frame.origin.x
        } else {
            dx = 0
        }
        for kind in kinds {
            guard let button = window.standardWindowButton(kind),
                  let container = button.superview else { continue }
            let y = container.bounds.height
                - Self.trafficLightInset
                - button.frame.height / 2
            button.setFrameOrigin(
                NSPoint(x: button.frame.origin.x + dx, y: y)
            )
        }
    }

    deinit {
        appearanceObservation?.cancel()
        languageObservation?.cancel()
        systemAppearanceObservation?.invalidate()
    }

    func showSettings(tab: SettingsTab = .general) {
        if let existingWindow = window {
            existingWindow.delegate = nil
            existingWindow.close()
            window = nil
            // The accessory view controller belongs to the closed window;
            // drop the controller-held reference so the next window gets
            // its own (otherwise installTitlebarAccessory() below would
            // skip and traffic-light clicks break again on reopen).
            titlebarAccessory = nil
        }

        let settingsView = SettingsView(
            capabilities: capabilities,
            chargeManager: chargeManager,
            diagnosticCenter: diagnosticCenter,
            updateService: updateService,
            initialTab: tab
        )
        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = AidenteL10n.t("Aidente 设置", "Aidente Settings")
        newWindow.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView,
        ]
        newWindow.appearance = AidenteAppearanceResolver.resolved(Defaults[.appAppearance])
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        // No hairline under the hidden title bar: the prototype has no
        // full-width band, only the sidebar/detail divider running top-down.
        newWindow.titlebarSeparatorStyle = .none
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.contentView?.wantsLayer = true
        newWindow.contentView?.layer?.cornerRadius = 12
        newWindow.contentView?.layer?.masksToBounds = true
        // Width is locked at 750pt; height is resizable from 475pt (default)
        // up to 960pt. minSize/maxSize pin the width so AppKit's resize handles
        // cannot drag it horizontally. A new autosave key avoids restoring the
        // old fixed 640pt-tall frame while still remembering window position.
        newWindow.minSize = NSSize(width: 750, height: 475)
        newWindow.maxSize = NSSize(width: 750, height: 960)
        newWindow.setContentSize(NSSize(width: 750, height: 475))
        newWindow.center()
        newWindow.setFrameAutosaveName("SettingsWindow750x475")
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
        installTitlebarAccessory()
        // Force the titlebar container to adopt the accessory's extra height
        // before computing the buttons' y, otherwise it still reads ~28pt.
        newWindow.layoutIfNeeded()
        positionTrafficLights()
    }

    nonisolated func windowDidBecomeKey(_ notification: Notification) {
        MainActor.assumeIsolated { positionTrafficLights() }
    }

    nonisolated func windowDidResize(_ notification: Notification) {
        MainActor.assumeIsolated { positionTrafficLights() }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            window = nil
            // Accessory belongs to the closing window; reset so a later
            // showSettings() installs a fresh one for the new window.
            titlebarAccessory = nil
        }
    }
}

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
    private var systemAppearanceObservation: NSKeyValueObservation?
    private let capabilities: DeviceCapabilities
    private let chargeManager: ChargeManager
    private let diagnosticCenter: DiagnosticCenter
    private let updateService: UpdateService

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
        // While「自动」is selected, follow live system appearance flips.
        systemAppearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                self?.applyAppearance()
            }
        }
    }

    private func applyAppearance() {
        window?.appearance = AidenteAppearanceResolver.resolved(Defaults[.appAppearance])
    }

    deinit {
        appearanceObservation?.cancel()
        systemAppearanceObservation?.invalidate()
    }

    func showSettings(tab: SettingsTab = .general) {
        if let existingWindow = window {
            existingWindow.delegate = nil
            existingWindow.close()
            window = nil
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
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.contentView?.wantsLayer = true
        newWindow.contentView?.layer?.cornerRadius = 14
        newWindow.contentView?.layer?.masksToBounds = true
        newWindow.center()
        newWindow.setFrameAutosaveName("SettingsWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            window = nil
        }
    }
}

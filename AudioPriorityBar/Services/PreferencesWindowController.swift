import AppKit
import SwiftUI

/// Singleton controller to manage the preferences window lifecycle
class PreferencesWindowController {
    /// Shared singleton instance
    static let shared = PreferencesWindowController()

    /// The preferences window instance
    private var window: NSWindow?

    /// Private initializer to enforce singleton pattern
    private init() {}

    /// Shows the preferences window, creating it if needed or bringing it to front if already exists
    /// - Parameter audioManager: The audio manager to pass to the preferences view
    func show(audioManager: AudioManager) {
        if let existingWindow = window {
            // Window already exists, just bring to front
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Create new window
            let preferencesView = PreferencesView()
                .environmentObject(audioManager)

            let hostingController = NSHostingController(rootView: preferencesView)

            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "Audio Priority Bar Preferences"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.setContentSize(NSSize(width: 480, height: 400))
            newWindow.center()
            newWindow.level = .floating
            newWindow.isReleasedWhenClosed = false
            newWindow.setFrameAutosaveName("PreferencesWindow")

            self.window = newWindow
            newWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Closes the preferences window
    func close() {
        window?.close()
    }
}

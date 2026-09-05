import AppKit
import SwiftUI

@main
@MainActor
struct PopoverLayoutTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        guard let domain = Bundle.main.bundleIdentifier,
              domain.hasPrefix("app.audioprioritybar.layouttests.") else {
            fatalError("Run through run-popover-layout-tests.sh for isolated preferences.")
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        // Use the existing manual-mode preference before constructing the real manager.
        UserDefaults.standard.setVolatileDomain(["customMode": true], forName: UserDefaults.argumentDomain)
        let manager = AudioManager()
        precondition(manager.isCustomMode)
        let host = NSHostingView(rootView: MenuBarView().environmentObject(manager))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 340, height: 553),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        // Replace only the displayed rows, so results do not depend on connected hardware.
        manager.speakerDevices = []
        manager.headphoneDevices = []
        for count in [3, 20] {
            manager.inputDevices = (1...count).map {
                AudioDevice(id: UInt32($0), uid: "layout-test-\($0)", name: "Test microphone \($0)", type: .input, isConnected: false)
            }
            for height: CGFloat in [553, 400, 300] {
                host.rootView = MenuBarView(availableHeight: height).environmentObject(manager)
                window.setContentSize(NSSize(width: 340, height: height))
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                guard host.bounds.height > 200 && host.bounds.height <= height + 1 else {
                    fputs("FAIL: requested \(height)-point panel, got \(host.bounds.height).\n", stderr)
                    exit(1)
                }
                guard host.fittingSize.height > 200 && host.fittingSize.height <= height else {
                    fputs("FAIL: ideal panel height is empty or exceeds the available height.\n", stderr)
                    exit(1)
                }
                print("PASS: \(count) rows, available \(Int(height)), actual \(Int(host.bounds.height)), ideal \(Int(host.fittingSize.height))")
            }
        }
        if ProcessInfo.processInfo.environment["POPOVER_LAYOUT_HOLD"] == "1" {
            print("Ready for native footer/scroll inspection at height 300; preview closes after two minutes.")
            fflush(stdout)
            Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in
                UserDefaults.standard.removePersistentDomain(forName: domain)
                app.terminate(nil)
            }
            app.run()
        }
    }
}

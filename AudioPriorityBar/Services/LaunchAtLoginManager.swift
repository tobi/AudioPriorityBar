import Foundation
import ServiceManagement

@MainActor
class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    
    @Published var isEnabled: Bool {
        didSet {
            if isEnabled {
                enableLaunchAtLogin()
            } else {
                disableLaunchAtLogin()
            }
        }
    }
    
    private init() {
        // Check current status
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = false
        }
    }
    
    private func enableLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
            } catch {
                print("Failed to enable launch at login: \(error)")
                // Revert the toggle if registration fails
                DispatchQueue.main.async {
                    self.isEnabled = false
                }
            }
        }
    }
    
    private func disableLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                print("Failed to disable launch at login: \(error)")
            }
        }
    }
    
    func refresh() {
        if #available(macOS 13.0, *) {
            let newStatus = SMAppService.mainApp.status == .enabled
            if newStatus != isEnabled {
                // Update without triggering didSet
                _isEnabled = Published(wrappedValue: newStatus)
            }
        }
    }
}


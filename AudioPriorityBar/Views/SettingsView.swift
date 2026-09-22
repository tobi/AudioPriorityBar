import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchManager.isEnabled)
            } header: {
                Text("General")
            }

            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Audio Priority Bar")
                            .font(.system(size: 14, weight: .semibold))
                        Text(appVersion)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Link("github.com/tobi/AudioPriorityBar",
                             destination: URL(string: "https://github.com/tobi/AudioPriorityBar")!)
                            .font(.system(size: 12))
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("About")
            } footer: {
                Text("Automatically switches to your highest-priority audio devices. MIT License.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchManager.refresh() }
    }
}

/// "Settings…" menu item for the menu bar popover. The app has no Dock icon,
/// so it must be activated explicitly or the window opens behind other apps.
struct SettingsMenuItem: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            ModernSettingsMenuItem()
        } else {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
        }
    }
}

@available(macOS 14.0, *)
private struct ModernSettingsMenuItem: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
    }
}

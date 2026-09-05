import SwiftUI
import AppKit

@MainActor
final class MicrophoneSettingsWindow {
    static let shared = MicrophoneSettingsWindow()
    private var window: NSWindow?

    func show(audioManager: AudioManager) {
        audioManager.refreshLidState()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Microphone Automation"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 520, height: 440)
            window.contentView = NSHostingView(rootView: MicrophoneSettingsView().environmentObject(audioManager))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MicrophoneSettingsView: View {
    @EnvironmentObject private var audioManager: AudioManager

    private var settings: MicrophoneSettings { audioManager.microphoneSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use microphone rules", isOn: Binding(
                    get: { settings.enabled },
                    set: { enabled in update { $0.enabled = enabled } }))
                    .font(.headline)
                Text("When off, microphones follow the device priority list. Manual mode pauses all automatic switching.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Changes apply immediately when automatic mode is active.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(audioManager.microphoneStatus)
                    .font(.callout).accessibilityIdentifier("microphone-status")
            }
            .padding(20)

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    rulesSection
                    devicesSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, minHeight: 440)
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selection rules").font(.headline)
            Text("First eligible type wins. Devices of the same type follow the device priority list.")
                .font(.callout).foregroundStyle(.secondary)
            Text(lidDescription).font(.caption).foregroundStyle(.secondary)

            ForEach(Array(settings.rules.enumerated()), id: \.element.id) { index, rule in
                HStack(spacing: 8) {
                    Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(rule.role.label).frame(maxWidth: .infinity, alignment: .leading)
                    Picker("Use \(rule.role.label)", selection: Binding(
                        get: { settings.rules.first { $0.role == rule.role }?.condition ?? .never },
                        set: { condition in
                            update { value in
                                if let i = value.rules.firstIndex(where: { $0.role == rule.role }) {
                                    value.rules[i].condition = condition
                                }
                            }
                        })) {
                        ForEach(MicrophoneCondition.allCases, id: \.self) { condition in
                            Text(condition.label).tag(condition)
                        }
                    }
                    .labelsHidden().frame(width: 155)
                    Button { move(rule.role, by: -1) } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0)
                        .accessibilityLabel("Move \(rule.role.label) earlier")
                        .help("Move earlier")
                    Button { move(rule.role, by: 1) } label: { Image(systemName: "arrow.down") }
                        .disabled(index == settings.rules.count - 1)
                        .accessibilityLabel("Move \(rule.role.label) later")
                        .help("Move later")
                }
                .padding(.vertical, 4)
            }
            Button("Restore default rules") { update { $0.rules = MicrophoneRule.defaults } }
            Text("If the lid state is unavailable, lid-specific rules are skipped. If no input qualifies, the current input stays unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Microphone types").font(.headline)
            Text("Detection uses device metadata first, then name hints. You can correct a type; the override stays with that device when it reconnects.")
                .font(.callout).foregroundStyle(.secondary)
            if audioManager.microphonesForSettings.isEmpty {
                Text("Connect a microphone to see its detected type.").foregroundStyle(.secondary)
            }
            ForEach(audioManager.microphonesForSettings, id: \.uid) { device in
                let detection = audioManager.microphoneClassification(for: device)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(device.name).fontWeight(.medium)
                        Spacer()
                        if !device.isConnected { Text("Disconnected").foregroundStyle(.secondary) }
                    }
                    Picker("Type for \(device.name)", selection: Binding<MicrophoneRole?>(
                        get: { settings.overrides[device.uid] },
                        set: { role in update { $0.overrides[device.uid] = role } })) {
                        Text("Auto: \(detection.role.label)").tag(Optional<MicrophoneRole>.none)
                        ForEach(MicrophoneRole.allCases, id: \.self) { role in
                            Text(role.label).tag(Optional(role))
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Type for \(device.name)")
                    Text(detection.reason).font(.caption).foregroundStyle(.secondary)
                    if audioManager.isNeverUse(device) || audioManager.isDeviceIgnored(device) {
                        Text("Excluded by your device settings.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var lidDescription: String {
        switch audioManager.lidState {
        case .open: return "Current lid state: open"
        case .closed: return "Current lid state: closed"
        case .unknown: return "Lid state unavailable. Use Always on a Mac without a lid."
        }
    }

    private func update(_ change: (inout MicrophoneSettings) -> Void) {
        var value = settings
        change(&value)
        audioManager.updateMicrophoneSettings(value)
    }

    private func move(_ role: MicrophoneRole, by offset: Int) {
        update { value in
            guard let index = value.rules.firstIndex(where: { $0.role == role }),
                  value.rules.indices.contains(index + offset) else { return }
            value.rules.swapAt(index, index + offset)
        }
    }
}

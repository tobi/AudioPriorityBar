import SwiftUI
import CoreAudio
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        VStack(spacing: 0) {
            // Header with mode toggle and volume
            VStack(spacing: 14) {
                ModeToggleView()
                VolumeSliderView()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.02))

            Divider()
                .padding(.horizontal, 12)

            ScrollView {
                VStack(spacing: 20) {
                    // Speakers (show in speaker mode or custom mode)
                    if audioManager.currentMode == .speaker || audioManager.isCustomMode {
                        DeviceSectionView(
                            title: "Speakers",
                            icon: "speaker.wave.2.fill",
                            devices: audioManager.speakerDevices,
                            currentDeviceId: audioManager.currentOutputId,
                            onMove: audioManager.moveSpeakerDevice,
                            onSelect: { device in
                                if !audioManager.isCustomMode {
                                    audioManager.setMode(.speaker)
                                }
                                audioManager.setOutputDevice(device)
                            },
                            onHide: { audioManager.hideDevice($0, category: .speaker) },
                            onUnhide: { audioManager.unhideDevice($0, category: .speaker) },
                            category: .speaker,
                            showCategoryPicker: true,
                            isActiveCategory: audioManager.currentMode == .speaker || audioManager.isCustomMode
                        )
                    }

                    // Headphones (show in headphone mode or custom mode)
                    if audioManager.currentMode == .headphone || audioManager.isCustomMode {
                        DeviceSectionView(
                            title: "Headphones",
                            icon: "headphones",
                            devices: audioManager.headphoneDevices,
                            currentDeviceId: audioManager.currentOutputId,
                            onMove: audioManager.moveHeadphoneDevice,
                            onSelect: { device in
                                if !audioManager.isCustomMode {
                                    audioManager.setMode(.headphone)
                                }
                                audioManager.setOutputDevice(device)
                            },
                            onHide: { audioManager.hideDevice($0, category: .headphone) },
                            onUnhide: { audioManager.unhideDevice($0, category: .headphone) },
                            category: .headphone,
                            showCategoryPicker: true,
                            isActiveCategory: audioManager.currentMode == .headphone || audioManager.isCustomMode
                        )
                    }

                    // Microphones (always shown, at the bottom)
                    DeviceSectionView(
                        title: "Microphones",
                        icon: "mic.fill",
                        devices: audioManager.inputDevices,
                        currentDeviceId: audioManager.currentInputId,
                        onMove: audioManager.moveInputDevice,
                        onSelect: audioManager.setInputDevice,
                        onHide: { audioManager.hideDevice($0, category: nil) },
                        onUnhide: { audioManager.unhideDevice($0, category: nil) },
                        category: nil,
                        showCategoryPicker: false
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .frame(maxHeight: 420)

            Divider()
                .padding(.horizontal, 12)

            // Footer
            HStack(spacing: 16) {
                // Hidden devices toggle (only in normal mode)
                if !audioManager.isEditMode {
                    HiddenDevicesToggleView()
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Spacer()

                // Settings button
                Button {
                    PreferencesWindowController.shared.show(audioManager: audioManager)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Preferences")

                // Edit mode toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        audioManager.toggleEditMode()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: audioManager.isEditMode ? "checkmark.circle.fill" : "pencil.circle")
                            .font(.system(size: 12))
                        Text(audioManager.isEditMode ? "Done" : "Edit")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(audioManager.isEditMode ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: audioManager.isEditMode)

                // Quit button
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Quit")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.2), value: audioManager.isEditMode)
        }
        .frame(width: 340)
    }
}

struct ModeToggleView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        HStack(spacing: 4) {
            ForEach(OutputCategory.allCases, id: \.self) { mode in
                let isSelected = audioManager.currentMode == mode && !audioManager.isCustomMode
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if audioManager.isCustomMode {
                            audioManager.setCustomMode(false)
                        }
                        audioManager.setMode(mode)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11))
                        Text(mode.label)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.accentColor : Color.clear)
                    )
                    .foregroundColor(isSelected ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Custom mode toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    audioManager.setCustomMode(!audioManager.isCustomMode)
                }
            } label: {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(audioManager.isCustomMode ? Color.orange : Color.clear)
                    )
                    .foregroundColor(audioManager.isCustomMode ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .help("Manual mode - disable auto-switching")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
        )
        .animation(.easeInOut(duration: 0.2), value: audioManager.currentMode)
        .animation(.easeInOut(duration: 0.2), value: audioManager.isCustomMode)
    }
}

struct VolumeSliderView: View {
    @EnvironmentObject var audioManager: AudioManager

    var volumeIcon: String {
        if audioManager.isActiveOutputMuted {
            return "speaker.slash.fill"
        } else if audioManager.currentMode == .headphone {
            return "headphones"
        } else {
            if audioManager.volume <= 0 {
                return "speaker.fill"
            } else if audioManager.volume < 0.33 {
                return "speaker.wave.1.fill"
            } else if audioManager.volume < 0.66 {
                return "speaker.wave.2.fill"
            } else {
                return "speaker.wave.3.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                audioManager.toggleOutputMute()
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                    .animation(.easeInOut(duration: 0.15), value: volumeIcon)
            }
            .buttonStyle(.plain)
            .help(audioManager.isActiveOutputMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { Double(audioManager.volume) },
                    set: { audioManager.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .controlSize(.small)

            Text("\(Int(audioManager.volume * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .onScrollWheel { delta in
            let newVolume = audioManager.volume + Float(delta * 0.02)
            audioManager.setVolume(max(0, min(1, newVolume)))
        }
    }
}

// Scroll wheel modifier
struct ScrollWheelModifier: ViewModifier {
    let onScroll: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelReceiver(onScroll: onScroll)
        )
    }
}

struct ScrollWheelReceiver: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.deltaY)
    }
}

extension View {
    func onScrollWheel(_ action: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelModifier(onScroll: action))
    }
}

struct DeviceSectionView: View {
    let title: String
    let icon: String
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    var onHide: ((AudioDevice) -> Void)?
    var onUnhide: ((AudioDevice) -> Void)?
    var category: OutputCategory?
    var showCategoryPicker: Bool = false
    var isActiveCategory: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(isActiveCategory ? .accentColor : .secondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            if devices.isEmpty {
                Text("No devices")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DeviceListView(
                    devices: devices,
                    currentDeviceId: currentDeviceId,
                    onMove: onMove,
                    onSelect: onSelect,
                    showCategoryPicker: showCategoryPicker,
                    onHide: onHide,
                    onUnhide: onUnhide,
                    category: category
                )
            }
        }
    }
}

struct HiddenDevicesToggleView: View {
    @EnvironmentObject var audioManager: AudioManager
    @State private var isExpanded = false

    var allHiddenDevices: [AudioDevice] {
        audioManager.hiddenInputDevices +
        audioManager.hiddenSpeakerDevices +
        audioManager.hiddenHeadphoneDevices
    }

    var body: some View {
        if allHiddenDevices.isEmpty {
            Text("")
                .frame(height: 1)
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Image(systemName: "eye.slash")
                        .font(.system(size: 11))
                    Text("\(allHiddenDevices.count) ignored")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allHiddenDevices, id: \.id) { device in
                        HiddenDeviceRow(device: device)
                    }
                }
                .padding(12)
                .frame(minWidth: 220)
            }
        }
    }
}

struct HiddenDeviceRow: View {
    @EnvironmentObject var audioManager: AudioManager
    let device: AudioDevice
    @State private var isHovering = false

    var deviceIcon: String {
        if device.type == .input {
            return "mic.fill"
        } else {
            let category = audioManager.priorityManager.getCategory(for: device)
            return category == .headphone ? "headphones" : "speaker.wave.2.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: deviceIcon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 18)

            Text(device.name)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if isHovering {
                Button {
                    audioManager.unhideDevice(device)
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Stop ignoring")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

struct LaunchAtLoginToggle: View {
    @StateObject private var launchManager = LaunchAtLoginManager.shared
    
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                launchManager.isEnabled.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: launchManager.isEnabled ? "power.circle.fill" : "power.circle")
                    .font(.system(size: 12))
                Text("Login")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(launchManager.isEnabled ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(launchManager.isEnabled ? "Disable launch at login" : "Enable launch at login")
    }
}

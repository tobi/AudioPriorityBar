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
            .padding(.vertical, 8)

            Divider()

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
                            isActiveCategory: false
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
                            isActiveCategory: false
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
                        showCategoryPicker: false,
                        isActiveCategory: false
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(minHeight: 280, maxHeight: 480)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Footer
            VStack(spacing: 4) {
                // Standard menu items
                EditModeToggle()

                LaunchAtLoginToggle()

                Divider()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MenuItemButtonStyle())
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .animation(.easeInOut(duration: 0.2), value: audioManager.isEditMode)
        }
        .frame(width: 340)
    }
}

private struct SegmentButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 14, height: 14)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundColor(isSelected ? .primary : .secondary)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "segment", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ModeToggleView: View {
    @EnvironmentObject var audioManager: AudioManager
    @Namespace private var segmentAnimation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OutputCategory.allCases, id: \.self) { mode in
                SegmentButton(
                    icon: mode.icon,
                    label: mode.label,
                    isSelected: !audioManager.isCustomMode && audioManager.currentMode == mode,
                    namespace: segmentAnimation
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if audioManager.isCustomMode {
                            audioManager.setCustomMode(false)
                        }
                        audioManager.setMode(mode)
                    }
                }
            }

            SegmentButton(
                icon: "hand.raised.fill",
                label: "Manual",
                isSelected: audioManager.isCustomMode,
                namespace: segmentAnimation
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    audioManager.setCustomMode(!audioManager.isCustomMode)
                }
            }
            .help("Manual mode - disable auto-switching")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

struct VolumeSliderView: View {
    @EnvironmentObject var audioManager: AudioManager
    @State private var isEditing = false
    @State private var isTransitioning = false

    var volumeIcon: String {
        if audioManager.currentMode == .headphone {
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
            if #available(macOS 14.0, *) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 13))
                    .frame(width: 20, height: 14)
                    .foregroundColor(isEditing ? .accentColor : .primary)
                    .scaleEffect(isEditing ? 1.05 : (isTransitioning ? 0.9 : 1))
                    .blur(radius: isTransitioning ? 1 : 0)
                    .opacity(isTransitioning ? 0.5 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isEditing)
                    .animation(.easeInOut(duration: 0.25), value: isTransitioning)
                    .onChange(of: isEditing) { _, _ in
                        isTransitioning = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isTransitioning = false
                        }
                    }
            } else {
                // Fallback on earlier versions
            }

            Slider(
                value: Binding(
                    get: { Double(audioManager.volume) },
                    set: { audioManager.setVolume(Float($0)) }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isEditing = editing
                }
            )
            .controlSize(.small)

            Text("\(Int(audioManager.volume * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 4)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 12)

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
                .fill(isHovering ? Color.primary.opacity(0.1) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

struct EditModeToggle: View {
    @EnvironmentObject var audioManager: AudioManager

    var hiddenCount: Int {
        audioManager.hiddenInputDevices.count +
        audioManager.hiddenSpeakerDevices.count +
        audioManager.hiddenHeadphoneDevices.count
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                audioManager.toggleEditMode()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(audioManager.isEditMode ? 1 : 0)
                    .frame(width: 14)
                Text(audioManager.isEditMode ? "Done Editing" : "Edit Devices...")
                Spacer()
                if !audioManager.isEditMode && hiddenCount > 0 {
                    Text("\(hiddenCount) ignored")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(MenuItemButtonStyle())
    }
}

struct LaunchAtLoginToggle: View {
    @StateObject private var launchManager = LaunchAtLoginManager.shared

    var body: some View {
        Button {
            launchManager.isEnabled.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(launchManager.isEnabled ? 1 : 0)
                    .frame(width: 14)
                Text("Launch at Login")
                Spacer()
            }
        }
        .buttonStyle(MenuItemButtonStyle())
    }
}

struct MenuItemButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovering ? Color.primary.opacity(0.1) : Color.clear)
            )
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

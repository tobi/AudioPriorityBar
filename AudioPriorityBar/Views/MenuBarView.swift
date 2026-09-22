import SwiftUI
import CoreAudio
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var audioManager: AudioManager
    @State private var deviceListHeight: CGFloat = 0

    private let maxDeviceListHeight: CGFloat = 540

    private var deviceListOverflows: Bool {
        deviceListHeight.rounded(.up) > maxDeviceListHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Audio Priority Bar")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            ModeToggleView()
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Divider()

            VolumeSliderView()
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Microphones first, so the output mode tabs below clearly apply to outputs only
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

                    Divider()

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
                            showCategoryPicker: true
                        )
                    }

                    // Headphones (show in headphone mode or custom mode)
                    if audioManager.currentMode == .headphone || audioManager.isCustomMode {
                        // Separate from Speakers when both are shown; otherwise the divider above already does
                        if audioManager.isCustomMode {
                            Divider()
                        }

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
                            showCategoryPicker: true
                        )
                    }
                }
                // No horizontal padding: device rows span edge to edge and inset their own content
                .padding(.vertical, 14)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            // A ScrollView accepts any height it's offered, so the menu bar window would
            // never shrink when devices are removed. Size it to its content instead.
            // Round up so fractional heights don't leave the list scrollable by a sliver, and only
            // allow scrolling (and show the scroll bar) when the list really is taller than the cap.
            .frame(height: min(deviceListHeight.rounded(.up), maxDeviceListHeight))
            .scrollDisabled(!deviceListOverflows)
            .scrollIndicators(deviceListOverflows ? .automatic : .never)
            .onPreferenceChange(ContentHeightKey.self) { deviceListHeight = $0 }

            Divider()

            // Footer
            Group {
                if audioManager.isEditMode {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            audioManager.toggleEditMode()
                        }
                    } label: {
                        Text("Done Editing")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(nsColor: .controlAccentColor))  // white text needs the full-strength accent
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                } else {
                    HStack(spacing: 16) {
                        HiddenDevicesCountView()
                        Spacer()
                        FooterMenu()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .transition(.opacity)
        }
        .frame(width: 320)
        .tint(.appAccent)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ModeToggleView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderLabel(title: "Mode")

            HStack(spacing: 12) {
                ForEach(OutputCategory.allCases, id: \.self) { mode in
                    ModeRadioButton(
                        title: mode.label,
                        isSelected: audioManager.currentMode == mode && !audioManager.isCustomMode
                    ) {
                        if audioManager.isCustomMode {
                            audioManager.setCustomMode(false)
                        }
                        audioManager.setMode(mode)
                    }
                }

                ModeRadioButton(
                    title: "Manual",
                    isSelected: audioManager.isCustomMode
                ) {
                    audioManager.setCustomMode(true)
                }
                .help("Manual mode - disable auto-switching")

                Spacer(minLength: 0)
            }
        }
    }
}

extension Color {
    /// The system accent color, adjusted for contrast on the translucent popover:
    /// lightened in Dark Mode, deepened slightly in Light Mode.
    static let appAccent = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let accent = NSColor.controlAccentColor
        return (isDark
            ? accent.blended(withFraction: 0.35, of: .white)
            : accent.blended(withFraction: 0.15, of: .black)) ?? accent
    })
}

struct FooterMenu: View {
    @EnvironmentObject var audioManager: AudioManager
    @State private var isHovering = false

    var body: some View {
        Menu {
            SettingsMenuItem()

            Button("Edit Mode…") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    audioManager.toggleEditMode()
                }
            }

            Divider()

            Button("Quit Audio Priority Bar") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15))
                .foregroundColor(isHovering ? .primary : .secondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings, Edit Mode, Quit")
        .accessibilityLabel("Options")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

struct HeaderLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

struct ModeRadioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                action()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .appAccent : .secondary)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct VolumeSliderView: View {
    @EnvironmentObject var audioManager: AudioManager

    /// The active output device's hardware icon; generic speakers show the volume level instead
    var volumeIcon: String {
        let icon = audioManager.activeOutputDevice.map {
            $0.hardwareIcon(category: audioManager.priorityManager.getCategory(for: $0))
        } ?? (audioManager.currentMode == .headphone ? "headphones" : "speaker.wave.2")

        guard icon == "speaker.wave.2" else { return icon }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderLabel(title: "Volume")

            HStack(spacing: 10) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 13))
                    .foregroundColor(.appAccent)
                    .frame(width: 20)
                    .animation(.easeInOut(duration: 0.15), value: volumeIcon)

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                // Same width as the rows' priority column, so the icon lines up with the numbers below
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: DeviceListView.priorityColumnWidth)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.horizontal, DeviceListView.horizontalInset)

            if devices.isEmpty {
                Text("No devices")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()
                    .padding(.vertical, 10)
                    .padding(.horizontal, DeviceListView.horizontalInset)
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

struct HiddenDevicesCountView: View {
    @EnvironmentObject var audioManager: AudioManager
    @State private var isHovering = false

    /// Counts physical devices, so a device ignored as both input and output counts once
    var hiddenDeviceCount: Int {
        let all = audioManager.hiddenInputDevices +
            audioManager.hiddenSpeakerDevices +
            audioManager.hiddenHeadphoneDevices
        return Set(all.map(\.uid)).count
    }

    var body: some View {
        if hiddenDeviceCount == 0 {
            Text("")
                .frame(height: 1)
        } else {
            // Edit mode lists ignored devices alongside the rest, where they can be un-ignored
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    audioManager.toggleEditMode()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 11))
                    Text("\(hiddenDeviceCount) ignored")
                        .font(.system(size: 12))
                }
                .foregroundColor(isHovering ? .primary : .secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show ignored devices in Edit Mode")
            .onHover { isHovering = $0 }
        }
    }
}

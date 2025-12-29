import SwiftUI
import CoreAudio
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        VStack(spacing: 0) {
            // Header with mode toggle and volume
            VStack(spacing: 6) {
                ModeToggleView()
                VolumeSliderView()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 10)

            ScrollView {
                VStack(spacing: 12) {
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }

            Divider()
                .padding(.horizontal, 10)

            // Footer
            FooterView()
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: 600)
    }
}

struct FooterView: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var nowPlayingService: NowPlayingService

    var body: some View {
        VStack(spacing: 0) {
            // Now Playing (if something is playing)
            if nowPlayingService.nowPlaying != nil {
                NowPlayingView()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                Divider()
                    .padding(.horizontal, 10)
            }

            // Hidden devices toggle (only in normal mode)
            if !audioManager.isEditMode && !audioManager.allHiddenDevices.isEmpty {
                HiddenDevicesToggleView()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                Divider()
                    .padding(.horizontal, 10)
            }

            // Bottom row with Edit and Quit
            HStack(spacing: 0) {
                // Edit mode toggle
                Button {
                    audioManager.toggleEditMode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: audioManager.isEditMode ? "checkmark" : "slider.horizontal.3")
                            .font(.system(size: 10))
                        Text(audioManager.isEditMode ? "Done" : "Edit Priorities...")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(audioManager.isEditMode ? .accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 20)

                // Quit button
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack(spacing: 4) {
                        Text("Quit")
                            .font(.system(size: 11))
                        Spacer()
                        Text("⌘Q")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 70)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Now Playing

struct NowPlayingView: View {
    @EnvironmentObject var nowPlayingService: NowPlayingService
    @State private var isHovering = false

    var body: some View {
        if let nowPlaying = nowPlayingService.nowPlaying {
            HStack(spacing: 8) {
                // Album art or app icon
                Group {
                    if let artwork = nowPlaying.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let appIcon = nowPlaying.appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 32, height: 32)
                .cornerRadius(4)
                .clipped()

                // Track info
                VStack(alignment: .leading, spacing: 1) {
                    Text(nowPlaying.title ?? "Unknown")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let artist = nowPlaying.artist {
                        Text(artist)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Playback controls
                HStack(spacing: 2) {
                    Button {
                        nowPlayingService.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 9))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                    Button {
                        nowPlayingService.togglePlayPause()
                    } label: {
                        Image(systemName: nowPlayingService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)

                    Button {
                        nowPlayingService.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 9))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovering ? 0.06 : 0.03))
            )
            .onHover { hovering in
                isHovering = hovering
            }
        }
    }
}

struct ModeToggleView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        HStack(spacing: 1) {
            ForEach(OutputCategory.allCases, id: \.self) { mode in
                let isActive = audioManager.currentMode == mode && !audioManager.isCustomMode
                Button {
                    if audioManager.isCustomMode {
                        audioManager.setCustomMode(false)
                    }
                    audioManager.setMode(mode)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 10))
                        Text(mode.label)
                            .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isActive ? Color.accentColor : Color.clear)
                    )
                    .foregroundColor(isActive ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Custom mode toggle
            Button {
                audioManager.setCustomMode(!audioManager.isCustomMode)
            } label: {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(audioManager.isCustomMode ? Color.orange : Color.clear)
                    )
                    .foregroundColor(audioManager.isCustomMode ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .help("Manual mode - disable auto-switching")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
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
        HStack(spacing: 5) {
            Image(systemName: volumeIcon)
                .font(.system(size: 10))
                .foregroundColor(audioManager.isActiveOutputMuted ? .red : .accentColor)
                .frame(width: 16)

            Slider(
                value: Binding(
                    get: { Double(audioManager.volume) },
                    set: { audioManager.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .controlSize(.mini)

            Text("\(Int(audioManager.volume * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .trailing)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(isActiveCategory ? .accentColor : .secondary)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
            }
            .padding(.leading, 2)

            if devices.isEmpty {
                Text("No devices")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .italic()
                    .padding(.vertical, 6)
                    .padding(.leading, 2)
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

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 9))
                Text("\(audioManager.allHiddenDevices.count) ignored")
                    .font(.system(size: 10))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .foregroundColor(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(audioManager.allHiddenDevices, id: \.id) { device in
                    HiddenDeviceRow(device: device)
                }
            }
            .padding(6)
            .frame(minWidth: 180)
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
        HStack(spacing: 6) {
            Image(systemName: deviceIcon)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(width: 14)

            Text(device.name)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if isHovering {
                Button {
                    audioManager.unhideDevice(device)
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Stop ignoring")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

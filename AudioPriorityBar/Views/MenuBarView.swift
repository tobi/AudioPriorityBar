import SwiftUI
import CoreAudio
import AppKit

private enum MenuChromePart: Hashable {
    case guidance
    case outputSection
    case inputSection
    case footer
}

private struct MenuChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [MenuChromePart: CGFloat] = [:]

    static func reduce(
        value: inout [MenuChromePart: CGFloat],
        nextValue: () -> [MenuChromePart: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private extension View {
    func reportMenuChromeHeight(_ part: MenuChromePart, additionalHeight: CGFloat = 0) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MenuChromeHeightPreferenceKey.self,
                    value: [part: proxy.size.height + additionalHeight]
                )
            }
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var audioManager: AudioManager
    @State private var measuredChromeHeights: [MenuChromePart: CGFloat] = [:]

    private var fixedChromeHeight: CGFloat {
        let parts: [MenuChromePart] = [.guidance, .outputSection, .inputSection, .footer]
        guard parts.allSatisfy({ measuredChromeHeights[$0] != nil }) else {
            return AdaptiveDeviceListLayout.estimatedFixedChromeHeight
        }
        let measuredParts = parts.reduce(CGFloat(0)) { total, part in
            total + (measuredChromeHeights[part] ?? 0)
        }
        return measuredParts + AdaptiveDeviceListLayout.dividerHeight * 3
    }

    private var listHeights: AdaptiveDeviceListHeights {
        AdaptiveDeviceListLayout.allocate(
            outputCount: audioManager.outputDevices.count,
            inputCount: audioManager.inputDevices.count,
            availableHeight: max(0, maximumMenuHeight - fixedChromeHeight)
        )
    }

    private var maximumMenuHeight: CGFloat {
        let pointerLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointerLocation, $0.frame, false) }
            ?? NSScreen.main
        let visibleHeight = screen?.visibleFrame.height ?? AdaptiveDeviceListLayout.maximumPreferredMenuHeight
        return min(
            AdaptiveDeviceListLayout.maximumPreferredMenuHeight,
            max(0, visibleHeight - AdaptiveDeviceListLayout.screenEdgeMargin)
        )
    }

    private var menuHeight: CGFloat {
        min(maximumMenuHeight, fixedChromeHeight + listHeights.output + listHeights.input)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Rank devices from highest to lowest.")
                Text("Auto-switch uses the highest connected device.")
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .reportMenuChromeHeight(.guidance)

            Divider()
                .padding(.horizontal, 12)

            DeviceSectionView(
                type: .output,
                title: "Output",
                icon: "speaker.wave.2.fill",
                helperText: "Uses the highest connected output",
                devices: audioManager.outputDevices,
                currentDeviceId: audioManager.currentOutputId,
                listHeight: listHeights.output,
                isAutoSwitchEnabled: audioManager.isOutputAutoSwitchEnabled,
                onAutoSwitchChanged: audioManager.setOutputAutoSwitchEnabled,
                onMove: audioManager.moveOutputDevice,
                onSelect: audioManager.setOutputDevice,
                onPromote: audioManager.promoteOutputDevice,
                onHide: audioManager.hideDevice,
                onUnhide: audioManager.unhideDevice,
                showsOutputControls: true
            )

            Divider()
                .padding(.horizontal, 12)

            DeviceSectionView(
                type: .input,
                title: "Input",
                icon: "mic.fill",
                helperText: "Uses the highest connected input",
                devices: audioManager.inputDevices,
                currentDeviceId: audioManager.currentInputId,
                listHeight: listHeights.input,
                isAutoSwitchEnabled: audioManager.isInputAutoSwitchEnabled,
                onAutoSwitchChanged: audioManager.setInputAutoSwitchEnabled,
                onMove: audioManager.moveInputDevice,
                onSelect: audioManager.setInputDevice,
                onPromote: audioManager.promoteInputDevice,
                onHide: audioManager.hideDevice,
                onUnhide: audioManager.unhideDevice
            )

            Divider()
                .padding(.horizontal, 12)

            HStack(spacing: 12) {
                AutomationMenuView()

                Spacer(minLength: 4)

                LaunchAtLoginToggle()

                Divider()
                    .frame(height: 18)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        audioManager.toggleEditMode()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: audioManager.isEditMode ? "checkmark.circle.fill" : "pencil.circle")
                            .font(.system(size: 12))
                        Text(audioManager.isEditMode ? "Done" : "Edit")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(audioManager.isEditMode ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: audioManager.isEditMode)

                Divider()
                    .frame(height: 18)

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
            .fixedSize(horizontal: false, vertical: true)
            .reportMenuChromeHeight(.footer)
            .animation(.easeInOut(duration: 0.2), value: audioManager.isEditMode)
        }
        .onPreferenceChange(MenuChromeHeightPreferenceKey.self) { heights in
            if heights != measuredChromeHeights {
                measuredChromeHeights = heights
            }
        }
        .frame(width: 340)
        .frame(height: menuHeight, alignment: .top)
    }
}

struct AutomationMenuView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        Menu {
            if audioManager.isAutomationPaused {
                Button {
                    audioManager.setAutomationPaused(false)
                } label: {
                    Label("Resume all auto-switching", systemImage: "play.circle")
                }
                Text("Restores Output and Input")
            } else {
                Button {
                    audioManager.setAutomationPaused(true)
                } label: {
                    Label("Pause all auto-switching", systemImage: "pause.circle")
                }
                Text("Stops Output and Input")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: audioManager.isAutomationPaused ? "pause.circle.fill" : "gearshape.2")
                    .font(.system(size: 11))
                Text(audioManager.isAutomationPaused ? "Paused" : "Automation")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(audioManager.isAutomationPaused ? .orange : .secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(audioManager.isAutomationPaused ? "Auto-switching is paused" : "Automation options")
        .accessibilityLabel(Text("Automation"))
        .accessibilityValue(Text(audioManager.isAutomationPaused ? "Paused" : "Running"))
    }
}

struct VolumeSliderView: View {
    @EnvironmentObject var audioManager: AudioManager

    var volumeIcon: String {
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
        HStack(spacing: 10) {
            Image(systemName: volumeIcon)
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
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
    @EnvironmentObject var audioManager: AudioManager
    let type: AudioDeviceType
    let title: String
    let icon: String
    let helperText: String
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let listHeight: CGFloat
    let isAutoSwitchEnabled: Bool
    let onAutoSwitchChanged: (Bool) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    let onPromote: (AudioDevice) -> Void
    var onHide: ((AudioDevice) -> Void)?
    var onUnhide: ((AudioDevice) -> Void)?
    var showsOutputControls: Bool = false

    private var accentColor: Color {
        type == .input ? .green : .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accentColor)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()

                    Toggle(
                        "Auto-switch",
                        isOn: Binding(
                            get: { isAutoSwitchEnabled },
                            set: onAutoSwitchChanged
                        )
                    )
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(accentColor)
                    .disabled(audioManager.isAutomationPaused)
                    .help(
                        audioManager.isAutomationPaused
                            ? "Resume all auto-switching to change this setting"
                            : "Automatically use the highest connected \(title.lowercased())"
                    )
                }

                Text(helperText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if showsOutputControls {
                    VolumeSliderView()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .reportMenuChromeHeight(
                type == .output ? .outputSection : .inputSection,
                additionalHeight: 32
            )

            ScrollView(.vertical) {
                if devices.isEmpty {
                    Text("No devices")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                        .italic()
                        .padding(.horizontal, 10)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: AdaptiveDeviceListLayout.emptyStateHeight,
                            alignment: .leading
                        )
                } else {
                    DeviceListView(
                        devices: devices,
                        currentDeviceId: currentDeviceId,
                        onMove: onMove,
                        onSelect: onSelect,
                        onPromote: onPromote,
                        selectionChangesPriority: audioManager.isAutomationActive(for: type),
                        onHide: onHide,
                        onUnhide: onUnhide
                    )
                    .padding(.vertical, AdaptiveDeviceListLayout.listVerticalPadding / 2)
                }
            }
            .frame(height: listHeight)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

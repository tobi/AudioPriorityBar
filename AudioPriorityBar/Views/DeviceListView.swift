import SwiftUI
import CoreAudio

struct DeviceListView: View {
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    var showCategoryPicker: Bool = false
    var onHide: ((AudioDevice) -> Void)?
    var onUnhide: ((AudioDevice) -> Void)?
    var isHiddenSection: Bool = false
    var category: OutputCategory? = nil

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                DeviceRowView(
                    device: device,
                    index: index,
                    totalCount: devices.count,
                    isSelected: device.id == currentDeviceId,
                    onSelect: { onSelect(device) },
                    showCategoryPicker: showCategoryPicker,
                    onHide: onHide,
                    onUnhide: onUnhide,
                    isHiddenSection: isHiddenSection,
                    category: category,
                    onMoveUp: index > 0 ? {
                        onMove(IndexSet(integer: index), index - 1)
                    } : nil,
                    onMoveDown: index < devices.count - 1 ? {
                        onMove(IndexSet(integer: index), index + 2)
                    } : nil
                )
                .draggable(device.uid) {
                    DeviceDragPreview(name: device.name)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let droppedUid = items.first,
                          let fromIndex = devices.firstIndex(where: { $0.uid == droppedUid }),
                          fromIndex != index else { return false }

                    let toIndex = fromIndex < index ? index + 1 : index
                    onMove(IndexSet(integer: fromIndex), toIndex)
                    return true
                }
            }
        }
    }
}

struct DeviceDragPreview: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
            Text(name)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
        .shadow(radius: 3)
    }
}

struct DeviceRowView: View {
    @EnvironmentObject var audioManager: AudioManager
    let device: AudioDevice
    let index: Int
    var totalCount: Int = 1
    let isSelected: Bool
    let onSelect: () -> Void
    var showCategoryPicker: Bool = false
    var onHide: ((AudioDevice) -> Void)?
    var onUnhide: ((AudioDevice) -> Void)?
    var isHiddenSection: Bool = false
    var category: OutputCategory? = nil
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    @State private var isHovering = false

    var isDisconnected: Bool {
        !device.isConnected
    }

    var isIgnored: Bool {
        audioManager.isDeviceIgnored(device, inCategory: category)
    }

    var isAlwaysIgnored: Bool {
        audioManager.isAlwaysIgnored(device)
    }

    var isGrayed: Bool {
        isDisconnected || isHiddenSection || isAlwaysIgnored
    }

    var statusIcon: String? {
        if isDisconnected {
            return "wifi.slash"
        } else if isAlwaysIgnored {
            return "forward.fill"
        } else if isIgnored && audioManager.isEditMode {
            return "eye.slash"
        }
        return nil
    }

    var lastSeenText: String? {
        guard isDisconnected,
              let stored = audioManager.priorityManager.getStoredDevice(uid: device.uid) else {
            return nil
        }
        return stored.lastSeenRelative
    }

    var isMuted: Bool {
        device.isConnected && audioManager.isDeviceMuted(device)
    }

    var body: some View {
        HStack(spacing: 3) {
            // Priority label OR reorder controls (on hover)
            if !isHiddenSection {
                ZStack {
                    // Reorder controls on hover
                    HStack(spacing: 0) {
                        Button {
                            onMoveUp?()
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .semibold))
                                .frame(width: 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(onMoveUp != nil ? .secondary : .secondary.opacity(0.3))
                        .disabled(onMoveUp == nil)

                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .frame(width: 8)

                        Button {
                            onMoveDown?()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .frame(width: 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(onMoveDown != nil ? .secondary : .secondary.opacity(0.3))
                        .disabled(onMoveDown == nil)
                    }
                    .opacity(isHovering ? 1 : 0)

                    // Priority number when not hovering
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(isSelected && !isDisconnected ? .accentColor : .secondary)
                        .opacity(isHovering ? 0 : 1)
                }
                .frame(width: 32)
            }

            // Active indicator dot
            Circle()
                .fill(isSelected && !isDisconnected ? Color.accentColor : Color.clear)
                .frame(width: 5, height: 5)

            // Device name
            Button(action: {
                if !isDisconnected && audioManager.isCustomMode {
                    onSelect()
                }
            }) {
                HStack(spacing: 4) {
                    Text(device.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(isGrayed ? .secondary : .primary)

                    // Status indicator
                    if let icon = statusIcon {
                        Image(systemName: icon)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.6))
                    }

                    // Last seen time for disconnected devices
                    if let lastSeen = lastSeenText {
                        Text(lastSeen)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                    }

                    // Status badges
                    if isAlwaysIgnored {
                        Text("Skip")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange))
                    }

                    if isMuted {
                        Text("Muted")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisconnected)

            // Actions menu (shown on hover)
            if isHovering {
                Menu {
                    if showCategoryPicker {
                        Button {
                            audioManager.setCategory(.speaker, for: device)
                        } label: {
                            Label("Move to Speakers", systemImage: "speaker.wave.2.fill")
                        }
                        Button {
                            audioManager.setCategory(.headphone, for: device)
                        } label: {
                            Label("Move to Headphones", systemImage: "headphones")
                        }
                        Divider()
                    }

                    // Always ignore toggle (visible for connected devices)
                    if !isDisconnected {
                        Button {
                            audioManager.setAlwaysIgnored(device, ignored: !isAlwaysIgnored)
                        } label: {
                            if isAlwaysIgnored {
                                Label("Stop Skipping", systemImage: "play.fill")
                            } else {
                                Label("Always Skip", systemImage: "forward.fill")
                            }
                        }
                    }

                    if !isAlwaysIgnored {
                        if isHiddenSection || isIgnored {
                            Button {
                                audioManager.unhideDevice(device)
                            } label: {
                                Label("Stop Ignoring", systemImage: "eye")
                            }
                        } else {
                            if let onHide {
                                Divider()

                                Button {
                                    onHide(device)
                                } label: {
                                    let categoryLabel = device.type == .input ? "microphone" :
                                        (category == .headphone ? "headphone" : "speaker")
                                    Label("Ignore as \(categoryLabel)", systemImage: "eye.slash")
                                }

                                // "Ignore entirely" option for output devices
                                if device.type == .output {
                                    Button {
                                        audioManager.hideDeviceEntirely(device)
                                    } label: {
                                        Label("Ignore entirely", systemImage: "eye.slash.fill")
                                    }
                                }
                            }
                        }
                    }

                    // Option to forget disconnected devices
                    if isDisconnected {
                        Divider()
                        Button(role: .destructive) {
                            audioManager.priorityManager.forgetDevice(device.uid)
                            audioManager.refreshDevices()
                        } label: {
                            Label("Forget Device", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .opacity(isGrayed ? 0.5 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

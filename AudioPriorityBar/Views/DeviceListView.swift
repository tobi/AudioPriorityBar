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
        VStack(spacing: 2) {
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
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
            Text(name)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .shadow(radius: 4)
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

    var isGrayed: Bool {
        isDisconnected || isIgnored || isHiddenSection
    }

    var statusIcon: String? {
        if isDisconnected {
            return "wifi.slash"
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

    var body: some View {
        HStack(spacing: 4) {
            // Reorder controls (on hover)
            if !isHiddenSection {
                HStack(spacing: 0) {
                    // Up arrow
                    Button {
                        onMoveUp?()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 16, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(onMoveUp != nil && isHovering ? .secondary : .clear)
                    .disabled(onMoveUp == nil)

                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 9))
                        .foregroundColor(isHovering ? .secondary : .clear)
                        .frame(width: 12)

                    // Down arrow
                    Button {
                        onMoveDown?()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 16, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(onMoveDown != nil && isHovering ? .secondary : .clear)
                    .disabled(onMoveDown == nil)
                }
            }

            // Priority number
            if !isHiddenSection {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            }

            // Device name
            Button(action: {
                if !isDisconnected {
                    onSelect()
                }
            }) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(isGrayed ? .secondary : .primary)

                    // Status indicator
                    if let icon = statusIcon {
                        Image(systemName: icon)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    // Last seen time for disconnected devices
                    if let lastSeen = lastSeenText {
                        Text(lastSeen)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                    }

                    Spacer()

                    if isSelected && !isDisconnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 14))
                    }
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

                    if isHiddenSection || isIgnored {
                        Button {
                            audioManager.unhideDevice(device)
                        } label: {
                            Label("Stop Ignoring", systemImage: "eye")
                        }
                    } else {
                        if let onHide {
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
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .opacity(isGrayed ? 0.6 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected && !isDisconnected ? Color.accentColor.opacity(0.1) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

import SwiftUI
import AVFoundation
import AppKit

struct CameraListView: View {
    let cameras: [CameraDevice]
    let currentCameraId: String?
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (CameraDevice) -> Void
    var onHide: ((CameraDevice) -> Void)?
    var onUnhide: ((CameraDevice) -> Void)?
    var isHiddenSection: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(cameras.enumerated()), id: \.element.id) { index, camera in
                CameraRowView(
                    camera: camera,
                    index: index,
                    totalCount: cameras.count,
                    isSelected: camera.id == currentCameraId,
                    onSelect: { onSelect(camera) },
                    onHide: onHide,
                    onUnhide: onUnhide,
                    isHiddenSection: isHiddenSection,
                    onMoveUp: index > 0 ? {
                        onMove(IndexSet(integer: index), index - 1)
                    } : nil,
                    onMoveDown: index < cameras.count - 1 ? {
                        onMove(IndexSet(integer: index), index + 2)
                    } : nil
                )
                .draggable(camera.uid) {
                    CameraDragPreview(name: camera.name)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let droppedUid = items.first,
                          let fromIndex = cameras.firstIndex(where: { $0.uid == droppedUid }),
                          fromIndex != index else { return false }

                    let toIndex = fromIndex < index ? index + 1 : index
                    onMove(IndexSet(integer: fromIndex), toIndex)
                    return true
                }
            }
        }
    }
}

struct CameraDragPreview: View {
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

struct CameraRowView: View {
    @EnvironmentObject var audioManager: AudioManager
    let camera: CameraDevice
    let index: Int
    var totalCount: Int = 1
    let isSelected: Bool
    let onSelect: () -> Void
    var onHide: ((CameraDevice) -> Void)?
    var onUnhide: ((CameraDevice) -> Void)?
    var isHiddenSection: Bool = false
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    @State private var isHovering = false

    var isDisconnected: Bool {
        !camera.isConnected
    }

    var isIgnored: Bool {
        audioManager.isCameraHidden(camera)
    }

    var isGrayed: Bool {
        isDisconnected || isHiddenSection
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
              let stored = audioManager.priorityManager.getStoredDevice(uid: camera.uid) else {
            return nil
        }
        return stored.lastSeenRelative
    }

    var body: some View {
        HStack(spacing: 4) {
            // Priority label OR reorder controls (on hover)
            if !isHiddenSection {
                ZStack {
                    // Reorder controls on hover
                    HStack(spacing: 0) {
                        Button {
                            onMoveUp?()
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(onMoveUp != nil ? .secondary : .secondary.opacity(0.3))
                        .disabled(onMoveUp == nil)

                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 10)

                        Button {
                            onMoveDown?()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(onMoveDown != nil ? .secondary : .secondary.opacity(0.3))
                        .disabled(onMoveDown == nil)
                    }
                    .opacity(isHovering ? 1 : 0)

                    // Priority number or "Active" label when not hovering
                    Group {
                        if isSelected && !isDisconnected {
                            Text("Active")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.accentColor)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .opacity(isHovering ? 0 : 1)
                }
                .frame(width: 38)
            }

            // Camera name
            Button(action: {
                if !isDisconnected && audioManager.isCustomMode {
                    onSelect()
                }
            }) {
                HStack(spacing: 6) {
                    Text(camera.name)
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

                    // Last seen time for disconnected cameras
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
                    if isHiddenSection || isIgnored {
                        Button {
                            audioManager.unhideCamera(camera)
                        } label: {
                            Label("Stop Ignoring", systemImage: "eye")
                        }
                    } else {
                        if let onHide {
                            Button {
                                onHide(camera)
                            } label: {
                                Label("Ignore camera", systemImage: "eye.slash")
                            }
                        }
                    }

                    // Option to forget disconnected cameras
                    if isDisconnected {
                        Divider()
                        Button(role: .destructive) {
                            audioManager.forgetCamera(camera)
                        } label: {
                            Label("Forget Camera", systemImage: "trash")
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
        .padding(.leading, 2)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .opacity(isGrayed ? 0.6 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected && !isDisconnected ? Color.accentColor.opacity(0.1) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected && !isDisconnected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct CameraSectionView: View {
    let title: String
    let icon: String
    let cameras: [CameraDevice]
    let currentCameraId: String?
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (CameraDevice) -> Void
    var onHide: ((CameraDevice) -> Void)?
    var onUnhide: ((CameraDevice) -> Void)?
    var isActiveCategory: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isActiveCategory ? .accentColor : .secondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            if cameras.isEmpty {
                Text("No cameras")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
                CameraListView(
                    cameras: cameras,
                    currentCameraId: currentCameraId,
                    onMove: onMove,
                    onSelect: onSelect,
                    onHide: onHide,
                    onUnhide: onUnhide
                )
            }
        }
    }
}

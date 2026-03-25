import SwiftUI
import CoreAudio
import UniformTypeIdentifiers

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

    // Only track which item is being dragged and the target - not the offset
    @State private var draggingIndex: Int? = nil
    @State private var targetIndex: Int? = nil
    
    private let rowHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                DraggableDeviceRow(
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
                    } : nil,
                    isDragging: draggingIndex == index,
                    isDropTarget: isDropTarget(for: index),
                    isDropTargetBelow: isDropTargetBelow(for: index),
                    rowHeight: rowHeight,
                    deviceCount: devices.count,
                    onDragStarted: {
                        draggingIndex = index
                    },
                    onTargetChanged: { newTarget in
                        targetIndex = newTarget
                    },
                    onDragEnded: {
                        performMove(fromIndex: index)
                    }
                )
                .zIndex(draggingIndex == index ? 100 : 0)
            }
        }
    }
    
    private func isDropTarget(for index: Int) -> Bool {
        guard let target = targetIndex, let dragging = draggingIndex else { return false }
        return target == index && dragging != index && dragging != index - 1
    }
    
    private func isDropTargetBelow(for index: Int) -> Bool {
        guard let target = targetIndex, let dragging = draggingIndex else { return false }
        return target == devices.count && index == devices.count - 1 && dragging != devices.count - 1
    }
    
    private func performMove(fromIndex: Int) {
        if let target = targetIndex, target != fromIndex {
            onMove(IndexSet(integer: fromIndex), target)
        }
        draggingIndex = nil
        targetIndex = nil
    }
}

// Row wrapper that handles the drag gesture
struct DraggableDeviceRow: View {
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
    let isDragging: Bool
    var isDropTarget: Bool = false
    var isDropTargetBelow: Bool = false
    let rowHeight: CGFloat
    let deviceCount: Int
    let onDragStarted: () -> Void
    let onTargetChanged: (Int?) -> Void
    let onDragEnded: () -> Void
    
    @State private var isHovering = false
    @State private var lastReportedTarget: Int? = nil

    var isDisconnected: Bool {
        !device.isConnected
    }

    var isIgnored: Bool {
        audioManager.isDeviceIgnored(device, inCategory: category)
    }

    var isGrayed: Bool {
        isDisconnected || isHiddenSection
    }

    var isNeverUse: Bool {
        audioManager.isNeverUse(device)
    }

    var statusIcon: String? {
        if isDisconnected {
            return "wifi.slash"
        } else if isIgnored && audioManager.isEditMode {
            return "eye.slash"
        } else if isNeverUse {
            return "nosign"
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
    
    private func calculateTarget(offset: CGFloat) -> Int? {
        let rowsOffset = Int(round(offset / rowHeight))
        var newTarget = index + rowsOffset
        newTarget = max(0, min(deviceCount, newTarget))
        
        if newTarget == index || newTarget == index + 1 {
            return nil
        }
        return newTarget
    }

    var body: some View {
        HStack(spacing: 8) {
            // Drag handle + priority label area
            if !isHiddenSection {
                ZStack {
                    // Drag handle icon
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: rowHeight)
                        .opacity(isHovering || isDragging ? 1 : 0)
                        .scaleEffect(isHovering || isDragging ? 1 : 0.8)
                    
                    // Priority number or "Active" label when not hovering
                    Group {
                        if isSelected && !isDisconnected {
                            Text("Active")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.accentColor)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }
                    .opacity(isHovering || isDragging ? 0 : 1)
                    .scaleEffect(isHovering || isDragging ? 0.8 : 1)
                }
                .frame(width: 36)
                .animation(.easeInOut(duration: 0.12), value: isHovering)
                .animation(.easeInOut(duration: 0.12), value: isDragging)
            }

            // Device name - use HStack with tap gesture instead of Button to not interfere with drag
            HStack(spacing: 8) {
                Text(device.name)
                    .font(.system(size: 13, weight: .regular))
                    .strikethrough(isNeverUse, color: .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(isGrayed || isNeverUse ? .secondary : .primary)

                if let icon = statusIcon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }

                if let lastSeen = lastSeenText {
                    Text(lastSeen)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                if isMuted {
                    Text("Muted")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red))
                }

                Spacer(minLength: 12)

                if isSelected && !isDisconnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 15))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

            // Actions menu - always reserve space to prevent layout shifts
            ZStack {
                // Invisible placeholder to reserve space
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .opacity(0)
                
                // Actual menu (shown on hover)
                if isHovering && !isDragging {
                    Group {
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

                            if device.type == .output {
                                Button {
                                    audioManager.hideDeviceEntirely(device)
                                } label: {
                                    Label("Ignore entirely", systemImage: "eye.slash.fill")
                                }
                            }
                        }
                    }

                    // Prefer for current output (input devices only)
                    if device.type == .input && device.isConnected, let currentOutputId = audioManager.currentOutputId,
                       let currentOutput = (audioManager.speakerDevices + audioManager.headphoneDevices).first(where: { $0.id == currentOutputId }) {
                        Divider()
                        let isPreferred = audioManager.getPreferredInputUID(forOutput: currentOutput.uid) == device.uid
                        Button {
                            if isPreferred {
                                audioManager.clearPreferredInput(forOutput: currentOutput.uid)
                            } else {
                                audioManager.setPreferredInput(device, forOutput: currentOutput.uid)
                            }
                        } label: {
                            if isPreferred {
                                Label("Clear preferred for \(currentOutput.name)", systemImage: "star.slash")
                            } else {
                                Label("Prefer for \(currentOutput.name)", systemImage: "star")
                            }
                        }
                    }

                    if isDisconnected {
                        Divider()
                        Button(role: .destructive) {
                            audioManager.priorityManager.forgetDevice(device.uid)
                            audioManager.refreshDevices()
                        } label: {
                            Label("Forget Device", systemImage: "trash")
                        }
                    }

                    if device.isConnected {
                        Divider()
                        Button {
                            audioManager.setNeverUse(device, neverUse: !audioManager.isNeverUse(device))
                        } label: {
                            if audioManager.isNeverUse(device) {
                                Label("Allow Use", systemImage: "checkmark.circle")
                            } else {
                                Label("Never Use", systemImage: "nosign")
                            }
                        }
                    }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(width: 32)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .opacity(isDragging ? 0.5 : (isGrayed ? 0.6 : 1.0))
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected && !isDisconnected ? Color.accentColor.opacity(0.12) : (isHovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected && !isDisconnected ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 1.5)
        )
        // Drop indicator above this row
        .overlay(alignment: .top) {
            if isDropTarget {
                DropIndicatorLine()
                    .offset(y: -5)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        // Drop indicator below this row (for last position)
        .overlay(alignment: .bottom) {
            if isDropTargetBelow {
                DropIndicatorLine()
                    .offset(y: 5)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        // Highlight the dragged row with a border instead of moving it
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDragging ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
        .animation(.easeInOut(duration: 0.1), value: isDropTarget)
        .animation(.easeInOut(duration: 0.1), value: isDropTargetBelow)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDisconnected && audioManager.isCustomMode {
                onSelect()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if !isDragging {
                        onDragStarted()
                    }
                    let newTarget = calculateTarget(offset: value.translation.height)
                    if newTarget != lastReportedTarget {
                        lastReportedTarget = newTarget
                        onTargetChanged(newTarget)
                    }
                }
                .onEnded { _ in
                    lastReportedTarget = nil
                    onDragEnded()
                }
        )
    }
}

// Drop indicator line
struct DropIndicatorLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .padding(.horizontal, 2)
    }
}

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
    
    private let rowHeight: CGFloat = 26

    /// Rows span the full window width; this insets their content to match the section headers
    static let horizontalInset: CGFloat = 16
    /// Width of the priority number / checkmark / drag handle column
    static let priorityColumnWidth: CGFloat = 16
    static let rowVerticalPadding: CGFloat = 4
    static let rowSpacing: CGFloat = 2

    var body: some View {
        VStack(spacing: DeviceListView.rowSpacing) {
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

    var isActive: Bool {
        isSelected && !isDisconnected
    }

    /// Text color for the row; the actions menu icon matches it
    var rowTextColor: Color {
        isActive ? .appAccent : (isGrayed || isNeverUse ? .secondary : .primary)
    }

    /// The output category the device is currently assigned to
    var currentCategory: OutputCategory {
        audioManager.priorityManager.getCategory(for: device)
    }

    var isNeverUse: Bool {
        audioManager.isNeverUse(device)
    }

    var statusIcon: String? {
        if isDisconnected {
            return "wifi.slash"
        } else if isIgnored && audioManager.isEditMode {
            return "eye.slash"
        }
        // Never-use devices are shown with strikethrough text instead of an icon
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
        // Distance from one row's top to the next row's top
        let rowPitch = rowHeight + 2 * DeviceListView.rowVerticalPadding + DeviceListView.rowSpacing
        let rowsOffset = Int(round(offset / rowPitch))
        var newTarget = index + rowsOffset
        newTarget = max(0, min(deviceCount, newTarget))
        
        if newTarget == index || newTarget == index + 1 {
            return nil
        }
        return newTarget
    }

    private let actionsMenuWidth: CGFloat = 24
    private let nameFadeWidth: CGFloat = 20

    /// Opaque everywhere except, while the actions menu is showing, a fade into the area it covers
    private var nameFadeMask: some View {
        let showsMenu = isHovering && !isDragging
        return HStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: showsMenu ? nameFadeWidth : 0)
            Color.clear
                .frame(width: showsMenu ? actionsMenuWidth : 0)
        }
    }

    private var actionsMenu: some View {
        ZStack {
            if isHovering && !isDragging {
                Group {
                Menu {
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
                                Label("Ignore as speaker and headphones", systemImage: "eye.slash.fill")
                            }
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

                if showCategoryPicker {
                    Divider()
                    Button {
                        audioManager.setCategory(.speaker, for: device)
                    } label: {
                        Label("Move to Speakers", systemImage: "speaker.wave.2.fill")
                    }
                    .disabled(currentCategory == .speaker)
                    Button {
                        audioManager.setCategory(.headphone, for: device)
                    } label: {
                        Label("Move to Headphones", systemImage: "headphones")
                    }
                    .disabled(currentCategory == .headphone)
                }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundColor(rowTextColor)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                // .borderlessButton draws the label through AppKit and ignores its color
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(width: actionsMenuWidth)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
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
                        .frame(width: DeviceListView.priorityColumnWidth, height: rowHeight)
                        .opacity(isHovering || isDragging ? 1 : 0)
                        .scaleEffect(isHovering || isDragging ? 1 : 0.8)
                    
                    // Priority number or active checkmark when not hovering
                    Group {
                        if isActive {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.appAccent)
                                .accessibilityLabel("Active")
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }
                    .opacity(isHovering || isDragging ? 0 : 1)
                    .scaleEffect(isHovering || isDragging ? 0.8 : 1)
                }
                .frame(width: DeviceListView.priorityColumnWidth)
                .animation(.easeInOut(duration: 0.12), value: isHovering)
                .animation(.easeInOut(duration: 0.12), value: isDragging)
            }

            // Device name - use HStack with tap gesture instead of Button to not interfere with drag
            HStack(spacing: 8) {
                Image(systemName: device.hardwareIcon(category: category))
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? .appAccent : .secondary)
                    .frame(width: 18)

                Text(device.name)
                    .font(.system(size: 13, weight: .regular))
                    .strikethrough(isNeverUse, color: .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(rowTextColor)

                if let icon = statusIcon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(isActive ? .appAccent : .secondary.opacity(0.7))
                        .fixedSize()
                }

                if let lastSeen = lastSeenText {
                    Text(lastSeen)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                        .fixedSize()
                }

                if isMuted {
                    Text("Muted")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red))
                        .fixedSize()
                }

                Spacer(minLength: 0)
            }
            // The actions menu overlays the end of the row instead of reserving space,
            // so names use the full width; fade the name out underneath it while hovering
            .mask(nameFadeMask)
        }
        .overlay(alignment: .trailing) { actionsMenu }
        .padding(.leading, DeviceListView.horizontalInset)
        .padding(.trailing, DeviceListView.horizontalInset - 2)  // the menu icon has its own padding
        .padding(.vertical, DeviceListView.rowVerticalPadding)
        .opacity(isDragging ? 0.5 : (isGrayed ? 0.6 : 1.0))
        .background(
            Rectangle()
                .fill(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        // Drop indicator above this row
        .overlay(alignment: .top) {
            if isDropTarget {
                DropIndicatorLine()
                    .offset(y: -DeviceListView.rowSpacing / 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        // Drop indicator below this row (for last position)
        .overlay(alignment: .bottom) {
            if isDropTargetBelow {
                DropIndicatorLine()
                    .offset(y: DeviceListView.rowSpacing / 2)
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
            Rectangle()
                .stroke(isDragging ? Color.appAccent : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
        .animation(.easeInOut(duration: 0.1), value: isDropTarget)
        .animation(.easeInOut(duration: 0.1), value: isDropTargetBelow)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDisconnected && audioManager.isCustomMode && !audioManager.isEditMode {
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
                .fill(Color.appAccent)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.appAccent)
                .frame(height: 2)
        }
        .padding(.horizontal, 2)
    }
}

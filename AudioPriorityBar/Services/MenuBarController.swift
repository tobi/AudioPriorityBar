import AppKit
import SwiftUI

/// Controls the menu bar item and handles click events
@MainActor
class MenuBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let audioManager: AudioManager
    private var updateTimer: Timer?

    // Long press detection
    private var longPressTimer: Timer?
    private var longPressTriggered = false
    private var eventMonitor: Any?

    private enum MouseButton {
        case left, right
    }

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
        setupMenuBar()
        setupUpdateTimer()
    }

    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateButton()

            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self

            // Monitor for mouse down events
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handleMouseDownEvent(event)
                return event
            }
        }

        // Create popover for menu content
        let popover = NSPopover()
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(audioManager)
        )
        popover.behavior = .transient
        self.popover = popover
    }
    
    private func setupUpdateTimer() {
        // Update the menu bar icon periodically to reflect state changes
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateButton()
            }
        }
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            return
        }

        let button: MouseButton = event.type == .leftMouseUp ? .left : .right
        handleMouseUp(button: button, sender: sender)
    }

    private func handleMouseDownEvent(_ event: NSEvent) {
        // Check if the event is on our status bar button
        guard let button = statusItem?.button,
              let window = event.window,
              window == button.window else {
            return
        }

        let locationInWindow = event.locationInWindow
        let locationInButton = button.convert(locationInWindow, from: nil)

        guard button.bounds.contains(locationInButton) else {
            return
        }

        let mouseButton: MouseButton = event.type == .leftMouseDown ? .left : .right
        handleMouseDown(button: mouseButton)
    }

    private func handleMouseDown(button: MouseButton) {
        longPressTriggered = false

        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.handleLongPress(button: button)
        }
        RunLoop.current.add(timer, forMode: .common)
        longPressTimer = timer
    }

    private func handleMouseUp(button: MouseButton, sender: NSStatusBarButton) {
        longPressTimer?.invalidate()
        longPressTimer = nil

        if !longPressTriggered {
            let config = audioManager.priorityManager.clickActionsConfig
            let action = button == .left ? config.leftClick : config.rightClick
            executeAction(action, sender: sender)
        }

        longPressTriggered = false
    }

    private func handleLongPress(button: MouseButton) {
        longPressTriggered = true
        let config = audioManager.priorityManager.clickActionsConfig
        let action = button == .left ? config.longLeftClick : config.longRightClick
        executeAction(action, sender: statusItem?.button)
    }

    private func executeAction(_ action: ClickAction, sender: NSStatusBarButton? = nil) {
        switch action {
        case .toggle:
            let toggled = audioManager.toggleMode()
            if toggled {
                updateButton()
            } else if let sender = sender {
                showPopover(sender)
            }
        case .menu:
            if let sender = sender {
                showPopover(sender)
            }
        case .noAction:
            break
        }
    }
    
    private func showPopover(_ sender: NSStatusBarButton) {
        guard let popover = popover else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    func updateButton() {
        guard let button = statusItem?.button else { return }
        
        // Build icon using SF Symbols based on state
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        var symbols: [NSImage] = []
        
        // Input mute indicator
        if audioManager.isActiveInputMuted {
            let micIcon = audioManager.micFlashState ? "mic.fill" : "mic.slash.fill"
            if let image = NSImage(systemSymbolName: micIcon, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                symbols.append(image)
            }
        }
        
        // Custom mode indicator
        if audioManager.isCustomMode {
            if let image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                symbols.append(image)
            }
        }
        
        // Output indicator - headphone in headphone mode, speaker in speaker mode
        if audioManager.currentMode == .headphone {
            // Headphone icon
            if let image = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                symbols.append(image)
            }
        } else {
            // Speaker icon with volume indication
            let speakerIcon: String
            if audioManager.isActiveOutputMuted {
                speakerIcon = "speaker.slash.fill"
            } else {
                // Use variable speaker icon based on volume
                let volume = audioManager.volume
                if volume > 0.66 {
                    speakerIcon = "speaker.wave.3.fill"
                } else if volume > 0.33 {
                    speakerIcon = "speaker.wave.2.fill"
                } else if volume > 0 {
                    speakerIcon = "speaker.wave.1.fill"
                } else {
                    speakerIcon = "speaker.fill"
                }
            }
            
            if let image = NSImage(systemSymbolName: speakerIcon, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                // Pad to the widest possible speaker icon so the slot width never changes
                let allSpeakerIcons = ["speaker.slash.fill", "speaker.wave.3.fill", "speaker.wave.2.fill", "speaker.wave.1.fill", "speaker.fill"]
                let maxWidth = allSpeakerIcons.compactMap {
                    NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(config)?.size.width
                }.max() ?? image.size.width

                if maxWidth > image.size.width {
                    let padded = NSImage(size: NSSize(width: maxWidth, height: image.size.height))
                    padded.lockFocus()
                    image.draw(at: NSPoint(x: (maxWidth - image.size.width) / 2, y: 0), from: .zero, operation: .sourceOver, fraction: 1.0)
                    padded.unlockFocus()
                    padded.isTemplate = true
                    symbols.append(padded)
                } else {
                    symbols.append(image)
                }
            }
        }
        
        // Combine symbols into one image
        if !symbols.isEmpty {
            let spacing: CGFloat = 2
            let totalWidth = symbols.map { $0.size.width }.reduce(0, +) + CGFloat(symbols.count - 1) * spacing
            let maxHeight = symbols.map { $0.size.height }.max() ?? 16
            
            let combinedImage = NSImage(size: NSSize(width: totalWidth, height: maxHeight))
            combinedImage.lockFocus()
            
            var xOffset: CGFloat = 0
            for symbol in symbols {
                let yOffset = (maxHeight - symbol.size.height) / 2
                symbol.draw(at: NSPoint(x: xOffset, y: yOffset), from: .zero, operation: .sourceOver, fraction: 1.0)
                xOffset += symbol.size.width + spacing
            }
            
            combinedImage.unlockFocus()
            combinedImage.isTemplate = true
            button.image = combinedImage
        }
    }
    
    deinit {
        updateTimer?.invalidate()
        longPressTimer?.invalidate()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

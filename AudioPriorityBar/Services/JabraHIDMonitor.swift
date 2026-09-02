import Foundation
import IOKit
import IOKit.hid

/// Watches Jabra Link USB dongles over HID to tell whether the *wireless* headset
/// is actually powered on and linked.
///
/// Why this exists: a Jabra Link dongle stays in the CoreAudio device list whether
/// the headset is on, off, or out of range. So when the headset powers off,
/// CoreAudio fires no device-list change and the app is left with an active but
/// silent input. The dongle *does* report the link state over HID, so we read that
/// bit directly and treat "headset off" like a disconnect.
///
/// Signal (confirmed on a Link 380, FW-dependent): a vendor-defined element at
/// usage page 0xFF30 / usage 0xFFFC is a stable level — value 1 when the headset
/// is OFF, value 0 when it is ON. We gate on Jabra's vendor ID (0x0B0E, shared by
/// all Jabra/GN Audio devices) and default to that element.
///
/// Fail-safe: if HID can't be opened or the element is absent (unknown dongle,
/// denied Input Monitoring, older firmware), we report the headset as live so the
/// app behaves exactly as it did before this monitor existed.
@MainActor
final class JabraHIDMonitor {
    /// GN Audio (Jabra) USB vendor ID — shared across all Jabra devices.
    private static let jabraVendorID = 0x0b0e
    /// Vendor-defined link-state element. 1 == headset off, 0 == headset on.
    private static let linkStateUsagePage: UInt32 = 0xff30
    private static let linkStateUsage: UInt32 = 0xfffc

    /// Called on the main actor whenever the headset transitions live <-> not-live.
    /// `true` == headset on and linked; `false` == headset off / out of range.
    var onHeadsetLiveChanged: ((Bool) -> Void)?

    /// Current best-known state. Defaults to `true` (fail-safe: assume live).
    private(set) var isHeadsetLive = true

    private var manager: IOHIDManager?

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let match: [String: Any] = [kIOHIDVendorIDKey: Self.jabraVendorID]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, Self.valueCallback, context)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchCallback, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else {
            // Can't observe — stay fail-safe (isHeadsetLive == true).
            self.manager = nil
            return
        }

        readInitialState()
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    // MARK: - State

    /// Read the link-state element synchronously at startup so we start correct
    /// even if the headset is already off (no callback would fire otherwise).
    private func readInitialState() {
        guard let manager,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }

        for device in devices {
            guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else { continue }
            for element in elements where Self.isLinkStateElement(element) {
                var valueRef: Unmanaged<IOHIDValue>?
                // IOHIDDeviceGetValue takes a non-optional out-pointer; rebind our
                // optional to match, then read what it wrote (get => don't own it).
                let status = withUnsafeMutablePointer(to: &valueRef) { ptr in
                    ptr.withMemoryRebound(to: Unmanaged<IOHIDValue>.self, capacity: 1) {
                        IOHIDDeviceGetValue(device, element, $0)
                    }
                }
                if status == kIOReturnSuccess, let value = valueRef?.takeUnretainedValue() {
                    apply(rawLinkValue: IOHIDValueGetIntegerValue(value))
                    return
                }
            }
        }
    }

    /// rawLinkValue: 1 == off, 0 == on. Only fires the callback on an actual flip.
    private func apply(rawLinkValue: Int) {
        let live = (rawLinkValue == 0)
        guard live != isHeadsetLive else { return }
        isHeadsetLive = live
        onHeadsetLiveChanged?(live)
    }

    private static func isLinkStateElement(_ element: IOHIDElement) -> Bool {
        IOHIDElementGetUsagePage(element) == linkStateUsagePage
            && IOHIDElementGetUsage(element) == linkStateUsage
    }

    // MARK: - C callbacks

    private static let matchCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        let monitor = Unmanaged<JabraHIDMonitor>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { monitor.readInitialState() }
    }

    private static let valueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let element = IOHIDValueGetElement(value)
        guard isLinkStateElement(element) else { return }
        let raw = IOHIDValueGetIntegerValue(value)
        let monitor = Unmanaged<JabraHIDMonitor>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { monitor.apply(rawLinkValue: raw) }
    }
}

import Foundation
import IOKit
import IOKit.hid

/// Reports whether a wireless headset is actually linked to its USB dongle.
///
/// A dongle publishes its CoreAudio devices whenever it is plugged in, whether or not
/// the headset it pairs with is powered on. Nothing in CoreAudio separates the two
/// states — measured on a Jabra Link 390 with the headset off and then on, the driver
/// never publishes `kAudioDevicePropertyJackIsConnected`, and `DeviceIsAlive`, channel
/// counts, available sample rates, stream formats and `CanBeDefaultDevice` are all
/// identical. Priority selection therefore picks the dongle and sends audio into a
/// dead link: it shows as Active while nothing comes out.
///
/// Some dongles do report the truth over HID. This monitor reads that bit for the
/// dongles it knows about.
///
/// **A device this monitor does not recognise is always reported as usable**, so
/// behaviour is unchanged for every other piece of hardware.
final class WirelessLinkMonitor {

    /// A dongle whose HID interface exposes a headset-link bit.
    struct DongleProfile {
        let vendorID: Int
        /// Matched against both the HID product string and the CoreAudio device name.
        let nameFragment: String
        let reportID: UInt8
        let byteIndex: Int
        let bitMask: UInt8
    }

    /// Jabra Link 390. HID Telephony usage 0x2A ("Line"), report 0x04 byte 1 bit 3.
    /// It reads 1 only while the headset is linked to the dongle.
    ///
    /// Verified against the hardware: powering the headset on over Bluetooth left the
    /// bit at 0 while the headset's Bluetooth devices appeared, and when the headset
    /// later moved its link to the dongle the bit went to 1 and the Bluetooth devices
    /// were removed 1.7 seconds later.
    static let knownDongles: [DongleProfile] = [
        DongleProfile(vendorID: 0x0B0E,
                      nameFragment: "Jabra Link 390",
                      reportID: 0x04,
                      byteIndex: 1,
                      bitMask: 0x08)
    ]

    enum LinkState {
        case up        // headset is linked to the dongle
        case down      // dongle present, headset not linked
        case unknown   // no matching dongle, or the bit could not be read
    }

    /// How long the link must stay down before the device is treated as unusable.
    /// Rides out a momentary drop so a brief glitch cannot pull audio away mid-call.
    private static let downDebounce: TimeInterval = 3.0

    /// Called when a link goes up or down, on the main queue.
    var onLinkChange: (() -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var attached: [IOHIDDevice: DongleProfile] = [:]
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private var states: [String: LinkState] = [:]     // keyed by nameFragment
    private var downSince: [String: Date] = [:]
    private var pollTimer: Timer?

    // MARK: - Lifecycle

    func start() {
        let criteria = Self.knownDongles.map { [kIOHIDVendorIDKey: $0.vendorID] }
        IOHIDManagerSetDeviceMatchingMultiple(manager, criteria as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<WirelessLinkMonitor>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<WirelessLinkMonitor>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices { attach(device) }
        }

        // Backstop for a missed report, which would otherwise leave a device gated
        // until the next time the headset is toggled.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    deinit {
        pollTimer?.invalidate()
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        for buffer in buffers { buffer.deallocate() }
    }

    // MARK: - Queries

    /// Link state for a CoreAudio device, matched by name.
    func linkState(forDeviceNamed name: String) -> LinkState {
        guard let profile = Self.knownDongles.first(where: { name.contains($0.nameFragment) }) else {
            return .unknown
        }
        return states[profile.nameFragment] ?? .unknown
    }

    /// Whether a device may be auto-selected. Only a settled `down` blocks it; anything
    /// unrecognised or unreadable stays selectable.
    func isUsable(deviceNamed name: String) -> Bool {
        guard case .down = linkState(forDeviceNamed: name) else { return true }
        guard let profile = Self.knownDongles.first(where: { name.contains($0.nameFragment) }),
              let since = downSince[profile.nameFragment] else { return true }
        return Date().timeIntervalSince(since) < Self.downDebounce
    }

    // MARK: - HID

    private func profile(for device: IOHIDDevice) -> DongleProfile? {
        guard let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String else {
            return nil
        }
        return Self.knownDongles.first { product.contains($0.nameFragment) }
    }

    /// The matching callback also fires for devices already connected at startup, so
    /// without this guard the explicit enumeration would attach each device twice.
    private func attach(_ device: IOHIDDevice) {
        guard attached[device] == nil, let profile = profile(for: device) else { return }
        attached[device] = profile

        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        let size = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        buffers.append(buffer)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { context, _, sender, _, reportID, report, length in
            guard let context, let sender else { return }
            let monitor = Unmanaged<WirelessLinkMonitor>.fromOpaque(context).takeUnretainedValue()
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            guard let profile = monitor.attached[device],
                  UInt8(reportID) == profile.reportID,
                  Int(length) > profile.byteIndex else { return }
            monitor.update(profile: profile, isLinked: (report[profile.byteIndex] & profile.bitMask) != 0)
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        if let isLinked = read(device, profile) {
            // A link already down at startup gets no grace period: the debounce is for
            // riding out a drop during use.
            states[profile.nameFragment] = isLinked ? .up : .down
            downSince[profile.nameFragment] = isLinked ? nil : .distantPast
        }
        onLinkChange?()
    }

    private func detach(_ device: IOHIDDevice) {
        guard let profile = attached.removeValue(forKey: device) else { return }
        states[profile.nameFragment] = .unknown
        downSince[profile.nameFragment] = nil
        onLinkChange?()
    }

    private func read(_ device: IOHIDDevice, _ profile: DongleProfile) -> Bool? {
        var buffer = [UInt8](repeating: 0, count: 64)
        var length = CFIndex(buffer.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput,
                                          CFIndex(profile.reportID), &buffer, &length)
        guard result == kIOReturnSuccess, Int(length) > profile.byteIndex else { return nil }
        return (buffer[profile.byteIndex] & profile.bitMask) != 0
    }

    private func poll() {
        for (device, profile) in attached {
            if let isLinked = read(device, profile) {
                update(profile: profile, isLinked: isLinked)
            }
        }
    }

    private func update(profile: DongleProfile, isLinked: Bool) {
        let newState: LinkState = isLinked ? .up : .down
        guard states[profile.nameFragment] != newState else { return }
        states[profile.nameFragment] = newState

        if isLinked {
            downSince[profile.nameFragment] = nil
        } else {
            downSince[profile.nameFragment] = Date()
            // No further HID report will arrive, so re-evaluate once the debounce ends.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.downDebounce + 0.1) { [weak self] in
                self?.onLinkChange?()
            }
        }
        onLinkChange?()
    }
}

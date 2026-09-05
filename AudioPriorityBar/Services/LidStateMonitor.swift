import Foundation
import IOKit

@MainActor
final class LidStateMonitor {
    var onChange: ((LidState) -> Void)?
    private var timer: Timer?
    private var lastState = LidState.unknown

    static func readState() -> LidState {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != 0 else { return .unknown }
        defer { IOObjectRelease(entry) }
        guard let closed = IORegistryEntryCreateCFProperty(entry, "AppleClamshellState" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool else { return .unknown }
        return closed ? .closed : .open
    }

    func setEnabled(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        lastState = Self.readState()
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let state = Self.readState()
                guard state != self.lastState else { return }
                self.lastState = state
                self.onChange?(state)
            }
        }
        timer?.tolerance = 0.2
    }

    deinit { timer?.invalidate() }
}

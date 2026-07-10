import CoreAudio
import XCTest

final class PriorityManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var manager: PriorityManager!

    override func setUp() {
        super.setUp()
        suiteName = "AudioPriorityBarTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        manager = PriorityManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        manager = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func device(
        _ uid: String,
        type: AudioDeviceType = .input,
        connected: Bool = true
    ) -> AudioDevice {
        AudioDevice(id: connected ? AudioObjectID(abs(uid.hashValue % 10_000) + 1) : 0,
                    uid: uid,
                    name: uid,
                    type: type,
                    isConnected: connected)
    }

    private func remember(_ uid: String, type: AudioDeviceType = .input) {
        manager.rememberDevice(uid, name: uid, isInput: type == .input)
    }

    func testDiscoveryDoesNotConfigureNewInstall() {
        remember("A")
        remember("B")

        manager.registerDiscoveredUIDs(["B", "A"], type: .input)

        XCTAssertFalse(manager.isPriorityConfigured(type: .input))
        XCTAssertFalse(manager.hasPriorities(type: .input))
        XCTAssertEqual(manager.priorityUIDs(type: .input), [])
    }

    func testExistingSavedPrioritiesInitializeConfiguredRole() {
        defaults.set(["B", "A"], forKey: "inputPriorities")

        manager = PriorityManager(defaults: defaults)

        XCTAssertTrue(manager.isPriorityConfigured(type: .input))
        XCTAssertEqual(manager.priorityUIDs(type: .input), ["B", "A"])
    }

    func testLegacyKnownDevicesAreCanonicalizedBeforeNewDiscovery() {
        remember("A")
        remember("B")
        defaults.set(["A"], forKey: "inputPriorities")

        manager = PriorityManager(defaults: defaults)
        manager.registerDiscoveredUIDs(["C"], type: .input)

        XCTAssertEqual(manager.priorityUIDs(type: .input), ["A", "B", "C"])
    }

    func testFirstExplicitMergeSeedsVisibleOrderThenRemainingKnownDevices() {
        remember("A")
        remember("B")
        remember("C")

        manager.mergeVisibleOrder([device("C"), device("B")], type: .input)

        XCTAssertTrue(manager.isPriorityConfigured(type: .input))
        XCTAssertEqual(manager.priorityUIDs(type: .input), ["C", "B", "A"])
    }

    func testVisibleMergePreservesMultipleAbsentSlots() {
        let all = ["A", "H1", "B", "H2", "C"].map { device($0) }
        manager.mergeVisibleOrder(all, type: .input)

        manager.mergeVisibleOrder([device("C"), device("B"), device("A")], type: .input)

        XCTAssertEqual(manager.priorityUIDs(type: .input), ["C", "H1", "B", "H2", "A"])
    }

    func testEmptyVisibleMergeDoesNotClearCanonicalOrder() {
        manager.mergeVisibleOrder([device("A"), device("B")], type: .input)

        manager.mergeVisibleOrder([], type: .input)

        XCTAssertEqual(manager.priorityUIDs(type: .input), ["A", "B"])
    }

    func testAutoUseOffDeviceStillParticipatesWhenVisible() {
        let a = device("A")
        let b = device("B")
        let c = device("C")
        manager.mergeVisibleOrder([a, b, c], type: .input)
        manager.setAutoUseDisabled(b, disabled: true)

        manager.mergeVisibleOrder([c, b, a], type: .input)

        XCTAssertEqual(manager.priorityUIDs(type: .input), ["C", "B", "A"])
        XCTAssertTrue(manager.isAutoUseDisabled(b))
    }

    func testPromoteMovesDeviceToAbsoluteFirstAcrossAbsentDevices() {
        let a = device("A")
        let b = device("B")
        let c = device("C")
        manager.mergeVisibleOrder([a, b, c], type: .input)

        manager.promote(c, visibleDevices: [b, c])

        XCTAssertEqual(manager.priorityUIDs(type: .input), ["C", "A", "B"])
    }

    func testFirstPromoteConfiguresRoleWithoutEnumerationBasedDiscovery() {
        remember("A")
        remember("B")
        let b = device("B")

        manager.promote(b, visibleDevices: [device("A"), b])

        XCTAssertTrue(manager.isPriorityConfigured(type: .input))
        XCTAssertEqual(manager.priorityUIDs(type: .input), ["B", "A"])
    }

    func testConfiguredRoleAppendsNewUIDsDeterministically() {
        manager.mergeVisibleOrder([device("A")], type: .input)

        manager.registerDiscoveredUIDs(["C", "B", "C"], type: .input)

        XCTAssertEqual(manager.priorityUIDs(type: .input), ["A", "B", "C"])
    }

    func testInputAndOutputCanonicalOrdersAreIndependentForSharedUID() {
        let input = device("shared", type: .input)
        let output = device("shared", type: .output)
        manager.mergeVisibleOrder([input, device("input-2")], type: .input)
        manager.mergeVisibleOrder([device("output-2", type: .output), output], type: .output)

        manager.promote(input, visibleDevices: [input, device("input-2")])

        XCTAssertEqual(manager.priorityUIDs(type: .input), ["shared", "input-2"])
        XCTAssertEqual(manager.priorityUIDs(type: .output), ["output-2", "shared"])
    }

    func testCanonicalReorderRequiresCompleteCurrentUniverse() {
        ["A", "B", "C"].forEach { remember($0) }
        manager.mergeVisibleOrder([device("A"), device("B"), device("C")], type: .input)

        XCTAssertFalse(manager.reorderCanonical([device("C"), device("A")], type: .input))
        XCTAssertEqual(manager.priorityUIDs(type: .input), ["A", "B", "C"])
        XCTAssertTrue(manager.reorderCanonical([device("C"), device("A"), device("B")], type: .input))
        XCTAssertEqual(manager.priorityUIDs(type: .input), ["C", "A", "B"])
    }

    func testCanonicalOnlyUIDCanBePreservedByCompleteEditReorder() {
        defaults.set(["orphan", "known"], forKey: "inputPriorities")
        defaults.set(true, forKey: "inputPrioritiesConfigured")
        remember("known")

        let reordered = [device("known"), device("orphan", connected: false)]

        XCTAssertTrue(manager.reorderCanonical(reordered, type: .input))
        XCTAssertEqual(manager.priorityUIDs(type: .input), ["known", "orphan"])
    }

    func testForgetRemovesOnlyOneRolesCompleteState() {
        let input = device("shared", type: .input)
        let output = device("shared", type: .output)
        remember("shared", type: .input)
        remember("shared", type: .output)
        manager.mergeVisibleOrder([input], type: .input)
        manager.mergeVisibleOrder([output], type: .output)
        manager.hideDevice(input)
        manager.hideDevice(output)
        manager.setAutoUseDisabled(input, disabled: true)
        manager.setAutoUseDisabled(output, disabled: true)

        manager.forgetDevice("shared", type: .input)

        XCTAssertEqual(manager.priorityUIDs(type: .input), [])
        XCTAssertFalse(manager.isHidden(input))
        XCTAssertFalse(manager.isAutoUseDisabled(input))
        XCTAssertEqual(manager.priorityUIDs(type: .output), ["shared"])
        XCTAssertTrue(manager.isHidden(output))
        XCTAssertTrue(manager.isAutoUseDisabled(output))
        let known = manager.getKnownDevices()
        XCTAssertEqual(known.count, 1)
        XCTAssertEqual(known.first?.uid, "shared")
        XCTAssertEqual(known.first?.isInput, false)
    }

    func testPriorityReadSalvagesStringsAndDeduplicatesCorruptArray() {
        defaults.set(["A", 7, "", "A", "B"], forKey: "inputPriorities")

        XCTAssertEqual(manager.priorityUIDs(type: .input), ["A", "B"])
    }

    func testUnrankedDevicesUseKnownOrderThenUIDFallback() {
        remember("B")
        remember("A")
        let devices = [device("C"), device("A"), device("B")]

        XCTAssertEqual(manager.sortByPriority(devices, type: .input).map(\.uid), ["B", "A", "C"])
    }

    func testLegacyOutputMigrationStillSupportsSubsetMerge() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(["speaker-a", "shared"], forKey: "speakerPriorities")
        defaults.set(["headphone-a", "shared"], forKey: "headphonePriorities")
        defaults.set("speaker", forKey: "currentMode")
        manager = PriorityManager(defaults: defaults)

        manager.mergeVisibleOrder(
            [device("headphone-a", type: .output), device("speaker-a", type: .output)],
            type: .output
        )

        XCTAssertEqual(manager.priorityUIDs(type: .output), ["headphone-a", "shared", "speaker-a"])
    }
}

final class DefaultDeviceChangeTrackerTests: XCTestCase {
    func testDuplicateCallbacksPreserveManualSelection() {
        var tracker = DefaultDeviceChangeTracker()
        tracker.preserveManualSelection(11, type: .input)

        XCTAssertTrue(tracker.shouldPreserveManualSelection(currentDeviceId: 11, type: .input))
        XCTAssertTrue(tracker.shouldPreserveManualSelection(currentDeviceId: 11, type: .input))
    }

    func testDifferentDefaultClearsManualSelection() {
        var tracker = DefaultDeviceChangeTracker()
        tracker.preserveManualSelection(11, type: .input)

        XCTAssertFalse(tracker.shouldPreserveManualSelection(currentDeviceId: 12, type: .input))
        XCTAssertFalse(tracker.shouldPreserveManualSelection(currentDeviceId: 11, type: .input))
    }

    func testRapidManualSelectionsPreserveLatestDeviceAcrossCoalescedCallbacks() {
        var tracker = DefaultDeviceChangeTracker()
        tracker.preserveManualSelection(11, type: .input)
        tracker.preserveManualSelection(12, type: .input)

        XCTAssertTrue(tracker.shouldPreserveManualSelection(currentDeviceId: 12, type: .input))
        XCTAssertTrue(tracker.shouldPreserveManualSelection(currentDeviceId: 12, type: .input))
    }

    func testClearOneRoleDoesNotAffectOppositeRole() {
        var tracker = DefaultDeviceChangeTracker()
        tracker.preserveManualSelection(11, type: .input)
        tracker.preserveManualSelection(22, type: .output)

        tracker.clearManualSelection(type: .input)

        XCTAssertFalse(tracker.shouldPreserveManualSelection(currentDeviceId: 11, type: .input))
        XCTAssertTrue(tracker.shouldPreserveManualSelection(currentDeviceId: 22, type: .output))
    }

    func testDeviceListChangeClearsAllManualSelections() {
        var tracker = DefaultDeviceChangeTracker()
        tracker.preserveManualSelection(11, type: .input)
        tracker.preserveManualSelection(22, type: .output)

        tracker.clearAllManualSelections()

        XCTAssertFalse(tracker.shouldPreserveManualSelection(currentDeviceId: 11, type: .input))
        XCTAssertFalse(tracker.shouldPreserveManualSelection(currentDeviceId: 22, type: .output))
    }
}

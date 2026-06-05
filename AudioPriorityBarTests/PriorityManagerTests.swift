import XCTest
import CoreAudio
@testable import AudioPriorityBar

final class PriorityManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var manager: PriorityManager!

    override func setUp() {
        super.setUp()
        suiteName = "AudioPriorityBarTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        manager = PriorityManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        manager = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func device(_ uid: String, _ name: String? = nil, type: AudioDeviceType = .output, connected: Bool = true) -> AudioDevice {
        // PriorityManager keys everything off uid; the AudioObjectID is irrelevant here.
        AudioDevice(id: 0, uid: uid, name: name ?? uid, type: type, isConnected: connected)
    }

    private func savedPriorities(category: OutputCategory) -> [String] {
        let key = category == .speaker ? "speakerPriorities" : "headphonePriorities"
        return defaults.array(forKey: key) as? [String] ?? []
    }

    private func savedInputPriorities() -> [String] {
        defaults.array(forKey: "inputPriorities") as? [String] ?? []
    }

    // MARK: - savePriorities merge behavior
    // Bug fixed: a reorder of only the visible subset used to overwrite the
    // entire saved list, wiping the saved positions of disconnected, hidden,
    // and never-use devices.

    func test_savePriorities_preservesDisconnectedDevicesInBetween() {
        // Seed the saved list as if A, B, C, D had all been ordered together.
        manager.savePriorities([device("A"), device("B"), device("C"), device("D")], category: .speaker)

        // Now C is disconnected — only A, B, D are visible. User reorders to B, A, D.
        manager.savePriorities([device("B"), device("A"), device("D")], category: .speaker)

        // C must still be in the saved list, in its original slot relative to A/B/D.
        XCTAssertEqual(savedPriorities(category: .speaker), ["B", "A", "C", "D"])
    }

    func test_savePriorities_preservesHiddenDevicesAtTheirPositions() {
        manager.savePriorities([device("A"), device("Hidden"), device("B"), device("C")], category: .headphone)

        // User hides "Hidden" then reorders the remaining visible devices.
        manager.savePriorities([device("C"), device("A"), device("B")], category: .headphone)

        XCTAssertEqual(savedPriorities(category: .headphone), ["C", "Hidden", "A", "B"])
    }

    func test_savePriorities_appendsBrandNewDeviceAtEnd() {
        manager.savePriorities([device("A"), device("B")], category: .speaker)

        // A new device E shows up alongside A and B; user keeps A, B in front.
        manager.savePriorities([device("A"), device("B"), device("E")], category: .speaker)

        XCTAssertEqual(savedPriorities(category: .speaker), ["A", "B", "E"])
    }

    func test_savePriorities_emptyExistingListBecomesNewOrder() {
        manager.savePriorities([device("X"), device("Y"), device("Z")], category: .speaker)
        XCTAssertEqual(savedPriorities(category: .speaker), ["X", "Y", "Z"])
    }

    func test_savePriorities_visibleReorderPreservesMultipleHiddenSlots() {
        manager.savePriorities([device("A"), device("H1"), device("B"), device("H2"), device("C")], category: .speaker)

        manager.savePriorities([device("C"), device("B"), device("A")], category: .speaker)

        // Visible devices (A, B, C) take the visible slots in their new order;
        // hidden slots stay where they were.
        XCTAssertEqual(savedPriorities(category: .speaker), ["C", "H1", "B", "H2", "A"])
    }

    func test_savePriorities_doesNotDuplicateUIDsWhenNewDeviceAlreadyInOldList() {
        manager.savePriorities([device("A"), device("B"), device("C")], category: .speaker)

        // New visible list has same devices, just reordered.
        manager.savePriorities([device("B"), device("C"), device("A")], category: .speaker)

        let saved = savedPriorities(category: .speaker)
        XCTAssertEqual(saved.count, Set(saved).count, "Saved list should contain no duplicate UIDs")
        XCTAssertEqual(saved, ["B", "C", "A"])
    }

    func test_savePriorities_inputAndOutputListsAreIndependent() {
        manager.savePriorities([device("Mic1", type: .input), device("Mic2", type: .input)], type: .input)
        manager.savePriorities([device("Spk1"), device("Spk2")], category: .speaker)

        XCTAssertEqual(savedInputPriorities(), ["Mic1", "Mic2"])
        XCTAssertEqual(savedPriorities(category: .speaker), ["Spk1", "Spk2"])
    }

    // MARK: - consolidateDuplicates
    // Bug fixed: HDMI/DisplayPort display audio devices report a fresh UID
    // each reconnect, accumulating dozens of "known device" entries with the
    // same name. consolidateDuplicates merges them by (name, isInput) and
    // migrates the user's settings onto the surviving UID.

    func test_consolidateDuplicates_collapsesDuplicateNamedDisconnectedEntries() {
        manager.rememberDevice("uid-1", name: "C34J79x", isInput: false)
        manager.rememberDevice("uid-2", name: "C34J79x", isInput: false)
        manager.rememberDevice("uid-3", name: "C34J79x", isInput: false)
        XCTAssertEqual(manager.getKnownDevices().count, 3)

        // None currently connected — survivor is most recently seen (uid-3).
        manager.consolidateDuplicates(connectedUIDs: [])

        let known = manager.getKnownDevices()
        XCTAssertEqual(known.count, 1)
        XCTAssertEqual(known.first?.uid, "uid-3")
        XCTAssertEqual(known.first?.name, "C34J79x")
    }

    func test_consolidateDuplicates_prefersConnectedSurvivor() {
        manager.rememberDevice("old-1", name: "C34J79x", isInput: false)
        manager.rememberDevice("old-2", name: "C34J79x", isInput: false)
        // Most recently seen is "fresh" but the connected one is "old-1".
        manager.rememberDevice("fresh", name: "C34J79x", isInput: false)

        manager.consolidateDuplicates(connectedUIDs: ["old-1"])

        let known = manager.getKnownDevices()
        XCTAssertEqual(known.map { $0.uid }, ["old-1"])
    }

    func test_consolidateDuplicates_doesNotMergeDifferentNames() {
        manager.rememberDevice("a-uid", name: "A", isInput: false)
        manager.rememberDevice("b-uid", name: "B", isInput: false)

        manager.consolidateDuplicates(connectedUIDs: [])

        XCTAssertEqual(manager.getKnownDevices().count, 2)
    }

    func test_consolidateDuplicates_doesNotMergeAcrossInputOutput() {
        manager.rememberDevice("input-uid", name: "Same Name", isInput: true)
        manager.rememberDevice("output-uid", name: "Same Name", isInput: false)

        manager.consolidateDuplicates(connectedUIDs: [])

        XCTAssertEqual(manager.getKnownDevices().count, 2)
    }

    func test_consolidateDuplicates_leavesAloneWhenMultipleEntriesAreConnected() {
        // Two distinct physically-present devices that happen to share a name
        // — assume they're real distinct hardware and don't merge.
        manager.rememberDevice("uid-1", name: "USB Audio", isInput: false)
        manager.rememberDevice("uid-2", name: "USB Audio", isInput: false)

        manager.consolidateDuplicates(connectedUIDs: ["uid-1", "uid-2"])

        XCTAssertEqual(manager.getKnownDevices().count, 2)
    }

    func test_consolidateDuplicates_migratesPriorityListToSurvivorUID() {
        manager.rememberDevice("old", name: "C34J79x", isInput: false)
        manager.rememberDevice("new", name: "C34J79x", isInput: false)
        manager.savePriorities([device("Speaker1"), device("old", "C34J79x"), device("Speaker2")], category: .speaker)

        // "new" just connected with a fresh UID; "old" is gone.
        manager.consolidateDuplicates(connectedUIDs: ["new"])

        XCTAssertEqual(savedPriorities(category: .speaker), ["Speaker1", "new", "Speaker2"])
    }

    func test_consolidateDuplicates_doesNotInsertSurvivorTwiceIfAlreadyInList() {
        // Both old and new UIDs are already in the priority list.
        manager.rememberDevice("old", name: "C34J79x", isInput: false)
        manager.rememberDevice("new", name: "C34J79x", isInput: false)
        manager.savePriorities([device("old", "C34J79x"), device("new", "C34J79x"), device("Speaker1")], category: .speaker)

        manager.consolidateDuplicates(connectedUIDs: ["new"])

        // Survivor "new" stays at its position; "old" is removed.
        let saved = savedPriorities(category: .speaker)
        XCTAssertEqual(saved, ["new", "Speaker1"])
        XCTAssertEqual(saved.count, Set(saved).count)
    }

    func test_consolidateDuplicates_migratesNeverUseFlag() {
        manager.rememberDevice("old", name: "C34J79x", isInput: false)
        manager.rememberDevice("new", name: "C34J79x", isInput: false)
        manager.setNeverUse(device("old", "C34J79x"), neverUse: true)
        XCTAssertTrue(manager.isNeverUse(device("old", "C34J79x")))

        manager.consolidateDuplicates(connectedUIDs: ["new"])

        XCTAssertTrue(manager.isNeverUse(device("new", "C34J79x")))
        XCTAssertFalse(manager.isNeverUse(device("old", "C34J79x")))
    }

    func test_consolidateDuplicates_migratesCategoryAssignment() {
        manager.rememberDevice("old", name: "C34J79x", isInput: false)
        manager.rememberDevice("new", name: "C34J79x", isInput: false)
        manager.setCategory(.headphone, for: device("old", "C34J79x"))

        manager.consolidateDuplicates(connectedUIDs: ["new"])

        XCTAssertEqual(manager.getCategory(for: device("new", "C34J79x")), .headphone)
    }

    func test_consolidateDuplicates_migratesHiddenList() {
        manager.rememberDevice("old", name: "C34J79x", isInput: false)
        manager.rememberDevice("new", name: "C34J79x", isInput: false)
        manager.setCategory(.speaker, for: device("old", "C34J79x"))
        manager.setCategory(.speaker, for: device("new", "C34J79x"))
        manager.hideDevice(device("old", "C34J79x"), inCategory: .speaker)
        XCTAssertTrue(manager.isHidden(device("old", "C34J79x"), inCategory: .speaker))

        manager.consolidateDuplicates(connectedUIDs: ["new"])

        XCTAssertTrue(manager.isHidden(device("new", "C34J79x"), inCategory: .speaker))
    }

    func test_consolidateDuplicates_isIdempotent() {
        manager.rememberDevice("uid-1", name: "C34J79x", isInput: false)
        manager.rememberDevice("uid-2", name: "C34J79x", isInput: false)

        manager.consolidateDuplicates(connectedUIDs: [])
        let firstPass = manager.getKnownDevices()
        manager.consolidateDuplicates(connectedUIDs: [])
        let secondPass = manager.getKnownDevices()

        XCTAssertEqual(firstPass.count, 1)
        XCTAssertEqual(firstPass.map { $0.uid }, secondPass.map { $0.uid })
    }

    func test_consolidateDuplicates_acrossReconnectsConvergesToOneEntry() {
        // Simulate the real-world scenario: monitor reconnects 5 times with
        // fresh UIDs each time; each reconnect triggers a refresh that calls
        // rememberDevice + consolidateDuplicates.
        for i in 1...5 {
            let uid = "C34J79x-session-\(i)"
            manager.rememberDevice(uid, name: "C34J79x", isInput: false)
            manager.consolidateDuplicates(connectedUIDs: [uid])
            XCTAssertEqual(manager.getKnownDevices().count, 1, "Should never accumulate duplicates")
        }

        XCTAssertEqual(manager.getKnownDevices().first?.uid, "C34J79x-session-5")
    }

    func test_consolidateDuplicates_preservesPriorityAcrossReconnects() {
        // First connection: add to priority list with a manual position.
        manager.rememberDevice("session-1", name: "C34J79x", isInput: false)
        manager.rememberDevice("Speaker1", name: "Built-in", isInput: false)
        manager.savePriorities([device("Speaker1"), device("session-1", "C34J79x")], category: .speaker)
        manager.consolidateDuplicates(connectedUIDs: ["session-1", "Speaker1"])

        // Reconnect with a new UID — the saved priority position should follow.
        manager.rememberDevice("session-2", name: "C34J79x", isInput: false)
        manager.consolidateDuplicates(connectedUIDs: ["session-2", "Speaker1"])

        XCTAssertEqual(savedPriorities(category: .speaker), ["Speaker1", "session-2"])
    }
}

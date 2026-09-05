import Foundation
import CoreAudio

@main
enum MicrophoneAutomationTests {
    static var passed = 0

    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else {
            fputs("FAIL: \(name)\n", stderr)
            exit(1)
        }
        passed += 1
        print("PASS: \(name)")
    }

    static func classify(_ name: String, _ transport: UInt32? = nil, _ terminals: [UInt32] = []) -> MicrophoneClassification {
        MicrophoneClassifier.classify(name: name, metadata: .init(transport: transport, inputTerminals: terminals))
    }

    static func main() throws {
        let mic = UInt32(kAudioStreamTerminalTypeMicrophone)
        let headset = UInt32(kAudioStreamTerminalTypeHeadsetMicrophone)
        let usb = UInt32(kAudioDeviceTransportTypeUSB)
        let builtIn = UInt32(kAudioDeviceTransportTypeBuiltIn)

        for transport in [kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate] {
            check(classify("AirPods Webcam", UInt32(transport), [headset]).role == .virtual, "virtual/aggregate transport overrides misleading names (\(transport))")
        }
        for transport in [kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless] {
            check(classify("USB Headset Camera", UInt32(transport), [headset]).role == .continuity, "Continuity transport overrides headset and camera hints (\(transport))")
        }
        check(classify("USB Headset", UInt32(kAudioDeviceTransportTypeBluetooth)).role == .bluetooth, "Bluetooth transport wins over a wired name")
        check(classify("Camera", UInt32(kAudioDeviceTransportTypeBluetoothLE)).role == .bluetooth, "Bluetooth LE is supported")
        check(MicrophoneRole.bluetooth.label == "Bluetooth microphone", "Bluetooth is not assumed to be a headset")
        check(classify("External Webcam", builtIn, [mic]).role == .builtIn, "built-in transport wins over name")
        check(classify("External Microphone", builtIn, [headset]).role == .wired, "analog headset uses headset terminal rather than built-in role")
        check(classify("Desk Unit", usb, [headset]).role == .wired, "USB headset terminal identifies wired headset")
        check(classify("Studio Microphone", usb, [mic]).role == .external, "USB microphone is not a headset")
        check(classify("Unknown USB Device", usb).role == .unknown, "USB transport alone is not enough")
        check(classify("Logitech", usb).role == .unknown, "vendor alone is not a camera")
        check(classify("HD Pro Webcam C920", usb, [mic]).role == .camera, "webcam hint identifies camera input")
        check(classify("StreamCam", usb, [mic]).role == .camera, "StreamCam name is recognized")
        check(classify("Meeting Headset", usb).role == .wired, "USB plus headset hint identifies likely wired headset")
        check(classify("AirPods").role == .unknown, "headset name without transport does not invent a connection")
        check(classify("Cameraman Studio", usb).role == .unknown, "name hints match full words")
        check(classify("Meeting Headset", usb).reason.contains("name"), "name-based classification explains its evidence")
        check(classify("Input", nil, [mic]).role == .external, "standard microphone terminal is external")
        check(classify("Input").role == .unknown, "missing metadata stays unknown")

        let mac = AudioDevice(id: 1, uid: "mac", name: "Mac", type: .input)
        let camera = AudioDevice(id: 2, uid: "camera", name: "Camera", type: .input)
        let otherCamera = AudioDevice(id: 3, uid: "camera-2", name: "Other Camera", type: .input)
        let virtual = AudioDevice(id: 4, uid: "virtual", name: "Virtual", type: .input)
        let unknown = AudioDevice(id: 5, uid: "unknown", name: "Unknown", type: .input)
        let output = AudioDevice(id: 6, uid: "speaker", name: "Speaker", type: .output)
        let disconnected = AudioDevice.disconnected(uid: "offline", name: "Offline", type: .input)
        let classes: [String: MicrophoneClassification] = [
            "mac": .init(role: .builtIn, reason: "test"),
            "camera": .init(role: .camera, reason: "test"),
            "camera-2": .init(role: .camera, reason: "test"),
            "virtual": .init(role: .virtual, reason: "test")
        ]
        func choose(_ devices: [AudioDevice], _ settings: MicrophoneSettings, _ lid: LidState = .open) -> AudioDevice? {
            MicrophoneSelection.choose(candidates: devices, settings: settings, classifications: classes, lid: lid)
        }
        check(!MicrophoneSettings().enabled, "rules are disabled by default")
        check(choose([output, disconnected, unknown, mac], .init())?.uid == "unknown", "disabled rules preserve connected input priority including unknown devices")
        check(choose([virtual, mac], .init(enabled: true))?.uid == "mac", "virtual devices are excluded from enabled default rules")
        check(choose([unknown, virtual], .init(enabled: true)) == nil, "no eligible role produces no switch target")
        check(choose([camera, mac], .init(enabled: true))?.uid == "mac", "role order takes priority over device order")
        check(choose([otherCamera, camera], .init(enabled: true))?.uid == "camera-2", "existing device priority breaks ties within a role")
        check(choose([camera, mac], .init(enabled: true, overrides: ["camera": .wired]))?.uid == "camera", "manual UID role override wins over automatic classification")
        check(choose([mac, camera], .init(enabled: true, overrides: ["mac": .virtual]))?.uid == "camera", "manual exclusion wins over automatic role")
        let lidSettings = MicrophoneSettings(enabled: true, rules: [
            .init(role: .camera, condition: .lidClosed),
            .init(role: .builtIn, condition: .lidOpen)
        ])
        check(choose([mac, camera], lidSettings, .closed)?.uid == "camera", "closed lid uses camera rule")
        check(choose([camera, mac], lidSettings, .open)?.uid == "mac", "open lid uses built-in rule")
        check(choose([camera, mac], lidSettings, .unknown) == nil, "unknown lid does not claim open or closed")
        check(choose([camera, mac], .init(enabled: true), .unknown)?.uid == "mac", "always rules work on desktop and unknown lid")
        let reordered = MicrophoneSettings(enabled: true, rules: [.init(role: .camera, condition: .always)])
        check(choose([mac, camera], reordered)?.uid == "camera", "edited role order changes selection")
        let reconnected = AudioDevice(id: 99, uid: camera.uid, name: camera.name, type: .input)
        check(choose([mac, reconnected], .init(enabled: true, overrides: [camera.uid: .wired]))?.id == 99, "overrides survive a changed numeric device ID")
        check(choose([output, disconnected], .init(enabled: true)) == nil, "selection rejects outputs and disconnected inputs")
        for state in [LidState.open, .closed, .unknown] {
            check(!MicrophoneCondition.never.allows(state), "never excludes devices for lid state \(state.rawValue)")
        }

        let suiteName = "AudioPriorityBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MicrophoneSettingsStore(defaults: defaults)
        check(store.settings == MicrophoneSettings(), "fresh store uses safe opt-in defaults")
        defaults.set("keep", forKey: "existingDevicePriorities")
        let custom = MicrophoneSettings(enabled: true, rules: lidSettings.rules, overrides: ["camera": .wired])
        store.save(custom)
        check(MicrophoneSettingsStore(defaults: defaults).settings == custom.normalized(), "settings round-trip across store instances")
        check(defaults.string(forKey: "existingDevicePriorities") == "keep", "save does not change existing device preferences")
        let otherSuiteName = "AudioPriorityBarTests.\(UUID().uuidString)"
        let otherDefaults = UserDefaults(suiteName: otherSuiteName)!
        defer { otherDefaults.removePersistentDomain(forName: otherSuiteName) }
        check(MicrophoneSettingsStore(defaults: otherDefaults).settings == MicrophoneSettings(), "injected defaults isolate storage")
        defaults.set(Data("bad JSON".utf8), forKey: "microphoneAutomation.v1")
        check(MicrophoneSettingsStore(defaults: defaults).settings == MicrophoneSettings(), "corrupt storage falls back to disabled defaults")
        let partialJSON = """
        {"enabled":true,"rules":[
          {"role":"camera","condition":"lidClosed"},
          {"role":"camera","condition":"always"},
          {"role":"future-role","condition":"always"},
          {"role":"builtIn","condition":"future-condition"},
          42
        ],"overrides":{"camera":"wired","future":"future-role","":"wired"}}
        """
        defaults.set(Data(partialJSON.utf8), forKey: "microphoneAutomation.v1")
        let restored = MicrophoneSettingsStore(defaults: defaults).settings
        check(restored.enabled, "valid enabled state survives malformed rule entries")
        check(restored.rules.first == .init(role: .camera, condition: .lidClosed), "first duplicate rule wins and preserves order")
        check(Set(restored.rules.map(\.role)).count == MicrophoneRole.allCases.count && restored.rules.count == MicrophoneRole.allCases.count, "normalization fills all missing roles exactly once")
        check(restored.rules.first(where: { $0.role == .builtIn })?.condition == .always, "invalid condition falls back to role default")
        check(restored.overrides == ["camera": .wired], "unknown override enums and empty UIDs are discarded")
        let wrongTypes = try JSONDecoder().decode(MicrophoneSettings.self, from: Data("{\"enabled\":\"yes\",\"rules\":{},\"overrides\":[]}".utf8))
        check(wrongTypes == MicrophoneSettings(), "invalid top-level field types restore defaults")
        store.save(.init(enabled: true, rules: [.init(role: .wired, condition: .never), .init(role: .wired, condition: .always)]))
        check(store.settings.rules.count == MicrophoneRole.allCases.count && store.settings.rules.first?.condition == .never, "save also normalizes duplicate and incomplete rules")
        print("\(passed) microphone automation checks passed.")
    }
}

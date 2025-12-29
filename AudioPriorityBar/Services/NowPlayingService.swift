import Foundation
import AppKit

// MediaRemote private framework types
typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
typealias MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
typealias MRMediaRemoteSendCommandFunction = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool
typealias MRMediaRemoteRegisterForNowPlayingNotificationsFunction = @convention(c) (DispatchQueue) -> Void

// MediaRemote commands
let kMRPlay: UInt32 = 0
let kMRPause: UInt32 = 1
let kMRTogglePlayPause: UInt32 = 2
let kMRStop: UInt32 = 3
let kMRNextTrack: UInt32 = 4
let kMRPreviousTrack: UInt32 = 5

// MediaRemote notification names
let kMRMediaRemoteNowPlayingInfoDidChangeNotification = "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
let kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification = "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"

struct NowPlayingInfo: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let artwork: NSImage?
    let appBundleIdentifier: String?

    var hasContent: Bool {
        title != nil || artist != nil
    }

    var appIcon: NSImage? {
        guard let bundleId = appBundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.appBundleIdentifier == rhs.appBundleIdentifier
    }
}

@MainActor
class NowPlayingService: ObservableObject {
    @Published var nowPlaying: NowPlayingInfo?
    @Published var isPlaying: Bool = false

    private var mediaRemoteBundle: CFBundle?
    private var getNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunction?
    private var getIsPlaying: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction?
    private var sendCommand: MRMediaRemoteSendCommandFunction?
    private var registerForNotifications: MRMediaRemoteRegisterForNowPlayingNotificationsFunction?

    init() {
        loadMediaRemoteFramework()
        setupNotifications()
        refresh()
    }

    private func loadMediaRemoteFramework() {
        guard let bundle = CFBundleCreate(kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")) else {
            return
        }

        mediaRemoteBundle = bundle

        // Load functions
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
            getNowPlayingInfo = unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
        }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString) {
            getIsPlaying = unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction.self)
        }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            sendCommand = unsafeBitCast(ptr, to: MRMediaRemoteSendCommandFunction.self)
        }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) {
            registerForNotifications = unsafeBitCast(ptr, to: MRMediaRemoteRegisterForNowPlayingNotificationsFunction.self)
        }
    }

    private func setupNotifications() {
        registerForNotifications?(DispatchQueue.main)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNowPlayingChange),
            name: NSNotification.Name(kMRMediaRemoteNowPlayingInfoDidChangeNotification),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlayingStateChange),
            name: NSNotification.Name(kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification),
            object: nil
        )
    }

    @objc private func handleNowPlayingChange() {
        refresh()
    }

    @objc private func handlePlayingStateChange() {
        refreshPlayingState()
    }

    func refresh() {
        getNowPlayingInfo?(DispatchQueue.main) { [weak self] info in
            Task { @MainActor in
                self?.updateNowPlaying(from: info)
            }
        }
        refreshPlayingState()
    }

    private func refreshPlayingState() {
        getIsPlaying?(DispatchQueue.main) { [weak self] playing in
            Task { @MainActor in
                self?.isPlaying = playing
            }
        }
    }

    private func updateNowPlaying(from info: [String: Any]) {
        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
        let bundleId = info["kMRMediaRemoteNowPlayingInfoClientPropertiesApplicationBundleIdentifier"] as? String

        var artwork: NSImage?
        if let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            artwork = NSImage(data: artworkData)
        }

        if title != nil || artist != nil {
            nowPlaying = NowPlayingInfo(
                title: title,
                artist: artist,
                album: album,
                artwork: artwork,
                appBundleIdentifier: bundleId
            )
        } else {
            nowPlaying = nil
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        _ = sendCommand?(kMRTogglePlayPause, nil)
    }

    func play() {
        _ = sendCommand?(kMRPlay, nil)
    }

    func pause() {
        _ = sendCommand?(kMRPause, nil)
    }

    func nextTrack() {
        _ = sendCommand?(kMRNextTrack, nil)
    }

    func previousTrack() {
        _ = sendCommand?(kMRPreviousTrack, nil)
    }
}

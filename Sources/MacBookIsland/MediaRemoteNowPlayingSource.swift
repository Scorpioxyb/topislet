import AppKit
import Foundation

struct MediaRemoteNowPlayingTrack: Equatable {
    let title: String
    let artist: String
    let album: String?
    let artworkData: Data?
    let isPlaying: Bool?
    let progress: Double
    let elapsedTime: TimeInterval?
    let duration: TimeInterval?
    let sourceBundleIdentifier: String?
    let sourceProcessIdentifier: pid_t?
    let sourceName: String
}

struct MediaRemoteNowPlayingSnapshot: Equatable {
    let isAvailable: Bool
    let isVerifiedQishuiSource: Bool
    let currentTrack: MediaRemoteNowPlayingTrack?
    let diagnostic: String
    let checkedAt: Date
}

final class MediaRemoteNowPlayingSource {
    private let qishuiBundleIdentifier = "com.soda.music"
    private let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private let callbackQueue = DispatchQueue(label: "MacBookIsland.MediaRemote", qos: .userInitiated)
    private let timeout: DispatchTimeInterval = .milliseconds(280)

    private var handle: UnsafeMutableRawPointer?
    private var observers: [NSObjectProtocol] = []
    private var didRegisterNotifications = false

    private typealias NowPlayingInfoCallback = @convention(block) (CFDictionary?) -> Void
    private typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping NowPlayingInfoCallback) -> Void
    private typealias IsPlayingCallback = @convention(block) (Bool) -> Void
    private typealias GetNowPlayingApplicationIsPlaying = @convention(c) (DispatchQueue, @escaping IsPlayingCallback) -> Void
    private typealias PlaybackStateCallback = @convention(block) (UInt32) -> Void
    private typealias GetNowPlayingApplicationPlaybackState = @convention(c) (DispatchQueue, @escaping PlaybackStateCallback) -> Void
    private typealias PIDCallback = @convention(block) (pid_t) -> Void
    private typealias GetNowPlayingApplicationPID = @convention(c) (DispatchQueue, @escaping PIDCallback) -> Void
    private typealias DisplayIDCallback = @convention(block) (CFString?) -> Void
    private typealias GetNowPlayingApplicationDisplayID = @convention(c) (DispatchQueue, @escaping DisplayIDCallback) -> Void
    private typealias RegisterForNowPlayingNotifications = @convention(c) (DispatchQueue) -> Void
    private typealias SetWantsNowPlayingNotifications = @convention(c) (Bool) -> Void

    deinit {
        stop()
    }

    func start(onChange: @escaping () -> Void) {
        guard loadFramework() else { return }
        registerForMediaRemoteNotifications()
        guard observers.isEmpty else { return }

        let notificationNames = [
            constantString(named: "kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            constantString(named: "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
            constantString(named: "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            constantString(named: "kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification")
        ].compactMap { $0 }

        for name in notificationNames {
            let observer = NotificationCenter.default.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { _ in
                onChange()
            }
            observers.append(observer)
        }
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    func snapshot() -> MediaRemoteNowPlayingSnapshot {
        let checkedAt = Date()
        guard loadFramework() else {
            return MediaRemoteNowPlayingSnapshot(
                isAvailable: false,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote 私有框架不可用；已降级到汽水窗口 AX。",
                checkedAt: checkedAt
            )
        }

        let info = fetchNowPlayingInfo()
        let sourcePID = fetchApplicationPID()
        let displayID = fetchApplicationDisplayID()
        let isPlaying = fetchIsPlaying() ?? isPlayingFromPlaybackState(fetchPlaybackState())

        let infoBundleID = stringValue(info?["kMRMediaRemoteNowPlayingInfoBundleIdentifier"])
        let title = stringValue(info?["kMRMediaRemoteNowPlayingInfoTitle"])?.trimmedNonEmpty
        let artist = stringValue(info?["kMRMediaRemoteNowPlayingInfoArtist"])?.trimmedNonEmpty
        let album = stringValue(info?["kMRMediaRemoteNowPlayingInfoAlbum"])?.trimmedNonEmpty
        let elapsedTime = doubleValue(info?["kMRMediaRemoteNowPlayingInfoElapsedTime"])
        let duration = doubleValue(info?["kMRMediaRemoteNowPlayingInfoDuration"])
        let playbackRate = doubleValue(info?["kMRMediaRemoteNowPlayingInfoPlaybackRate"])
        let artworkData = dataValue(info?["kMRMediaRemoteNowPlayingInfoArtworkData"])

        let verifiedSource = isVerifiedQishuiSource(
            infoBundleID: infoBundleID,
            displayID: displayID,
            pid: sourcePID
        )

        guard verifiedSource else {
            let source = infoBundleID ?? displayID ?? sourcePID.map { "pid \($0)" } ?? "unknown"
            return MediaRemoteNowPlayingSnapshot(
                isAvailable: true,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote 当前来源不是汽水音乐或无法确认来源：\(source)。不会把其他播放器冒充为汽水。",
                checkedAt: checkedAt
            )
        }

        guard let title, !title.isEmpty else {
            return MediaRemoteNowPlayingSnapshot(
                isAvailable: true,
                isVerifiedQishuiSource: true,
                currentTrack: nil,
                diagnostic: "MediaRemote 已确认汽水音乐来源，但当前没有暴露歌名；已降级到 AX 兜底。",
                checkedAt: checkedAt
            )
        }

        let realIsPlaying = isPlaying ?? playbackRate.map { $0 > 0.01 }
        let progress: Double
        if let elapsedTime, let duration, duration > 0 {
            progress = min(max(elapsedTime / duration, 0), 1)
        } else {
            progress = 0
        }

        let track = MediaRemoteNowPlayingTrack(
            title: title,
            artist: artist ?? "汽水音乐",
            album: album,
            artworkData: artworkData,
            isPlaying: realIsPlaying,
            progress: progress,
            elapsedTime: elapsedTime,
            duration: duration,
            sourceBundleIdentifier: infoBundleID ?? displayID,
            sourceProcessIdentifier: sourcePID,
            sourceName: "MediaRemote Now Playing"
        )

        return MediaRemoteNowPlayingSnapshot(
            isAvailable: true,
            isVerifiedQishuiSource: true,
            currentTrack: track,
            diagnostic: "已通过 macOS Now Playing 事件源确认汽水音乐；来源 \(infoBundleID ?? displayID ?? "pid \(sourcePID ?? 0)")，封面 \(artworkData.map { "\($0.count) bytes" } ?? "未提供")。",
            checkedAt: checkedAt
        )
    }

    private func registerForMediaRemoteNotifications() {
        guard !didRegisterNotifications else { return }
        guard let register = symbol(
            "MRMediaRemoteRegisterForNowPlayingNotifications",
            as: RegisterForNowPlayingNotifications.self
        ) else {
            return
        }

        register(DispatchQueue.main)
        if let setWants = symbol(
            "MRMediaRemoteSetWantsNowPlayingNotifications",
            as: SetWantsNowPlayingNotifications.self
        ) {
            setWants(true)
        }
        didRegisterNotifications = true
    }

    private func fetchNowPlayingInfo() -> NSDictionary? {
        guard let function = symbol("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlayingInfo.self) else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var received: NSDictionary?
        function(callbackQueue) { info in
            received = info as NSDictionary?
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return received
    }

    private func fetchIsPlaying() -> Bool? {
        guard let function = symbol(
            "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
            as: GetNowPlayingApplicationIsPlaying.self
        ) else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var received: Bool?
        function(callbackQueue) { isPlaying in
            received = isPlaying
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return received
    }

    private func fetchPlaybackState() -> UInt32? {
        guard let function = symbol(
            "MRMediaRemoteGetNowPlayingApplicationPlaybackState",
            as: GetNowPlayingApplicationPlaybackState.self
        ) else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var received: UInt32?
        function(callbackQueue) { playbackState in
            received = playbackState
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return received
    }

    private func fetchApplicationPID() -> pid_t? {
        guard let function = symbol(
            "MRMediaRemoteGetNowPlayingApplicationPID",
            as: GetNowPlayingApplicationPID.self
        ) else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var received: pid_t?
        function(callbackQueue) { pid in
            received = pid > 0 ? pid : nil
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return received
    }

    private func fetchApplicationDisplayID() -> String? {
        guard let function = symbol(
            "MRMediaRemoteGetNowPlayingApplicationDisplayID",
            as: GetNowPlayingApplicationDisplayID.self
        ) else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var received: String?
        function(callbackQueue) { displayID in
            received = displayID as String?
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return received?.trimmedNonEmpty
    }

    private func isVerifiedQishuiSource(infoBundleID: String?, displayID: String?, pid: pid_t?) -> Bool {
        if infoBundleID == qishuiBundleIdentifier || displayID == qishuiBundleIdentifier {
            return true
        }

        guard let pid else { return false }
        if let app = NSRunningApplication(processIdentifier: pid) {
            if app.bundleIdentifier == qishuiBundleIdentifier {
                return true
            }
            if app.bundleIdentifier?.hasPrefix(qishuiBundleIdentifier + ".") == true {
                return true
            }
            let executablePath = app.executableURL?.path ?? ""
            let bundlePath = app.bundleURL?.path ?? ""
            if executablePath.hasPrefix("/Applications/汽水音乐.app/")
                || bundlePath.hasPrefix("/Applications/汽水音乐.app/") {
                return true
            }
        }

        return NSRunningApplication
            .runningApplications(withBundleIdentifier: qishuiBundleIdentifier)
            .contains { $0.processIdentifier == pid }
    }

    private func isPlayingFromPlaybackState(_ state: UInt32?) -> Bool? {
        guard let state else { return nil }
        if state == 1 { return true }
        if state == 2 { return false }
        return nil
    }

    private func loadFramework() -> Bool {
        if handle != nil { return true }
        handle = dlopen(frameworkPath, RTLD_NOW)
        return handle != nil
    }

    private func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle,
              let rawSymbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(rawSymbol, to: T.self)
    }

    private func constantString(named name: String) -> String? {
        guard let handle,
              let rawSymbol = dlsym(handle, name) else {
            return nil
        }
        return rawSymbol.assumingMemoryBound(to: CFString?.self).pointee as String?
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSString { return value as String }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func dataValue(_ value: Any?) -> Data? {
        if let value = value as? Data { return value }
        if let value = value as? NSData { return value as Data }
        return nil
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

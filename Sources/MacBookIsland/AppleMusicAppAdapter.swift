import AppKit
import AppleMusicBridge
import ApplicationServices
import Foundation

enum AppleMusicAutomationAccess: Equatable, Sendable {
    case allowed
    case targetNotRunning
    case consentRequired
    case denied
    case unavailable(status: OSStatus)

    var displayName: String {
        switch self {
        case .allowed:
            return "已授权"
        case .targetNotRunning:
            return "等待 Apple Music 运行"
        case .consentRequired:
            return "需要授权"
        case .denied:
            return "已拒绝"
        case let .unavailable(status):
            return "不可用（\(status)）"
        }
    }

    var diagnosticCode: String {
        switch self {
        case .allowed:
            return "allowed"
        case .targetNotRunning:
            return "targetNotRunning"
        case .consentRequired:
            return "consentRequired"
        case .denied:
            return "denied"
        case let .unavailable(status):
            return "unavailable:\(status)"
        }
    }
}

struct AppleMusicObservation: Equatable, Sendable {
    let persistentIdentifier: String?
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?
    let state: MusicPlaybackState

    var trackIdentity: MusicTrackIdentity? {
        guard let title, !title.isEmpty else { return nil }
        return MusicTrackIdentity(
            providerIdentifier: persistentIdentifier,
            fallbackSignature: [title, artist ?? "", album ?? ""]
                .joined(separator: "\u{1f}")
        )
    }

    var artworkReuseIdentity: AppleMusicArtworkReuseIdentity? {
        AppleMusicArtworkReuseIdentity(artist: artist, album: album)
    }

    static func decode(
        fields: [String],
        artworkData: Data? = nil
    ) -> AppleMusicObservation? {
        guard fields.count == 7 else { return nil }
        let state = playbackState(from: fields[6])
        let title = fields[1].nilIfEmpty
        return AppleMusicObservation(
            persistentIdentifier: fields[0].nilIfEmpty,
            title: title,
            artist: fields[2].nilIfEmpty,
            album: fields[3].nilIfEmpty,
            artworkData: artworkData,
            duration: positiveFiniteDouble(fields[4]),
            elapsedTime: nonnegativeFiniteDouble(fields[5]),
            state: state
        )
    }

    func withArtworkData(_ artworkData: Data?) -> AppleMusicObservation {
        AppleMusicObservation(
            persistentIdentifier: persistentIdentifier,
            title: title,
            artist: artist,
            album: album,
            artworkData: artworkData,
            duration: duration,
            elapsedTime: elapsedTime,
            state: state
        )
    }

    static func playbackState(from rawValue: String) -> MusicPlaybackState {
        switch rawValue.lowercased() {
        case "playing", "fast forwarding", "rewinding":
            return .playing
        case "paused":
            return .paused
        case "stopped":
            return .stopped
        default:
            return .unknown
        }
    }

    private static func positiveFiniteDouble(_ rawValue: String) -> Double? {
        guard let value = Double(rawValue), value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func nonnegativeFiniteDouble(_ rawValue: String) -> Double? {
        guard let value = Double(rawValue), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

struct AppleMusicArtworkReuseIdentity: Equatable, Sendable {
    let artist: String
    let album: String

    init?(artist: String?, album: String?) {
        guard let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines),
              !artist.isEmpty,
              let album = album?.trimmingCharacters(in: .whitespacesAndNewlines),
              !album.isEmpty else {
            return nil
        }
        self.artist = artist
        self.album = album
    }
}

struct AppleMusicArtworkReuseCache: Sendable {
    private var entry: (identity: AppleMusicArtworkReuseIdentity, data: Data)?
    let maximumArtworkBytes: Int

    init(maximumArtworkBytes: Int = 8 * 1024 * 1024) {
        self.maximumArtworkBytes = maximumArtworkBytes
    }

    func data(for observation: AppleMusicObservation) -> Data? {
        guard let identity = observation.artworkReuseIdentity,
              entry?.identity == identity else { return nil }
        return entry?.data
    }

    mutating func remember(
        _ data: Data,
        for observation: AppleMusicObservation
    ) {
        guard !data.isEmpty,
              data.count <= maximumArtworkBytes,
              let identity = observation.artworkReuseIdentity else { return }
        entry = (identity: identity, data: data)
    }

    mutating func reset() {
        entry = nil
    }
}

struct AppleMusicPlayerInfoCandidate: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String?

    init?(userInfo: [AnyHashable: Any]?) {
        guard let title = userInfo?["Name"] as? String,
              !title.isEmpty,
              let artist = userInfo?["Artist"] as? String,
              !artist.isEmpty else {
            return nil
        }
        self.title = title
        self.artist = artist
        album = (userInfo?["Album"] as? String)?.nilIfEmpty
    }

    init?(observation: AppleMusicObservation) {
        guard let title = observation.title,
              !title.isEmpty,
              let artist = observation.artist,
              !artist.isEmpty else {
            return nil
        }
        self.title = title
        self.artist = artist
        album = observation.album
    }

    var fallbackSignature: String {
        [title, artist, album ?? ""].joined(separator: "\u{1f}")
    }

    var observation: AppleMusicObservation {
        AppleMusicObservation(
            persistentIdentifier: nil,
            title: title,
            artist: artist,
            album: album,
            artworkData: nil,
            duration: nil,
            elapsedTime: nil,
            state: .unknown
        )
    }
}

enum AppleMusicArtworkPrefetchRoute: Equatable, Sendable {
    case native
    case catalog
}

enum AppleMusicArtworkPrefetchPolicy {
    // Native artwork is normally faster. The catalog starts only when the
    // native Apple Event has not completed within this short head start.
    static let catalogHedgeDelayNanoseconds: UInt64 = 350_000_000
}

enum AppleMusicMetadataArtworkPolicy {
    static func shouldIncludeArtwork(
        nativeRecoverySignature: String?
    ) -> Bool {
        nativeRecoverySignature != nil
    }
}

struct AppleMusicArtworkRecoveryState: Equatable, Sendable {
    private(set) var catalogFallbackSignature: String?
    private(set) var nativeRecoveryScheduledSignature: String?
    private(set) var nativeRecoveryAttemptedSignature: String?

    func route(for fallbackSignature: String) -> AppleMusicArtworkPrefetchRoute {
        catalogFallbackSignature == fallbackSignature ? .catalog : .native
    }

    mutating func recordMetadataResult(
        _ observation: AppleMusicObservation,
        artworkRequested: Bool,
        nativeRecoverySignature: String?
    ) -> Bool {
        guard artworkRequested else { return false }
        guard let identity = observation.trackIdentity else {
            return true
        }
        let fallbackSignature = identity.fallbackSignature
        if observation.artworkData != nil {
            recordArtworkSuccess(for: fallbackSignature)
            return false
        }
        if nativeRecoverySignature == fallbackSignature
            || nativeRecoveryAttemptedSignature == fallbackSignature {
            catalogFallbackSignature = nil
            nativeRecoveryScheduledSignature = nil
            nativeRecoveryAttemptedSignature = fallbackSignature
            return false
        }
        catalogFallbackSignature = fallbackSignature
        nativeRecoveryScheduledSignature = nil
        nativeRecoveryAttemptedSignature = nil
        return false
    }

    mutating func recordNativePrefetchMiss(
        for fallbackSignature: String
    ) -> Bool {
        guard nativeRecoveryAttemptedSignature != fallbackSignature else {
            catalogFallbackSignature = nil
            return false
        }
        catalogFallbackSignature = fallbackSignature
        return true
    }

    mutating func recordArtworkSuccess(for fallbackSignature: String) {
        if catalogFallbackSignature == fallbackSignature {
            catalogFallbackSignature = nil
        }
        if nativeRecoveryScheduledSignature == fallbackSignature {
            nativeRecoveryScheduledSignature = nil
        }
        if nativeRecoveryAttemptedSignature == fallbackSignature {
            nativeRecoveryAttemptedSignature = nil
        }
    }

    mutating func scheduleNativeRecoveryAfterCatalogFailure(
        fallbackSignature: String,
        currentIdentity: MusicTrackIdentity?
    ) -> Bool {
        guard currentIdentity?.fallbackSignature == fallbackSignature,
              nativeRecoveryScheduledSignature != fallbackSignature,
              nativeRecoveryAttemptedSignature != fallbackSignature else {
            return false
        }
        catalogFallbackSignature = nil
        nativeRecoveryScheduledSignature = fallbackSignature
        return true
    }

    mutating func consumeNativeRecoverySignature() -> String? {
        guard let signature = nativeRecoveryScheduledSignature else {
            return nil
        }
        nativeRecoveryScheduledSignature = nil
        nativeRecoveryAttemptedSignature = signature
        return signature
    }

    mutating func reset() {
        catalogFallbackSignature = nil
        nativeRecoveryScheduledSignature = nil
        nativeRecoveryAttemptedSignature = nil
    }
}

func appleMusicSnapshotByReplacingArtworkData(
    _ snapshot: MusicAppSnapshot,
    artworkData: Data,
    identity: MusicTrackIdentity,
    revision: UInt64
) -> MusicAppSnapshot? {
    guard let track = snapshot.track,
          track.identity == identity else { return nil }
    let updatedTrack = MusicTrackSnapshot(
        identity: track.identity,
        title: track.title,
        artist: track.artist,
        album: track.album,
        artworkData: artworkData,
        lyrics: track.lyrics
    )
    return MusicAppSnapshot(
        descriptor: snapshot.descriptor,
        instance: snapshot.instance,
        availability: snapshot.availability,
        track: updatedTrack,
        playbackState: snapshot.playbackState,
        timeline: snapshot.timeline,
        controls: snapshot.controls,
        revision: revision,
        provenance: snapshot.provenance,
        checkedAt: snapshot.checkedAt,
        diagnostic: "Apple Music 播放状态保持原快照；封面 \(artworkData.count) bytes 已异步补齐。"
    )
}

private struct AppleMusicBridgeFailure: Error, Sendable {
    let diagnostic: String
}

struct AppleMusicArtworkCache: Sendable {
    enum FailureKind: Sendable {
        case notFound
        case transient
    }

    private struct Entry: Sendable {
        var data: Data?
        var attemptedAt: Date
        var retryAfter: Date
        var transientFailureCount: Int
    }

    private var entries: [MusicTrackIdentity: Entry] = [:]
    private var order: [MusicTrackIdentity] = []
    private(set) var totalBytes = 0
    let retryInterval: TimeInterval
    let maximumEntryCount: Int
    let maximumArtworkBytes: Int
    let maximumTotalBytes: Int

    init(
        retryInterval: TimeInterval = 30,
        maximumEntryCount: Int = 16,
        maximumArtworkBytes: Int = 8 * 1024 * 1024,
        maximumTotalBytes: Int = 24 * 1024 * 1024
    ) {
        self.retryInterval = retryInterval
        self.maximumEntryCount = maximumEntryCount
        self.maximumArtworkBytes = maximumArtworkBytes
        self.maximumTotalBytes = maximumTotalBytes
    }

    func data(for identity: MusicTrackIdentity) -> Data? {
        entries[identity]?.data
    }

    func shouldFetch(
        for identity: MusicTrackIdentity,
        at now: Date
    ) -> Bool {
        guard let entry = entries[identity] else { return true }
        guard entry.data == nil else { return false }
        return now >= entry.retryAfter
    }

    mutating func recordAttempt(
        for identity: MusicTrackIdentity,
        at now: Date
    ) {
        let existingData = entries[identity]?.data
        entries[identity] = Entry(
            data: existingData,
            attemptedAt: now,
            retryAfter: now.addingTimeInterval(retryInterval),
            transientFailureCount: entries[identity]?.transientFailureCount ?? 0
        )
        touch(identity)
        trimIfNeeded()
    }

    mutating func recordFailure(
        _ failure: FailureKind,
        for identity: MusicTrackIdentity,
        at now: Date
    ) {
        if let existingData = entries[identity]?.data {
            totalBytes -= existingData.count
        }
        let previousFailureCount = entries[identity]?.transientFailureCount ?? 0
        let transientFailureCount: Int
        let retryDelay: TimeInterval
        switch failure {
        case .notFound:
            transientFailureCount = 0
            retryDelay = max(retryInterval, 5 * 60)
        case .transient:
            transientFailureCount = min(previousFailureCount + 1, 5)
            retryDelay = min(
                retryInterval * pow(2, Double(transientFailureCount - 1)),
                5 * 60
            )
        }
        entries[identity] = Entry(
            data: nil,
            attemptedAt: now,
            retryAfter: now.addingTimeInterval(retryDelay),
            transientFailureCount: transientFailureCount
        )
        touch(identity)
        trimIfNeeded()
    }

    @discardableResult
    mutating func store(
        _ data: Data,
        for identity: MusicTrackIdentity,
        at now: Date
    ) -> Bool {
        guard !data.isEmpty,
              data.count <= maximumArtworkBytes else { return false }
        if let existingData = entries[identity]?.data {
            totalBytes -= existingData.count
        }
        entries[identity] = Entry(
            data: data,
            attemptedAt: now,
            retryAfter: .distantFuture,
            transientFailureCount: 0
        )
        totalBytes += data.count
        touch(identity)
        trimIfNeeded()
        return entries[identity]?.data != nil
    }

    private mutating func touch(_ identity: MusicTrackIdentity) {
        order.removeAll { $0 == identity }
        order.append(identity)
    }

    private mutating func trimIfNeeded() {
        while order.count > maximumEntryCount
            || totalBytes > maximumTotalBytes {
            guard let removedIdentity = order.first else { break }
            order.removeFirst()
            if let removedData = entries.removeValue(
                forKey: removedIdentity
            )?.data {
                totalBytes -= removedData.count
            }
        }
    }
}

private enum AppleMusicBridgeRunner {
    static func readObservation(
        processIdentifier: pid_t,
        includeArtwork: Bool
    ) -> Result<AppleMusicObservation, AppleMusicBridgeFailure> {
        var bridgeError: NSError?
        guard let snapshot = TopIsletAppleMusicCopySnapshot(
            processIdentifier,
            includeArtwork,
            &bridgeError
        ) else {
            return .failure(failure(bridgeError))
        }
        let fields = [
            snapshot["persistentIdentifier"] as? String ?? "",
            snapshot["title"] as? String ?? "",
            snapshot["artist"] as? String ?? "",
            snapshot["album"] as? String ?? "",
            numberText(snapshot["duration"]),
            numberText(snapshot["elapsedTime"]),
            snapshot["state"] as? String ?? "unknown"
        ]
        guard let observation = AppleMusicObservation.decode(
            fields: fields,
            artworkData: snapshot["artworkData"] as? Data
        ) else {
            return .failure(AppleMusicBridgeFailure(
                diagnostic: "Apple Music 返回了无法解析的播放快照。"
            ))
        }
        return .success(observation)
    }

    static func perform(
        processIdentifier: pid_t,
        action: MusicControlAction,
        expectedTrack: MusicTrackIdentity?
    ) -> Result<Void, AppleMusicBridgeFailure> {
        let actionName: String
        let normalizedProgress: Double
        switch action {
        case .playPause:
            actionName = "playPause"
            normalizedProgress = 0
        case .play:
            actionName = "play"
            normalizedProgress = 0
        case .pause:
            actionName = "pause"
            normalizedProgress = 0
        case .previousTrack:
            actionName = "previousTrack"
            normalizedProgress = 0
        case .nextTrack:
            actionName = "nextTrack"
            normalizedProgress = 0
        case let .seekNormalized(progress):
            guard progress.isFinite, (0...1).contains(progress) else {
                return .failure(AppleMusicBridgeFailure(
                    diagnostic: "Apple Music 进度目标必须位于 0 到 1。"
                ))
            }
            actionName = "seekNormalized"
            normalizedProgress = progress
        }

        var bridgeError: NSError?
        let succeeded = TopIsletAppleMusicPerformAction(
            processIdentifier,
            actionName,
            expectedTrack?.providerIdentifier,
            expectedTrack?.fallbackSignature,
            normalizedProgress,
            &bridgeError
        )
        return succeeded ? .success(()) : .failure(failure(bridgeError))
    }

    private static func numberText(_ value: Any?) -> String {
        guard let number = value as? NSNumber else { return "" }
        return String(
            format: "%.9f",
            locale: Locale(identifier: "en_US_POSIX"),
            number.doubleValue
        )
    }

    private static func failure(_ error: NSError?) -> AppleMusicBridgeFailure {
        let message = error?.localizedDescription
            ?? "Apple Music 定向通信失败。"
        return AppleMusicBridgeFailure(
            diagnostic: error.map { "\(message)（\($0.code)）" } ?? message
        )
    }
}

enum AppleMusicArtworkLoadResult: Sendable {
    case success(Data)
    case notFound
    case transientFailure
}

typealias AppleMusicArtworkLoading = @Sendable (
    pid_t,
    AppleMusicObservation,
    Bool
) async -> AppleMusicArtworkLoadResult

private final class AppleMusicArtworkBridgeRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private final class AppleMusicArtworkBridgeExecutor: @unchecked Sendable {
    static let shared = AppleMusicArtworkBridgeExecutor()

    private let queue = DispatchQueue(
        label: "TopIslet.AppleMusicArtworkBridge"
    )

    func readObservation(
        processIdentifier: pid_t,
        request: AppleMusicArtworkBridgeRequest
    ) async -> Result<AppleMusicObservation, AppleMusicBridgeFailure>? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !request.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                let result = AppleMusicBridgeRunner.readObservation(
                    processIdentifier: processIdentifier,
                    includeArtwork: true
                )
                continuation.resume(
                    returning: request.isCancelled ? nil : result
                )
            }
        }
    }
}

private enum AppleMusicArtworkLoader {
    static func load(
        processIdentifier: pid_t,
        observation: AppleMusicObservation,
        nativeArtworkAlreadyChecked: Bool
    ) async -> AppleMusicArtworkLoadResult {
        if !nativeArtworkAlreadyChecked {
            let request = AppleMusicArtworkBridgeRequest()
            let directResult = await withTaskCancellationHandler {
                await AppleMusicArtworkBridgeExecutor.shared.readObservation(
                    processIdentifier: processIdentifier,
                    request: request
                )
            } onCancel: {
                request.cancel()
            }
            guard !Task.isCancelled,
                  let directResult,
                  case let .success(directObservation) = directResult,
                  directObservation.trackIdentity == observation.trackIdentity else {
                return .transientFailure
            }
            if let artworkData = directObservation.artworkData {
                return .success(artworkData)
            }
        }
        switch await AppleMusicCatalogArtworkResolver().artworkData(for: observation) {
        case let .success(data):
            return .success(data)
        case .notFound:
            return .notFound
        case .transientFailure:
            return .transientFailure
        }
    }
}

final class AppleMusicControlLifecycleGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var isActive = false

    func activate() {
        lock.lock()
        generation &+= 1
        isActive = true
        lock.unlock()
    }

    func deactivate() {
        lock.lock()
        generation &+= 1
        isActive = false
        lock.unlock()
    }

    func token() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return isActive ? generation : nil
    }

    func isValid(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isActive && generation == token
    }
}

@MainActor
final class AppleMusicAppAdapter: MusicAppAdapter {
    let descriptor = MusicAdapterRegistry.appleMusic.descriptor

    private var notificationToken: NSObjectProtocol?
    private var observationGeneration: UInt64 = 0
    private var playerInfoDebounceTask: Task<Void, Never>?
    private var invalidationHandler: (@MainActor @Sendable (
        MusicAdapterInvalidation
    ) -> Void)?
    private var lastObservation: AppleMusicObservation?
    private var lastInstance: MusicAppInstance?
    private var lastSnapshot: MusicAppSnapshot?
    private var revision: UInt64 = 0
    private var artworkCache = AppleMusicArtworkCache()
    private var artworkReuseCache = AppleMusicArtworkReuseCache()
    private let artworkLoader: AppleMusicArtworkLoading
    private let transitionTimeline: AppleMusicTransitionTimeline
    private let controlQueue = DispatchQueue(
        label: "TopIslet.AppleMusicControl"
    )
    private let controlLifecycleGate = AppleMusicControlLifecycleGate()
    private var artworkFetchTask: Task<Void, Never>?
    private var artworkFetchIdentity: MusicTrackIdentity?
    private var artworkFetchGeneration: UInt64 = 0
    private var artworkRecoveryState = AppleMusicArtworkRecoveryState()
    private var nativeArtworkPrefetchTask: Task<Void, Never>?
    private var nativeArtworkPrefetchRequest: AppleMusicArtworkBridgeRequest?
    private var nativeArtworkPrefetchGeneration: UInt64 = 0
    private var nativeArtworkPrefetchFallbackSignature: String?
    private var catalogPrefetchTask: Task<Void, Never>?
    private var catalogPrefetchGeneration: UInt64 = 0
    private var catalogPrefetchFallbackSignature: String?
    private var catalogPrefetchRequestStarted = false
    private var catalogPrefetchFailure: (
        fallbackSignature: String,
        retryAfter: Date
    )?
    private var pendingNativeArtwork: (identity: MusicTrackIdentity, data: Data)?
    private var pendingCatalogArtwork: (fallbackSignature: String, data: Data)?

    init(
        artworkLoader: AppleMusicArtworkLoading? = nil,
        transitionTimeline: AppleMusicTransitionTimeline? = nil
    ) {
        self.transitionTimeline = transitionTimeline
            ?? AppleMusicTransitionTimeline()
        self.artworkLoader = artworkLoader ?? {
            processIdentifier,
            observation,
            nativeArtworkAlreadyChecked in
            await AppleMusicArtworkLoader.load(
                processIdentifier: processIdentifier,
                observation: observation,
                nativeArtworkAlreadyChecked: nativeArtworkAlreadyChecked
            )
        }
    }

    func start(
        onInvalidation: @escaping @MainActor @Sendable (
            MusicAdapterInvalidation
        ) -> Void
    ) {
        stop()
        observationGeneration &+= 1
        let generation = observationGeneration
        controlLifecycleGate.activate()
        invalidationHandler = onInvalidation
        notificationToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let candidate = AppleMusicPlayerInfoCandidate(
                userInfo: notification.userInfo
            )
            let receivedAt = Date()
            let receivedUptime = ProcessInfo.processInfo.systemUptime
            Task { @MainActor in
                guard let self,
                      generation == self.observationGeneration else { return }
                if let candidate {
                    self.transitionTimeline.notePlayerInfo(
                        candidateSignature: candidate.fallbackSignature,
                        detail: "track=\(candidate.title) artist=\(candidate.artist) album=\(candidate.album ?? "")",
                        observedAt: receivedAt,
                        observedUptime: receivedUptime
                    )
                    if self.artworkRecoveryState.route(
                        for: candidate.fallbackSignature
                    ) == .catalog {
                        self.cancelNativeArtworkPrefetch(clearPending: true)
                        self.scheduleCatalogPrefetch(for: candidate)
                    } else {
                        _ = self.scheduleNativeArtworkPrefetch(for: candidate)
                    }
                } else {
                    self.transitionTimeline.notePlayerInfo(
                        candidateSignature: nil,
                        detail: "candidate=unavailable",
                        observedAt: receivedAt,
                        observedUptime: receivedUptime
                    )
                }
                self.playerInfoDebounceTask?.cancel()
                self.playerInfoDebounceTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    guard !Task.isCancelled,
                          let self,
                          generation == self.observationGeneration else { return }
                    self.invalidationHandler?(.sourceChanged)
                }
            }
        }
    }

    func stop() {
        observationGeneration &+= 1
        controlLifecycleGate.deactivate()
        if let notificationToken {
            DistributedNotificationCenter.default().removeObserver(notificationToken)
        }
        notificationToken = nil
        playerInfoDebounceTask?.cancel()
        playerInfoDebounceTask = nil
        artworkRecoveryState.reset()
        catalogPrefetchFailure = nil
        cancelNativeArtworkPrefetch(clearPending: true)
        cancelCatalogPrefetch(clearPending: true)
        cancelArtworkFetch()
        artworkReuseCache.reset()
        lastObservation = nil
        lastInstance = nil
        lastSnapshot = nil
        invalidationHandler = nil
    }

    func snapshot(refresh: MusicSnapshotRefresh) async -> MusicAppSnapshot {
        let checkedAt = Date()
        let lifecycleGeneration = observationGeneration
        guard let app = runningApplication() else {
            cancelArtworkFetch()
            cancelNativeArtworkPrefetch(clearPending: true)
            cancelCatalogPrefetch(clearPending: true)
            lastObservation = nil
            lastInstance = nil
            lastSnapshot = nil
            return unavailableSnapshot(
                availability: .notRunning,
                checkedAt: checkedAt,
                diagnostic: "Apple Music 未运行；顶屿不会自动启动它。"
            )
        }

        let instance = MusicAppInstance(
            app: descriptor,
            processIdentifier: app.processIdentifier,
            launchedAt: app.launchDate
        )
        if case .cached = refresh {
            guard lastInstance == instance,
                  let lastSnapshot else {
                return unavailableSnapshot(
                    instance: instance,
                    availability: .degraded(reason: "Apple Music 尚无缓存快照。"),
                    checkedAt: checkedAt,
                    diagnostic: "Apple Music 尚无缓存快照；本次未发送 Apple Event。"
                )
            }
            return lastSnapshot
        }
        let access = Self.automationAccess(
            prompt: false,
            processIdentifier: app.processIdentifier
        )
        guard access == .allowed else {
            return unavailableSnapshot(
                instance: instance,
                availability: .permissionRequired(permission: "自动化 - Apple Music"),
                checkedAt: checkedAt,
                diagnostic: "Apple Music 自动化状态：\(access.displayName)。"
            )
        }

        let processIdentifier = app.processIdentifier
        let includeArtwork: Bool
        let nativeRecoverySignature: String?
        if case .metadata = refresh {
            // Ordinary metadata must never wait on a radio artwork Apple Event.
            // A direct artwork read is only folded into metadata for the single
            // bounded native-recovery attempt after both async paths fail.
            nativeRecoverySignature = artworkRecoveryState
                .consumeNativeRecoverySignature()
            includeArtwork = AppleMusicMetadataArtworkPolicy
                .shouldIncludeArtwork(
                    nativeRecoverySignature: nativeRecoverySignature
                )
        } else {
            includeArtwork = false
            nativeRecoverySignature = nil
        }
        let refreshLabel: String
        switch refresh {
        case .cached:
            refreshLabel = "cached"
        case .metadata:
            refreshLabel = "metadata"
        case .timeline:
            refreshLabel = "timeline"
        }
        transitionTimeline.record(
            .metadataReadStarted,
            detail: "refresh=\(refreshLabel) includeArtwork=\(includeArtwork)"
        )
        let metadataStartedUptime = ProcessInfo.processInfo.systemUptime
        let result = await Task.detached(priority: .userInitiated) {
            AppleMusicBridgeRunner.readObservation(
                processIdentifier: processIdentifier,
                includeArtwork: includeArtwork
            )
        }.value
        let metadataDurationMilliseconds = Int(
            ((ProcessInfo.processInfo.systemUptime - metadataStartedUptime) * 1_000)
                .rounded()
        )
        switch result {
        case let .failure(error):
            transitionTimeline.record(
                .metadataReadCompleted,
                detail: "refresh=\(refreshLabel) result=failure durationMs=\(metadataDurationMilliseconds) error=\(error.diagnostic)"
            )
        case let .success(observation):
            transitionTimeline.record(
                .metadataReadCompleted,
                detail: "refresh=\(refreshLabel) result=success durationMs=\(metadataDurationMilliseconds) track=\(observation.title ?? "") artist=\(observation.artist ?? "") artworkBytes=\(observation.artworkData?.count ?? 0)"
            )
        }
        guard lifecycleGeneration == observationGeneration else {
            return unavailableSnapshot(
                availability: .unavailable(reason: "Apple Music 适配生命周期已变化。"),
                checkedAt: checkedAt,
                diagnostic: "Apple Music 读取期间适配已停止或重启，已丢弃迟到结果。"
            )
        }
        switch result {
        case let .failure(error):
            return unavailableSnapshot(
                instance: instance,
                availability: .degraded(reason: error.diagnostic),
                checkedAt: checkedAt,
                diagnostic: error.diagnostic
            )
        case let .success(observation):
            var resolvedObservation = observation
            if observation.artworkData == nil,
               let reusedArtwork = artworkReuseCache.data(for: observation) {
                resolvedObservation = observation.withArtworkData(reusedArtwork)
            }
            if let identity = observation.trackIdentity {
                if let artworkData = resolvedObservation.artworkData {
                    _ = artworkCache.store(
                        artworkData,
                        for: identity,
                        at: checkedAt
                    )
                    artworkRecoveryState.recordArtworkSuccess(
                        for: identity.fallbackSignature
                    )
                    cancelNativeArtworkPrefetch(clearPending: true)
                    cancelCatalogPrefetch(clearPending: true)
                } else if let pendingNativeArtwork,
                          pendingNativeArtwork.identity == identity {
                    _ = artworkCache.store(
                        pendingNativeArtwork.data,
                        for: identity,
                        at: checkedAt
                    )
                    resolvedObservation = observation.withArtworkData(
                        pendingNativeArtwork.data
                    )
                    self.pendingNativeArtwork = nil
                } else if let pendingCatalogArtwork,
                          pendingCatalogArtwork.fallbackSignature
                            == identity.fallbackSignature {
                    _ = artworkCache.store(
                        pendingCatalogArtwork.data,
                        for: identity,
                        at: checkedAt
                    )
                    resolvedObservation = observation.withArtworkData(
                        pendingCatalogArtwork.data
                    )
                    self.pendingCatalogArtwork = nil
                } else if let artworkData = artworkCache.data(for: identity) {
                    resolvedObservation = observation.withArtworkData(artworkData)
                }
            }
            if let artworkData = resolvedObservation.artworkData {
                artworkReuseCache.remember(
                    artworkData,
                    for: resolvedObservation
                )
            }
            guard runningApplication()?.processIdentifier == processIdentifier else {
                return unavailableSnapshot(
                    availability: .notRunning,
                    checkedAt: checkedAt,
                    diagnostic: "Apple Music 应用实例在读取过程中发生变化。"
                )
            }
            if resolvedObservation != lastObservation {
                revision &+= 1
                lastObservation = resolvedObservation
            }
            lastInstance = instance
            if includeArtwork {
                _ = artworkRecoveryState.recordMetadataResult(
                    resolvedObservation,
                    artworkRequested: true,
                    nativeRecoverySignature: nativeRecoverySignature
                )
            }
            if case .metadata = refresh {
                if resolvedObservation.artworkData == nil,
                   let candidate = AppleMusicPlayerInfoCandidate(
                       observation: resolvedObservation
                   ) {
                    switch artworkRecoveryState.route(
                        for: candidate.fallbackSignature
                    ) {
                    case .native:
                        _ = scheduleNativeArtworkPrefetch(for: candidate)
                    case .catalog:
                        scheduleCatalogPrefetch(for: candidate)
                    }
                } else {
                    scheduleArtworkFetch(
                        for: observation,
                        instance: instance,
                        processIdentifier: processIdentifier,
                        nativeArtworkAlreadyChecked: includeArtwork,
                        at: checkedAt
                    )
                }
            }
            let snapshot = readySnapshot(
                observation: resolvedObservation,
                instance: instance,
                checkedAt: checkedAt
            )
            lastSnapshot = snapshot
            return snapshot
        }
    }

    func perform(_ request: MusicControlRequest) async -> MusicControlResult {
        guard let lifecycleToken = controlLifecycleGate.token(),
              request.target.app.bundleIdentifier == descriptor.bundleIdentifier,
              let app = runningApplication(),
              app.processIdentifier == request.target.processIdentifier else {
            return MusicControlResult(
                requestID: request.id,
                disposition: .rejected,
                diagnostic: "Apple Music 应用实例已变化，未发送控制。"
            )
        }
        let processIdentifier = request.target.processIdentifier
        guard Self.automationAccess(
            prompt: false,
            processIdentifier: processIdentifier
        ) == .allowed else {
            return MusicControlResult(
                requestID: request.id,
                disposition: .rejected,
                diagnostic: "Apple Music 自动化权限不可用，未发送控制。"
            )
        }

        let action = request.action
        let expectedTrack = request.expectedTrack
        let controlQueue = controlQueue
        let controlLifecycleGate = controlLifecycleGate
        let result: Result<Void, AppleMusicBridgeFailure> = await withCheckedContinuation {
            continuation in
            controlQueue.async {
                guard controlLifecycleGate.isValid(lifecycleToken) else {
                    continuation.resume(returning: .failure(AppleMusicBridgeFailure(
                        diagnostic: "Apple Music 适配已关闭，未发送排队中的控制。"
                    )))
                    return
                }
                continuation.resume(returning: AppleMusicBridgeRunner.perform(
                    processIdentifier: processIdentifier,
                    action: action,
                    expectedTrack: expectedTrack
                ))
            }
        }
        switch result {
        case let .failure(error):
            return MusicControlResult(
                requestID: request.id,
                disposition: .failed,
                diagnostic: error.diagnostic
            )
        case .success:
            return MusicControlResult(
                requestID: request.id,
                disposition: .accepted,
                diagnostic: "Apple Music 已接受定向控制，等待新快照确认。"
            )
        }
    }

    static func automationAccess(prompt: Bool) -> AppleMusicAutomationAccess {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
        ).first else {
            return .targetNotRunning
        }
        return automationAccess(
            prompt: prompt,
            processIdentifier: app.processIdentifier
        )
    }

    private static func automationAccess(
        prompt: Bool,
        processIdentifier: pid_t
    ) -> AppleMusicAutomationAccess {
        var target = AEAddressDesc()
        var targetProcessIdentifier = processIdentifier
        let createStatus = withUnsafeBytes(of: &targetProcessIdentifier) { bytes in
            AECreateDesc(
                DescType(typeKernelProcessID),
                bytes.baseAddress,
                bytes.count,
                &target
            )
        }
        guard createStatus == noErr else {
            return .unavailable(status: OSStatus(createStatus))
        }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            prompt
        )
        return automationAccess(for: status)
    }

    nonisolated static func automationAccess(for status: OSStatus) -> AppleMusicAutomationAccess {
        switch status {
        case noErr:
            return .allowed
        case -600:
            return .targetNotRunning
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .consentRequired
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .unavailable(status: status)
        }
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
        ).isEmpty
    }

    private func runningApplication() -> NSRunningApplication? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: descriptor.bundleIdentifier)
            .first
    }

    private func scheduleNativeArtworkPrefetch(
        for candidate: AppleMusicPlayerInfoCandidate
    ) -> Bool {
        if artworkReuseCache.data(for: candidate.observation) != nil {
            return true
        }
        if let identity = lastObservation?.trackIdentity,
           identity.fallbackSignature == candidate.fallbackSignature,
           artworkCache.data(for: identity) != nil {
            return true
        }
        if pendingNativeArtwork?.identity.fallbackSignature
            == candidate.fallbackSignature {
            return true
        }
        if nativeArtworkPrefetchFallbackSignature == candidate.fallbackSignature,
           nativeArtworkPrefetchTask != nil {
            return true
        }
        if artworkFetchIdentity?.fallbackSignature == candidate.fallbackSignature,
           artworkFetchTask != nil {
            return true
        }
        if catalogPrefetchFallbackSignature == candidate.fallbackSignature,
           catalogPrefetchTask != nil {
            return true
        }
        guard let app = runningApplication(),
              Self.automationAccess(
                prompt: false,
                processIdentifier: app.processIdentifier
              ) == .allowed else {
            return false
        }

        cancelNativeArtworkPrefetch(clearPending: true)
        cancelCatalogPrefetch(clearPending: true)
        nativeArtworkPrefetchGeneration &+= 1
        let generation = nativeArtworkPrefetchGeneration
        let fallbackSignature = candidate.fallbackSignature
        let processIdentifier = app.processIdentifier
        let request = AppleMusicArtworkBridgeRequest()
        let startedUptime = ProcessInfo.processInfo.systemUptime
        nativeArtworkPrefetchRequest = request
        nativeArtworkPrefetchFallbackSignature = fallbackSignature
        transitionTimeline.record(
            .artworkReadStarted,
            detail: "mechanism=native track=\(candidate.title) artist=\(candidate.artist)"
        )
        nativeArtworkPrefetchTask = Task(priority: .userInitiated) { [weak self] in
            let result = await withTaskCancellationHandler {
                await AppleMusicArtworkBridgeExecutor.shared.readObservation(
                    processIdentifier: processIdentifier,
                    request: request
                )
            } onCancel: {
                request.cancel()
            }
            guard !Task.isCancelled,
                  let self,
                  generation == self.nativeArtworkPrefetchGeneration else {
                return
            }
            self.finishNativeArtworkPrefetch(
                result,
                candidate: candidate,
                processIdentifier: processIdentifier,
                generation: generation,
                startedUptime: startedUptime
            )
        }
        scheduleCatalogPrefetch(
            for: candidate,
            delayNanoseconds: AppleMusicArtworkPrefetchPolicy
                .catalogHedgeDelayNanoseconds,
            allowWhileNativePrefetching: true
        )
        return true
    }

    private func finishNativeArtworkPrefetch(
        _ result: Result<AppleMusicObservation, AppleMusicBridgeFailure>?,
        candidate: AppleMusicPlayerInfoCandidate,
        processIdentifier: pid_t,
        generation: UInt64,
        startedUptime: TimeInterval
    ) {
        guard generation == nativeArtworkPrefetchGeneration else { return }
        nativeArtworkPrefetchTask = nil
        nativeArtworkPrefetchRequest = nil
        nativeArtworkPrefetchFallbackSignature = nil
        let durationMilliseconds = Int(
            ((ProcessInfo.processInfo.systemUptime - startedUptime) * 1_000)
                .rounded()
        )

        guard runningApplication()?.processIdentifier == processIdentifier,
              let result,
              case let .success(observation) = result,
              observation.trackIdentity?.fallbackSignature
                == candidate.fallbackSignature else {
            transitionTimeline.record(
                .artworkReadCompleted,
                detail: "mechanism=native result=stale-or-failure durationMs=\(durationMilliseconds)"
            )
            invalidationHandler?(.sourceChanged)
            return
        }
        guard let identity = observation.trackIdentity,
              let artworkData = observation.artworkData else {
            transitionTimeline.record(
                .artworkReadCompleted,
                detail: "mechanism=native result=no-artwork durationMs=\(durationMilliseconds)"
            )
            if artworkRecoveryState.recordNativePrefetchMiss(
                for: candidate.fallbackSignature
            ) {
                scheduleCatalogPrefetch(for: candidate)
            }
            return
        }
        transitionTimeline.record(
            .artworkReadCompleted,
            detail: "mechanism=native result=success durationMs=\(durationMilliseconds) artworkBytes=\(artworkData.count)"
        )
        cancelCatalogPrefetch(clearPending: true)
        artworkRecoveryState.recordArtworkSuccess(
            for: identity.fallbackSignature
        )
        if !applyPrefetchedArtwork(
            artworkData,
            identity: identity,
            at: Date()
        ) {
            pendingNativeArtwork = (
                identity: identity,
                data: artworkData
            )
        }
    }

    private func cancelNativeArtworkPrefetch(clearPending: Bool) {
        nativeArtworkPrefetchGeneration &+= 1
        nativeArtworkPrefetchRequest?.cancel()
        nativeArtworkPrefetchTask?.cancel()
        nativeArtworkPrefetchTask = nil
        nativeArtworkPrefetchRequest = nil
        nativeArtworkPrefetchFallbackSignature = nil
        if clearPending {
            pendingNativeArtwork = nil
        }
    }

    private func scheduleCatalogPrefetch(
        for candidate: AppleMusicPlayerInfoCandidate,
        delayNanoseconds: UInt64 = 0,
        allowWhileNativePrefetching: Bool = false
    ) {
        let now = Date()
        if let catalogPrefetchFailure,
           catalogPrefetchFailure.fallbackSignature == candidate.fallbackSignature,
           now < catalogPrefetchFailure.retryAfter {
            return
        }
        if let identity = lastObservation?.trackIdentity,
           identity.fallbackSignature == candidate.fallbackSignature {
            if artworkCache.data(for: identity) != nil
                || !artworkCache.shouldFetch(for: identity, at: now) {
                return
            }
        }
        if pendingCatalogArtwork?.fallbackSignature == candidate.fallbackSignature {
            return
        }
        if catalogPrefetchFallbackSignature == candidate.fallbackSignature,
           catalogPrefetchTask != nil {
            if delayNanoseconds == 0,
               !catalogPrefetchRequestStarted {
                cancelCatalogPrefetch(clearPending: true)
            } else {
                return
            }
        }
        if artworkFetchIdentity?.fallbackSignature == candidate.fallbackSignature,
           artworkFetchTask != nil {
            return
        }
        if nativeArtworkPrefetchFallbackSignature == candidate.fallbackSignature,
           nativeArtworkPrefetchTask != nil,
           !allowWhileNativePrefetching {
            return
        }
        cancelCatalogPrefetch(clearPending: true)
        catalogPrefetchGeneration &+= 1
        let generation = catalogPrefetchGeneration
        let fallbackSignature = candidate.fallbackSignature
        catalogPrefetchFallbackSignature = fallbackSignature
        catalogPrefetchRequestStarted = false
        catalogPrefetchTask = Task(priority: .utility) { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled,
                  let self,
                  generation == self.catalogPrefetchGeneration else {
                return
            }
            let startedUptime = ProcessInfo.processInfo.systemUptime
            self.catalogPrefetchRequestStarted = true
            self.transitionTimeline.record(
                .artworkReadStarted,
                detail: "mechanism=catalog hedgeDelayMs=\(delayNanoseconds / 1_000_000) track=\(candidate.title) artist=\(candidate.artist)"
            )
            let result = await AppleMusicCatalogArtworkResolver().artworkData(
                for: candidate.observation
            )
            guard !Task.isCancelled,
                  generation == self.catalogPrefetchGeneration else {
                return
            }
            self.finishCatalogPrefetch(
                result,
                fallbackSignature: fallbackSignature,
                generation: generation,
                startedUptime: startedUptime
            )
        }
    }

    private func finishCatalogPrefetch(
        _ result: AppleMusicCatalogArtworkResult,
        fallbackSignature: String,
        generation: UInt64,
        startedUptime: TimeInterval
    ) {
        guard generation == catalogPrefetchGeneration else { return }
        catalogPrefetchTask = nil
        catalogPrefetchFallbackSignature = nil
        catalogPrefetchRequestStarted = false
        let completedAt = Date()
        let durationMilliseconds = Int(
            ((ProcessInfo.processInfo.systemUptime - startedUptime) * 1_000)
                .rounded()
        )

        switch result {
        case .notFound:
            transitionTimeline.record(
                .artworkReadCompleted,
                detail: "mechanism=catalog result=not-found durationMs=\(durationMilliseconds)"
            )
            catalogPrefetchFailure = (
                fallbackSignature: fallbackSignature,
                retryAfter: completedAt.addingTimeInterval(5 * 60)
            )
        case .transientFailure:
            transitionTimeline.record(
                .artworkReadCompleted,
                detail: "mechanism=catalog result=transient-failure durationMs=\(durationMilliseconds)"
            )
            catalogPrefetchFailure = (
                fallbackSignature: fallbackSignature,
                retryAfter: completedAt.addingTimeInterval(30)
            )
        case let .success(data):
            transitionTimeline.record(
                .artworkReadCompleted,
                detail: "mechanism=catalog result=success durationMs=\(durationMilliseconds) artworkBytes=\(data.count)"
            )
            cancelNativeArtworkPrefetch(clearPending: true)
            if catalogPrefetchFailure?.fallbackSignature == fallbackSignature {
                catalogPrefetchFailure = nil
            }
        }

        guard let identity = lastObservation?.trackIdentity,
              identity.fallbackSignature == fallbackSignature else {
            if case let .success(data) = result {
                pendingCatalogArtwork = (
                    fallbackSignature: fallbackSignature,
                    data: data
                )
            }
            return
        }
        switch result {
        case .notFound:
            artworkCache.recordFailure(
                .notFound,
                for: identity,
                at: completedAt
            )
            if !isNativeArtworkPrefetchActive(for: fallbackSignature) {
                scheduleNativeArtworkRecoveryIfNeeded(
                    fallbackSignature: fallbackSignature,
                    identity: identity
                )
            }
        case .transientFailure:
            artworkCache.recordFailure(
                .transient,
                for: identity,
                at: completedAt
            )
            if !isNativeArtworkPrefetchActive(for: fallbackSignature) {
                scheduleNativeArtworkRecoveryIfNeeded(
                    fallbackSignature: fallbackSignature,
                    identity: identity
                )
            }
        case let .success(data):
            artworkRecoveryState.recordArtworkSuccess(
                for: fallbackSignature
            )
            guard applyPrefetchedArtwork(
                data,
                identity: identity,
                at: completedAt
            ) else {
                return
            }
            pendingCatalogArtwork = nil
        }
    }

    private func isNativeArtworkPrefetchActive(
        for fallbackSignature: String
    ) -> Bool {
        nativeArtworkPrefetchTask != nil
            && nativeArtworkPrefetchFallbackSignature == fallbackSignature
    }

    private func scheduleNativeArtworkRecoveryIfNeeded(
        fallbackSignature: String,
        identity: MusicTrackIdentity
    ) {
        guard artworkRecoveryState.scheduleNativeRecoveryAfterCatalogFailure(
            fallbackSignature: fallbackSignature,
            currentIdentity: identity
        ) else {
            return
        }
        invalidationHandler?(.sourceChanged)
    }

    private func applyPrefetchedArtwork(
        _ data: Data,
        identity: MusicTrackIdentity,
        at completedAt: Date
    ) -> Bool {
        guard lastObservation?.trackIdentity == identity,
              let instance = lastInstance,
              runningApplication()?.processIdentifier == instance.processIdentifier,
              artworkCache.store(data, for: identity, at: completedAt),
              let lastObservation,
              let lastSnapshot,
              let updatedSnapshot = appleMusicSnapshotByReplacingArtworkData(
                lastSnapshot,
                artworkData: data,
                identity: identity,
                revision: revision &+ 1
              ) else {
            return false
        }
        self.lastObservation = lastObservation.withArtworkData(data)
        artworkReuseCache.remember(data, for: lastObservation)
        revision &+= 1
        self.lastSnapshot = updatedSnapshot
        invalidationHandler?(.cachedDataChanged)
        return true
    }

    private func cancelCatalogPrefetch(clearPending: Bool) {
        catalogPrefetchGeneration &+= 1
        catalogPrefetchTask?.cancel()
        catalogPrefetchTask = nil
        catalogPrefetchFallbackSignature = nil
        catalogPrefetchRequestStarted = false
        if clearPending {
            pendingCatalogArtwork = nil
        }
    }

    private func scheduleArtworkFetch(
        for observation: AppleMusicObservation,
        instance: MusicAppInstance,
        processIdentifier: pid_t,
        nativeArtworkAlreadyChecked: Bool,
        at now: Date
    ) {
        guard let identity = observation.trackIdentity,
              artworkCache.data(for: identity) == nil,
              artworkCache.shouldFetch(for: identity, at: now) else {
            return
        }
        if artworkFetchIdentity == identity,
           artworkFetchTask != nil {
            return
        }
        if catalogPrefetchFallbackSignature == identity.fallbackSignature,
           catalogPrefetchTask != nil {
            return
        }
        if nativeArtworkPrefetchFallbackSignature == identity.fallbackSignature,
           nativeArtworkPrefetchTask != nil {
            return
        }

        cancelArtworkFetch()
        artworkCache.recordAttempt(for: identity, at: now)
        artworkFetchGeneration &+= 1
        let generation = artworkFetchGeneration
        artworkFetchIdentity = identity
        let artworkLoader = artworkLoader
        transitionTimeline.record(
            .artworkReadStarted,
            detail: "mechanism=fallback track=\(observation.title ?? "") artist=\(observation.artist ?? "") nativeChecked=\(nativeArtworkAlreadyChecked)"
        )
        artworkFetchTask = Task(priority: .utility) { [weak self] in
            let result = await artworkLoader(
                processIdentifier,
                observation,
                nativeArtworkAlreadyChecked
            )
            guard !Task.isCancelled,
                  let self,
                  generation == self.artworkFetchGeneration else {
                return
            }
            self.finishArtworkFetch(
                result,
                identity: identity,
                instance: instance,
                generation: generation
            )
        }
    }

    private func finishArtworkFetch(
        _ result: AppleMusicArtworkLoadResult,
        identity: MusicTrackIdentity,
        instance: MusicAppInstance,
        generation: UInt64
    ) {
        guard generation == artworkFetchGeneration else { return }
        artworkFetchTask = nil
        artworkFetchIdentity = nil
        guard lastInstance == instance,
              runningApplication()?.processIdentifier == instance.processIdentifier,
              lastObservation?.trackIdentity == identity else {
            return
        }
        let completedAt = Date()
        switch result {
        case .notFound:
            transitionTimeline.record(
                .artworkReadCompleted,
                detail: "mechanism=fallback result=not-found"
            )
            artworkCache.recordFailure(
                .notFound,
                for: identity,
                at: completedAt
            )
            return
        case .transientFailure:
            transitionTimeline.record(
                .artworkReadCompleted,
                detail: "mechanism=fallback result=transient-failure"
            )
            artworkCache.recordFailure(
                .transient,
                for: identity,
                at: completedAt
            )
            return
        case let .success(data):
            transitionTimeline.record(
                .artworkReadCompleted,
                detail: "mechanism=fallback result=success artworkBytes=\(data.count)"
            )
            guard artworkCache.store(data, for: identity, at: completedAt) else {
                artworkCache.recordFailure(
                    .transient,
                    for: identity,
                    at: completedAt
                )
                return
            }
        }
        guard let artworkData = artworkCache.data(for: identity),
              let lastObservation,
              lastObservation.artworkData != artworkData,
              let lastSnapshot,
              let updatedSnapshot = appleMusicSnapshotByReplacingArtworkData(
                lastSnapshot,
                artworkData: artworkData,
                identity: identity,
                revision: revision &+ 1
              ) else {
            return
        }
        self.lastObservation = lastObservation.withArtworkData(artworkData)
        artworkReuseCache.remember(artworkData, for: lastObservation)
        revision &+= 1
        self.lastSnapshot = updatedSnapshot
        invalidationHandler?(.cachedDataChanged)
    }

    private func cancelArtworkFetch() {
        artworkFetchGeneration &+= 1
        artworkFetchTask?.cancel()
        artworkFetchTask = nil
        artworkFetchIdentity = nil
    }

    private func readySnapshot(
        observation: AppleMusicObservation,
        instance: MusicAppInstance,
        checkedAt: Date
    ) -> MusicAppSnapshot {
        let track = observation.trackIdentity.map { identity in
            MusicTrackSnapshot(
                identity: identity,
                title: observation.title ?? "Apple Music",
                artist: observation.artist,
                album: observation.album,
                artworkData: observation.artworkData,
                lyrics: []
            )
        }
        let timeline: MusicTimelineSnapshot?
        if let elapsedTime = observation.elapsedTime,
           let duration = observation.duration {
            timeline = MusicTimelineSnapshot(
                elapsedTime: min(max(elapsedTime, 0), duration),
                duration: duration,
                playbackRate: observation.state == .playing ? 1 : 0,
                observedAt: checkedAt
            )
        } else {
            timeline = nil
        }
        let verifiedAt = checkedAt
        let readyControl = MusicControlCapability.ready(
            target: instance,
            mechanism: .appleEvent,
            verifiedAt: verifiedAt
        )
        var controlValues: [MusicControlKind: MusicControlCapability] = [
            .playPause: readyControl
        ]
        if track != nil {
            controlValues[.previousTrack] = readyControl
            controlValues[.nextTrack] = readyControl
        }
        if observation.persistentIdentifier != nil,
           timeline != nil {
            controlValues[.absoluteSeek] = readyControl
        }
        let controls = MusicControlCapabilities(values: controlValues)
        return MusicAppSnapshot(
            descriptor: descriptor,
            instance: instance,
            availability: .ready,
            track: track,
            playbackState: observation.state,
            timeline: timeline,
            controls: controls,
            revision: revision,
            provenance: MusicSnapshotProvenance(
                bundleIdentifier: descriptor.bundleIdentifier,
                mechanisms: [.appleEvent]
            ),
            checkedAt: checkedAt,
            diagnostic: "已通过定向 Apple Event 读取 Apple Music；封面 \(track?.artworkData.map { "\($0.count) bytes" } ?? "暂未提供")。"
        )
    }

    private func unavailableSnapshot(
        instance: MusicAppInstance? = nil,
        availability: MusicAppAvailability,
        checkedAt: Date,
        diagnostic: String
    ) -> MusicAppSnapshot {
        MusicAppSnapshot(
            descriptor: descriptor,
            instance: instance,
            availability: availability,
            track: nil,
            playbackState: .unknown,
            timeline: nil,
            controls: .none,
            revision: revision,
            provenance: MusicSnapshotProvenance(
                bundleIdentifier: descriptor.bundleIdentifier,
                mechanisms: [.appleEvent]
            ),
            checkedAt: checkedAt,
            diagnostic: diagnostic
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

import AppKit
import ApplicationServices
import Foundation

enum NeteaseMusicRefreshRetryPolicy {
    static let delaysNanoseconds: [UInt64] = [
        350_000_000,
        700_000_000,
        1_200_000_000
    ]

    static func nextDelay(
        afterFailedAttempt attempt: Int,
        appIsRunning: Bool,
        availability: MusicAppAvailability
    ) -> UInt64? {
        guard appIsRunning, delaysNanoseconds.indices.contains(attempt) else { return nil }
        switch availability {
        case .notRunning, .degraded:
            return delaysNanoseconds[attempt]
        case .ready, .permissionRequired, .unavailable:
            return nil
        }
    }
}

@MainActor
final class NeteaseMusicAppAdapter: MusicAppAdapter {
    nonisolated private static let transitionPlaybackConfirmationInterval: TimeInterval = 2.2
    private static let postRebindVerificationDelays: [UInt64] = [
        200_000_000,
        500_000_000,
        1_000_000_000
    ]

    private struct PendingTrackTransition {
        let baselineIdentity: String
        let baselineDescriptiveIdentity: String
        let baselineArtworkData: Data?
        let expectedPlaybackState: MusicPlaybackState
        let issuedAt: Date
    }

    private struct PendingPlaybackExpectation {
        let trackIdentity: MusicTrackIdentity
        let targetState: MusicPlaybackState
        let anchorElapsedTime: TimeInterval?
        let issuedAt: Date
    }

    let descriptor = MusicAdapterRegistry.neteaseMusic.descriptor

    private let runningInstancesProvider: @Sendable () -> [MusicAppInstance]
    private let bridge: MediaRemoteClientBridge
    private let payloadReaderForTesting: (
        @MainActor @Sendable (Bool) async -> MediaRemoteClientPayload?
    )?
    private let semanticController = NeteaseMusicSemanticAXController()
    private var invalidationHandler: (@MainActor @Sendable (MusicAdapterInvalidation) -> Void)?
    private var latestSnapshot: MusicAppSnapshot?
    private var metadataRefreshTask: Task<Void, Never>?
    private var metadataRefreshGeneration: UInt64 = 0
    private var pendingMetadataIdentity: String?
    private var pendingTrackTransition: PendingTrackTransition?
    private var pendingPlaybackExpectation: PendingPlaybackExpectation?
    private var bridgeNeedsRunningInstanceRebind = false
    private var postRebindVerificationAttempt: Int?
    private var revision: UInt64 = 0
    private var artworkCache: [String: Data] = [:]
    private var artworkCacheOrder: [String] = []

    init(
        runningInstancesProvider: @escaping @Sendable () -> [MusicAppInstance] = {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier
            )
            .filter { !$0.isTerminated }
            .map {
                MusicAppInstance(
                    app: MusicAdapterRegistry.neteaseMusic.descriptor,
                    processIdentifier: $0.processIdentifier,
                    launchedAt: $0.launchDate
                )
            }
        },
        payloadReaderForTesting: (
            @MainActor @Sendable (Bool) async -> MediaRemoteClientPayload?
        )? = nil
    ) {
        self.runningInstancesProvider = runningInstancesProvider
        self.payloadReaderForTesting = payloadReaderForTesting
        bridge = MediaRemoteClientBridge(
            bundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier,
            runningProcessIdentifiersProvider: {
                Set(runningInstancesProvider().map(\.processIdentifier))
            }
        )
    }

    func start(
        onInvalidation: @escaping @MainActor @Sendable (
            MusicAdapterInvalidation
        ) -> Void
    ) {
        invalidationHandler = onInvalidation
        if payloadReaderForTesting == nil {
            startBridge()
            scheduleMetadataRefresh(candidate: nil)
        }
    }

    func stop() {
        metadataRefreshGeneration &+= 1
        metadataRefreshTask?.cancel()
        metadataRefreshTask = nil
        pendingMetadataIdentity = nil
        pendingTrackTransition = nil
        pendingPlaybackExpectation = nil
        bridgeNeedsRunningInstanceRebind = false
        postRebindVerificationAttempt = nil
        bridge.stop()
        invalidationHandler = nil
        latestSnapshot = nil
    }

    func snapshot(refresh: MusicSnapshotRefresh) async -> MusicAppSnapshot {
        guard let instance = currentInstance() else {
            return notRunningSnapshot()
        }
        if refresh == .cached,
           let latestSnapshot,
           latestSnapshot.instance == instance {
            return latestSnapshot
        }
        if pendingTrackTransition != nil,
           let latestSnapshot,
           latestSnapshot.instance == instance {
            return latestSnapshot
        }
        let payload = await readPayload(includeArtwork: refresh == .metadata)
        guard let payload,
              payload.processIdentifier == instance.processIdentifier else {
            if let latestSnapshot, latestSnapshot.instance == instance {
                return latestSnapshot
            }
            return degradedSnapshot(
                instance: instance,
                diagnostic: "网易云音乐专属状态暂未返回。"
            )
        }
        let didRebindBridge = completeBridgeRebindIfNeeded()
        if refresh == .timeline,
           let latestSnapshot,
           latestSnapshot.instance == instance,
           latestSnapshot.track?.identity.fallbackSignature != payload.stableTrackSignature {
            scheduleMetadataRefresh(candidate: payload)
            return latestSnapshot
        }
        let snapshot = apply(payload, existingArtwork: cachedArtwork(for: payload))
        if didRebindBridge {
            scheduleNextPostRebindVerification()
        }
        return snapshot
    }

    func perform(_ request: MusicControlRequest) async -> MusicControlResult {
        guard let instance = currentInstance(), instance == request.target else {
            return controlResult(
                request,
                disposition: .rejected,
                diagnostic: "网易云音乐控制目标进程已失效。"
            )
        }
        guard let snapshot = latestSnapshot,
              snapshot.instance == instance,
              request.expectedTrack == nil || snapshot.track?.identity == request.expectedTrack else {
            return controlResult(
                request,
                disposition: .rejected,
                diagnostic: "网易云音乐当前歌曲已变化，旧控制请求已取消。"
            )
        }
        if case .seekNormalized = request.action {
            return controlResult(
                request,
                disposition: .rejected,
                diagnostic: "网易云音乐 Alpha 暂不提供定向进度跳转。"
            )
        }

        let controller = semanticController
        let action = request.action
        let processIdentifier = instance.processIdentifier
        let result = await Task.detached(priority: .userInitiated) {
            controller.perform(action, processIdentifier: processIdentifier)
        }.value
        guard result.didPress else {
            return controlResult(
                request,
                disposition: .failed,
                diagnostic: result.diagnostic
            )
        }

        applyOptimisticPlaybackState(for: action, at: Date())
        invalidationHandler?(.sourceChanged)
        if action == .previousTrack || action == .nextTrack {
            if let track = snapshot.track {
                pendingTrackTransition = PendingTrackTransition(
                    baselineIdentity: track.identity.fallbackSignature,
                    baselineDescriptiveIdentity: Self.descriptiveIdentity(for: track),
                    baselineArtworkData: track.artworkData,
                    expectedPlaybackState: snapshot.playbackState,
                    issuedAt: Date()
                )
            }
            pendingPlaybackExpectation = nil
            scheduleMetadataRefresh(candidate: nil, delayNanoseconds: 40_000_000)
        } else {
            scheduleMetadataRefresh(candidate: nil, delayNanoseconds: 120_000_000)
        }
        return controlResult(
            request,
            disposition: .accepted,
            diagnostic: result.diagnostic
        )
    }

    func invalidateRunningInstance(processIdentifier: pid_t?) {
        guard processIdentifier == nil
                || latestSnapshot?.instance?.processIdentifier == processIdentifier else {
            return
        }
        metadataRefreshGeneration &+= 1
        metadataRefreshTask?.cancel()
        metadataRefreshTask = nil
        pendingMetadataIdentity = nil
        pendingTrackTransition = nil
        pendingPlaybackExpectation = nil
        bridgeNeedsRunningInstanceRebind = false
        postRebindVerificationAttempt = nil
        latestSnapshot = nil
        invalidationHandler?(.sourceChanged)
    }

    func rebindObservationToRunningInstance() {
        metadataRefreshGeneration &+= 1
        metadataRefreshTask?.cancel()
        metadataRefreshTask = nil
        pendingMetadataIdentity = nil
        pendingTrackTransition = nil
        pendingPlaybackExpectation = nil
        bridgeNeedsRunningInstanceRebind = true
        postRebindVerificationAttempt = nil
    }

    func applyPayloadForTesting(_ payload: MediaRemoteClientPayload) -> MusicAppSnapshot {
        apply(payload, existingArtwork: cachedArtwork(for: payload))
    }

    func receiveStreamPayloadForTesting(_ payload: MediaRemoteClientPayload) {
        receiveStreamPayload(payload)
    }

    private func receiveStreamPayload(_ payload: MediaRemoteClientPayload) {
        guard currentInstance()?.processIdentifier == payload.processIdentifier else { return }
        let identity = payload.stableTrackSignature
        let currentIdentity = latestSnapshot?.track?.identity.fallbackSignature
        if let pendingTrackTransition {
            if identity == pendingTrackTransition.baselineIdentity {
                return
            }
            scheduleMetadataRefresh(candidate: payload)
            return
        }
        if currentIdentity == identity {
            _ = apply(payload, existingArtwork: cachedArtwork(for: payload))
            invalidationHandler?(.sourceChanged)
            if latestSnapshot?.track?.artworkData == nil
                || payload.elapsedTime == nil
                || payload.duration == nil
                || payload.isPlaying == nil {
                scheduleMetadataRefresh(candidate: payload)
            }
            return
        }
        if let snapshot = latestSnapshot,
           let track = snapshot.track,
           payload.descriptiveTrackSignature != Self.descriptiveIdentity(for: track) {
            pendingTrackTransition = PendingTrackTransition(
                baselineIdentity: track.identity.fallbackSignature,
                baselineDescriptiveIdentity: Self.descriptiveIdentity(for: track),
                baselineArtworkData: track.artworkData,
                expectedPlaybackState: snapshot.playbackState,
                issuedAt: Date()
            )
        }
        scheduleMetadataRefresh(candidate: payload)
    }

    private func scheduleMetadataRefresh(
        candidate: MediaRemoteClientPayload?,
        delayNanoseconds: UInt64 = 0
    ) {
        if pendingTrackTransition != nil,
           metadataRefreshTask != nil {
            return
        }
        let requestedIdentity = candidate?.stableTrackSignature
        if metadataRefreshTask != nil,
           pendingMetadataIdentity == requestedIdentity,
           requestedIdentity != nil {
            return
        }
        metadataRefreshGeneration &+= 1
        let generation = metadataRefreshGeneration
        metadataRefreshTask?.cancel()
        pendingMetadataIdentity = requestedIdentity
        metadataRefreshTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled, let self else { return }
            let baselineIdentity = self.pendingTrackTransition?.baselineIdentity
                ?? self.latestSnapshot?.track?.identity.fallbackSignature
            if let pendingTrackTransition = self.pendingTrackTransition {
                let minimumReadAt = pendingTrackTransition.issuedAt.addingTimeInterval(0.12)
                let remainingDelay = minimumReadAt.timeIntervalSinceNow
                if remainingDelay > 0 {
                    try? await Task.sleep(
                        nanoseconds: UInt64(remainingDelay * 1_000_000_000)
                    )
                }
            }

            var previousCandidateFingerprint: MediaRemoteClientTransitionFingerprint?
            let deadline = Date().addingTimeInterval(
                self.pendingTrackTransition == nil ? 2.0 : 2.8
            )
            while !Task.isCancelled,
                  generation == self.metadataRefreshGeneration,
                  Date() < deadline {
                guard let payload = await self.readPayload(includeArtwork: true) else {
                    try? await Task.sleep(nanoseconds: 90_000_000)
                    continue
                }
                guard generation == self.metadataRefreshGeneration else { return }
                _ = self.completeBridgeRebindIfNeeded()

                if baselineIdentity == nil
                    || payload.stableTrackSignature == baselineIdentity {
                    if baselineIdentity == nil
                        || self.pendingTrackTransition == nil {
                        _ = self.apply(
                            payload,
                            existingArtwork: self.cachedArtwork(for: payload)
                        )
                        self.finishMetadataRefresh(generation: generation)
                        self.scheduleNextPostRebindVerification()
                        self.invalidationHandler?(.sourceChanged)
                        return
                    }
                    previousCandidateFingerprint = nil
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    continue
                }

                if let transition = self.pendingTrackTransition,
                   payload.descriptiveTrackSignature == transition.baselineDescriptiveIdentity {
                    // 网易云切歌时会先更新时长；旧标题、旧封面配新时长不是新歌曲。
                    previousCandidateFingerprint = nil
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    continue
                }

                if let transition = self.pendingTrackTransition,
                   Self.shouldAwaitPlaybackConfirmation(
                    expectedState: transition.expectedPlaybackState,
                    candidateIsPlaying: payload.isPlaying,
                    issuedAt: transition.issuedAt,
                    now: Date()
                   ) {
                    // 网易云会先发新曲 paused + 临时时长，再补 playing + 真实时长。
                    previousCandidateFingerprint = nil
                    try? await Task.sleep(nanoseconds: 70_000_000)
                    continue
                }

                let fingerprint = payload.transitionFingerprint
                let artworkConfirmsTransition = self.pendingTrackTransition.map {
                    Self.artworkConfirmsTransition(
                        candidate: payload.artworkData,
                        baseline: $0.baselineArtworkData
                    )
                } ?? false
                if artworkConfirmsTransition || previousCandidateFingerprint == fingerprint {
                    self.pendingTrackTransition = nil
                    _ = self.apply(
                        payload,
                        existingArtwork: self.cachedArtwork(for: payload)
                    )
                    self.finishMetadataRefresh(generation: generation)
                    self.scheduleNextPostRebindVerification()
                    self.invalidationHandler?(.sourceChanged)
                    return
                }
                previousCandidateFingerprint = fingerprint
                try? await Task.sleep(nanoseconds: 70_000_000)
            }
            if generation == self.metadataRefreshGeneration {
                self.pendingTrackTransition = nil
            }
            self.finishMetadataRefresh(generation: generation)
        }
    }

    private func finishMetadataRefresh(generation: UInt64) {
        guard generation == metadataRefreshGeneration else { return }
        metadataRefreshTask = nil
        pendingMetadataIdentity = nil
    }

    private func startBridge() {
        bridge.start(
            onPayload: { [weak self] payload in
                self?.receiveStreamPayload(payload)
            },
            onFailure: { [weak self] diagnostic in
                self?.publishDegradedIfNeeded(diagnostic: diagnostic)
            }
        )
    }

    private func readPayload(includeArtwork: Bool) async -> MediaRemoteClientPayload? {
        if let payloadReaderForTesting {
            return await payloadReaderForTesting(includeArtwork)
        }
        return await bridge.readOnce(includeArtwork: includeArtwork)
    }

    private func scheduleNextPostRebindVerification() {
        guard let attempt = postRebindVerificationAttempt,
              Self.postRebindVerificationDelays.indices.contains(attempt) else {
            postRebindVerificationAttempt = nil
            return
        }
        postRebindVerificationAttempt = attempt + 1
        scheduleMetadataRefresh(
            candidate: nil,
            delayNanoseconds: Self.postRebindVerificationDelays[attempt]
        )
    }

    @discardableResult
    private func completeBridgeRebindIfNeeded() -> Bool {
        guard bridgeNeedsRunningInstanceRebind else { return false }
        bridgeNeedsRunningInstanceRebind = false
        if payloadReaderForTesting == nil {
            bridge.restart()
        }
        postRebindVerificationAttempt = 0
        return true
    }

    @discardableResult
    private func apply(
        _ payload: MediaRemoteClientPayload,
        existingArtwork: Data?
    ) -> MusicAppSnapshot {
        guard let instance = currentInstance(),
              instance.processIdentifier == payload.processIdentifier else {
            let snapshot = notRunningSnapshot()
            latestSnapshot = snapshot
            return snapshot
        }
        revision &+= 1
        let artworkData = payload.artworkData ?? existingArtwork
        if let artworkData {
            rememberArtwork(artworkData, for: payload.stableTrackSignature)
        }
        let trackIdentity = MusicTrackIdentity(
            providerIdentifier: nil,
            fallbackSignature: payload.stableTrackSignature
        )
        let previousSnapshot = latestSnapshot
        let isSameTrack = previousSnapshot?.track?.identity == trackIdentity
        let hasCompleteTimeline = payload.elapsedTime != nil && payload.duration != nil
        var playbackState: MusicPlaybackState
        if isSameTrack, !hasCompleteTimeline, let previousSnapshot {
            playbackState = previousSnapshot.playbackState
        } else {
            switch payload.isPlaying {
            case true:
                playbackState = .playing
            case false:
                playbackState = .paused
            case nil:
                playbackState = .unknown
            }
        }
        var timeline: MusicTimelineSnapshot?
        if let elapsedTime = payload.elapsedTime,
           let duration = payload.duration,
           duration > 0 {
            timeline = MusicTimelineSnapshot(
                elapsedTime: min(max(elapsedTime, 0), duration),
                duration: duration,
                playbackRate: playbackState == .playing
                    ? max(payload.playbackRate ?? 1, 0)
                    : 0,
                observedAt: payload.observedAt
            )
        } else if isSameTrack,
                  let previousTimeline = previousSnapshot?.timeline {
            let elapsed = projectedElapsedTime(from: previousTimeline, at: payload.observedAt)
            timeline = MusicTimelineSnapshot(
                elapsedTime: elapsed,
                duration: previousTimeline.duration,
                playbackRate: playbackState == .playing
                    ? max(previousTimeline.playbackRate, 1)
                    : 0,
                observedAt: payload.observedAt
            )
        } else {
            timeline = nil
        }
        if let expectation = pendingPlaybackExpectation {
            if expectation.trackIdentity != trackIdentity {
                pendingPlaybackExpectation = nil
            } else if payload.observedAt.timeIntervalSince(expectation.issuedAt) < 0.8 {
                playbackState = expectation.targetState
                if let duration = timeline?.duration,
                   let anchorElapsedTime = expectation.anchorElapsedTime {
                    let elapsed = expectation.targetState == .playing
                        ? anchorElapsedTime
                            + max(payload.observedAt.timeIntervalSince(expectation.issuedAt), 0)
                        : anchorElapsedTime
                    timeline = MusicTimelineSnapshot(
                        elapsedTime: min(max(elapsed, 0), duration),
                        duration: duration,
                        playbackRate: expectation.targetState == .playing ? 1 : 0,
                        observedAt: payload.observedAt
                    )
                }
            } else {
                pendingPlaybackExpectation = nil
            }
        }
        let controls = controlCapabilities(for: instance, checkedAt: payload.observedAt)
        let snapshot = MusicAppSnapshot(
            descriptor: descriptor,
            instance: instance,
            availability: .ready,
            track: MusicTrackSnapshot(
                identity: trackIdentity,
                title: payload.title,
                artist: payload.artist,
                album: payload.album,
                artworkData: artworkData,
                lyrics: []
            ),
            playbackState: playbackState,
            timeline: timeline,
            controls: controls,
            revision: revision,
            provenance: MusicSnapshotProvenance(
                bundleIdentifier: descriptor.bundleIdentifier,
                mechanisms: [.applicationClient, .semanticAccessibility]
            ),
            checkedAt: payload.observedAt,
            diagnostic: "已通过 Bundle ID 与 PID 定向读取网易云音乐专属状态。"
        )
        latestSnapshot = snapshot
        return snapshot
    }

    private func applyOptimisticPlaybackState(
        for action: MusicControlAction,
        at now: Date
    ) {
        guard let snapshot = latestSnapshot else { return }
        let nextState: MusicPlaybackState?
        switch action {
        case .playPause:
            nextState = snapshot.playbackState == .playing ? .paused : .playing
        case .play:
            nextState = .playing
        case .pause:
            nextState = .paused
        case .previousTrack, .nextTrack, .seekNormalized:
            nextState = nil
        }
        guard let nextState else { return }
        revision &+= 1
        let timeline = snapshot.timeline.map {
            MusicTimelineSnapshot(
                elapsedTime: projectedElapsedTime(from: $0, at: now),
                duration: $0.duration,
                playbackRate: nextState == .playing ? 1 : 0,
                observedAt: now
            )
        }
        latestSnapshot = MusicAppSnapshot(
            descriptor: snapshot.descriptor,
            instance: snapshot.instance,
            availability: snapshot.availability,
            track: snapshot.track,
            playbackState: nextState,
            timeline: timeline,
            controls: snapshot.controls,
            revision: revision,
            provenance: snapshot.provenance,
            checkedAt: now,
            diagnostic: "网易云音乐控制已发送，等待专属状态流确认。"
        )
        if let trackIdentity = snapshot.track?.identity {
            pendingPlaybackExpectation = PendingPlaybackExpectation(
                trackIdentity: trackIdentity,
                targetState: nextState,
                anchorElapsedTime: timeline?.elapsedTime,
                issuedAt: now
            )
        }
    }

    private func projectedElapsedTime(
        from timeline: MusicTimelineSnapshot,
        at now: Date
    ) -> TimeInterval {
        let projected = timeline.elapsedTime
            + max(now.timeIntervalSince(timeline.observedAt), 0) * timeline.playbackRate
        return min(max(projected, 0), timeline.duration)
    }

    private static func descriptiveIdentity(for track: MusicTrackSnapshot) -> String {
        [track.title, track.artist ?? "", track.album ?? ""]
            .joined(separator: "\u{1f}")
    }

    nonisolated static func artworkConfirmsTransition(
        candidate: Data?,
        baseline: Data?
    ) -> Bool {
        guard let candidate else { return false }
        return candidate != baseline
    }

    nonisolated static func shouldAwaitPlaybackConfirmation(
        expectedState: MusicPlaybackState,
        candidateIsPlaying: Bool?,
        issuedAt: Date,
        now: Date
    ) -> Bool {
        expectedState == .playing
            && candidateIsPlaying != true
            && now.timeIntervalSince(issuedAt) < transitionPlaybackConfirmationInterval
    }

    private func controlCapabilities(
        for instance: MusicAppInstance,
        checkedAt: Date
    ) -> MusicControlCapabilities {
        guard AXIsProcessTrusted() else {
            let unavailable = MusicControlCapability.unavailable(
                reason: "需要辅助功能权限才能控制网易云音乐。"
            )
            return MusicControlCapabilities(values: [
                .playPause: unavailable,
                .previousTrack: unavailable,
                .nextTrack: unavailable
            ])
        }
        let ready = MusicControlCapability.ready(
            target: instance,
            mechanism: .semanticAccessibility,
            verifiedAt: checkedAt
        )
        return MusicControlCapabilities(values: [
            .playPause: ready,
            .previousTrack: ready,
            .nextTrack: ready
        ])
    }

    private func currentInstance() -> MusicAppInstance? {
        let instances = runningInstancesProvider()
        guard instances.count == 1 else { return nil }
        return instances[0]
    }

    private func notRunningSnapshot() -> MusicAppSnapshot {
        revision &+= 1
        return MusicAppSnapshot(
            descriptor: descriptor,
            instance: nil,
            availability: .notRunning,
            track: nil,
            playbackState: .stopped,
            timeline: nil,
            controls: .none,
            revision: revision,
            provenance: MusicSnapshotProvenance(
                bundleIdentifier: descriptor.bundleIdentifier,
                mechanisms: [.applicationClient, .semanticAccessibility]
            ),
            checkedAt: Date(),
            diagnostic: "网易云音乐当前未运行。"
        )
    }

    private func degradedSnapshot(
        instance: MusicAppInstance,
        diagnostic: String
    ) -> MusicAppSnapshot {
        revision &+= 1
        return MusicAppSnapshot(
            descriptor: descriptor,
            instance: instance,
            availability: .degraded(reason: diagnostic),
            track: nil,
            playbackState: .unknown,
            timeline: nil,
            controls: controlCapabilities(for: instance, checkedAt: Date()),
            revision: revision,
            provenance: MusicSnapshotProvenance(
                bundleIdentifier: descriptor.bundleIdentifier,
                mechanisms: [.applicationClient, .semanticAccessibility]
            ),
            checkedAt: Date(),
            diagnostic: diagnostic
        )
    }

    private func publishDegradedIfNeeded(diagnostic: String) {
        guard let instance = currentInstance(), latestSnapshot?.track == nil else { return }
        latestSnapshot = degradedSnapshot(instance: instance, diagnostic: diagnostic)
        invalidationHandler?(.sourceChanged)
    }

    private func cachedArtwork(for payload: MediaRemoteClientPayload) -> Data? {
        artworkCache[payload.stableTrackSignature]
    }

    private func rememberArtwork(_ data: Data, for identity: String) {
        artworkCache[identity] = data
        artworkCacheOrder.removeAll { $0 == identity }
        artworkCacheOrder.append(identity)
        while artworkCacheOrder.count > 16 {
            artworkCache.removeValue(forKey: artworkCacheOrder.removeFirst())
        }
    }

    private func controlResult(
        _ request: MusicControlRequest,
        disposition: MusicControlDisposition,
        diagnostic: String
    ) -> MusicControlResult {
        MusicControlResult(
            requestID: request.id,
            disposition: disposition,
            diagnostic: diagnostic
        )
    }
}

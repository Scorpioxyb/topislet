import Foundation

// Optimistic Qishui play/pause state, extracted from MusicAdapterCoordinator
// (global plan 4.2 step 2). It owns three pieces of state that previously
// lived as loose coordinator properties:
//   - the pending play/pause operation awaiting a matching source readback;
//   - the pause timeline floor that keeps the UI position from creeping
//     forward between pressing pause and the source confirming it;
//   - the cached playback override used while the media focus is cached.
// The coordinator still decides when to publish, what status to show and
// which usage events to record; this type only holds and transforms state.
// Behavior is unchanged from the coordinator version; the clock is injected
// so the transformations can be tested deterministically.

struct PlaybackTrackIdentity: Equatable {
    let title: String
    let artist: String

    init(title: String, artist: String) {
        self.title = title
        self.artist = artist
    }

    init(_ track: MediaRemoteNowPlayingTrack) {
        self.init(title: track.title, artist: track.artist)
    }

    /// Same title, and the same artist unless either side carries the
    /// Qishui placeholder artist shown before the real one is known.
    func matches(_ other: PlaybackTrackIdentity) -> Bool {
        guard title == other.title else { return false }
        return artist == other.artist
            || artist == PlaybackTrackIdentity.placeholderArtist
            || other.artist == PlaybackTrackIdentity.placeholderArtist
    }

    static let placeholderArtist = "汽水音乐"
}

struct PendingPlaybackOperation {
    let id: Int
    let targetIsPlaying: Bool
    let issuedAt: Date
    let trackIdentity: PlaybackTrackIdentity
    let anchorElapsed: TimeInterval?
    let anchorDuration: TimeInterval?
    let baselineSampleID: UInt64
    let baselineSampleSource: MediaRemoteSampleSource
    let requiresObservedOppositeState: Bool
    var observedOppositeState: Bool
}

struct PlaybackTimelineFloor {
    let trackIdentity: PlaybackTrackIdentity
    let elapsedTime: TimeInterval
    let issuedAt: Date
}

struct CachedPlaybackOverride {
    let trackIdentity: PlaybackTrackIdentity
    let isPlaying: Bool
    let elapsedTime: TimeInterval?
    let duration: TimeInterval?
    let updatedAt: Date
}

@MainActor
final class PlaybackOperationTracker {
    /// A readback earlier than this after the press predates the command.
    static let minimumConfirmationDelay: TimeInterval = 0.2
    static let cachedOverrideRefreshInterval: TimeInterval = 1.0

    private(set) var pendingOperation: PendingPlaybackOperation?
    private(set) var timelineFloor: PlaybackTimelineFloor?
    private(set) var cachedOverride: CachedPlaybackOverride?
    private(set) var lastCachedOverrideRefreshAttemptAt: Date?
    private var nextOperationID = 0
    private var timeoutTask: Task<Void, Never>?
    private let confirmationTimeout: TimeInterval
    private let clock: () -> Date

    init(confirmationTimeout: TimeInterval = 4, clock: @escaping () -> Date = Date.init) {
        self.confirmationTimeout = confirmationTimeout
        self.clock = clock
    }

    var hasPendingOperation: Bool { pendingOperation != nil }

    // MARK: Operation lifecycle

    /// Starts an optimistic play/pause toggle from the state the user saw.
    /// Replacing an unconfirmed operation requires the source to show the
    /// opposite state first, so a stale readback cannot confirm the new one.
    @discardableResult
    func begin(
        requestedState: MusicState,
        baselineSampleID: UInt64,
        baselineSampleSource: MediaRemoteSampleSource
    ) -> Int {
        let replacesPendingOperation = pendingOperation != nil
        let targetIsPlaying = !requestedState.isPlaying
        nextOperationID += 1
        let operation = PendingPlaybackOperation(
            id: nextOperationID,
            targetIsPlaying: targetIsPlaying,
            issuedAt: clock(),
            trackIdentity: PlaybackTrackIdentity(
                title: requestedState.track.title,
                artist: requestedState.track.artist
            ),
            anchorElapsed: PlaybackControlTimeline.anchorElapsed(
                targetIsPlaying: targetIsPlaying,
                requestElapsed: requestedState.elapsedTime,
                dispatchCompletionElapsed: nil
            ),
            anchorDuration: requestedState.duration,
            baselineSampleID: baselineSampleID,
            baselineSampleSource: baselineSampleSource,
            requiresObservedOppositeState: replacesPendingOperation,
            observedOppositeState: false
        )

        pendingOperation = operation
        if operation.targetIsPlaying {
            timelineFloor = nil
        } else if let anchorElapsed = operation.anchorElapsed {
            timelineFloor = PlaybackTimelineFloor(
                trackIdentity: operation.trackIdentity,
                elapsedTime: anchorElapsed,
                issuedAt: operation.issuedAt
            )
        }

        cancelTimeout()
        return operation.id
    }

    func isCurrent(_ id: Int) -> Bool {
        PlaybackControlTimeline.isCurrentOperation(
            completedOperationID: id,
            currentOperationID: pendingOperation?.id
        )
    }

    /// Calls `onExpire` with the operation ID if no confirmation arrives in
    /// time. The callback decides how to roll back and what to report.
    func scheduleConfirmationTimeout(id: Int, onExpire: @escaping @MainActor (Int) -> Void) {
        guard isCurrent(id) else { return }
        timeoutTask?.cancel()
        let nanoseconds = UInt64(max(confirmationTimeout, 0) * 1_000_000_000)
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            onExpire(id)
        }
    }

    func finish(id: Int) {
        guard pendingOperation?.id == id else { return }
        pendingOperation = nil
        cancelTimeout()
    }

    /// Drops the operation and its pause floor. Returns false, changing
    /// nothing, when `id` is no longer the current operation.
    @discardableResult
    func rollback(id: Int) -> Bool {
        guard isCurrent(id) else { return false }
        pendingOperation = nil
        cancelTimeout()
        timelineFloor = nil
        return true
    }

    func reset(clearTimelineFloor: Bool) {
        pendingOperation = nil
        cancelTimeout()
        if clearTimelineFloor {
            timelineFloor = nil
            cachedOverride = nil
            lastCachedOverrideRefreshAttemptAt = nil
        }
    }

    /// The optimistic play state for this track, or nil when nothing is
    /// pending. A pending operation for another track is discarded.
    func pendingTarget(title: String, artist: String) -> Bool? {
        guard let operation = pendingOperation else { return nil }
        guard PlaybackTrackIdentity(title: title, artist: artist).matches(operation.trackIdentity) else {
            reset(clearTimelineFloor: true)
            return nil
        }
        return operation.targetIsPlaying
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    // MARK: Confirmation

    /// Applies one observed play state. Returns the operation it confirmed,
    /// which is then finished; nil when it did not confirm anything.
    func observeConfirmation(isPlaying: Bool, operationID: Int) -> PendingPlaybackOperation? {
        guard var operation = pendingOperation,
              operation.id == operationID else { return nil }

        guard isPlaying == operation.targetIsPlaying else {
            operation.observedOppositeState = true
            pendingOperation = operation
            return nil
        }
        guard !operation.requiresObservedOppositeState || operation.observedOppositeState else {
            return nil
        }
        finish(id: operation.id)
        return operation
    }

    /// Confirmation from AX progress inference on the direct Qishui track.
    func confirmFromInferredPlayback(
        directTrack: PlaybackTrackIdentity?,
        inferredIsPlaying: Bool?,
        checkedAt: Date
    ) -> PendingPlaybackOperation? {
        guard let operation = pendingOperation,
              checkedAt.timeIntervalSince(operation.issuedAt) >= Self.minimumConfirmationDelay,
              let inferredIsPlaying,
              let directTrack,
              directTrack.matches(operation.trackIdentity) else { return nil }
        return observeConfirmation(isPlaying: inferredIsPlaying, operationID: operation.id)
    }

    /// Confirmation from a fresh MediaRemote sample taken after the press.
    /// An accepted confirmation also becomes the cached playback override.
    func confirmFromMediaRemote(snapshot: MediaRemoteNowPlayingSnapshot) -> PendingPlaybackOperation? {
        guard let operation = pendingOperation,
              snapshot.sampleOrigin != .cached,
              snapshot.sampleOrigin != .unknown,
              isNewSample(snapshot, for: operation),
              snapshot.checkedAt.timeIntervalSince(operation.issuedAt) >= Self.minimumConfirmationDelay,
              let track = snapshot.currentTrack,
              PlaybackTrackIdentity(track).matches(operation.trackIdentity),
              let isPlaying = track.isPlaying else { return nil }

        guard let confirmed = observeConfirmation(isPlaying: isPlaying, operationID: operation.id) else {
            return nil
        }
        updateCachedOverride(from: track, confirming: confirmed, checkedAt: snapshot.checkedAt)
        return confirmed
    }

    private func isNewSample(
        _ snapshot: MediaRemoteNowPlayingSnapshot,
        for operation: PendingPlaybackOperation
    ) -> Bool {
        guard snapshot.sampleID > 0 else { return false }
        guard snapshot.sampleSource == operation.baselineSampleSource else { return true }
        return snapshot.sampleID > operation.baselineSampleID
    }

    // MARK: Timeline presentation

    /// The track as the UI should show it now: the optimistic state while an
    /// operation is pending, otherwise the live position, held at the pause
    /// floor until a fresh sample supersedes it.
    func liveTrack(
        from track: MediaRemoteNowPlayingTrack,
        checkedAt: Date,
        allowsTimelineFloorRelease: Bool
    ) -> MediaRemoteNowPlayingTrack {
        if let operation = pendingOperation {
            guard PlaybackTrackIdentity(track).matches(operation.trackIdentity) else {
                reset(clearTimelineFloor: true)
                return liveTrack(
                    from: track,
                    checkedAt: checkedAt,
                    allowsTimelineFloorRelease: allowsTimelineFloorRelease
                )
            }

            let duration = operation.anchorDuration ?? track.duration
            let anchorElapsed = operation.anchorElapsed ?? track.elapsedTime
            let elapsed: TimeInterval?
            let progress: Double
            if let anchorElapsed, let duration, duration > 0 {
                let optimisticElapsed = PlaybackControlTimeline.optimisticElapsed(
                    targetIsPlaying: operation.targetIsPlaying,
                    anchorElapsed: anchorElapsed,
                    issuedAt: operation.issuedAt,
                    now: clock(),
                    duration: duration
                ) ?? anchorElapsed
                let clampedElapsed = min(max(optimisticElapsed, 0), duration)
                elapsed = clampedElapsed
                progress = min(max(clampedElapsed / duration, 0), 1)
            } else {
                elapsed = anchorElapsed
                progress = track.progress
            }

            return track.replacingPlayback(
                isPlaying: operation.targetIsPlaying,
                progress: progress,
                elapsedTime: elapsed,
                duration: duration
            )
        }

        let liveTrack: MediaRemoteNowPlayingTrack
        if track.isPlaying == true,
           let elapsed = track.elapsedTime,
           let duration = track.duration,
           duration > 0 {
            let liveElapsed = min(max(elapsed + clock().timeIntervalSince(checkedAt), 0), duration)
            liveTrack = track.replacingPlayback(
                isPlaying: track.isPlaying,
                progress: min(max(liveElapsed / duration, 0), 1),
                elapsedTime: liveElapsed,
                duration: duration
            )
        } else {
            liveTrack = track
        }

        guard let floor = timelineFloor else { return liveTrack }
        guard PlaybackTrackIdentity(liveTrack).matches(floor.trackIdentity) else {
            timelineFloor = nil
            return liveTrack
        }
        if PlaybackControlTimeline.shouldReleasePauseFloor(
            floorIssuedAt: floor.issuedAt,
            sampleReceivedAt: checkedAt,
            isFreshSample: allowsTimelineFloorRelease,
            isPlaying: liveTrack.isPlaying,
            elapsedTime: liveTrack.elapsedTime
        ) {
            timelineFloor = nil
            return liveTrack
        }
        guard let duration = liveTrack.duration,
              duration > 0 else { return liveTrack }

        let incomingElapsed = allowsTimelineFloorRelease
            ? (liveTrack.elapsedTime ?? floor.elapsedTime)
            : floor.elapsedTime
        let stableElapsed = min(max(max(floor.elapsedTime, incomingElapsed), 0), duration)
        timelineFloor = PlaybackTimelineFloor(
            trackIdentity: floor.trackIdentity,
            elapsedTime: stableElapsed,
            issuedAt: floor.issuedAt
        )

        return liveTrack.replacingPlayback(
            isPlaying: false,
            progress: min(max(stableElapsed / duration, 0), 1),
            elapsedTime: stableElapsed,
            duration: duration
        )
    }

    /// Applies the cached override while the media focus is cached. Has no
    /// effect while an operation is pending.
    func cachedPlaybackTrack(from track: MediaRemoteNowPlayingTrack) -> MediaRemoteNowPlayingTrack {
        guard pendingOperation == nil,
              let override = cachedOverride else { return track }
        guard PlaybackTrackIdentity(track).matches(override.trackIdentity) else {
            cachedOverride = nil
            return track
        }

        let duration = override.duration ?? track.duration
        var elapsedTime = override.elapsedTime ?? track.elapsedTime
        if override.isPlaying, let elapsedTimeValue = elapsedTime {
            elapsedTime = elapsedTimeValue + clock().timeIntervalSince(override.updatedAt)
            timelineFloor = nil
        }
        if let duration, duration > 0, let elapsedTimeValue = elapsedTime {
            elapsedTime = min(max(elapsedTimeValue, 0), duration)
        }
        if !override.isPlaying,
           let floor = timelineFloor,
           PlaybackTrackIdentity(track).matches(floor.trackIdentity) {
            elapsedTime = max(elapsedTime ?? floor.elapsedTime, floor.elapsedTime)
            timelineFloor = PlaybackTimelineFloor(
                trackIdentity: floor.trackIdentity,
                elapsedTime: elapsedTime ?? floor.elapsedTime,
                issuedAt: floor.issuedAt
            )
        }

        let progress: Double
        if let duration, duration > 0, let elapsedTime {
            progress = min(max(elapsedTime / duration, 0), 1)
        } else {
            progress = track.progress
        }
        return track.replacingPlayback(
            isPlaying: override.isPlaying,
            progress: progress,
            elapsedTime: elapsedTime,
            duration: duration
        )
    }

    // MARK: Cached override

    /// True when the cached override should be refreshed from the source:
    /// always while an operation is pending, otherwise at most once a second.
    var shouldRefreshCachedOverride: Bool {
        pendingOperation != nil || cachedOverrideRefreshIsDue
    }

    var cachedOverrideRefreshIsDue: Bool {
        guard let lastCachedOverrideRefreshAttemptAt else { return true }
        return clock().timeIntervalSince(lastCachedOverrideRefreshAttemptAt) >= Self.cachedOverrideRefreshInterval
    }

    func noteCachedOverrideRefreshAttempt() {
        lastCachedOverrideRefreshAttemptAt = clock()
    }

    /// Override from the direct (AX) Qishui track, with position taken from
    /// the matching MediaRemote sample when there is one.
    func updateCachedOverride(
        fromDirect track: QishuiDirectTrack,
        inferredIsPlaying: Bool?,
        mediaSnapshot: MediaRemoteNowPlayingSnapshot?,
        checkedAt: Date
    ) {
        guard let isPlaying = track.isPlaying ?? inferredIsPlaying else { return }
        let identity = PlaybackTrackIdentity(title: track.title, artist: track.artist)
        let mediaTrack = mediaSnapshot?.currentTrack.flatMap {
            PlaybackTrackIdentity($0).matches(identity) ? $0 : nil
        }
        let existingOverride = cachedOverride.flatMap {
            $0.trackIdentity.matches(identity) ? $0 : nil
        }
        let duration = mediaTrack?.duration ?? existingOverride?.duration
        let mediaRemoteElapsed = mediaTrack?.elapsedTime.map { elapsed in
            guard mediaTrack?.isPlaying == true,
                  existingOverride?.isPlaying != false,
                  let mediaSnapshot else { return elapsed }
            return elapsed + max(checkedAt.timeIntervalSince(mediaSnapshot.checkedAt), 0)
        }
        let existingElapsed = existingOverride?.elapsedTime.map { elapsed in
            guard existingOverride?.isPlaying == true,
                  let updatedAt = existingOverride?.updatedAt else { return elapsed }
            return elapsed + max(checkedAt.timeIntervalSince(updatedAt), 0)
        }
        let elapsedTime = PlaybackControlTimeline.cachedOverrideElapsed(
            mediaRemoteElapsed: mediaRemoteElapsed,
            axProgress: track.progress,
            duration: duration,
            existingElapsed: existingElapsed,
            existingIsPlaying: existingOverride?.isPlaying,
            axIsPlaying: isPlaying
        ) ?? pendingOperation.flatMap { operation in
            operation.trackIdentity.matches(identity) ? operation.anchorElapsed : nil
        }

        cachedOverride = CachedPlaybackOverride(
            trackIdentity: identity,
            isPlaying: isPlaying,
            elapsedTime: elapsedTime,
            duration: duration,
            updatedAt: checkedAt
        )
        lastCachedOverrideRefreshAttemptAt = checkedAt
    }

    /// Override straight from a verified MediaRemote track.
    func updateCachedOverride(from track: MediaRemoteNowPlayingTrack, checkedAt: Date) {
        guard let isPlaying = track.isPlaying else { return }
        cachedOverride = CachedPlaybackOverride(
            trackIdentity: PlaybackTrackIdentity(track),
            isPlaying: isPlaying,
            elapsedTime: track.elapsedTime,
            duration: track.duration,
            updatedAt: checkedAt
        )
        lastCachedOverrideRefreshAttemptAt = checkedAt
    }

    private func updateCachedOverride(
        from track: MediaRemoteNowPlayingTrack,
        confirming operation: PendingPlaybackOperation,
        checkedAt: Date
    ) {
        let duration = track.duration ?? operation.anchorDuration
        let elapsedTime = PlaybackControlTimeline.confirmedElapsed(
            targetIsPlaying: operation.targetIsPlaying,
            anchorElapsed: operation.anchorElapsed,
            confirmedElapsed: track.elapsedTime
        )
        cachedOverride = CachedPlaybackOverride(
            trackIdentity: operation.trackIdentity,
            isPlaying: operation.targetIsPlaying,
            elapsedTime: elapsedTime,
            duration: duration,
            updatedAt: checkedAt
        )
        lastCachedOverrideRefreshAttemptAt = checkedAt
    }
}

extension MediaRemoteNowPlayingTrack {
    /// The same track with only its playback fields replaced.
    func replacingPlayback(
        isPlaying: Bool?,
        progress: Double,
        elapsedTime: TimeInterval?,
        duration: TimeInterval?
    ) -> MediaRemoteNowPlayingTrack {
        MediaRemoteNowPlayingTrack(
            title: title,
            artist: artist,
            album: album,
            artworkData: artworkData,
            isPlaying: isPlaying,
            progress: progress,
            elapsedTime: elapsedTime,
            duration: duration,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceProcessIdentifier: sourceProcessIdentifier,
            sourceName: sourceName
        )
    }
}

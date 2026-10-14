import Foundation

enum QishuiTransitionDeliveryPolicy {
    static func accepts(state: MusicState, complete: QishuiTrackTransitionStageEvent) -> Bool {
        guard complete.stage == .atomicComplete,
              let identity = complete.candidateTrackIdentity,
              state.hasCurrentTrack,
              state.track.sourceBundleIdentifier == QishuiProcessLocator.bundleIdentifier,
              !complete.hasDuration || state.duration != nil,
              !complete.hasArtwork || state.track.hasArtwork
                || state.track.artworkData != nil || state.track.artworkURL != nil else { return false }
        return QishuiTrackCoherencePolicy.matches(
            mediaTitle: identity.title, mediaArtist: identity.artist,
            directTitle: state.track.title, directArtist: state.track.artist
        )
    }
}

enum QishuiIdentityRefreshPolicy {
    static func needsTransitionReconciliation(
        media: QishuiLyricIdentity,
        direct: QishuiLyricIdentity,
        directCheckedAt: Date,
        lastRequested: QishuiLyricIdentity?,
        isReadInFlight: Bool,
        now: Date = Date()
    ) -> Bool {
        guard !isReadInFlight, lastRequested != media,
              media.processIdentifier == direct.processIdentifier,
              QishuiDirectSnapshotFreshnessPolicy.accepts(checkedAt: directCheckedAt, now: now)
        else { return false }
        return !QishuiTrackCoherencePolicy.matches(
            mediaTitle: media.title, mediaArtist: media.artist,
            directTitle: direct.title, directArtist: direct.artist
        )
    }

    static func accepts(
        requested: QishuiLyricIdentity?,
        current: QishuiLyricIdentity?,
        result: QishuiLyricIdentity?
    ) -> Bool {
        // AX may lead MediaRemote while switching songs. Only reject a read
        // when the playback identity changed during that read and its result
        // does not describe the new authoritative identity.
        guard requested != current else { return true }
        guard let current, let result,
              current.processIdentifier == result.processIdentifier else { return false }
        return QishuiTrackCoherencePolicy.matches(
            mediaTitle: current.title, mediaArtist: current.artist,
            directTitle: result.title, directArtist: result.artist
        )
    }
}

enum QishuiPlaybackInstancePolicy {
    static func acceptsSnapshot(
        snapshotProcessIdentifier: Int32?,
        runningProcessIdentifiers: Set<Int32>
    ) -> Bool {
        guard let snapshotProcessIdentifier else { return false }
        return runningProcessIdentifiers.contains(snapshotProcessIdentifier)
    }
}

/// A probe belongs to one PID; its disappearance is not proof that the app's
/// current session disappeared. Check the fresh bundle-scoped inventory.
enum QishuiControlProbeCompletionPolicy {
    enum Resolution: Equatable {
        case accept
        case discardAndRefresh
        case sourceExited
    }

    static func resolution(
        requestedProcessIdentifier: Int32,
        runningProcessIdentifiers: Set<Int32>
    ) -> Resolution {
        if runningProcessIdentifiers.contains(requestedProcessIdentifier) { return .accept }
        return runningProcessIdentifiers.isEmpty ? .sourceExited : .discardAndRefresh
    }
}

import Foundation

enum MusicActivityPresentationPolicy {
    static func controlsAvailable(
        canPlayPause: Bool,
        canPreviousTrack: Bool,
        canNextTrack: Bool
    ) -> Bool {
        canPlayPause || canPreviousTrack || canNextTrack
    }
}

enum MusicPresentationTransitionPolicy {
    static func shouldPromoteToCompact(
        activeFeature: IslandFeature,
        currentMode: IslandMode,
        isArmed: Bool,
        hadCurrentTrack: Bool,
        hasCurrentTrack: Bool,
        hasPendingNotification: Bool
    ) -> Bool {
        activeFeature == .music
            && currentMode == .collapsed
            && isArmed
            && !hadCurrentTrack
            && hasCurrentTrack
            && !hasPendingNotification
    }

    static func shouldDisarmForUserRequest(_ targetMode: IslandMode) -> Bool {
        targetMode == .collapsed
    }

    static func shouldResetToDefaultAfterAllSourcesExit(
        currentMode: IslandMode
    ) -> Bool {
        currentMode != .collapsed
    }
}

enum MusicUpdatePolicy {
    static func playbackPresentationChanged(current: MusicState, candidate: MusicState) -> Bool {
        current.isPlaying != candidate.isPlaying
            || current.playbackStateKnown != candidate.playbackStateKnown
    }

    static func preservingTimeline(current: MusicState, candidate: MusicState) -> MusicState {
        var result = current
        result.isPlaying = candidate.isPlaying
        result.playbackStateKnown = candidate.playbackStateKnown
        result.isPlaybackPending = candidate.isPlaybackPending
        result.canPlayPause = candidate.canPlayPause
        result.canPreviousTrack = candidate.canPreviousTrack
        result.canNextTrack = candidate.canNextTrack
        result.controlUnavailableReason = candidate.controlUnavailableReason
        result.controlRecoveryAction = candidate.controlRecoveryAction
        result.hasCurrentTrack = candidate.hasCurrentTrack
        return result
    }

    static func didChangeSource(current: MusicState, candidate: MusicState) -> Bool {
        current.track.sourceBundleIdentifier
            != candidate.track.sourceBundleIdentifier
    }

    static func shouldIgnoreUntrustedProgressReset(
        current: MusicState,
        candidate: MusicState,
        sourceAvailability: MusicSourceAvailability?
    ) -> Bool {
        if sourceAvailability == .qishuiNotRunning {
            return false
        }
        guard current.track.sourceBundleIdentifier
            == candidate.track.sourceBundleIdentifier else {
            return false
        }
        // A missing timeline is recoverable only for the same track. Keeping
        // the old MusicState after a track change also keeps its old lyrics.
        guard current.track.title.trimmingCharacters(in: .whitespacesAndNewlines)
            == candidate.track.title.trimmingCharacters(in: .whitespacesAndNewlines),
              current.track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            == candidate.track.artist.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        guard candidate.hasCurrentTrack else {
            return false
        }
        guard current.duration != nil,
              current.elapsedTime != nil,
              current.progress > 0.01 else {
            return false
        }

        let candidateHasTrustedTiming = candidate.duration != nil
            && candidate.elapsedTime != nil
        guard !candidateHasTrustedTiming,
              candidate.progress <= 0.0001,
              !candidate.canSeek else {
            return false
        }

        return !candidate.track.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}

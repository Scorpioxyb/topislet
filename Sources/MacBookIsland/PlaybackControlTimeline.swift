import Foundation

enum PlaybackControlTimeline {
    struct AuthoritativeAnchor: Equatable {
        let trackIdentity: String
        let elapsedAtAnchor: TimeInterval
        let duration: TimeInterval?
        let isPlaying: Bool
        let playbackRate: Double
        let sourceTimestamp: Date
        let sourceEventTimestamp: Date?
        let anchorUptime: TimeInterval
    }

    static func anchorElapsed(
        targetIsPlaying: Bool,
        requestElapsed: TimeInterval?,
        dispatchCompletionElapsed: TimeInterval?
    ) -> TimeInterval? {
        if !targetIsPlaying {
            return requestElapsed ?? dispatchCompletionElapsed
        }
        return dispatchCompletionElapsed ?? requestElapsed
    }

    static func confirmedElapsed(
        targetIsPlaying: Bool,
        anchorElapsed: TimeInterval?,
        confirmedElapsed: TimeInterval?
    ) -> TimeInterval? {
        // Callers have already rejected cached, pre-command and mismatched
        // confirmations. The request anchor freezes the optimistic UI only;
        // once confirmed, the source owns the timeline in either state.
        return confirmedElapsed ?? anchorElapsed
    }

    static func shouldReleasePauseFloor(
        floorIssuedAt: Date,
        sampleReceivedAt: Date,
        isFreshSample: Bool,
        isPlaying: Bool?,
        elapsedTime: TimeInterval?
    ) -> Bool {
        guard isFreshSample, sampleReceivedAt >= floorIssuedAt,
              let isPlaying, let elapsedTime,
              elapsedTime.isFinite, elapsedTime >= 0 else { return false }
        // Both playing and paused source positions supersede the temporary
        // pause floor. A small backward correction is valid after a seek.
        _ = isPlaying
        return true
    }

    static func optimisticElapsed(
        targetIsPlaying: Bool,
        anchorElapsed: TimeInterval?,
        issuedAt: Date,
        now: Date,
        duration: TimeInterval?
    ) -> TimeInterval? {
        guard let anchorElapsed else { return nil }
        let elapsed = targetIsPlaying
            ? anchorElapsed + max(now.timeIntervalSince(issuedAt), 0)
            : anchorElapsed
        guard let duration, duration > 0 else { return elapsed }
        return min(max(elapsed, 0), duration)
    }

    static func isCurrentOperation(
        completedOperationID: Int,
        currentOperationID: Int?
    ) -> Bool {
        completedOperationID == currentOperationID
    }

    static func authoritativeAnchor(
        trackIdentity: String,
        elapsedTime: TimeInterval?,
        elapsedTimeNow: TimeInterval?,
        sourceTimestamp: Date?,
        playbackRate: Double?,
        isPlaying: Bool?,
        duration: TimeInterval?,
        receivedAt: Date,
        receivedUptime: TimeInterval
    ) -> AuthoritativeAnchor? {
        guard isPlaying != nil || playbackRate != nil else { return nil }
        let effectiveIsPlaying = isPlaying ?? ((playbackRate ?? 0) > 0.01)
        let effectiveRate = effectiveIsPlaying ? max(playbackRate ?? 1, 0) : 0
        let elapsedAtReceipt: TimeInterval
        let effectiveTimestamp: Date

        if let elapsedTimeNow {
            elapsedAtReceipt = elapsedTimeNow
            effectiveTimestamp = receivedAt
        } else if let elapsedTime, let sourceTimestamp {
            elapsedAtReceipt = elapsedTime
                + max(receivedAt.timeIntervalSince(sourceTimestamp), 0) * effectiveRate
            effectiveTimestamp = sourceTimestamp
        } else if let elapsedTime {
            elapsedAtReceipt = elapsedTime
            effectiveTimestamp = receivedAt
        } else {
            return nil
        }

        let clampedElapsed: TimeInterval
        if let duration, duration > 0 {
            clampedElapsed = min(max(elapsedAtReceipt, 0), duration)
        } else {
            clampedElapsed = max(elapsedAtReceipt, 0)
        }
        return AuthoritativeAnchor(
            trackIdentity: trackIdentity,
            elapsedAtAnchor: clampedElapsed,
            duration: duration,
            isPlaying: effectiveIsPlaying,
            playbackRate: effectiveRate,
            sourceTimestamp: effectiveTimestamp,
            sourceEventTimestamp: sourceTimestamp,
            anchorUptime: receivedUptime
        )
    }

    static func accepting(
        _ candidate: AuthoritativeAnchor,
        over current: AuthoritativeAnchor?
    ) -> AuthoritativeAnchor {
        guard let current else { return candidate }
        guard candidate.trackIdentity == current.trackIdentity else { return candidate }

        // get-now positions are anchored at receipt, whereas stream positions
        // retain the source event's timestamp. Compare source events first so
        // a genuine pause is not rejected as older than a get-now receipt.
        if let candidateEvent = candidate.sourceEventTimestamp,
           let currentEvent = current.sourceEventTimestamp {
            let eventDelta = candidateEvent.timeIntervalSince(currentEvent)
            if eventDelta > 0.001 { return candidate }
            if eventDelta < -0.001 { return current }
            if candidate.isPlaying != current.isPlaying,
               candidate.anchorUptime >= current.anchorUptime {
                // The source clock is rounded to seconds. A state change in
                // that same second can be newer than a get-now receipt;
                // retain the existing backward-position safety tolerance.
                let currentElapsed = elapsed(from: current, nowUptime: candidate.anchorUptime)
                    ?? current.elapsedAtAnchor
                return candidate.elapsedAtAnchor + 0.35 >= currentElapsed ? candidate : current
            }
        }
        let timestampDelta = candidate.sourceTimestamp.timeIntervalSince(current.sourceTimestamp)
        if timestampDelta > 0.001 {
            return candidate
        }
        if timestampDelta < -0.001 {
            return current
        }

        guard candidate.isPlaying != current.isPlaying,
              candidate.anchorUptime >= current.anchorUptime else {
            return current
        }
        let currentElapsed = elapsed(from: current, nowUptime: candidate.anchorUptime)
            ?? current.elapsedAtAnchor
        return candidate.elapsedAtAnchor + 0.35 >= currentElapsed ? candidate : current
    }

    static func elapsed(
        from anchor: AuthoritativeAnchor,
        nowUptime: TimeInterval
    ) -> TimeInterval? {
        let elapsed = anchor.elapsedAtAnchor
            + max(nowUptime - anchor.anchorUptime, 0) * anchor.playbackRate
        guard let duration = anchor.duration, duration > 0 else {
            return max(elapsed, 0)
        }
        return min(max(elapsed, 0), duration)
    }

    static func shouldAcceptAsyncSample(
        requestSampleID: UInt64,
        currentSampleID: UInt64,
        responseTrackIdentity: String?,
        currentTrackIdentity: String?
    ) -> Bool {
        guard currentSampleID > requestSampleID,
              let responseTrackIdentity,
              let currentTrackIdentity else {
            return true
        }
        return responseTrackIdentity == currentTrackIdentity
    }

    static func cachedOverrideElapsed(
        mediaRemoteElapsed: TimeInterval?,
        axProgress: Double?,
        duration: TimeInterval?,
        existingElapsed: TimeInterval?,
        existingIsPlaying: Bool?,
        axIsPlaying: Bool
    ) -> TimeInterval? {
        let elapsed: TimeInterval?
        if let mediaRemoteElapsed {
            elapsed = !axIsPlaying || existingIsPlaying == false
                ? max(mediaRemoteElapsed, existingElapsed ?? mediaRemoteElapsed)
                : mediaRemoteElapsed
        } else if let axProgress, let duration, duration > 0 {
            elapsed = min(max(axProgress, 0), 1) * duration
        } else {
            elapsed = existingElapsed
        }

        guard let elapsed else { return nil }
        guard let duration, duration > 0 else { return max(elapsed, 0) }
        return min(max(elapsed, 0), duration)
    }

}

import Foundation

enum PlaybackControlTimeline {
    enum TargetedControlExpectation: Equatable {
        case playbackState(
            baselineTrackIdentity: String,
            baselineIsPlaying: Bool,
            expectedIsPlaying: Bool
        )
        case trackChange(baselineIdentity: String)
    }

    enum TargetedControlConfirmation: Equatable {
        case confirmed
        case explicitlyUnchanged
        case inconclusive
    }

    struct TargetedControlObservation: Equatable {
        let sampleID: UInt64
        let trackIdentity: String?
        let isPlaying: Bool?
        let isValidQishuiSample: Bool

        init(
            sampleID: UInt64,
            trackIdentity: String?,
            isPlaying: Bool?,
            isValidQishuiSample: Bool = true
        ) {
            self.sampleID = sampleID
            self.trackIdentity = trackIdentity
            self.isPlaying = isPlaying
            self.isValidQishuiSample = isValidQishuiSample
        }
    }

    struct AuthoritativeAnchor: Equatable {
        let trackIdentity: String
        let elapsedAtAnchor: TimeInterval
        let duration: TimeInterval?
        let isPlaying: Bool
        let playbackRate: Double
        let sourceTimestamp: Date
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
        if targetIsPlaying {
            return confirmedElapsed ?? anchorElapsed
        }
        return anchorElapsed ?? confirmedElapsed
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
            anchorUptime: receivedUptime
        )
    }

    static func accepting(
        _ candidate: AuthoritativeAnchor,
        over current: AuthoritativeAnchor?
    ) -> AuthoritativeAnchor {
        guard let current else { return candidate }
        guard candidate.trackIdentity == current.trackIdentity else { return candidate }

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

    static func targetedControlConfirmation(
        expectation: TargetedControlExpectation,
        baselineSampleID: UInt64,
        observations: [TargetedControlObservation]
    ) -> TargetedControlConfirmation {
        var seenSampleIDs = Set<UInt64>()
        var unchangedSampleCount = 0
        var encounteredInvalidSample = false

        for observation in observations {
            guard observation.sampleID > baselineSampleID,
                  seenSampleIDs.insert(observation.sampleID).inserted else {
                continue
            }
            guard observation.isValidQishuiSample else {
                encounteredInvalidSample = true
                continue
            }

            switch expectation {
            case let .playbackState(
                baselineTrackIdentity,
                baselineIsPlaying,
                expectedIsPlaying
            ):
                guard observation.trackIdentity == baselineTrackIdentity,
                      let isPlaying = observation.isPlaying else {
                    encounteredInvalidSample = true
                    continue
                }
                if isPlaying == expectedIsPlaying {
                    return .confirmed
                }
                if isPlaying == baselineIsPlaying {
                    unchangedSampleCount += 1
                } else {
                    encounteredInvalidSample = true
                }
            case let .trackChange(baselineIdentity):
                guard let trackIdentity = observation.trackIdentity else {
                    encounteredInvalidSample = true
                    continue
                }
                if trackIdentity != baselineIdentity {
                    return .confirmed
                }
                unchangedSampleCount += 1
            }
        }

        guard !encounteredInvalidSample else { return .inconclusive }
        return unchangedSampleCount >= 2 ? .explicitlyUnchanged : .inconclusive
    }

    static func shouldRunAXFallback(
        controlGeneration: Int,
        currentGeneration: Int,
        targetedDispatched: Bool,
        confirmation: TargetedControlConfirmation
    ) -> Bool {
        guard controlGeneration == currentGeneration else { return false }
        return !targetedDispatched || confirmation == .explicitlyUnchanged
    }
}

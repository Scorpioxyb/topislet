import Foundation

/// Why one window/desktop lyric read produced what it did. Diagnostic only:
/// none of these values changes which lyric is shown or relaxes a gate.
enum QishuiLyricReadDiagnosis: String, Equatable, Sendable {
    case lines
    case noAccess = "no_access"
    case windowUnavailable = "window_unavailable"
    case identityRejected = "identity_rejected"
    case noCandidate = "no_candidate"

    static func classify(
        hasLines: Bool,
        windowState: QishuiMainWindowState,
        hasDesktopWindow: Bool,
        identityMismatch: Bool
    ) -> Self {
        if hasLines { return .lines }
        if windowState == .unknown { return .noAccess }
        if identityMismatch { return .identityRejected }
        if windowState != .open, !hasDesktopWindow { return .windowUnavailable }
        return .noCandidate
    }
}

/// Main-window state as seen by the read-only lyric reader. `open` means
/// present and not explicitly minimized; it may still be behind other windows.
enum QishuiMainWindowState: String, Equatable, Sendable {
    case open
    case minimized
    case closed
    case unknown
}

/// Accumulates one anonymous lyric outcome per Qishui track (global plan 4.4,
/// step 1). It records only categories, a count of seconds and the existing
/// truncated track hash, never titles, artists or lyric text.
struct QishuiLyricOutcomeTracker: Equatable {
    struct Outcome: Equatable {
        let result: String
        let timed: String
        let window: String
        let observedSeconds: Int
        let track: String

        var fields: [String: String] {
            [
                "source": "qishui",
                "result": result,
                "timed": timed,
                "window": window,
                "observed_s": String(observedSeconds),
                "track": track
            ]
        }
    }

    private enum TimedState: String {
        case off
        case notFinished = "not_finished"
        case ready
        case networkFailed = "network_failed"
        case unmatched
    }

    private var track: String?
    private var startedAt = Date.distantPast
    private var timed = TimedState.off
    private var reads = 0
    private var shownWindowLines = false
    private var shownDesktopLines = false
    private var lastEmptyDiagnosis: QishuiLyricReadDiagnosis?
    private var lastWindowState = QishuiMainWindowState.unknown

    /// Starts observing `track` and returns the finished outcome of the
    /// previous track, if there was one.
    mutating func restart(track newTrack: String?, timedEnabled: Bool, at now: Date) -> Outcome? {
        let finished = outcome(at: now)
        self = QishuiLyricOutcomeTracker()
        track = newTrack
        startedAt = now
        timed = timedEnabled ? .notFinished : .off
        return finished
    }

    mutating func recordRead(
        diagnosis: QishuiLyricReadDiagnosis,
        windowState: QishuiMainWindowState,
        acceptedLines: Bool,
        acceptedDesktop: Bool
    ) {
        guard track != nil else { return }
        reads += 1
        lastWindowState = windowState
        if acceptedLines {
            if acceptedDesktop { shownDesktopLines = true } else { shownWindowLines = true }
        }
        if diagnosis != .lines { lastEmptyDiagnosis = diagnosis }
    }

    mutating func recordTimedRead(receivedData: Bool) {
        guard track != nil, timed != .ready, !receivedData else { return }
        timed = .networkFailed
    }

    mutating func recordTimedFinished(hasLines: Bool) {
        guard track != nil, timed != .off else { return }
        if hasLines {
            timed = .ready
        } else if timed != .networkFailed {
            timed = .unmatched
        }
    }

    func outcome(at now: Date) -> Outcome? {
        guard let track else { return nil }
        return Outcome(
            result: result,
            timed: timed.rawValue,
            window: lastWindowState.rawValue,
            observedSeconds: max(0, Int(now.timeIntervalSince(startedAt))),
            track: track
        )
    }

    private var result: String {
        if timed == .ready { return "timed_verified" }
        if shownWindowLines { return "ax_window" }
        if shownDesktopLines { return "desktop_snapshot" }
        if reads == 0, timed == .off || timed == .notFinished { return "not_attempted" }
        switch lastEmptyDiagnosis {
        case .identityRejected: return "none_identity_rejected"
        default: break
        }
        if timed == .networkFailed { return "none_network_failed" }
        switch lastEmptyDiagnosis {
        case .noAccess: return "none_no_access"
        case .windowUnavailable: return "none_window_unavailable"
        default: return "none_no_candidate"
        }
    }
}

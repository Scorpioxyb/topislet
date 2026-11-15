import Foundation
import MusicUsageDiagnostics

/// Qishui lyrics: window / desktop AX reads on a background queue and the optional
/// network word-timed timeline, both bound to the identity the coordinator selects.
///
/// Moved out of `MusicAdapterCoordinator` unchanged (coordinator split step 4.2). The
/// coordinator's state reaches it only through `Host`, evaluated live at the same
/// points as before, so identity gates and their order are unchanged.
@MainActor
final class QishuiLyricPipeline {
    struct Host {
        let isObserving: @MainActor () -> Bool
        /// The coordinator's selection-gated lyric identity (calls source selection).
        let currentIdentity: @MainActor () -> QishuiLyricIdentity?
        let mediaTrack: @MainActor () -> MediaRemoteNowPlayingTrack?
        let directSnapshot: @MainActor () -> QishuiDirectSnapshot?
        let recordEvent: @MainActor (String, [String: String]) -> Void
        let publish: @MainActor () -> Void
        let debugSourceDescription: @MainActor () -> String

        @MainActor func record(_ name: String, fields: [String: String] = [:]) {
            recordEvent(name, fields)
        }
    }

    private let debugEnabled: Bool
    private let host: Host
    private let qishuiLyricReader = QishuiLyricReader()
    private let qishuiLyricQueue = DispatchQueue(label: "MacBookIsland.QishuiLyrics", qos: .userInitiated)
    private var latestQishuiLyrics: QishuiLyricSnapshot?
    private var requestedQishuiLyricIdentity: QishuiLyricIdentity?
    private var qishuiLyricGeneration: UInt64 = 0
    private var qishuiLyricReadInFlight = false
    private var qishuiLyricOutcome = QishuiLyricOutcomeTracker()
    private var lastQishuiLyricReadAt = Date.distantPast
    private var requestedTimedLyricIdentity: QishuiLyricIdentity?
    private(set) var timedIdentity: QishuiLyricIdentity?
    private(set) var timedLines: [QishuiTimedLine] = []
    private var lastTimedLyricAttemptAt = Date.distantPast
    private var timedLyricFailureCount = 0
    private var timedLyricCache = QishuiTimedLyricCache()
    private var timedLyricsEnabled = false
    private var timedLyricTask: Task<Void, Never>?

    init(debugEnabled: Bool, host: Host) {
        self.debugEnabled = debugEnabled
        self.host = host
    }

    func setTimedLyricsEnabled(_ enabled: Bool) {
        timedLyricsEnabled = enabled
        if !enabled {
            timedLyricTask?.cancel()
            timedLyricTask = nil
            requestedTimedLyricIdentity = nil
            timedIdentity = nil
            timedLines = []
            timedLyricCache = QishuiTimedLyricCache()
            timedLyricFailureCount = 0
            lastTimedLyricAttemptAt = .distantPast
        }
    }

    /// Age of the lyric snapshot behind a published lyric, or -1 when the
    /// published lines did not come from the current window/desktop read.
    func publishedLyricAgeMilliseconds(for state: MusicState) -> Int {
        guard let snapshot = latestQishuiLyrics,
              snapshot.lines == state.track.lyrics,
              QishuiTrackCoherencePolicy.matches(
                  mediaTitle: snapshot.identity.title,
                  mediaArtist: snapshot.identity.artist,
                  directTitle: state.track.title,
                  directArtist: state.track.artist
              ) else { return -1 }
        return max(Int(Date().timeIntervalSince(snapshot.checkedAt) * 1_000), 0)
    }

    func invalidate() {
        timedLyricTask?.cancel()
        timedLyricTask = nil
        qishuiLyricGeneration &+= 1
        latestQishuiLyrics = nil
        requestedQishuiLyricIdentity = nil
        lastQishuiLyricReadAt = .distantPast
        timedLines = []
        timedIdentity = nil
        requestedTimedLyricIdentity = nil
        lastTimedLyricAttemptAt = .distantPast
        timedLyricFailureCount = 0
    }

    func scheduleRefresh() {
        guard host.isObserving() else { return }
        let desiredIdentity = host.currentIdentity()
        if debugEnabled {
            fputs("[MusicAdapter] lyric identity=\(String(describing: desiredIdentity)) source=\(host.debugSourceDescription())\n", stderr)
        }
        if requestedQishuiLyricIdentity != desiredIdentity {
            invalidate()
            requestedQishuiLyricIdentity = desiredIdentity
            let finished = qishuiLyricOutcome.restart(
                track: desiredIdentity.map {
                    MusicUsageTrackFingerprint.make(source: "qishui", title: $0.title, artist: $0.artist)
                },
                timedEnabled: timedLyricsEnabled,
                at: Date()
            )
            if let finished { host.record("lyric_outcome", fields: finished.fields) }
        }
        guard let identity = desiredIdentity else { return }
        scheduleTimedRefresh(identity: identity)
        let now = Date()
        let position = host.mediaTrack()?.elapsedTime
        let isIntro = position.map {
            QishuiTimedLyricParser.upcomingFirstLine(at: $0, in: timedLines) != nil
                || QishuiTimedLyricParser.activeLine(at: $0, in: timedLines)
                    .map { MusicLyricPresentation.isSourceCredit($0.current.text) } == true
        } ?? false
        let hasVerifiedTimeline = hasTimedTimeline(for: identity) && !isIntro
        guard !qishuiLyricReadInFlight,
              now.timeIntervalSince(lastQishuiLyricReadAt) >= QishuiLyricRefreshPolicy.interval(
                  hasVerifiedTimeline: hasVerifiedTimeline
              ) else { return }
        lastQishuiLyricReadAt = now
        qishuiLyricReadInFlight = true
        let generation = qishuiLyricGeneration
        let reader = qishuiLyricReader
        let debugEnabled = debugEnabled
        qishuiLyricQueue.async { [weak self] in
            let snapshot = reader.read(identity: identity, includeIntroCredits: isIntro)
            let diagnosis = reader.lastDiagnosis
            let windowState = reader.lastWindowState
            if debugEnabled {
                fputs("[MusicAdapter] lyric read lines=\(snapshot.lines) identity=\(snapshot.identity)\n", stderr)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.qishuiLyricReadInFlight = false
                guard self.host.isObserving(),
                      self.qishuiLyricGeneration == generation,
                      self.host.currentIdentity() == identity else { return }
                let accepted = QishuiLyricRefreshPolicy.acceptedSnapshot(
                    snapshot, previous: self.latestQishuiLyrics, now: Date()
                )
                let linesChanged = self.latestQishuiLyrics?.lines != accepted.lines
                self.latestQishuiLyrics = accepted
                self.qishuiLyricOutcome.recordRead(
                    diagnosis: diagnosis,
                    windowState: windowState,
                    acceptedLines: !accepted.lines.isEmpty,
                    acceptedDesktop: accepted.isDesktopSnapshot
                )
                if linesChanged {
                    self.host.publish()
                }
                if self.debugEnabled {
                    fputs("[MusicAdapter] lyric published lines=\(snapshot.lines)\n", stderr)
                }
            }
        }
    }

    private func hasTimedTimeline(for identity: QishuiLyricIdentity) -> Bool {
        guard timedLyricsEnabled,
              timedIdentity == identity,
              !timedLines.isEmpty,
              let track = host.mediaTrack(),
              track.elapsedTime != nil else { return false }
        return QishuiTrackCoherencePolicy.matches(
            mediaTitle: identity.title, mediaArtist: identity.artist,
            directTitle: track.title, directArtist: track.artist
        )
    }

    private func scheduleTimedRefresh(identity: QishuiLyricIdentity) {
        guard timedLyricsEnabled,
              requestedTimedLyricIdentity != identity,
              let track = host.mediaTrack(),
              let duration = track.duration, duration > 0,
              QishuiTrackCoherencePolicy.matches(
                  mediaTitle: identity.title,
                  mediaArtist: identity.artist,
                  directTitle: track.title,
                  directArtist: track.artist
              ) else { return }
        if let cached = timedLyricCache.lines(
            title: identity.title, artist: identity.artist, duration: duration
        ) {
            requestedTimedLyricIdentity = identity
            timedIdentity = identity
            timedLines = cached
            qishuiLyricOutcome.recordTimedFinished(hasLines: true)
            host.record("timed_lyrics_ready", fields: ["origin": "cache"])
            return
        }
        guard Date().timeIntervalSince(lastTimedLyricAttemptAt) >=
                QishuiTimedLyricRetryPolicy.interval(failureCount: timedLyricFailureCount) else { return }
        requestedTimedLyricIdentity = identity
        lastTimedLyricAttemptAt = Date()
        let startedAt = Date()
        let generation = qishuiLyricGeneration
        timedLyricTask = Task { [weak self] in
            let lines = await QishuiTimedLyricSource().fetch(
                title: identity.title,
                artist: identity.artist,
                duration: duration
            ) { [weak self] measurement in
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled, let self,
                          self.host.isObserving(),
                          self.qishuiLyricGeneration == generation,
                          self.requestedTimedLyricIdentity == identity,
                          self.host.currentIdentity() == identity,
                          self.timedLyricsEnabled else { return }
                    self.qishuiLyricOutcome.recordTimedRead(receivedData: measurement.receivedData)
                    self.host.record("timed_lyric_read", fields: [
                        "stage": measurement.stage.rawValue,
                        "latency_ms": String(measurement.latencyMilliseconds),
                        "outcome": measurement.receivedData ? "received" : "empty"
                    ])
                }
            }
            guard !Task.isCancelled,
                  let self, self.qishuiLyricGeneration == generation,
                  self.requestedTimedLyricIdentity == identity,
                  self.host.currentIdentity() == identity,
                  self.timedLyricsEnabled else { return }
            self.timedIdentity = lines.isEmpty ? nil : identity
            self.timedLines = lines
            self.qishuiLyricOutcome.recordTimedFinished(hasLines: !lines.isEmpty)
            if lines.isEmpty {
                self.requestedTimedLyricIdentity = nil
                self.timedLyricFailureCount = min(self.timedLyricFailureCount + 1, 5)
                // Backoff starts at completion, not at the beginning of a slow request.
                self.lastTimedLyricAttemptAt = Date()
            } else {
                self.timedLyricFailureCount = 0
                self.timedLyricCache.insert(lines, title: identity.title, artist: identity.artist, duration: duration)
                self.host.record("timed_lyrics_ready", fields: [
                    "origin": "network",
                    "latency_ms": String(max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)))
                ])
                self.host.publish()
            }
        }
    }

    func lyrics(for track: MediaRemoteNowPlayingTrack) -> QishuiLyricSnapshot? {
        // The verified visible credit row is authoritative during the intro.
        let isIntro = track.elapsedTime.map {
            QishuiTimedLyricParser.upcomingFirstLine(at: $0, in: timedLines) != nil
                || QishuiTimedLyricParser.activeLine(at: $0, in: timedLines)
                    .map { MusicLyricPresentation.isSourceCredit($0.current.text) } == true
        } ?? false
        if let snapshot = latestQishuiLyrics,
           timedLines.isEmpty || isIntro,
           snapshot.identity == host.currentIdentity(),
           snapshot.lines.first.map(MusicLyricPresentation.isSourceCredit) == true,
           QishuiTrackCoherencePolicy.matches(mediaTitle: snapshot.identity.title, mediaArtist: snapshot.identity.artist,
                                             directTitle: track.title, directArtist: track.artist),
           QishuiLyricFreshnessPolicy.accepts(checkedAt: snapshot.checkedAt, now: Date()) {
            return snapshot
        }
        if let timed = timedLyrics(for: track) { return timed }
        if let snapshot = latestQishuiLyrics,
           snapshot.identity == host.currentIdentity(),
           !snapshot.lines.isEmpty,
           QishuiTrackCoherencePolicy.matches(
               mediaTitle: snapshot.identity.title,
               mediaArtist: snapshot.identity.artist,
               directTitle: track.title,
               directArtist: track.artist
           ),
           QishuiLyricFreshnessPolicy.accepts(checkedAt: snapshot.checkedAt, now: Date()) {
            return snapshot
        }
        return nil
    }

    private func timedLyrics(for track: MediaRemoteNowPlayingTrack) -> QishuiLyricSnapshot? {
        guard timedLyricsEnabled,
              let identity = timedIdentity,
              identity == host.currentIdentity(),
              QishuiTrackCoherencePolicy.matches(
                  mediaTitle: identity.title,
                  mediaArtist: identity.artist,
                  directTitle: track.title,
                  directArtist: track.artist
              ),
              let elapsed = track.elapsedTime else { return nil }
        if QishuiTimedLyricParser.upcomingFirstLine(at: elapsed, in: timedLines) != nil {
            let sourceCredits: [String]
            if let directTrack = host.directSnapshot()?.currentTrack,
               QishuiTrackCoherencePolicy.matches(
                   mediaTitle: track.title,
                   mediaArtist: track.artist,
                   directTitle: directTrack.title,
                   directArtist: directTrack.artist
               ) {
                sourceCredits = MusicLyricPresentation.sourceCreditLines(directTrack.lyrics)
            } else {
                sourceCredits = []
            }
            guard !sourceCredits.isEmpty else { return nil }
            return QishuiLyricSnapshot(
                identity: identity,
                lines: sourceCredits,
                isDesktopSnapshot: true,
                checkedAt: Date()
            )
        }
        guard let active = QishuiTimedLyricParser.activeLine(
            at: elapsed, in: timedLines, trackDuration: track.duration
        ) else { return nil }
        return QishuiLyricSnapshot(
            identity: identity,
            lines: [active.current.text] + (active.next.map { [$0.text] } ?? []),
            isDesktopSnapshot: true,
            checkedAt: Date()
        )
    }

    func lyrics(for track: QishuiDirectTrack) -> QishuiLyricSnapshot? {
        guard let snapshot = latestQishuiLyrics,
              snapshot.identity.processIdentifier == host.directSnapshot()?.processIdentifier,
              QishuiTrackCoherencePolicy.matches(
                  mediaTitle: snapshot.identity.title,
                  mediaArtist: snapshot.identity.artist,
                  directTitle: track.title,
                  directArtist: track.artist
              ),
              QishuiLyricFreshnessPolicy.accepts(
                  checkedAt: snapshot.checkedAt,
                  now: Date()
              ) else { return nil }
        return snapshot
    }
}

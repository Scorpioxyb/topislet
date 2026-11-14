import Foundation
import MusicUsageDiagnostics
import OSLog

/// A Qishui next/previous command whose stages are still being timed.
struct PendingUsageQishuiTrackTransition {
    let transitionID: String
    let startedAt: Date
    let baselineTrackFingerprint: String?
    var atomicCompleteEvent: QishuiTrackTransitionStageEvent?
    var didRecordAdapterDelivery = false
}

/// Write-only anonymous usage diagnostics for the music coordinator (global
/// plan 4.2, step 1). It owns the de-duplication fingerprints and the
/// track-transition timing state. Nothing it holds feeds back into what is
/// displayed or controlled; the values it returns only tell the coordinator
/// that a track change was recorded or a transition finished, which the
/// coordinator already acted on before this type existed.
final class MusicUsageEmitter {
    typealias Sink = (MusicUsageEvent) -> Void

    private static let logger = Logger(
        subsystem: "io.github.scorpioxyb.topislet",
        category: "MusicUsage"
    )

    static func log(_ event: MusicUsageEvent) {
        let message = event.encodedMessage
        logger.notice("\(message, privacy: .public)")
    }

    private let sink: Sink
    private var requestID: UInt64 = 0
    private var observationStartedAt: Date?
    private var lastHeartbeatAt: Date?
    private var lastTrackFingerprint: String?
    private var lastTrackSource = "none"
    private var lastTrackHadArtwork = false
    private var artworkPendingSince: [String: Date] = [:]
    private var lastPlaybackFingerprint: String?
    private var lastSyncFingerprint: String?
    private var lastUIPublishFingerprint: String?
    private var lastTimelineUIPublishFingerprint: String?
    private var lastAdmissionFingerprint: String?
    private var lastLyricFingerprint: String?
    private var lastDirectIdentityFingerprint: String?
    private(set) var pendingQishuiTransition: PendingUsageQishuiTrackTransition?

    init(sink: @escaping Sink = MusicUsageEmitter.log) {
        self.sink = sink
    }

    nonisolated static func sourceLabel(_ source: MusicSourceID?) -> String {
        switch source {
        case .qishui:
            return "qishui"
        case .neteaseMusic:
            return "netease"
        case .appleMusic:
            return "apple-music"
        case nil:
            return "none"
        }
    }

    func record(_ name: String, fields: [String: String] = [:]) {
        sink(MusicUsageEvent(name: name, fields: fields))
    }

    func nextRequestID() -> UInt64 {
        requestID &+= 1
        return requestID
    }

    // MARK: Observation lifecycle and heartbeat

    func observationStarted(at now: Date) {
        observationStartedAt = now
        lastHeartbeatAt = now
        record("observation_start")
    }

    func observationStopped(at now: Date) {
        let durationMilliseconds = observationStartedAt.map {
            max(Int(now.timeIntervalSince($0) * 1_000), 0)
        } ?? 0
        record("observation_stop", fields: [
            "duration_ms": String(durationMilliseconds)
        ])
        observationStartedAt = nil
        lastHeartbeatAt = nil
        lastLyricFingerprint = nil
        lastDirectIdentityFingerprint = nil
    }

    func recordHeartbeatIfNeeded(
        isObserving: Bool,
        hasTrack: Bool,
        isPlaying: Bool,
        source: String,
        now: Date
    ) {
        guard isObserving,
              MusicUsageHeartbeatPolicy.shouldRecord(
                lastRecordedAt: lastHeartbeatAt,
                now: now
              ) else { return }
        lastHeartbeatAt = now
        record("observation_heartbeat", fields: [
            "has_track": hasTrack ? "1" : "0",
            "playback": isPlaying ? "playing" : "paused",
            "source": source,
            "uptime_ms": String(max(Int(
                now.timeIntervalSince(observationStartedAt ?? now) * 1_000
            ), 0))
        ])
    }

    // MARK: De-duplicated source evidence

    func recordDirectIdentityIfChanged(fingerprint: String, hasTrack: Bool, hasProgress: Bool) {
        guard fingerprint != lastDirectIdentityFingerprint else { return }
        lastDirectIdentityFingerprint = fingerprint
        record("direct_identity_applied", fields: [
            "source": "qishui", "track": fingerprint,
            "has_track": hasTrack ? "1" : "0",
            "has_progress": hasProgress ? "1" : "0"
        ])
    }

    func recordAdmissionEvidenceIfChanged(evidence: String, directPlayback: Bool, origin: String) {
        let fingerprint = "\(evidence):\(directPlayback):\(origin)"
        guard fingerprint != lastAdmissionFingerprint else { return }
        lastAdmissionFingerprint = fingerprint
        record("playback_admission_evidence", fields: [
            "source": "qishui", "evidence": evidence,
            "direct_playback": directPlayback ? "1" : "0",
            "origin": origin
        ])
    }

    // MARK: Qishui track transitions

    func beginQishuiTransition(
        transitionID: String,
        startedAt: Date,
        baselineTrackFingerprint: String?
    ) {
        pendingQishuiTransition = PendingUsageQishuiTrackTransition(
            transitionID: transitionID,
            startedAt: startedAt,
            baselineTrackFingerprint: baselineTrackFingerprint
        )
    }

    func clearQishuiTransition() {
        pendingQishuiTransition = nil
    }

    func recordQishuiTransitionStage(_ event: QishuiTrackTransitionStageEvent) {
        guard var transition = pendingQishuiTransition,
              transition.transitionID == event.transitionID else { return }
        recordQishuiTransitionStage(
            transitionID: event.transitionID,
            stage: event.stage.rawValue,
            latencyMilliseconds: event.latencyMilliseconds,
            hasArtist: event.hasArtist,
            hasArtwork: event.hasArtwork,
            hasAlbum: event.hasAlbum,
            hasDuration: event.hasDuration,
            wasDeferred: event.wasDeferred
        )
        if event.stage == .atomicComplete {
            transition.atomicCompleteEvent = event
            pendingQishuiTransition = transition
        }
    }

    func recordQishuiTransitionStage(
        transitionID: String,
        stage: String,
        latencyMilliseconds: Int,
        hasArtist: Bool,
        hasArtwork: Bool,
        hasAlbum: Bool,
        hasDuration: Bool,
        wasDeferred: Bool
    ) {
        record("track_transition_stage", fields: [
            "deferred": wasDeferred ? "1" : "0",
            "has_album": hasAlbum ? "1" : "0",
            "has_artist": hasArtist ? "1" : "0",
            "has_artwork": hasArtwork ? "1" : "0",
            "has_duration": hasDuration ? "1" : "0",
            "latency_ms": String(max(latencyMilliseconds, 0)),
            "source": "qishui",
            "stage": stage,
            "transition": transitionID
        ])
    }

    // MARK: Adapter state

    /// Records sync, track, artwork and playback changes for a state the
    /// coordinator produced. Returns true when a new track was recorded.
    @discardableResult
    func recordState(
        _ state: MusicState,
        status: MusicSourceStatus,
        sourceID: MusicSourceID?,
        mediaTrack: (title: String, artist: String)?,
        directTrack: (title: String, artist: String)?,
        now: Date = Date()
    ) -> Bool {
        let source = Self.sourceLabel(sourceID)
        let syncFingerprint = "\(source):\(status.availability.rawValue)"
        if syncFingerprint != lastSyncFingerprint {
            lastSyncFingerprint = syncFingerprint
            record("sync_state", fields: [
                "source": source,
                "status": status.availability.rawValue
            ])
        }

        guard state.hasCurrentTrack else {
            if let previousTrack = lastTrackFingerprint {
                record("track_empty", fields: [
                    "source": lastTrackSource,
                    "track": previousTrack
                ])
            }
            lastTrackFingerprint = nil
            lastTrackSource = source
            lastTrackHadArtwork = false
            lastPlaybackFingerprint = nil
            return false
        }

        let trackFingerprint = MusicUsageTrackFingerprint.make(
            source: source,
            title: state.track.title,
            artist: state.track.artist
        )
        if sourceID == .qishui,
           var transition = pendingQishuiTransition,
           let complete = transition.atomicCompleteEvent,
           !transition.didRecordAdapterDelivery,
           QishuiTransitionDeliveryPolicy.accepts(state: state, complete: complete) {
            transition.didRecordAdapterDelivery = true
            pendingQishuiTransition = transition
            recordQishuiTransitionStage(
                transitionID: transition.transitionID, stage: "adapter_delivery",
                latencyMilliseconds: max(0, Int(now.timeIntervalSince(transition.startedAt) * 1_000)),
                hasArtist: !state.track.artist.isEmpty,
                hasArtwork: state.track.hasArtwork || state.track.artworkData != nil || state.track.artworkURL != nil,
                hasAlbum: complete.hasAlbum, hasDuration: state.duration != nil,
                wasDeferred: false
            )
        }
        let artworkKey = "\(source):\(trackFingerprint)"
        let hasArtwork = state.track.hasArtwork
            || state.track.artworkData != nil
            || state.track.artworkURL != nil
        let didChangeTrack = trackFingerprint != lastTrackFingerprint
            || source != lastTrackSource
        if didChangeTrack {
            lastTrackFingerprint = trackFingerprint
            lastTrackSource = source
            lastTrackHadArtwork = hasArtwork
            if !hasArtwork {
                artworkPendingSince[artworkKey] = now
                while artworkPendingSince.count > 12,
                      let oldest = artworkPendingSince.min(
                        by: { $0.value < $1.value }
                      )?.key {
                    artworkPendingSince.removeValue(forKey: oldest)
                }
            }
            var trackFields = [
                "can_seek": state.canSeek ? "1" : "0",
                "has_artist": state.track.artist.isEmpty ? "0" : "1",
                "has_artwork": hasArtwork ? "1" : "0",
                "has_duration": state.duration != nil ? "1" : "0",
                "has_lyrics": state.track.lyrics.isEmpty ? "0" : "1",
                "playback": state.isPlaying ? "playing" : "paused",
                "source": source,
                "track": trackFingerprint
            ]
            if sourceID == .qishui {
                trackFields["media_track"] = mediaTrack.map {
                    MusicUsageTrackFingerprint.make(source: "qishui", title: $0.title, artist: $0.artist)
                } ?? "none"
                trackFields["direct_track"] = directTrack.map {
                    MusicUsageTrackFingerprint.make(source: "qishui", title: $0.title, artist: $0.artist)
                } ?? "none"
                trackFields["media_match"] = mediaTrack.map {
                    QishuiTrackCoherencePolicy.matches(
                        mediaTitle: state.track.title, mediaArtist: state.track.artist,
                        directTitle: $0.title, directArtist: $0.artist
                    ) ? "1" : "0"
                } ?? "0"
                trackFields["direct_match"] = directTrack.map {
                    QishuiTrackCoherencePolicy.matches(
                        mediaTitle: state.track.title, mediaArtist: state.track.artist,
                        directTitle: $0.title, directArtist: $0.artist
                    ) ? "1" : "0"
                } ?? "0"
            }
            record("track_changed", fields: trackFields)
        } else if hasArtwork, !lastTrackHadArtwork {
            let latencyMilliseconds = artworkPendingSince
                .removeValue(forKey: artworkKey)
                .map { max(Int(now.timeIntervalSince($0) * 1_000), 0) }
            lastTrackHadArtwork = true
            record("artwork_ready", fields: [
                "latency_ms": String(latencyMilliseconds ?? 0),
                "source": source,
                "track": trackFingerprint
            ])
        }

        let playbackFingerprint = "\(source):\(trackFingerprint):\(state.isPlaying)"
        if playbackFingerprint != lastPlaybackFingerprint {
            lastPlaybackFingerprint = playbackFingerprint
            record("playback_state", fields: [
                "source": source,
                "state": state.isPlaying ? "playing" : "paused",
                "track": trackFingerprint
            ])
        }
        return didChangeTrack
    }

    // MARK: UI publication

    /// Records what the island actually published. `lyricAgeMilliseconds`
    /// is evaluated only when a new lyric publication is recorded. Returns
    /// the ID of a Qishui transition this publication completed, so the
    /// caller can end the stream source's observation of it.
    func recordUIPublished(
        _ state: MusicState,
        lyricAgeMilliseconds: () -> Int,
        now: Date = Date()
    ) -> String? {
        guard state.hasCurrentTrack else {
            lastUIPublishFingerprint = nil
            lastTimelineUIPublishFingerprint = nil
            return nil
        }
        let source = Self.sourceLabel(MusicSourceID(
            bundleIdentifier: state.track.sourceBundleIdentifier
        ))
        let trackFingerprint = MusicUsageTrackFingerprint.make(
            source: source,
            title: state.track.title,
            artist: state.track.artist
        )
        let hasArtwork = state.track.hasArtwork
            || state.track.artworkData != nil
            || state.track.artworkURL != nil
        let uiFingerprint = [
            source,
            trackFingerprint,
            hasArtwork ? "artwork" : "no-artwork",
            state.isPlaying ? "playing" : "paused"
        ].joined(separator: ":")
        if uiFingerprint != lastUIPublishFingerprint {
            lastUIPublishFingerprint = uiFingerprint
            record("ui_published", fields: [
                "has_artwork": hasArtwork ? "1" : "0",
                "playback": state.isPlaying ? "playing" : "paused",
                "source": source,
                "track": trackFingerprint
            ])
        }
        // A single AX sample can be empty during view reconstruction.
        // Record actual published timeline capability separately so that
        // we can distinguish that from a real data/capability downgrade.
        let timelineFingerprint = [
            source, trackFingerprint,
            state.duration == nil ? "no-duration" : "duration",
            state.elapsedTime == nil ? "no-elapsed" : "elapsed",
            state.canSeek ? "seek" : "no-seek",
            state.playbackStateKnown ? "known" : "unknown"
        ].joined(separator: ":")
        if timelineFingerprint != lastTimelineUIPublishFingerprint {
            lastTimelineUIPublishFingerprint = timelineFingerprint
            record("timeline_ui_state", fields: [
                "source": source,
                "track": trackFingerprint,
                "has_duration": state.duration == nil ? "0" : "1",
                "has_elapsed": state.elapsedTime == nil ? "0" : "1",
                "can_seek": state.canSeek ? "1" : "0",
                "playback_known": state.playbackStateKnown ? "1" : "0"
            ])
        }

        if source == "qishui", !state.track.lyrics.isEmpty {
            let lyricFingerprint = MusicUsageLyricFingerprint.make(
                source: source,
                title: state.track.title,
                artist: state.track.artist,
                lines: state.track.lyrics
            )
            if lyricFingerprint != lastLyricFingerprint {
                lastLyricFingerprint = lyricFingerprint
                record("lyric_ui_published", fields: [
                    "desktop_snapshot": state.track.lyricsAreDesktopSnapshot ? "1" : "0",
                    "line_count": String(state.track.lyrics.count),
                    "lyric_age_ms": String(lyricAgeMilliseconds()),
                    "source": source,
                    "track": trackFingerprint,
                    "lyric": lyricFingerprint
                ])
            }
        } else if state.track.lyrics.isEmpty {
            lastLyricFingerprint = nil
        }
        guard source == "qishui",
              let transition = pendingQishuiTransition,
              let completeEvent = transition.atomicCompleteEvent,
              QishuiTransitionDeliveryPolicy.accepts(state: state, complete: completeEvent) else {
            return nil
        }
        recordQishuiTransitionStage(
            transitionID: transition.transitionID,
            stage: "ui_published",
            latencyMilliseconds: max(
                Int(now.timeIntervalSince(transition.startedAt) * 1_000),
                0
            ),
            hasArtist: !state.track.artist.isEmpty,
            hasArtwork: hasArtwork,
            hasAlbum: completeEvent.hasAlbum,
            hasDuration: state.duration != nil,
            wasDeferred: false
        )
        pendingQishuiTransition = nil
        return transition.transitionID
    }
}

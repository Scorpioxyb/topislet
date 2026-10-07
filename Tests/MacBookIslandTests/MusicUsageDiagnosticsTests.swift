import Foundation
import MusicUsageDiagnostics
import Testing

@Test
func usageEventRoundTripsWithoutFreeText() throws {
    let event = MusicUsageEvent(
        name: "control result",
        fields: [
            "source": "apple music",
            "latency_ms": "123"
        ]
    )
    #expect(event.encodedMessage == "topislet_usage v=1 event=control_result latency_ms=123 source=apple_music")
    #expect(MusicUsageEvent.parse(event.encodedMessage) == event)
}

@Test
func trackFingerprintIsStableAndDoesNotExposeMetadata() {
    let fingerprint = MusicUsageTrackFingerprint.make(
        source: "qishui",
        title: "Private Song",
        artist: "Private Artist"
    )
    #expect(fingerprint.count == 12)
    #expect(fingerprint == MusicUsageTrackFingerprint.make(
        source: "qishui",
        title: "Private Song",
        artist: "Private Artist"
    ))
    #expect(!fingerprint.contains("Private"))
}

@Test
func lyricFingerprintIsStableAndDoesNotExposeLyricText() {
    let first = MusicUsageLyricFingerprint.make(
        source: "qishui",
        title: "Private Song",
        artist: "Private Artist",
        lines: ["secret original", "secret translation"]
    )
    let second = MusicUsageLyricFingerprint.make(
        source: "qishui",
        title: "Private Song",
        artist: "Private Artist",
        lines: ["secret original", "secret translation"]
    )
    let changed = MusicUsageLyricFingerprint.make(
        source: "qishui",
        title: "Private Song",
        artist: "Private Artist",
        lines: ["next original", "next translation"]
    )

    #expect(first.count == 12)
    #expect(first == second)
    #expect(first != changed)
    #expect(!first.contains("secret"))
}

@Test
func dailyAnalyzerSummarizesAnonymousLyricPublicationLatency() {
    let start = Date(timeIntervalSince1970: 8_000)
    let records = [
        TimestampedMusicUsageEvent(
            timestamp: start,
            event: MusicUsageEvent(name: "lyric_ui_published", fields: [
                "source": "qishui",
                "lyric_age_ms": "351",
                "lyric": "abc123"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(1),
            event: MusicUsageEvent(name: "lyric_ui_published", fields: [
                "source": "qishui",
                "lyric_age_ms": "504",
                "lyric": "def456"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(2),
            event: MusicUsageEvent(name: "lyric_ui_published", fields: [
                "source": "qishui",
                "lyric_age_ms": "-1",
                "lyric": "unknown"
            ])
        )
    ]

    let summary = MusicUsageDailyAnalyzer.analyze(records)
    #expect(summary.lyricUIPublicationLatency.count == 2)
    #expect(summary.lyricUIPublicationLatency.p50Milliseconds == 351)
    #expect(summary.lyricUIPublicationLatency.p95Milliseconds == 504)
    #expect(summary.lyricUIPublicationLatency.maximumMilliseconds == 504)
}

@Test
func qishuiProbeOutputRedactsUserPathsAndIdentifiers() {
    let home = URL(fileURLWithPath: "/Users/private-user")
    let root = home.appendingPathComponent(
        "Library/Containers/com.soda.music/Data/Library/Application Support/SodaMusic"
    )

    #expect(QishuiProbePrivacy.rootDescription(root: root, home: home) ==
        "~/Library/Containers/com.soda.music/Data/Library/Application Support/SodaMusic")
    #expect(QishuiProbePrivacy.rootDescription(
        root: URL(fileURLWithPath: "/Users/private-user/Documents/private"),
        home: home
    ) == "~/Documents/private")
    #expect(QishuiProbePrivacy.keyLabel("u_123456789:feed") == "u_<redacted>:feed")
    #expect(QishuiProbePrivacy.keyLabel("track-6704975600089565186") == "track-<redacted>")
    #expect(QishuiProbePrivacy.candidateFieldLabel(for: "track_value") == "track")
    #expect(QishuiProbePrivacy.candidateFieldLabel(for: "currentPlayableKey") == "current_playable")

    let description = QishuiProbePrivacy.fileDescription(
        url: root.appendingPathComponent("LunaCacheV2/entries.db"),
        relativeTo: root
    )
    #expect(description.contains("bucket=LunaCacheV2"))
    #expect(description.contains("fileType=db"))
    #expect(!description.contains("private-user"))
    #expect(!description.contains("entries.db"))
}

@Test
func dailyAnalyzerSummarizesQishuiTransitionStagesWithoutMetadata() {
    let start = Date(timeIntervalSince1970: 3_500)
    let records = [
        TimestampedMusicUsageEvent(
            timestamp: start,
            event: MusicUsageEvent(name: "track_transition_stage", fields: [
                "source": "qishui", "stage": "control_result", "transition": "q1",
                "latency_ms": "0", "deferred": "0", "has_artwork": "1"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.1),
            event: MusicUsageEvent(name: "track_transition_stage", fields: [
                "source": "qishui", "stage": "first_candidate", "transition": "q1",
                "latency_ms": "100", "deferred": "1", "has_artwork": "0"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.6),
            event: MusicUsageEvent(name: "track_transition_stage", fields: [
                "source": "qishui", "stage": "atomic_complete", "transition": "q1",
                "latency_ms": "600", "deferred": "0", "has_artwork": "1"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.612),
            event: MusicUsageEvent(name: "track_transition_stage", fields: [
                "source": "qishui", "stage": "ui_published", "transition": "q1",
                "latency_ms": "612", "deferred": "0", "has_artwork": "1"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(1),
            event: MusicUsageEvent(name: "track_transition_stage", fields: [
                "source": "qishui", "stage": "control_result", "transition": "q2",
                "latency_ms": "0", "deferred": "0", "has_artwork": "1"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(1.1),
            event: MusicUsageEvent(name: "track_transition_stage", fields: [
                "source": "qishui", "stage": "first_candidate", "transition": "q2",
                "latency_ms": "100", "deferred": "1", "has_artwork": "0"
            ])
        )
    ]

    let summary = MusicUsageDailyAnalyzer.analyze(
        records,
        generatedAt: start.addingTimeInterval(2)
    )
    #expect(summary.schemaVersion == 6)
    #expect(summary.qishuiTrackTransitions.total == 2)
    #expect(summary.qishuiTrackTransitions.deferredCount == 2)
    #expect(summary.qishuiTrackTransitions.firstCandidateCount == 2)
    #expect(summary.qishuiTrackTransitions.atomicCompleteCount == 1)
    #expect(summary.qishuiTrackTransitions.uiPublishedCount == 1)
    #expect(summary.qishuiTrackTransitions.incompleteCount == 1)
    #expect(summary.qishuiTrackTransitions.atomicCompleteMissingArtworkCount == 0)
    #expect(summary.qishuiTrackTransitions.firstCandidateLatency.p50Milliseconds == 100)
    #expect(summary.qishuiTrackTransitions.atomicCompleteLatency.p95Milliseconds == 600)
    #expect(summary.qishuiTrackTransitions.uiPublishedLatency.p50Milliseconds == 612)
    #expect(summary.sampleCoverage.status == "partial")
    #expect(summary.sampleCoverage.missingSampleKinds.contains("qishui_transition"))
    #expect(summary.anomalies == ["qishui_transition_incomplete=1"])
}

@Test
func dailyAnalyzerCorrelatesControlTrackAndArtworkLatency() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let records = [
        TimestampedMusicUsageEvent(
            timestamp: start,
            event: MusicUsageEvent(name: "control_issued", fields: [
                "request": "7", "source": "qishui", "command": "next"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.1),
            event: MusicUsageEvent(name: "control_result", fields: [
                "request": "7", "source": "qishui", "command": "next",
                "outcome": "accepted", "latency_ms": "100"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.3),
            event: MusicUsageEvent(name: "track_changed", fields: [
                "source": "qishui", "track": "abc123", "has_artwork": "0"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.8),
            event: MusicUsageEvent(name: "artwork_ready", fields: [
                "source": "qishui", "track": "abc123"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.31),
            event: MusicUsageEvent(name: "ui_published", fields: [
                "source": "qishui", "track": "abc123", "has_artwork": "0"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.81),
            event: MusicUsageEvent(name: "ui_published", fields: [
                "source": "qishui", "track": "abc123", "has_artwork": "1"
            ])
        )
    ]
    let summary = MusicUsageDailyAnalyzer.analyze(
        records,
        generatedAt: start.addingTimeInterval(1)
    )
    #expect(summary.controls.accepted == 1)
    #expect(summary.controlToTrackLatency.p50Milliseconds == 310)
    #expect(summary.metadataToArtworkLatency.p50Milliseconds == 510)
    #expect(summary.controlToArtworkLatency.p50Milliseconds == 810)
    #expect(summary.anomalies.isEmpty)
}

@Test
func dailyAnalyzerSeparatesPlaybackUIAndAuthoritativeConfirmation() {
    let start = Date(timeIntervalSince1970: 1_500)
    let records = [
        TimestampedMusicUsageEvent(
            timestamp: start,
            event: MusicUsageEvent(name: "control_issued", fields: [
                "request": "8", "source": "qishui", "command": "play_pause",
                "target_playback": "paused"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.025),
            event: MusicUsageEvent(name: "ui_published", fields: [
                "source": "qishui", "track": "abc123", "has_artwork": "1",
                "playback": "paused"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.1),
            event: MusicUsageEvent(name: "control_result", fields: [
                "request": "8", "source": "qishui", "command": "play_pause",
                "target_playback": "paused", "outcome": "accepted",
                "latency_ms": "100"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.42),
            event: MusicUsageEvent(name: "playback_confirmed", fields: [
                "source": "qishui", "target_playback": "paused",
                "latency_ms": "420"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(1),
            event: MusicUsageEvent(name: "seek_confirmed", fields: [
                "source": "qishui", "latency_ms": "680"
            ])
        )
    ]
    let summary = MusicUsageDailyAnalyzer.analyze(records, generatedAt: start)
    #expect(summary.controlToPlaybackUILatency.p50Milliseconds == 25)
    #expect(summary.playbackConfirmationLatency.p50Milliseconds == 420)
    #expect(summary.playbackConfirmationTimeoutCount == 0)
    #expect(summary.seekConfirmationLatency.p50Milliseconds == 680)
    #expect(summary.seekConfirmationTimeoutCount == 0)
}

@Test
func dailyAnalyzerReportsOnlyActionableAnomalies() {
    let start = Date(timeIntervalSince1970: 2_000)
    let records = [
        TimestampedMusicUsageEvent(
            timestamp: start,
            event: MusicUsageEvent(name: "source_change", fields: [
                "from": "qishui", "to": "none"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.2),
            event: MusicUsageEvent(name: "source_change", fields: [
                "from": "none", "to": "qishui"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.3),
            event: MusicUsageEvent(name: "seek_result", fields: [
                "outcome": "rejected", "latency_ms": "20"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.4),
            event: MusicUsageEvent(name: "playback_confirmation_timeout")
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.5),
            event: MusicUsageEvent(name: "seek_confirmation_timeout")
        )
    ]
    let summary = MusicUsageDailyAnalyzer.analyze(records, generatedAt: start)
    #expect(summary.rapidSourceSwitchCount == 1)
    #expect(summary.anomalies == [
        "seek_rejected=1",
        "rapid_source_switch=1",
        "playback_confirmation_timeout=1",
        "seek_confirmation_timeout=1"
    ])
}

@Test
func dailyAnalyzerDoesNotTreatMissingUsageAsPassingCoverage() {
    let start = Date(timeIntervalSince1970: 3_000)
    let records = [
        TimestampedMusicUsageEvent(
            timestamp: start,
            event: MusicUsageEvent(name: "observation_start")
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(15 * 60),
            event: MusicUsageEvent(name: "observation_heartbeat", fields: [
                "source": "qishui", "has_track": "0", "playback": "paused"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(15 * 60 + 1),
            event: MusicUsageEvent(name: "observation_stop")
        )
    ]
    let summary = MusicUsageDailyAnalyzer.analyze(
        records,
        generatedAt: start.addingTimeInterval(16 * 60)
    )
    #expect(summary.schemaVersion == 6)
    #expect(summary.sampleCoverage.status == "no_media_activity")
    #expect(summary.sampleCoverage.observationHeartbeatCount == 1)
    #expect(summary.sampleCoverage.mediaPresenceHeartbeatCount == 0)
    #expect(summary.sampleCoverage.heartbeatGapCount == 0)
    #expect(summary.sampleCoverage.maximumHeartbeatGapMilliseconds == 900_000)
    #expect(summary.sampleCoverage.sourceEventCounts == ["qishui": 1])
    #expect(summary.sampleCoverage.missingSampleKinds == [
        "track_change", "source_switch", "control", "seek"
    ])
    #expect(summary.anomalies.isEmpty)

    let activeSummary = MusicUsageDailyAnalyzer.analyze([
        TimestampedMusicUsageEvent(
            timestamp: start,
            event: MusicUsageEvent(name: "observation_heartbeat", fields: [
                "source": "qishui", "has_track": "1", "playback": "playing"
            ])
        )
    ], generatedAt: start)
    #expect(activeSummary.sampleCoverage.status == "partial")
    #expect(activeSummary.sampleCoverage.mediaPresenceHeartbeatCount == 1)
    #expect(activeSummary.sampleCoverage.mediaActivityEventCount == 1)
}

@Test
func dailyAnalyzerMarksEndToEndSamplesComplete() {
    let start = Date(timeIntervalSince1970: 4_000)
    let records = [
        TimestampedMusicUsageEvent(
            timestamp: start,
            event: MusicUsageEvent(name: "source_change", fields: [
                "from": "none", "to": "qishui"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.1),
            event: MusicUsageEvent(name: "track_changed", fields: [
                "source": "qishui", "track": "abc123", "has_artwork": "1"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.2),
            event: MusicUsageEvent(name: "control_result", fields: [
                "request": "1", "source": "qishui", "command": "play_pause",
                "outcome": "accepted", "latency_ms": "20"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.3),
            event: MusicUsageEvent(name: "playback_confirmed", fields: [
                "source": "qishui", "latency_ms": "100"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.4),
            event: MusicUsageEvent(name: "seek_result", fields: [
                "source": "qishui", "outcome": "accepted", "latency_ms": "15"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.8),
            event: MusicUsageEvent(name: "seek_confirmed", fields: [
                "source": "qishui", "latency_ms": "400"
            ])
        )
    ]
    let summary = MusicUsageDailyAnalyzer.analyze(records, generatedAt: start.addingTimeInterval(1))
    #expect(summary.sampleCoverage.status == "complete")
    #expect(summary.sampleCoverage.mediaActivityEventCount == 4)
    #expect(summary.sampleCoverage.missingSampleKinds.isEmpty)
    #expect(summary.sampleCoverage.sourceEventCounts == ["qishui": 6])
    #expect(summary.anomalies.isEmpty)
}

@Test
func dailyAnalyzerTreatsCancelledSeeksAsTerminalCoverage() {
    let start = Date(timeIntervalSince1970: 5_000)
    let records = [
        TimestampedMusicUsageEvent(
            timestamp: start,
            event: MusicUsageEvent(name: "source_change", fields: [
                "from": "none", "to": "qishui"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.1),
            event: MusicUsageEvent(name: "track_changed", fields: [
                "source": "qishui", "track": "abc123", "has_artwork": "1"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.2),
            event: MusicUsageEvent(name: "control_result", fields: [
                "request": "1", "source": "qishui", "command": "next",
                "outcome": "accepted", "latency_ms": "20"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.3),
            event: MusicUsageEvent(name: "seek_result", fields: [
                "source": "qishui", "outcome": "accepted", "latency_ms": "15"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.4),
            event: MusicUsageEvent(name: "seek_cancelled", fields: [
                "source": "qishui", "reason": "superseded", "latency_ms": "100"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.5),
            event: MusicUsageEvent(name: "seek_result", fields: [
                "source": "qishui", "outcome": "accepted", "latency_ms": "15"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.6),
            event: MusicUsageEvent(name: "seek_cancelled", fields: [
                "source": "qishui", "reason": "track_changed", "latency_ms": "100"
            ])
        )
    ]
    let summary = MusicUsageDailyAnalyzer.analyze(
        records,
        generatedAt: start.addingTimeInterval(1)
    )
    #expect(summary.schemaVersion == 6)
    #expect(summary.seekCancellationCount == 2)
    #expect(summary.seekCancellationReasons == [
        "superseded": 1,
        "track_changed": 1
    ])
    #expect(summary.sampleCoverage.status == "complete")
    #expect(!summary.sampleCoverage.missingSampleKinds.contains("seek_confirmation"))
    #expect(summary.anomalies.isEmpty)
}

@Test
func dailyAnalyzerKeepsAcceptedSeekWithoutTerminalPartial() {
    let start = Date(timeIntervalSince1970: 6_000)
    let records = [
        TimestampedMusicUsageEvent(
            timestamp: start,
            event: MusicUsageEvent(name: "source_change", fields: [
                "from": "none", "to": "qishui"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.1),
            event: MusicUsageEvent(name: "track_changed", fields: [
                "source": "qishui", "track": "abc123", "has_artwork": "1"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.2),
            event: MusicUsageEvent(name: "control_result", fields: [
                "request": "1", "source": "qishui", "command": "next",
                "outcome": "accepted", "latency_ms": "20"
            ])
        ),
        TimestampedMusicUsageEvent(
            timestamp: start.addingTimeInterval(0.3),
            event: MusicUsageEvent(name: "seek_result", fields: [
                "source": "qishui", "outcome": "accepted", "latency_ms": "15"
            ])
        )
    ]
    let summary = MusicUsageDailyAnalyzer.analyze(
        records,
        generatedAt: start.addingTimeInterval(1)
    )
    #expect(summary.seekCancellationCount == 0)
    #expect(summary.seekCancellationReasons.isEmpty)
    #expect(summary.sampleCoverage.status == "partial")
    #expect(summary.sampleCoverage.missingSampleKinds == ["seek_confirmation"])
}

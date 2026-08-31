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
    #expect(summary.schemaVersion == 3)
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

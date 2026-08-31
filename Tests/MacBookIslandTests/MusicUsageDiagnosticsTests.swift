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

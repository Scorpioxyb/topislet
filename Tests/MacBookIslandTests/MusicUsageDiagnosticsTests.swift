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
        )
    ]
    let summary = MusicUsageDailyAnalyzer.analyze(records, generatedAt: start)
    #expect(summary.rapidSourceSwitchCount == 1)
    #expect(summary.anomalies == ["seek_rejected=1", "rapid_source_switch=1"])
}

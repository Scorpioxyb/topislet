import CryptoKit
import Foundation

public struct MusicUsageEvent: Equatable, Sendable {
    public static let prefix = "topislet_usage"
    public static let schemaVersion = 1

    public let name: String
    public let fields: [String: String]

    public init(name: String, fields: [String: String] = [:]) {
        self.name = Self.sanitized(name)
        self.fields = fields.reduce(into: [:]) { result, pair in
            result[Self.sanitized(pair.key)] = Self.sanitized(pair.value)
        }
    }

    public var encodedMessage: String {
        let fieldText = fields.keys.sorted().map { key in
            "\(key)=\(fields[key] ?? "unknown")"
        }
        return ([
            Self.prefix,
            "v=\(Self.schemaVersion)",
            "event=\(name)"
        ] + fieldText).joined(separator: " ")
    }

    public static func parse(_ message: String) -> MusicUsageEvent? {
        let components = message.split(whereSeparator: \Character.isWhitespace)
        guard components.first == Substring(prefix) else { return nil }
        var values: [String: String] = [:]
        for component in components.dropFirst() {
            guard let separator = component.firstIndex(of: "=") else { continue }
            let key = String(component[..<separator])
            let value = String(component[component.index(after: separator)...])
            values[key] = value
        }
        guard values["v"] == String(schemaVersion),
              let name = values.removeValue(forKey: "event") else {
            return nil
        }
        values.removeValue(forKey: "v")
        return MusicUsageEvent(name: name, fields: values)
    }

    private static func sanitized(_ value: String) -> String {
        let scalars = value.unicodeScalars.prefix(80).map { scalar -> Character in
            let value = scalar.value
            let isASCIILetter = (65...90).contains(value) || (97...122).contains(value)
            let isASCIIDigit = (48...57).contains(value)
            if isASCIILetter
                || isASCIIDigit
                || scalar == "_"
                || scalar == "-"
                || scalar == "." {
                return Character(String(scalar))
            }
            return "_"
        }
        let result = String(scalars)
        return result.isEmpty ? "unknown" : result
    }
}

public enum MusicUsageTrackFingerprint {
    public static func make(source: String, title: String, artist: String) -> String {
        let input = [source, title, artist].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

public struct TimestampedMusicUsageEvent: Equatable, Sendable {
    public let timestamp: Date
    public let event: MusicUsageEvent

    public init(timestamp: Date, event: MusicUsageEvent) {
        self.timestamp = timestamp
        self.event = event
    }
}

public struct MusicUsageLatencySummary: Codable, Equatable, Sendable {
    public let count: Int
    public let p50Milliseconds: Int?
    public let p95Milliseconds: Int?
    public let maximumMilliseconds: Int?
}

public struct MusicUsageOutcomeSummary: Codable, Equatable, Sendable {
    public let total: Int
    public let accepted: Int
    public let rejected: Int
    public let latency: MusicUsageLatencySummary
}

public struct MusicUsageSampleCoverage: Codable, Equatable, Sendable {
    public let status: String
    public let observationHeartbeatCount: Int
    public let mediaPresenceHeartbeatCount: Int
    public let heartbeatGapCount: Int
    public let maximumHeartbeatGapMilliseconds: Int?
    public let sourceEventCounts: [String: Int]
    public let mediaActivityEventCount: Int
    public let missingSampleKinds: [String]
}

public struct MusicUsageDailySummary: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let periodStart: Date?
    public let periodEnd: Date?
    public let structuredEventCount: Int
    public let observationStartCount: Int
    public let observationStopCount: Int
    public let sourceSwitchCount: Int
    public let rapidSourceSwitchCount: Int
    public let emptySourceCount: Int
    public let sourceTransitions: [String: Int]
    public let trackChangeCount: Int
    public let unresolvedArtworkCount: Int
    public let sourceProcessLaunchCount: Int
    public let sourceProcessTerminationCount: Int
    public let controls: MusicUsageOutcomeSummary
    public let seeks: MusicUsageOutcomeSummary
    public let controlToTrackLatency: MusicUsageLatencySummary
    public let controlToPlaybackUILatency: MusicUsageLatencySummary
    public let playbackConfirmationLatency: MusicUsageLatencySummary
    public let playbackConfirmationTimeoutCount: Int
    public let metadataToArtworkLatency: MusicUsageLatencySummary
    public let controlToArtworkLatency: MusicUsageLatencySummary
    public let seekConfirmationLatency: MusicUsageLatencySummary
    public let seekConfirmationTimeoutCount: Int
    public let seekCancellationCount: Int
    public let seekCancellationReasons: [String: Int]
    public let sampleCoverage: MusicUsageSampleCoverage
    public let anomalies: [String]
}

public enum MusicUsageDailyAnalyzer {
    private struct PendingControl {
        let timestamp: Date
        let command: String
        let targetPlayback: String?
    }

    private struct PendingArtwork {
        let timestamp: Date
        let controlTimestamp: Date?
    }

    public static func analyze(
        _ records: [TimestampedMusicUsageEvent],
        generatedAt: Date = Date()
    ) -> MusicUsageDailySummary {
        let records = records.sorted { $0.timestamp < $1.timestamp }
        var observationStarts = 0
        var observationStops = 0
        var observationHeartbeats = 0
        var mediaPresenceHeartbeats = 0
        var heartbeatGaps: [Int] = []
        var pendingHeartbeatGaps: [Int] = []
        var observationCheckpoint: Date?
        var observationSessionHasHeartbeat = false
        var sourceSwitches = 0
        var rapidSourceSwitches = 0
        var emptySources = 0
        var sourceTransitions: [String: Int] = [:]
        var trackChanges = 0
        var processLaunches = 0
        var processTerminations = 0
        var controlAccepted = 0
        var controlRejected = 0
        var seekAccepted = 0
        var seekRejected = 0
        var controlLatencies: [Int] = []
        var seekLatencies: [Int] = []
        var controlToTrackLatencies: [Int] = []
        var controlToPlaybackUILatencies: [Int] = []
        var playbackConfirmationLatencies: [Int] = []
        var playbackConfirmationTimeouts = 0
        var metadataToArtworkLatencies: [Int] = []
        var controlToArtworkLatencies: [Int] = []
        var seekConfirmationLatencies: [Int] = []
        var seekConfirmationTimeouts = 0
        var seekCancellations = 0
        var seekCancellationReasons: [String: Int] = [:]
        var acceptedPlayPauseControls = 0
        var sourceEventCounts: [String: Int] = [:]
        var issuedControls: [String: PendingControl] = [:]
        var pendingTrackControlBySource: [String: PendingControl] = [:]
        var pendingPlaybackControlBySource: [String: PendingControl] = [:]
        var pendingArtworkByTrack: [String: PendingArtwork] = [:]
        var lastUIPublishedTrackBySource: [String: String] = [:]
        var lastSourceChangeAt: Date?

        for record in records {
            let event = record.event
            if let source = event.fields["source"], source != "none" {
                sourceEventCounts[source, default: 0] += 1
            }
            switch event.name {
            case "observation_start":
                observationStarts += 1
                observationCheckpoint = record.timestamp
                observationSessionHasHeartbeat = false
                pendingHeartbeatGaps.removeAll(keepingCapacity: true)
            case "observation_heartbeat":
                observationHeartbeats += 1
                if event.fields["has_track"] == "1" {
                    mediaPresenceHeartbeats += 1
                }
                if let observationCheckpoint {
                    pendingHeartbeatGaps.append(milliseconds(
                        from: observationCheckpoint,
                        to: record.timestamp
                    ))
                }
                observationCheckpoint = record.timestamp
                observationSessionHasHeartbeat = true
            case "observation_stop":
                observationStops += 1
                if observationSessionHasHeartbeat, let observationCheckpoint {
                    pendingHeartbeatGaps.append(milliseconds(
                        from: observationCheckpoint,
                        to: record.timestamp
                    ))
                    heartbeatGaps.append(contentsOf: pendingHeartbeatGaps)
                }
                observationCheckpoint = nil
                observationSessionHasHeartbeat = false
                pendingHeartbeatGaps.removeAll(keepingCapacity: true)
            case "source_change":
                sourceSwitches += 1
                let from = event.fields["from"] ?? "unknown"
                let to = event.fields["to"] ?? "unknown"
                if event.fields["source"] == nil, to != "none" {
                    sourceEventCounts[to, default: 0] += 1
                }
                sourceTransitions["\(from)->\(to)", default: 0] += 1
                if to == "none" {
                    emptySources += 1
                }
                if let lastSourceChangeAt,
                   record.timestamp.timeIntervalSince(lastSourceChangeAt) < 1 {
                    rapidSourceSwitches += 1
                }
                lastSourceChangeAt = record.timestamp
            case "source_process":
                switch event.fields["lifecycle"] {
                case "launch": processLaunches += 1
                case "terminate": processTerminations += 1
                default: break
                }
            case "control_issued":
                if let request = event.fields["request"],
                   let command = event.fields["command"] {
                    let pending = PendingControl(
                        timestamp: record.timestamp,
                        command: command,
                        targetPlayback: event.fields["target_playback"]
                    )
                    issuedControls[request] = pending
                    if let source = event.fields["source"] {
                        if command == "next" || command == "previous" {
                            pendingTrackControlBySource[source] = pending
                        } else if command == "play_pause",
                                  pending.targetPlayback != nil {
                            pendingPlaybackControlBySource[source] = pending
                        }
                    }
                }
            case "control_result":
                let accepted = event.fields["outcome"] == "accepted"
                accepted ? (controlAccepted += 1) : (controlRejected += 1)
                if let latency = integer(event.fields["latency_ms"]) {
                    controlLatencies.append(latency)
                }
                let issued = event.fields["request"].flatMap {
                    issuedControls.removeValue(forKey: $0)
                }
                guard let source = event.fields["source"],
                      let command = event.fields["command"] else { break }
                let resolvedIssued = issued ?? PendingControl(
                        timestamp: record.timestamp.addingTimeInterval(
                            -Double(integer(event.fields["latency_ms"]) ?? 0) / 1_000
                        ),
                        command: command,
                        targetPlayback: event.fields["target_playback"]
                    )
                if command == "play_pause" {
                    if accepted {
                        acceptedPlayPauseControls += 1
                    }
                    if !accepted,
                       pendingPlaybackControlBySource[source]?.timestamp
                        == resolvedIssued.timestamp {
                        pendingPlaybackControlBySource.removeValue(forKey: source)
                    }
                    break
                }
                guard command == "next" || command == "previous" else { break }
                if accepted {
                    pendingTrackControlBySource[source] = resolvedIssued
                } else if pendingTrackControlBySource[source]?.timestamp
                    == resolvedIssued.timestamp {
                    pendingTrackControlBySource.removeValue(forKey: source)
                }
            case "seek_result":
                let accepted = event.fields["outcome"] == "accepted"
                accepted ? (seekAccepted += 1) : (seekRejected += 1)
                if let latency = integer(event.fields["latency_ms"]) {
                    seekLatencies.append(latency)
                }
            case "track_changed":
                trackChanges += 1
                guard let source = event.fields["source"],
                      let track = event.fields["track"] else { break }
                if event.fields["has_artwork"] != "1" {
                    pendingArtworkByTrack["\(source):\(track)"] = PendingArtwork(
                        timestamp: record.timestamp,
                        controlTimestamp: pendingTrackControlBySource[source]?.timestamp
                    )
                }
            case "artwork_ready":
                break
            case "playback_confirmed":
                if let latency = integer(event.fields["latency_ms"]) {
                    playbackConfirmationLatencies.append(latency)
                }
            case "playback_confirmation_timeout":
                playbackConfirmationTimeouts += 1
            case "seek_confirmed":
                if let latency = integer(event.fields["latency_ms"]) {
                    seekConfirmationLatencies.append(latency)
                }
            case "seek_confirmation_timeout":
                seekConfirmationTimeouts += 1
            case "seek_cancelled":
                seekCancellations += 1
                let reason = event.fields["reason"] ?? "unknown"
                seekCancellationReasons[reason, default: 0] += 1
            case "ui_published":
                guard let source = event.fields["source"],
                      let track = event.fields["track"] else { break }
                if let pendingPlayback = pendingPlaybackControlBySource[source],
                   event.fields["playback"] == pendingPlayback.targetPlayback,
                   record.timestamp.timeIntervalSince(pendingPlayback.timestamp) <= 10 {
                    controlToPlaybackUILatencies.append(milliseconds(
                        from: pendingPlayback.timestamp,
                        to: record.timestamp
                    ))
                    pendingPlaybackControlBySource.removeValue(forKey: source)
                }
                let isNewTrack = lastUIPublishedTrackBySource[source] != track
                lastUIPublishedTrackBySource[source] = track
                var didRecordControlArtwork = false
                if isNewTrack,
                   let pendingControl = pendingTrackControlBySource.removeValue(
                    forKey: source
                   ),
                   record.timestamp.timeIntervalSince(pendingControl.timestamp) <= 10 {
                    controlToTrackLatencies.append(milliseconds(
                        from: pendingControl.timestamp,
                        to: record.timestamp
                    ))
                    if event.fields["has_artwork"] == "1" {
                        controlToArtworkLatencies.append(milliseconds(
                            from: pendingControl.timestamp,
                            to: record.timestamp
                        ))
                        didRecordControlArtwork = true
                    }
                }
                if event.fields["has_artwork"] == "1",
                   let pending = pendingArtworkByTrack.removeValue(
                    forKey: "\(source):\(track)"
                   ) {
                    metadataToArtworkLatencies.append(milliseconds(
                        from: pending.timestamp,
                        to: record.timestamp
                    ))
                    if let controlTimestamp = pending.controlTimestamp,
                       !didRecordControlArtwork {
                        controlToArtworkLatencies.append(milliseconds(
                            from: controlTimestamp,
                            to: record.timestamp
                        ))
                    }
                }
            default:
                break
            }
        }

        if observationSessionHasHeartbeat, let observationCheckpoint {
            pendingHeartbeatGaps.append(milliseconds(
                from: observationCheckpoint,
                to: generatedAt
            ))
            heartbeatGaps.append(contentsOf: pendingHeartbeatGaps)
        }

        let unresolvedArtworkCount = pendingArtworkByTrack.values.filter {
            generatedAt.timeIntervalSince($0.timestamp) >= 5
        }.count
        var anomalies: [String] = []
        if controlRejected > 0 {
            anomalies.append("control_rejected=\(controlRejected)")
        }
        if seekRejected > 0 {
            anomalies.append("seek_rejected=\(seekRejected)")
        }
        if rapidSourceSwitches > 0 {
            anomalies.append("rapid_source_switch=\(rapidSourceSwitches)")
        }
        if unresolvedArtworkCount > 0 {
            anomalies.append("artwork_unresolved=\(unresolvedArtworkCount)")
        }
        if playbackConfirmationTimeouts > 0 {
            anomalies.append("playback_confirmation_timeout=\(playbackConfirmationTimeouts)")
        }
        if seekConfirmationTimeouts > 0 {
            anomalies.append("seek_confirmation_timeout=\(seekConfirmationTimeouts)")
        }

        let mediaActivityEventCount = sourceSwitches
            + trackChanges
            + controlAccepted
            + controlRejected
            + seekAccepted
            + seekRejected
            + mediaPresenceHeartbeats
        var missingSampleKinds: [String] = []
        if trackChanges == 0 {
            missingSampleKinds.append("track_change")
        }
        if sourceSwitches == 0 {
            missingSampleKinds.append("source_switch")
        }
        if controlAccepted + controlRejected == 0 {
            missingSampleKinds.append("control")
        }
        if seekAccepted + seekRejected == 0 {
            missingSampleKinds.append("seek")
        }
        if acceptedPlayPauseControls
            > playbackConfirmationLatencies.count + playbackConfirmationTimeouts {
            missingSampleKinds.append("playback_confirmation")
        }
        if seekAccepted
            > seekConfirmationLatencies.count + seekConfirmationTimeouts + seekCancellations {
            missingSampleKinds.append("seek_confirmation")
        }
        let coverageStatus: String
        if mediaActivityEventCount == 0 {
            coverageStatus = "no_media_activity"
        } else if missingSampleKinds.isEmpty {
            coverageStatus = "complete"
        } else {
            coverageStatus = "partial"
        }

        return MusicUsageDailySummary(
            schemaVersion: 4,
            generatedAt: generatedAt,
            periodStart: records.first?.timestamp,
            periodEnd: records.last?.timestamp,
            structuredEventCount: records.count,
            observationStartCount: observationStarts,
            observationStopCount: observationStops,
            sourceSwitchCount: sourceSwitches,
            rapidSourceSwitchCount: rapidSourceSwitches,
            emptySourceCount: emptySources,
            sourceTransitions: sourceTransitions,
            trackChangeCount: trackChanges,
            unresolvedArtworkCount: unresolvedArtworkCount,
            sourceProcessLaunchCount: processLaunches,
            sourceProcessTerminationCount: processTerminations,
            controls: outcomeSummary(
                accepted: controlAccepted,
                rejected: controlRejected,
                latencies: controlLatencies
            ),
            seeks: outcomeSummary(
                accepted: seekAccepted,
                rejected: seekRejected,
                latencies: seekLatencies
            ),
            controlToTrackLatency: latencySummary(controlToTrackLatencies),
            controlToPlaybackUILatency: latencySummary(controlToPlaybackUILatencies),
            playbackConfirmationLatency: latencySummary(playbackConfirmationLatencies),
            playbackConfirmationTimeoutCount: playbackConfirmationTimeouts,
            metadataToArtworkLatency: latencySummary(metadataToArtworkLatencies),
            controlToArtworkLatency: latencySummary(controlToArtworkLatencies),
            seekConfirmationLatency: latencySummary(seekConfirmationLatencies),
            seekConfirmationTimeoutCount: seekConfirmationTimeouts,
            seekCancellationCount: seekCancellations,
            seekCancellationReasons: seekCancellationReasons,
            sampleCoverage: MusicUsageSampleCoverage(
                status: coverageStatus,
                observationHeartbeatCount: observationHeartbeats,
                mediaPresenceHeartbeatCount: mediaPresenceHeartbeats,
                heartbeatGapCount: heartbeatGaps.filter { $0 > 20 * 60 * 1_000 }.count,
                maximumHeartbeatGapMilliseconds: heartbeatGaps.max(),
                sourceEventCounts: sourceEventCounts,
                mediaActivityEventCount: mediaActivityEventCount,
                missingSampleKinds: missingSampleKinds
            ),
            anomalies: anomalies
        )
    }

    private static func integer(_ value: String?) -> Int? {
        value.flatMap(Int.init)
    }

    private static func milliseconds(from start: Date, to end: Date) -> Int {
        max(Int((end.timeIntervalSince(start) * 1_000).rounded()), 0)
    }

    private static func outcomeSummary(
        accepted: Int,
        rejected: Int,
        latencies: [Int]
    ) -> MusicUsageOutcomeSummary {
        MusicUsageOutcomeSummary(
            total: accepted + rejected,
            accepted: accepted,
            rejected: rejected,
            latency: latencySummary(latencies)
        )
    }

    private static func latencySummary(_ values: [Int]) -> MusicUsageLatencySummary {
        MusicUsageLatencySummary(
            count: values.count,
            p50Milliseconds: percentile(values, fraction: 0.50),
            p95Milliseconds: percentile(values, fraction: 0.95),
            maximumMilliseconds: values.max()
        )
    }

    private static func percentile(_ values: [Int], fraction: Double) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = min(
            max(Int(ceil(Double(sorted.count) * fraction)) - 1, 0),
            sorted.count - 1
        )
        return sorted[index]
    }
}

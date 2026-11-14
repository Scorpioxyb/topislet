import Foundation
import Testing
@testable import MacBookIsland

// Replays recorded (or synthetic, same shape) Qishui stream sequences from
// Tests/Fixtures/streams/ through MediaRemoteAdapterStreamSource on a fixed
// clock, then checks two things:
//   1. no published track mixes fields of two tracks (header `tracks` table);
//   2. the publication sequence equals `<name>.expected.json`.
// The expected files pin current behavior so refactors (global plan 4.2) can
// prove they changed nothing. After an intended behavior change, regenerate
// them with TOPISLET_RECORD_STREAM_FIXTURES=1 swift test --filter StreamReplay
// and review the diff. Fixtures never contain real titles, lyrics or artwork:
// real captures go through Scripts/sanitize-qishui-stream.py first.

private let replayBaseDate = Date(timeIntervalSince1970: 1_767_225_600)
private let replayBaseUptime: TimeInterval = 10_000

private var streamFixtureDirectory: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/streams")
}

private func streamFixtureNames() -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: streamFixtureDirectory.path)) ?? []
    return files.filter { $0.hasSuffix(".jsonl") }
        .map { String($0.dropLast(".jsonl".count)) }
        .sorted()
}

struct StreamReplayTrack: Codable, Equatable {
    let title: String
    let artist: String
    let album: String?
    let duration: Double?
    let artwork: String?
    let playing: Bool?
    let elapsed: Double?
    let pid: Int32?
}

struct StreamReplayRecord: Codable, Equatable {
    let t: Double
    let step: String
    let deferred: Bool
    let verified: Bool?
    let origin: String?
    let track: StreamReplayTrack?
}

private struct StreamFixtureTrack {
    let title: String
    let artist: String?
    let album: String?
    let duration: Double?
    let artwork: String?
}

private final class ReplayClock: @unchecked Sendable {
    var now = replayBaseDate
}

private final class ReplayPIDs: @unchecked Sendable {
    var pids: Set<pid_t> = []
}

@MainActor
private struct StreamReplay {
    let name: String
    let tracks: [StreamFixtureTrack]
    let records: [StreamReplayRecord]

    init(name: String) throws {
        self.name = name
        let url = streamFixtureDirectory.appendingPathComponent("\(name).jsonl")
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        let objects = try lines.map {
            try #require(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        let header = try #require(objects.first)
        tracks = ((header["tracks"] as? [[String: Any]]) ?? []).map {
            StreamFixtureTrack(
                title: $0["title"] as? String ?? "",
                artist: $0["artist"] as? String,
                album: $0["album"] as? String,
                duration: ($0["duration"] as? NSNumber)?.doubleValue,
                artwork: $0["artwork"] as? String
            )
        }

        let clock = ReplayClock()
        let running = ReplayPIDs()
        running.pids = Set(((header["running_pids"] as? [NSNumber]) ?? []).map { pid_t($0.int32Value) })
        let source = MediaRemoteAdapterStreamSource(
            runningQishuiProcessIdentifiersProvider: { running.pids },
            clock: { clock.now }
        )
        let budget = source.deferredPublicationTimeBudgetForTesting
        var records: [StreamReplayRecord] = []

        func record(_ step: String, at t: Double, _ snapshot: MediaRemoteNowPlayingSnapshot?) {
            records.append(StreamReplayRecord(
                t: t,
                step: step,
                deferred: source.deferredPublicationStartedAtForTesting != nil,
                verified: snapshot?.isVerifiedQishuiSource,
                origin: snapshot.map { String(describing: $0.sampleOrigin) },
                track: snapshot?.currentTrack.map(Self.track)
            ))
        }

        // The scheduled deadline task fires at start + budget; replay it at
        // exactly that instant whenever the next step lies beyond it.
        func expireDeadline(before t: Double) {
            guard let startedAt = source.deferredPublicationStartedAtForTesting else { return }
            let deadline = startedAt.addingTimeInterval(budget)
            let deadlineT = deadline.timeIntervalSince(replayBaseDate)
            guard deadlineT <= t else { return }
            clock.now = deadline
            let snapshot = source.expireDeferredTrackPublicationForTesting(
                receivedAt: deadline,
                receivedUptime: replayBaseUptime + deadlineT
            )
            record("deadline", at: (deadlineT * 1000).rounded() / 1000, snapshot)
        }

        for object in objects.dropFirst() {
            let t = try #require((object["t"] as? NSNumber)?.doubleValue)
            expireDeadline(before: t)
            let at = replayBaseDate.addingTimeInterval(t)
            clock.now = at
            if let op = object["op"] as? String {
                switch op {
                case "invalidate_session":
                    source.invalidateQishuiSession(at: at)
                case "running_pids":
                    running.pids = Set(((object["pids"] as? [NSNumber]) ?? []).map { pid_t($0.int32Value) })
                case "seed_seek":
                    let target = try #require((object["target"] as? NSNumber)?.doubleValue)
                    source.seedSeekTimelineForTesting(target: target, issuedAt: at)
                default:
                    Issue.record("\(name): unknown op \(op)")
                }
                records.append(StreamReplayRecord(
                    t: t, step: "op:\(op)", deferred: source.deferredPublicationStartedAtForTesting != nil,
                    verified: nil, origin: nil, track: nil
                ))
                continue
            }
            var envelope = try #require(object["envelope"] as? [String: Any])
            if var payload = envelope["payload"] as? [String: Any],
               let latency = (payload.removeValue(forKey: "timestampLatency") as? NSNumber)?.doubleValue {
                payload["timestamp"] = ISO8601DateFormatter().string(from: at.addingTimeInterval(-latency))
                envelope["payload"] = payload
            }
            let line = try JSONSerialization.data(withJSONObject: envelope)
            let snapshot = source.ingestStreamEnvelopeForTesting(
                line,
                receivedAt: at,
                receivedUptime: replayBaseUptime + t
            )
            record("event", at: t, snapshot)
        }
        expireDeadline(before: .infinity)
        self.records = records
    }

    private static func track(_ track: MediaRemoteNowPlayingTrack) -> StreamReplayTrack {
        StreamReplayTrack(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            artwork: track.artworkData.map { String(data: $0, encoding: .utf8) ?? "bytes:\($0.count)" },
            playing: track.isPlaying,
            elapsed: track.elapsedTime.map { ($0 * 1000).rounded() / 1000 },
            pid: track.sourceProcessIdentifier
        )
    }

    /// Fields published together must all belong to the track named by the
    /// title; a field may be missing, never borrowed from another track.
    func mixedTrackViolations() -> [String] {
        records.compactMap { record in
            guard let track = record.track else { return nil }
            guard let expected = tracks.first(where: { $0.title == track.title }) else {
                return "t=\(record.t): unknown title \(track.title)"
            }
            var wrong: [String] = []
            if track.artist != expected.artist { wrong.append("artist \(track.artist)") }
            if let album = track.album, album != expected.album { wrong.append("album \(album)") }
            if let duration = track.duration, let want = expected.duration, abs(duration - want) > 0.001 {
                wrong.append("duration \(duration)")
            }
            if let artwork = track.artwork, artwork != expected.artwork { wrong.append("artwork \(artwork)") }
            return wrong.isEmpty ? nil : "t=\(record.t) \(track.title): \(wrong.joined(separator: ", "))"
        }
    }
}

@Suite("状态流重放夹具")
@MainActor
struct StreamReplayFixtureTests {
    @Test("夹具目录至少包含全局规划 5.1 的五类首批序列")
    func fixtureSetIsComplete() {
        let names = Set(streamFixtureNames())
        for required in [
            "normal-skip-mixed-then-complete",
            "rapid-four-skips",
            "pause-then-seek",
            "relaunch-new-pid",
            "empty-packet-deadline"
        ] {
            #expect(names.contains(required), "missing fixture \(required)")
        }
    }

    @Test("重放发布序列不混用两首歌的字段，且与已记录序列一致", arguments: streamFixtureNames())
    func replayMatchesExpectedPublications(name: String) throws {
        let replay = try StreamReplay(name: name)
        #expect(replay.mixedTrackViolations().isEmpty, "\(name): \(replay.mixedTrackViolations())")

        let expectedURL = streamFixtureDirectory.appendingPathComponent("\(name).expected.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if ProcessInfo.processInfo.environment["TOPISLET_RECORD_STREAM_FIXTURES"] == "1" {
            var data = try encoder.encode(replay.records)
            data.append(0x0A)
            try data.write(to: expectedURL)
            return
        }
        let expectedData = try Data(contentsOf: expectedURL)
        let expected = try JSONDecoder().decode([StreamReplayRecord].self, from: expectedData)
        #expect(replay.records.count == expected.count, "\(name): step count")
        for (index, pair) in zip(replay.records, expected).enumerated() where pair.0 != pair.1 {
            Issue.record("""
            \(name) step \(index) differs
              actual:   \(String(decoding: try encoder.encode(pair.0), as: UTF8.self))
              expected: \(String(decoding: try encoder.encode(pair.1), as: UTF8.self))
            """)
        }
    }
}

import Foundation
import MusicUsageDiagnostics
import Testing
@testable import MacBookIsland

private final class EventLog {
    var events: [MusicUsageEvent] = []
    var names: [String] { events.map(\.name) }
    func take() -> [String] {
        defer { events.removeAll() }
        return names
    }
}

private func makeEmitter() -> (MusicUsageEmitter, EventLog) {
    let log = EventLog()
    return (MusicUsageEmitter(sink: { log.events.append($0) }), log)
}

private func qishuiState(
    title: String = "Song A",
    artist: String = "Artist A",
    artwork: Bool = true,
    playing: Bool = true,
    duration: TimeInterval? = 180,
    lyrics: [String] = []
) -> MusicState {
    MusicState(
        track: MusicTrack(
            title: title,
            artist: artist,
            palette: [],
            lyrics: lyrics,
            hasArtwork: artwork,
            artworkData: nil,
            artworkURL: nil,
            sourceBundleIdentifier: "com.soda.music"
        ),
        isPlaying: playing,
        progress: 0.1,
        lyricIndex: 0,
        elapsedTime: 18,
        duration: duration,
        canSeek: true,
        hasCurrentTrack: true
    )
}

private func emptyState() -> MusicState {
    MusicState(
        track: MusicTrack(
            title: "", artist: "", palette: [], lyrics: [], hasArtwork: false,
            artworkData: nil, artworkURL: nil, sourceBundleIdentifier: nil
        ),
        isPlaying: false,
        progress: 0,
        lyricIndex: 0,
        hasCurrentTrack: false
    )
}

private let syncedStatus = MusicSourceStatus(
    sourceName: "汽水音乐",
    availability: .qishuiMediaRemoteSynced,
    headline: "",
    detail: "",
    checkedAt: Date(timeIntervalSince1970: 0)
)

@Suite("匿名使用诊断发射器")
struct MusicUsageEmitterTests {
    @Test("同一状态重复上报只记一次，播放态变化单独记录")
    func stateEventsAreDeduplicated() {
        let (emitter, log) = makeEmitter()
        let state = qishuiState()
        let first = emitter.recordState(state, status: syncedStatus, sourceID: .qishui,
                                        mediaTrack: ("Song A", "Artist A"), directTrack: nil)
        #expect(first)
        #expect(log.take() == ["sync_state", "track_changed", "playback_state"])

        let repeated = emitter.recordState(state, status: syncedStatus, sourceID: .qishui,
                                           mediaTrack: ("Song A", "Artist A"), directTrack: nil)
        #expect(!repeated)
        #expect(log.take().isEmpty)

        emitter.recordState(qishuiState(playing: false), status: syncedStatus, sourceID: .qishui,
                            mediaTrack: nil, directTrack: nil)
        #expect(log.take() == ["playback_state"])
    }

    @Test("汽水换歌记录媒体与直接身份是否一致，只写指纹不写歌名")
    func qishuiTrackChangeCarriesIdentityMatch() throws {
        let (emitter, log) = makeEmitter()
        emitter.recordState(qishuiState(), status: syncedStatus, sourceID: .qishui,
                            mediaTrack: ("Song A", "Artist A"), directTrack: ("Old Song", "Old Artist"))
        let changed = try #require(log.events.first { $0.name == "track_changed" })
        #expect(changed.fields["media_match"] == "1")
        #expect(changed.fields["direct_match"] == "0")
        #expect(changed.fields["source"] == "qishui")
        #expect(!changed.encodedMessage.contains("Song A"))
        #expect(!changed.encodedMessage.contains("Artist A"))
    }

    @Test("封面晚到记录一次 artwork_ready；歌曲清空记录 track_empty")
    func artworkReadyAndTrackEmpty() throws {
        let (emitter, log) = makeEmitter()
        let start = Date(timeIntervalSince1970: 1_000)
        emitter.recordState(qishuiState(artwork: false), status: syncedStatus, sourceID: .qishui,
                            mediaTrack: nil, directTrack: nil, now: start)
        _ = log.take()
        emitter.recordState(qishuiState(artwork: true), status: syncedStatus, sourceID: .qishui,
                            mediaTrack: nil, directTrack: nil, now: start.addingTimeInterval(0.25))
        let ready = try #require(log.events.first)
        #expect(log.names == ["artwork_ready"])
        #expect(ready.fields["latency_ms"] == "250")
        _ = log.take()

        emitter.recordState(emptyState(), status: syncedStatus, sourceID: .qishui,
                            mediaTrack: nil, directTrack: nil)
        #expect(log.take() == ["track_empty"])
        emitter.recordState(emptyState(), status: syncedStatus, sourceID: .qishui,
                            mediaTrack: nil, directTrack: nil)
        #expect(log.take().isEmpty)
    }

    @Test("心跳只在观察中且间隔满 15 分钟时记录")
    func heartbeatFollowsPolicy() throws {
        let (emitter, log) = makeEmitter()
        let start = Date(timeIntervalSince1970: 5_000)
        emitter.observationStarted(at: start)
        #expect(log.take() == ["observation_start"])

        emitter.recordHeartbeatIfNeeded(isObserving: true, hasTrack: true, isPlaying: true,
                                        source: "qishui", now: start.addingTimeInterval(60))
        #expect(log.take().isEmpty)
        emitter.recordHeartbeatIfNeeded(isObserving: false, hasTrack: true, isPlaying: true,
                                        source: "qishui", now: start.addingTimeInterval(16 * 60))
        #expect(log.take().isEmpty)
        emitter.recordHeartbeatIfNeeded(isObserving: true, hasTrack: true, isPlaying: false,
                                        source: "qishui", now: start.addingTimeInterval(15 * 60))
        let beat = try #require(log.events.first)
        #expect(beat.name == "observation_heartbeat")
        #expect(beat.fields["uptime_ms"] == "900000")
        #expect(beat.fields["playback"] == "paused")
        _ = log.take()

        emitter.observationStopped(at: start.addingTimeInterval(20 * 60))
        #expect(log.events.first?.fields["duration_ms"] == "1200000")
    }

    @Test("界面发布与时间轴能力按指纹去重，歌词年龄只在新歌词发布时计算")
    func uiPublicationDeduplicatesAndEvaluatesLyricAgeLazily() {
        let (emitter, log) = makeEmitter()
        var ageEvaluations = 0
        let lyricAge: () -> Int = { ageEvaluations += 1; return 42 }
        let state = qishuiState(lyrics: ["line one", "line two"])

        #expect(emitter.recordUIPublished(state, lyricAgeMilliseconds: lyricAge) == nil)
        #expect(log.take() == ["ui_published", "timeline_ui_state", "lyric_ui_published"])
        #expect(ageEvaluations == 1)

        _ = emitter.recordUIPublished(state, lyricAgeMilliseconds: lyricAge)
        #expect(log.take().isEmpty)
        #expect(ageEvaluations == 1)

        var noDuration = state
        noDuration.duration = nil
        _ = emitter.recordUIPublished(noDuration, lyricAgeMilliseconds: lyricAge)
        #expect(log.take() == ["timeline_ui_state"])

        _ = emitter.recordUIPublished(emptyState(), lyricAgeMilliseconds: lyricAge)
        _ = emitter.recordUIPublished(state, lyricAgeMilliseconds: lyricAge)
        #expect(log.take() == ["ui_published", "timeline_ui_state"])
    }

    @Test("切歌阶段：原子完整 → 适配器交付 → 界面发布，完成后返回切换编号且只交付一次")
    func qishuiTransitionStagesCompleteOnce() {
        let (emitter, log) = makeEmitter()
        let start = Date(timeIntervalSince1970: 9_000)
        emitter.beginQishuiTransition(transitionID: "q7", startedAt: start, baselineTrackFingerprint: nil)
        emitter.recordQishuiTransitionStage(QishuiTrackTransitionStageEvent(
            transitionID: "other", stage: .atomicComplete, latencyMilliseconds: 1,
            hasArtist: true, hasArtwork: true, hasAlbum: true, hasDuration: true,
            wasDeferred: false, candidateTrackIdentity: nil
        ))
        #expect(log.take().isEmpty)

        emitter.recordQishuiTransitionStage(QishuiTrackTransitionStageEvent(
            transitionID: "q7", stage: .atomicComplete, latencyMilliseconds: 600,
            hasArtist: true, hasArtwork: true, hasAlbum: true, hasDuration: true,
            wasDeferred: true,
            candidateTrackIdentity: QishuiLyricIdentity(processIdentifier: 1, title: "Song B", artist: "Artist B")
        ))
        #expect(log.take() == ["track_transition_stage"])

        let next = qishuiState(title: "Song B", artist: "Artist B")
        emitter.recordState(next, status: syncedStatus, sourceID: .qishui, mediaTrack: nil,
                            directTrack: nil, now: start.addingTimeInterval(0.61))
        let delivery = log.events.filter { $0.name == "track_transition_stage" }
        #expect(delivery.map { $0.fields["stage"] } == ["adapter_delivery"])
        #expect(delivery.first?.fields["latency_ms"] == "610")
        _ = log.take()
        emitter.recordState(next, status: syncedStatus, sourceID: .qishui, mediaTrack: nil,
                            directTrack: nil, now: start.addingTimeInterval(0.7))
        #expect(log.take().isEmpty)

        let finished = emitter.recordUIPublished(next, lyricAgeMilliseconds: { -1 },
                                                 now: start.addingTimeInterval(0.62))
        #expect(finished == "q7")
        #expect(log.events.last?.fields["stage"] == "ui_published")
        #expect(emitter.pendingQishuiTransition == nil)
    }

    @Test("直接身份与播放准入证据只在变化时记录；停止观察后直接身份重新记录")
    func evidenceChannelsDeduplicate() {
        let (emitter, log) = makeEmitter()
        emitter.recordDirectIdentityIfChanged(fingerprint: "abc", hasTrack: true, hasProgress: false)
        emitter.recordDirectIdentityIfChanged(fingerprint: "abc", hasTrack: true, hasProgress: true)
        emitter.recordAdmissionEvidenceIfChanged(evidence: "fresh", directPlayback: true, origin: "streamEvent")
        emitter.recordAdmissionEvidenceIfChanged(evidence: "fresh", directPlayback: true, origin: "streamEvent")
        emitter.recordAdmissionEvidenceIfChanged(evidence: "fresh", directPlayback: false, origin: "streamEvent")
        #expect(log.take() == [
            "direct_identity_applied", "playback_admission_evidence", "playback_admission_evidence"
        ])
        emitter.observationStopped(at: Date())
        emitter.recordDirectIdentityIfChanged(fingerprint: "abc", hasTrack: true, hasProgress: false)
        #expect(log.take() == ["observation_stop", "direct_identity_applied"])
    }

    @Test("请求编号递增；来源标签固定")
    func requestIDsAndLabels() {
        let (emitter, _) = makeEmitter()
        #expect(emitter.nextRequestID() == 1)
        #expect(emitter.nextRequestID() == 2)
        #expect(MusicUsageEmitter.sourceLabel(.qishui) == "qishui")
        #expect(MusicUsageEmitter.sourceLabel(.neteaseMusic) == "netease")
        #expect(MusicUsageEmitter.sourceLabel(.appleMusic) == "apple-music")
        #expect(MusicUsageEmitter.sourceLabel(nil) == "none")
    }
}

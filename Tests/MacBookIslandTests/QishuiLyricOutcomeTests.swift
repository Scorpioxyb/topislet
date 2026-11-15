import Foundation
@testable import MacBookIsland
import MusicUsageDiagnostics
import Testing

private let start = Date(timeIntervalSince1970: 1_800_000_000)

@Test("首次开始观察不产生结果，切到下一首时输出上一首的结果")
func lyricOutcomeIsEmittedForThePreviousTrackOnly() {
    var tracker = QishuiLyricOutcomeTracker()
    #expect(tracker.restart(track: "aaa", timedEnabled: true, at: start) == nil)
    tracker.recordTimedRead(receivedData: true)
    tracker.recordTimedFinished(hasLines: true)
    let finished = tracker.restart(track: "bbb", timedEnabled: true, at: start.addingTimeInterval(95))
    #expect(finished == .init(result: "timed_verified", timed: "ready", window: "unknown",
                              observedSeconds: 95, track: "aaa"))
    #expect(finished?.fields["source"] == "qishui")
    #expect(finished?.fields["observed_s"] == "95")
}

@Test("词级时间轴优先于窗口歌词，窗口歌词优先于桌面歌词")
func lyricOutcomePrefersTimedThenWindowThenDesktop() {
    var tracker = QishuiLyricOutcomeTracker()
    _ = tracker.restart(track: "aaa", timedEnabled: false, at: start)
    tracker.recordRead(diagnosis: .lines, windowState: .minimized, acceptedLines: true, acceptedDesktop: true)
    #expect(tracker.outcome(at: start)?.result == "desktop_snapshot")
    tracker.recordRead(diagnosis: .lines, windowState: .open, acceptedLines: true, acceptedDesktop: false)
    #expect(tracker.outcome(at: start)?.result == "ax_window")
    #expect(tracker.outcome(at: start)?.timed == "off")
}

@Test("无歌词时按原因分类：身份拒绝优先于网络失败，网络失败优先于窗口不可用")
func lyricOutcomeClassifiesMissingLyrics() {
    var rejected = QishuiLyricOutcomeTracker()
    _ = rejected.restart(track: "aaa", timedEnabled: true, at: start)
    rejected.recordTimedRead(receivedData: false)
    rejected.recordTimedFinished(hasLines: false)
    rejected.recordRead(diagnosis: .identityRejected, windowState: .open, acceptedLines: false, acceptedDesktop: false)
    #expect(rejected.outcome(at: start)?.result == "none_identity_rejected")
    #expect(rejected.outcome(at: start)?.timed == "network_failed")

    var network = QishuiLyricOutcomeTracker()
    _ = network.restart(track: "aaa", timedEnabled: true, at: start)
    network.recordTimedRead(receivedData: false)
    network.recordTimedFinished(hasLines: false)
    network.recordRead(diagnosis: .windowUnavailable, windowState: .closed, acceptedLines: false, acceptedDesktop: false)
    #expect(network.outcome(at: start)?.result == "none_network_failed")
    #expect(network.outcome(at: start)?.window == "closed")

    var window = QishuiLyricOutcomeTracker()
    _ = window.restart(track: "aaa", timedEnabled: true, at: start)
    window.recordTimedRead(receivedData: true)
    window.recordTimedFinished(hasLines: false)
    window.recordRead(diagnosis: .windowUnavailable, windowState: .minimized, acceptedLines: false, acceptedDesktop: false)
    #expect(window.outcome(at: start)?.result == "none_window_unavailable")
    #expect(window.outcome(at: start)?.timed == "unmatched")
}

@Test("早期的身份不一致不会覆盖后来更具体的空结果原因")
func lyricOutcomeUsesTheLatestEmptyDiagnosis() {
    var tracker = QishuiLyricOutcomeTracker()
    _ = tracker.restart(track: "aaa", timedEnabled: false, at: start)
    tracker.recordRead(diagnosis: .identityRejected, windowState: .open, acceptedLines: false, acceptedDesktop: false)
    tracker.recordRead(diagnosis: .noCandidate, windowState: .open, acceptedLines: false, acceptedDesktop: false)
    #expect(tracker.outcome(at: start)?.result == "none_no_candidate")
}

@Test("没有任何读取尝试时记为未尝试；重试成功后网络失败让位给已就绪")
func lyricOutcomeHandlesNoAttemptAndRetrySuccess() {
    var idle = QishuiLyricOutcomeTracker()
    _ = idle.restart(track: "aaa", timedEnabled: true, at: start)
    #expect(idle.outcome(at: start)?.result == "not_attempted")
    #expect(idle.outcome(at: start)?.timed == "not_finished")

    var retried = QishuiLyricOutcomeTracker()
    _ = retried.restart(track: "aaa", timedEnabled: true, at: start)
    retried.recordTimedRead(receivedData: false)
    retried.recordTimedFinished(hasLines: false)
    retried.recordTimedRead(receivedData: true)
    retried.recordTimedFinished(hasLines: true)
    #expect(retried.outcome(at: start)?.result == "timed_verified")
}

@Test("单次读取诊断：有歌词、无权限、身份不一致、窗口不可用、无候选")
func lyricReadDiagnosisClassification() {
    #expect(QishuiLyricReadDiagnosis.classify(hasLines: true, windowState: .unknown,
                                              hasDesktopWindow: false, identityMismatch: true) == .lines)
    #expect(QishuiLyricReadDiagnosis.classify(hasLines: false, windowState: .unknown,
                                              hasDesktopWindow: false, identityMismatch: false) == .noAccess)
    #expect(QishuiLyricReadDiagnosis.classify(hasLines: false, windowState: .open,
                                              hasDesktopWindow: false, identityMismatch: true) == .identityRejected)
    #expect(QishuiLyricReadDiagnosis.classify(hasLines: false, windowState: .minimized,
                                              hasDesktopWindow: false, identityMismatch: false) == .windowUnavailable)
    #expect(QishuiLyricReadDiagnosis.classify(hasLines: false, windowState: .minimized,
                                              hasDesktopWindow: true, identityMismatch: false) == .noCandidate)
    #expect(QishuiLyricReadDiagnosis.classify(hasLines: false, windowState: .open,
                                              hasDesktopWindow: false, identityMismatch: false) == .noCandidate)
}

@Test("结果事件只含分类、秒数和截断哈希")
func lyricOutcomeEventCarriesNoTrackContent() throws {
    var tracker = QishuiLyricOutcomeTracker()
    let hash = MusicUsageTrackFingerprint.make(source: "qishui", title: "Private Song", artist: "Private Artist")
    _ = tracker.restart(track: hash, timedEnabled: true, at: start)
    let finished = tracker.restart(track: nil, timedEnabled: true, at: start.addingTimeInterval(30))
    let outcome = try #require(finished)
    let message = MusicUsageEvent(name: "lyric_outcome", fields: outcome.fields).encodedMessage
    #expect(!message.contains("Private"))
    #expect(Set(outcome.fields.keys) == ["source", "result", "timed", "window", "observed_s", "track"])
    #expect(MusicUsageEvent.parse(message)?.fields["track"] == hash)
}

@Test("日报按首统计歌词结果，短于 20 秒的观察单独计数")
func dailyReportSummarizesLyricOutcomes() {
    func outcome(_ seconds: Double, result: String, window: String, timed: String, observed: Int) -> TimestampedMusicUsageEvent {
        TimestampedMusicUsageEvent(timestamp: start.addingTimeInterval(seconds), event: MusicUsageEvent(
            name: "lyric_outcome",
            fields: ["source": "qishui", "result": result, "timed": timed, "window": window,
                     "observed_s": String(observed), "track": "abc123abc123"]))
    }
    let summary = MusicUsageDailyAnalyzer.analyze([
        outcome(10, result: "timed_verified", window: "open", timed: "ready", observed: 200),
        outcome(20, result: "none_window_unavailable", window: "minimized", timed: "unmatched", observed: 180),
        outcome(30, result: "none_network_failed", window: "minimized", timed: "network_failed", observed: 60),
        outcome(40, result: "none_no_candidate", window: "open", timed: "unmatched", observed: 5)
    ], generatedAt: start)
    let lyrics = summary.lyricOutcomes
    #expect(lyrics.total == 4)
    #expect(lyrics.shortObservationCount == 1)
    #expect(lyrics.countedTotal == 3)
    #expect(lyrics.countedWithLyrics == 1)
    #expect(lyrics.results == ["timed_verified": 1, "none_window_unavailable": 1, "none_network_failed": 1])
    #expect(lyrics.windowStates == ["open": 1, "minimized": 2])
    #expect(lyrics.missingByWindowState == ["none_window_unavailable@minimized": 1,
                                            "none_network_failed@minimized": 1])
    #expect(summary.schemaVersion == 8)
}

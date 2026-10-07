import Testing
import Foundation
@testable import MacBookIsland

@Test("重复副歌在句间空拍仍保留正确词级时间，回拖重新定位")
func qishuiRepeatedChorusKeepsWordsDuringInstrumentalGap() {
    let lines = QishuiTimedLyricParser.parse("[1000,500]<0,500,0>Again\n[5000,500]<0,500,0>Again\n[9000,500]<0,500,0>End")
    #expect(QishuiTimedLyricParser.words(for: "Again", at: 3, in: lines).first?.start == 1)
    #expect(QishuiTimedLyricParser.words(for: "Again", at: 7, in: lines).first?.start == 5)
    #expect(QishuiTimedLyricParser.words(for: "Again", at: 3, in: lines).first?.start == 1)
    #expect(QishuiTimedLyricParser.words(for: "Again", at: 9.2, in: lines).isEmpty)
    let finalRepeat = Array(lines.prefix(2))
    #expect(QishuiTimedLyricParser.words(for: "Again", at: 7, in: finalRepeat, trackDuration: 10).first?.start == 5)
}

@Test("多歌手逗号与斜线格式一致，缺少或增加歌手仍拒绝")
func qishuiTimedArtistCreditsMatchSeparatorVariants() {
    #expect(QishuiTimedArtistPolicy.matches("Swimming Paul, Beaux Neptune", "Swimming Paul/Beaux Neptune"))
    #expect(QishuiTimedArtistPolicy.matches("Swimming Paul, Beaux Neptune", ["Swimming Paul", "Beaux Neptune"]))
    #expect(!QishuiTimedArtistPolicy.matches("Swimming Paul, Beaux Neptune", ["Swimming Paul"]))
    #expect(!QishuiTimedArtistPolicy.matches("Swimming Paul", "Swimming Paul/Beaux Neptune"))
    #expect(QishuiTimedArtistPolicy.matches("AC/DC", "AC/DC"))
    #expect(!QishuiTimedArtistPolicy.matches("", ""))
}

@Test("已核验歌词切回同曲直接命中缓存，不同版本不命中")
func qishuiTimedCacheReusesOnlyVerifiedTrack() {
    var cache = QishuiTimedLyricCache(capacity: 2)
    let lines = QishuiTimedLyricParser.parse("[1000,1000]<0,1000,0>Hello")
    cache.insert(lines, title: "Song", artist: "Artist", duration: 100)
    #expect(cache.lines(title: "Song", artist: "Artist", duration: 100) == lines)
    #expect(cache.lines(title: "Song", artist: "Other", duration: 100) == nil)
    #expect(cache.lines(title: "Song", artist: "Artist", duration: 101) == nil)
    cache.insert([], title: "Missing", artist: "Artist", duration: 100)
    #expect(cache.lines(title: "Missing", artist: "Artist", duration: 100) == nil)
}

@Test("歌词缓存有容量限制，并保留最近使用歌曲")
func qishuiTimedCacheEvictsLeastRecentlyUsed() {
    var cache = QishuiTimedLyricCache(capacity: 2)
    let lines = QishuiTimedLyricParser.parse("[1000,1000]<0,1000,0>Hello")
    for title in ["A", "B"] { cache.insert(lines, title: title, artist: "Artist", duration: 100) }
    #expect(cache.lines(title: "A", artist: "Artist", duration: 100) != nil)
    cache.insert(lines, title: "C", artist: "Artist", duration: 100)
    #expect(cache.lines(title: "B", artist: "Artist", duration: 100) == nil)
    #expect(cache.lines(title: "A", artist: "Artist", duration: 100) != nil)
    #expect(cache.lines(title: "C", artist: "Artist", duration: 100) != nil)
}

@Test("歌词首次失败三秒重试，重复失败有界退避")
func qishuiTimedRetryDoesNotWaitThirtySecondsAfterFirstMiss() {
    #expect(QishuiTimedLyricRetryPolicy.interval(failureCount: 0) == 0)
    #expect(QishuiTimedLyricRetryPolicy.interval(failureCount: 1) == 3)
    #expect(QishuiTimedLyricRetryPolicy.interval(failureCount: 2) == 6)
    #expect(QishuiTimedLyricRetryPolicy.interval(failureCount: 100) == 30)
}

@Test("已验证时间轴降低 AX 扫描频率，失去时间轴立即恢复快速读取")
func qishuiLyricPollingAdaptsToVerifiedTimeline() {
    #expect(QishuiLyricRefreshPolicy.interval(hasVerifiedTimeline: true) == 2)
    #expect(QishuiLyricRefreshPolicy.interval(hasVerifiedTimeline: false) == 0.18)
}

@Test("单帧空读取保留同曲新鲜歌词，但不刷新其时间戳")
func qishuiEmptyReadPreservesFreshFrameWithoutExtendingLifetime() {
    let now = Date()
    let identity = QishuiLyricIdentity(processIdentifier: 123, title: "Song", artist: "Artist")
    let previous = QishuiLyricSnapshot(identity: identity, lines: ["Current"], isDesktopSnapshot: false, checkedAt: now.addingTimeInterval(-0.3))
    let empty = QishuiLyricSnapshot(identity: identity, lines: [], isDesktopSnapshot: false, checkedAt: now)
    let accepted = QishuiLyricRefreshPolicy.acceptedSnapshot(empty, previous: previous, now: now)
    #expect(accepted.lines == ["Current"])
    #expect(accepted.checkedAt == previous.checkedAt)
    #expect(QishuiLyricRefreshPolicy.acceptedSnapshot(empty, previous: previous, now: now.addingTimeInterval(1)).lines.isEmpty)
}

@Test("换曲空读取不能保留旧曲歌词")
func qishuiEmptyReadRejectsDifferentIdentity() {
    let now = Date()
    let previous = QishuiLyricSnapshot(identity: .init(processIdentifier: 123, title: "Old", artist: "Artist"), lines: ["Old lyric"], isDesktopSnapshot: false, checkedAt: now)
    let empty = QishuiLyricSnapshot(identity: .init(processIdentifier: 123, title: "New", artist: "Artist"), lines: [], isDesktopSnapshot: false, checkedAt: now)
    #expect(QishuiLyricRefreshPolicy.acceptedSnapshot(empty, previous: previous, now: now).lines.isEmpty)
}

@Test("汽水 KRC 词级时间保持行起点与词内偏移")
func qishuiKRCParsesRealWordOffsets() {
    let lines = QishuiTimedLyricParser.parse("[7700,2040]<0,270,0>I <270,310,0>miss <580,180,0>that")
    #expect(lines.count == 1)
    #expect(lines.first?.text == "I miss that")
    #expect(lines.first?.words.map(\.start) == [7.70, 7.97, 8.28])
    #expect(zip(lines.first?.words.map(\.end) ?? [], [7.97, 8.28, 8.46]).allSatisfy { abs($0 - $1) < 0.0001 })
    #expect(QishuiTimedLyricParser.words(for: "I miss that", at: 8, in: lines).count == 3)
    #expect(QishuiTimedLyricParser.words(for: "another song", at: 8, in: lines).isEmpty)
    #expect(QishuiTimedLyricParser.activeLine(at: 7.5, in: lines) == nil)
    #expect(QishuiTimedLyricParser.upcomingFirstLine(at: 0, in: lines)?.text == "I miss that")
    #expect(QishuiTimedLyricParser.upcomingFirstLine(at: 7.7, in: lines) == nil)
    #expect(QishuiTimedLyricParser.activeLine(at: 8.0, in: lines)?.current.text == "I miss that")
    #expect(QishuiTimedLyricParser.activeLine(at: 9.5, in: lines) == nil)
    #expect(QishuiTimedLyricParser.activeLine(at: 9.5, in: lines, trackDuration: 10)?.current.text == "I miss that")
    #expect(QishuiTimedLyricParser.activeLine(at: 10.5, in: lines, trackDuration: 10) == nil)
    let chorus = QishuiTimedLyricParser.parse("[1000,500]<0,500,0>Again\n[5000,500]<0,500,0>Again")
    #expect(QishuiTimedLyricParser.words(for: "Again", at: 5.2, in: chorus).first?.start == 5)
    #expect(QishuiTimedLyricParser.words(for: "Again", at: nil, in: chorus).isEmpty)
    #expect(QishuiTimedLyricParser.activeLine(at: 3.0, in: chorus)?.current.text == "Again")
}

@Test("词级时间轴跨句和回拖使用播放位置，不滞留上一句")
func qishuiTimedTimelineTracksForwardAndBackwardSeek() {
    let lines = QishuiTimedLyricParser.parse("[1000,1000]<0,500,0>First <500,500,0>line\n[4000,1000]<0,1000,0>Second line\n[8000,1000]<0,1000,0>Final line")
    #expect(QishuiTimedLyricParser.activeLine(at: 1.5, in: lines)?.current.text == "First line")
    #expect(QishuiTimedLyricParser.activeLine(at: 4.2, in: lines)?.current.text == "Second line")
    #expect(QishuiTimedLyricParser.activeLine(at: 8.5, in: lines)?.current.text == "Final line")
    #expect(QishuiTimedLyricParser.activeLine(at: 1.6, in: lines)?.current.text == "First line")
    #expect(QishuiTimedLyricParser.activeLine(at: 1.6, in: lines)?.next?.text == "Second line")
    #expect(QishuiTimedLyricParser.activeLine(at: 6, in: lines)?.current.text == "Second line")
}

import Foundation
import Testing
@testable import MacBookIsland

@Test("播放身份稳定优先于窗口不同格式或推荐曲目")
func lyricPlaybackIdentitySurvivesAXFormatAndRecommendationChanges() {
    let media = QishuiLyricIdentity(processIdentifier: 42, title: "Song", artist: "A, B")
    let variants = [
        QishuiLyricIdentity(processIdentifier: 42, title: "Song", artist: "A / B"),
        QishuiLyricIdentity(processIdentifier: 42, title: "Recommendation", artist: "Other")
    ]
    for direct in variants {
        #expect(QishuiLyricIdentityPolicy.select(media: media, direct: direct, runningProcesses: [42]) == media)
    }
    let next = QishuiLyricIdentity(processIdentifier: 42, title: "Next", artist: "Singer")
    #expect(QishuiLyricIdentityPolicy.select(media: next, direct: variants[0], runningProcesses: [42]) == next)
}

@Test("已退出播放进程不能压过运行中的窗口身份")
func lyricIdentityRejectsExitedProcessAndFallsBackWithoutMedia() {
    let media = QishuiLyricIdentity(processIdentifier: 10, title: "Old", artist: "Singer")
    let direct = QishuiLyricIdentity(processIdentifier: 42, title: "New", artist: "Singer")
    #expect(QishuiLyricIdentityPolicy.select(media: media, direct: direct, runningProcesses: [42]) == direct)
    #expect(QishuiLyricIdentityPolicy.select(media: nil, direct: direct, runningProcesses: [42]) == direct)
    #expect(QishuiLyricIdentityPolicy.select(media: media, direct: direct, runningProcesses: []) == nil)
}

@Test("歌词必须与同一歌曲的标题和完整歌手列表相符")
func lyricIdentityRequiresTitleAndAllArtists() {
    let identity = QishuiLyricIdentity(processIdentifier: 42, title: "同名歌", artist: "甲, 乙")
    #expect(QishuiLyricAttribution.matches(identity, title: " 同名歌 ", artists: ["甲", "乙"]))
    #expect(QishuiLyricAttribution.matches(identity, title: "同名歌", artists: ["乙", "甲"]))
    #expect(QishuiLyricAttribution.matches(
        QishuiLyricIdentity(processIdentifier: 42, title: "同名歌", artist: "甲 / 乙"),
        title: "同名歌",
        artists: ["甲", "乙"]
    ))
    #expect(!QishuiLyricAttribution.matches(identity, title: "同名歌", artists: ["丙"]))
    #expect(!QishuiLyricAttribution.matches(identity, title: "下一首", artists: ["甲", "乙"]))
    #expect(!QishuiLyricAttribution.matches(identity, title: "同名歌", artists: ["甲"]))
}

@Test("桌面歌词未知归属、混有旧句或超过两行时不可显示")
func desktopLyricsMustBelongToVerifiedSong() {
    let corpus: Set<String> = ["甲句", "乙句", "雨"]
    #expect(QishuiLyricAttribution.acceptsDesktop(["甲句", "乙句"], corpus: corpus))
    #expect(QishuiLyricAttribution.acceptsDesktop(["雨"], corpus: corpus))
    #expect(QishuiLyricAttribution.acceptsDesktop(["甲句", "甲句"], corpus: corpus))
    #expect(!QishuiLyricAttribution.acceptsDesktop(["甲句", "上一首的歌词"], corpus: corpus))
    #expect(!QishuiLyricAttribution.acceptsDesktop(["甲句"], corpus: []))
    #expect(!QishuiLyricAttribution.acceptsDesktop([], corpus: corpus))
    #expect(!QishuiLyricAttribution.acceptsDesktop(["甲句", "乙句", "雨"], corpus: corpus))
}

@Test("换歌标题先到而旧歌词尚未更新时必须保持空白")
func lyricCorpusDoesNotAttributeOldDOMToNewTitle() {
    var gate = QishuiLyricCorpusGate()
    let first: Set<String> = ["第一首独有的句子", "共用句"]
    let accepted1 = gate.accept(first)
    #expect(!accepted1)
    let accepted2 = gate.accept(first)
    #expect(accepted2)
    gate.transition(sameProcess: true)
    let accepted3 = gate.accept(first)
    #expect(!accepted3)
    let accepted4 = gate.accept(first)
    #expect(!accepted4)
    gate.transition(sameProcess: true)
    let accepted5 = gate.accept(first)
    #expect(!accepted5)
    let partial: Set<String> = ["第二首的句子"]
    let second: Set<String> = ["第二首的句子", "共用句"]
    let accepted6 = gate.accept(partial)
    #expect(!accepted6)
    let accepted7 = gate.accept(second)
    #expect(!accepted7)
    let accepted8 = gate.accept(second)
    #expect(accepted8)
    gate.transition(sameProcess: false)
    let accepted9 = gate.accept(second)
    #expect(!accepted9)
    let accepted10 = gate.accept(second)
    #expect(accepted10)
}

@Test("歌词段落首次查找后复用节点；没有节点时限制重试频率")
func qishuiLyricParagraphDiscoveryIsThrottled() {
    let now = Date(timeIntervalSince1970: 100)
    #expect(QishuiLyricDiscoveryPolicy.shouldDiscoverParagraphs(
        paragraphCount: 0,
        lastAttemptAt: .distantPast,
        now: now
    ))
    #expect(!QishuiLyricDiscoveryPolicy.shouldDiscoverParagraphs(
        paragraphCount: 0,
        lastAttemptAt: now,
        now: now.addingTimeInterval(2.9)
    ))
    #expect(QishuiLyricDiscoveryPolicy.shouldDiscoverParagraphs(
        paragraphCount: 0,
        lastAttemptAt: now,
        now: now.addingTimeInterval(3)
    ))
    #expect(!QishuiLyricDiscoveryPolicy.shouldDiscoverParagraphs(
        paragraphCount: 8,
        lastAttemptAt: .distantPast,
        now: now
    ))
}

@Test("歌词快照超过新鲜窗口后不继续沿用")
func qishuiLyricSnapshotFreshnessIsBounded() {
    let checkedAt = Date(timeIntervalSince1970: 100)
    #expect(QishuiLyricFreshnessPolicy.accepts(
        checkedAt: checkedAt,
        now: checkedAt.addingTimeInterval(0.70)
    ))
    #expect(!QishuiLyricFreshnessPolicy.accepts(
        checkedAt: checkedAt,
        now: checkedAt.addingTimeInterval(0.721)
    ))
    #expect(!QishuiLyricFreshnessPolicy.accepts(
        checkedAt: checkedAt,
        now: checkedAt.addingTimeInterval(-0.01)
    ))
}

@Test("桌面歌词首次附着及换歌时验证两次，附着后及时跟随当前句")
func qishuiDesktopLyricGateFollowsLiveRows() {
    var gate = QishuiDesktopLyricGate()
    let first = QishuiLyricIdentity(processIdentifier: 10, title: "A", artist: "Singer")
    let second = QishuiLyricIdentity(processIdentifier: 10, title: "B", artist: "Singer")
    let firstRead = gate.accept(["first", "next"], identity: first)
    let secondRead = gate.accept(["first", "next"], identity: first)
    let changedRead = gate.accept(["next", "later"], identity: first)
    let oldTrackRead = gate.accept(["next", "later"], identity: second)
    let newTrackFirstRead = gate.accept(["new song", "second"], identity: second)
    let newTrackSecondRead = gate.accept(["new song", "second"], identity: second)
    #expect(!firstRead)
    #expect(secondRead)
    #expect(changedRead)
    #expect(!oldTrackRead)
    #expect(!newTrackFirstRead)
    #expect(newTrackSecondRead)
}

@Test("同一 PID 但歌曲不一致时拒绝拼接 MediaRemote 与 AX")
func qishuiTrackCoherenceRejectsDifferentSong() {
    #expect(QishuiTrackCoherencePolicy.matches(
        mediaTitle: "GO!",
        mediaArtist: "CORTIS",
        directTitle: "GO!",
        directArtist: "CORTIS"
    ))
    #expect(QishuiTrackCoherencePolicy.matches(
        mediaTitle: "  GO! ",
        mediaArtist: "CORTIS",
        directTitle: "go!",
        directArtist: "CORTIS"
    ))
    #expect(QishuiTrackCoherencePolicy.matches(
        mediaTitle: "COOL KIDS",
        mediaArtist: "BASSTON, FAST BASSTON, Tazzy",
        directTitle: "cool kids",
        directArtist: "Tazzy / FAST BASSTON / BASSTON"
    ))
    #expect(!QishuiTrackCoherencePolicy.matches(
        mediaTitle: "GO!",
        mediaArtist: "CORTIS",
        directTitle: "this is what slow dancing feels like",
        directArtist: "JVKE"
    ))
    #expect(!QishuiTrackCoherencePolicy.matches(
        mediaTitle: "GO!",
        mediaArtist: "CORTIS",
        directTitle: "GO!",
        directArtist: ""
    ))
}

@Test("新鲜汽水 AX 与 MediaRemote 歌曲不一致时拒绝旧媒体帧")
func qishuiMediaRemoteAdmissionRejectsFreshIdentityMismatch() {
    let now = Date(timeIntervalSince1970: 100)
    #expect(!QishuiMediaRemoteAdmissionPolicy.accepts(
        mediaTitle: "却憎恨别人奋不顾身",
        mediaArtist: "旧歌手",
        directTitle: "才二十三",
        directArtist: "方大同",
        directCheckedAt: now,
        now: now.addingTimeInterval(0.2)
    ))
    #expect(QishuiMediaRemoteAdmissionPolicy.accepts(
        mediaTitle: "却憎恨别人奋不顾身",
        mediaArtist: "旧歌手",
        directTitle: "才二十三",
        directArtist: "方大同",
        directCheckedAt: now,
        now: now.addingTimeInterval(2.001)
    ))
    #expect(QishuiMediaRemoteAdmissionPolicy.accepts(
        mediaTitle: "才二十三",
        mediaArtist: "方大同",
        directTitle: "才二十三",
        directArtist: "方大同",
        directCheckedAt: now,
        now: now.addingTimeInterval(0.2)
    ))
}

@Test("active 歌词只接受当前歌曲，并合并播放器拆开的长句片段")
func desktopLyricsRequireOneVerifiedActiveParagraph() {
    let corpus: Set<String> = ["The lights are fading", "灯光渐渐暗下"]
    #expect(QishuiVerifiedActiveLyricPolicy.currentLines(
        activeParagraphs: [["The lights are fading", "灯光渐渐暗下"]],
        corpus: corpus
    ) == ["The lights are fading", "灯光渐渐暗下"])
    #expect(QishuiVerifiedActiveLyricPolicy.currentLines(
        activeParagraphs: [["The lights are fading"], ["灯光渐渐暗下"]],
        corpus: corpus
    ) == nil)
    #expect(QishuiVerifiedActiveLyricPolicy.currentLines(
        activeParagraphs: [["A stale lyric"]],
        corpus: corpus
    ) == nil)
    #expect(QishuiVerifiedActiveLyricPolicy.currentLines(
        activeParagraphs: [["A valid line", "A stale translation"]],
        corpus: corpus.union(["A valid line"])
    ) == nil)
    #expect(QishuiVerifiedActiveLyricPolicy.currentLines(
        activeParagraphs: [[
            "Red was the color that I bled when you",
            "said it was over",
            "当你说结束时 我流出的血是红色的"
        ]],
        corpus: [
            "Red was the color that I bled when you",
            "said it was over",
            "当你说结束时 我流出的血是红色的"
        ]
    ) == ["Red was the color that I bled when you said it was over", "当你说结束时 我流出的血是红色的"])
}

@Test("当前歌词快照可以安全携带下一段完整歌词")
func lyricParagraphPolicyAcceptsOnlyVerifiedNextParagraph() {
    let corpus: Set<String> = [
        "First line", "第一句翻译",
        "Second line", "第二句翻译",
        "Stale line"
    ]
    #expect(QishuiVerifiedActiveLyricPolicy.paragraphLines(
        ["Second line", "第二句翻译"],
        corpus: corpus
    ) == ["Second line", "第二句翻译"])
    #expect(QishuiVerifiedActiveLyricPolicy.paragraphLines(
        ["Second line", "Stale translation"],
        corpus: corpus
    ) == nil)
    #expect(QishuiVerifiedActiveLyricPolicy.paragraphLines(
        ["First line", "continued", "第一句翻译"],
        corpus: corpus
    ) == nil)
}

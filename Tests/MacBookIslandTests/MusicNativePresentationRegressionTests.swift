import Foundation
import Testing
@testable import MacBookIsland

@Test("独立署名段落换行后的作者姓名不丢失，续行仍须来自核验语料")
func wrappedSourceCreditKeepsVerifiedContinuation() {
    let credit = ["作词：Justin Bieber, Julia Michaels, Justin", "Tranter, Skrillex, BloodPop"]
    let composer = ["作曲：Justin Bieber, Julia Michaels, Justin", credit[1]]
    let corpus = Set((credit + composer).map(QishuiLyricAttribution.normalize))
    let expected = credit.joined(separator: " ")
    #expect(QishuiVerifiedActiveLyricPolicy.currentLines(activeParagraphs: [credit], corpus: corpus) == [expected])
    #expect(QishuiVerifiedActiveLyricPolicy.paragraphLines(credit, corpus: corpus) == [expected])
    #expect(QishuiVerifiedActiveLyricPolicy.introCredits(paragraphs: [credit, composer], corpus: corpus)
        == [expected, composer.joined(separator: " ")])
    #expect(QishuiVerifiedActiveLyricPolicy.currentLines(activeParagraphs: [credit], corpus: [credit[0]]) == nil)
    #expect(QishuiVerifiedActiveLyricPolicy.introCredits(paragraphs: [credit], corpus: [credit[0]]) == [credit[0]])
}

@Test("前奏高亮行缺失时只允许同曲已核验语料中的源署名")
func introCreditFallbackRequiresVerifiedCorpus() {
    let lines = ["作词：Harry", "作曲：Harry", "Future line"]
    let corpus = Set(lines.map(QishuiLyricAttribution.normalize))
    #expect(QishuiVerifiedActiveLyricPolicy.introCredits(paragraphs: [lines], corpus: corpus) == Array(lines.prefix(2)))
    #expect(QishuiVerifiedActiveLyricPolicy.introCredits(paragraphs: [lines], corpus: ["Future line"]).isEmpty)
}

@Test("前奏作词作曲保留源内容，不与正文误配成译文")
func introCreditsRemainVisible() {
    let lines = ["作词：Harry Lee Boazman", "作曲：Harry Lee-Boazman", "Through your prism of love"]
    #expect(MusicLyricPresentation.clean(lines) == lines)
    #expect(MusicLyricPresentation.state(lines: lines, index: 0) == .current(primary: lines[0], translation: ""))
    let pairs = MusicLyricPresentation.sourceCurrentAndNextPairs(lines: lines, index: 1)
    #expect(pairs.current == LyricPair(primary: lines[1], translation: ""))
    #expect(pairs.next.primary == lines[2])
}

@Test("署名独立行不折叠为一行")
func activeCreditsRemainSeparateRows() {
    let lines = ["作词：Harry", "作曲：Harry"]
    let corpus = Set(lines.map(QishuiLyricAttribution.normalize))
    #expect(QishuiVerifiedActiveLyricPolicy.currentLines(activeParagraphs: [lines], corpus: corpus) == lines)
}

@Test("带时间戳但无逐字标签的署名仍按源时间加载")
func timedCreditsKeepSourceTiming() {
    let lines = QishuiTimedLyricParser.parse("[0,3000]作词：Harry\n[3000,4000]作曲：Harry\n[8000,1000]<0,1000,0>Through your prism of love")
    #expect(lines.count == 3)
    #expect(QishuiTimedLyricParser.activeLine(at: 5, in: lines)?.current.text == "作曲：Harry")
    #expect(QishuiTimedLyricParser.words(for: "作曲：Harry", at: 5, in: lines).isEmpty)
}

@Test("实时主线程发布不得同步扫描汽水 AX；主界面不显示同步文案")
func realtimePublicationAvoidsSynchronousAXAndTechnicalCopy() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let adapter = try String(contentsOf: root.appendingPathComponent("Sources/MacBookIsland/MediaAdapter.swift"), encoding: .utf8)
    let start = try #require(adapter.range(of: "    func refreshSourceStatus("))
    let end = try #require(adapter.range(of: "    private func applyQishuiDirectSnapshot(", range: start.upperBound..<adapter.endIndex))
    #expect(!adapter[start.lowerBound..<end.lowerBound].contains("qishuiAdapter.snapshot("))
    let ui = try String(contentsOf: root.appendingPathComponent("Sources/MacBookIsland/main.swift"), encoding: .utf8)
    #expect(!ui.contains("Text(\"状态同步中\")"))
}

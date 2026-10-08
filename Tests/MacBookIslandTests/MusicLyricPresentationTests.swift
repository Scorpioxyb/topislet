import Testing
@testable import MacBookIsland

@Test("无歌词视图使用听歌文案，不把空读或关闭当成错误")
func lyricEmptyStateUsesListeningCopy() {
    for lines in [[], ["正在加载歌词"], ["汽水窗口已同步，暂未暴露可见歌词"], ["暂无歌词，请欣赏"]] {
        #expect(MusicLyricPresentation.emptyStateText(lines: lines, lyricsEnabled: true) == "聆听音乐")
    }
    #expect(MusicLyricPresentation.emptyStateText(lines: [], lyricsEnabled: false) == "聆听音乐")
}

@Test("只有明确纯音乐标记才显示纯音乐文案，真实歌词不能被误标")
func lyricEmptyStateDoesNotInferInstrumentalFromMissingLyrics() {
    #expect(MusicLyricPresentation.emptyStateText(lines: ["纯音乐，请欣赏"], lyricsEnabled: true) == "纯音乐，请欣赏")
    #expect(MusicLyricPresentation.emptyStateText(lines: ["纯音乐，请欣赏", "真实歌词"], lyricsEnabled: true) == "聆听音乐")
    #expect(MusicLyricPresentation.emptyStateText(lines: ["纯音乐，请欣赏"], lyricsEnabled: false) == "聆听音乐")
}

@Test("歌词末句不会循环展示首句，无效索引清空两行")
func lyricPresentationDoesNotInventNextLine() {
    let lines = ["第一句", "第二句"]
    #expect(MusicLyricPresentation.currentAndNext(lines: lines, index: 0).next == "第二句")
    #expect(MusicLyricPresentation.currentAndNext(lines: lines, index: 1).current == "第二句")
    #expect(MusicLyricPresentation.currentAndNext(lines: lines, index: 1).next.isEmpty)
    for index in [-1, 2, Int.max] {
        let result = MusicLyricPresentation.currentAndNext(lines: lines, index: index)
        #expect(result.current.isEmpty && result.next.isEmpty)
    }
    #expect(MusicLyricPresentation.currentAndNext(lines: [], index: 0).current.isEmpty)
}

@Test("无歌词和来源诊断不占歌词位置，保留真实重复歌词和单字歌词")
func lyricPresentationKeepsLyricsWithoutStatusPlaceholders() {
    let lines = [
        " ", "汽水窗口已同步，暂未暴露可见歌词", "来自汽水音乐直接适配源",
        "正在加载歌词", "暂无歌词，请欣赏", "纯音乐，请欣赏", "来源：汽水窗口 AX",
        " 雨\n", "重复的一句", "重复的一句"
    ]
    #expect(MusicLyricPresentation.clean(lines) == ["雨", "重复的一句", "重复的一句"])
    #expect(MusicLyricPresentation.hasDisplayableLines(lines))
    #expect(!MusicLyricPresentation.hasDisplayableLines(["纯音乐，请欣赏", "正在加载歌词"]))
    #expect(MusicLyricPresentation.sourceCreditLines(["作词：王嘉尔", "作曲: 李四", "第一句"]) == ["作词 · 王嘉尔", "作曲 · 李四"])
    #expect(MusicLyricPresentation.isConfirmedInstrumental(["纯音乐，请欣赏"]))
    #expect(MusicLyricPresentation.isConfirmedInstrumental(["纯音乐请欣赏"]))
    #expect(!MusicLyricPresentation.isConfirmedInstrumental(["正在加载歌词"]))
}

@Test("AX 单个静态文本里的原文和译文换行会先拆开")
func lyricPresentationFlattensEmbeddedNewlines() {
    let lines = MusicLyricPresentation.clean([
        "First line\n第一句",
        "Second line\r\n第二句"
    ])
    #expect(lines == ["First line", "第一句", "Second line", "第二句"])
    let pair = MusicLyricPresentation.currentAndNextPairs(lines: lines, index: 0)
    #expect(pair.current == LyricPair(primary: "First line", translation: "第一句"))
    #expect(pair.next == LyricPair(primary: "Second line", translation: "第二句"))
}

@Test("歌词文本清理会丢弃汽水 AX 元数据行")
func lyricPresentationDropsCreditMetadata() {
    let lines = ["作词：张三", "作曲: 李四", "混音：王五", "夜色渐渐落下", "第二句"]
    #expect(MusicLyricPresentation.clean(lines) == ["夜色渐渐落下", "第二句"])
}

@Test("末句后的汽水歌词贡献者不能成为译文或下一句")
func lyricContributorDoesNotBecomeNextLyric() {
    let lines = ["Dj your love your love your love", "DJ你的爱意你的爱意你的爱意", "歌词贡献者：海屿你"]
    let pair = MusicLyricPresentation.sourceCurrentAndNextPairs(lines: lines, index: 0)
    #expect(pair.current.primary == lines[0])
    #expect(pair.current.translation == lines[1])
    #expect(pair.next.isEmpty)
    #expect(MusicLyricPresentation.state(lines: lines, index: 2) == .unavailable)
}

@Test("清洗歌词后仍按原始 lyricIndex 映射当前句")
func lyricPresentationRemapsIndexAfterFilteringMetadata() {
    let lines = ["作词：张三", "First line", "第一句", "Second line", "第二句"]
    #expect(MusicLyricPresentation.state(lines: lines, index: 1)
        == .current(primary: "First line", translation: "第一句"))
    #expect(MusicLyricPresentation.state(lines: lines, index: 3)
        == .current(primary: "Second line", translation: "第二句"))
    #expect(MusicLyricPresentation.state(lines: lines, index: 0) == .unavailable)
}

@Test("展开歌词使用同一套清洗后索引，避免元数据导致显示错句")
func lyricShelfRemapsSourceIndexAfterFilteringMetadata() {
    let result = MusicLyricPresentation.sourceCurrentAndNextPairs(
        lines: ["作词：张三", "First line", "第一句", "Second line", "第二句"],
        index: 3
    )
    #expect(result.current == LyricPair(primary: "Second line", translation: "第二句"))
    #expect(result.next.isEmpty)
}

@Test("当前歌词进入宽档，空歌词保持标准紧凑宽度")
func compactMusicLayoutUsesStableWidthTiers() {
    #expect(MusicCompactLayout.leadingWingWidth(hasCurrentLyric: true) == 344)
    #expect(MusicCompactLayout.trailingWingWidth(hasCurrentLyric: true) == 96)
    #expect(MusicCompactLayout.compactWidth(notchWidth: 185, hasCurrentLyric: true) == 625)
    #expect(MusicCompactLayout.compactWidth(notchWidth: 185, hasCurrentLyric: false) == 377)
    #expect(MusicCompactLayout.wingWidth(hasCurrentLyric: false) == 96)
    #expect(MusicCompactLayout.lyricLeadingWingWidth - 25 - 8 - 20 > 280)
    #expect(MusicCompactLayout.lyricContentHeight == 25)
    #expect(MusicCompactLayout.lyricPrimaryLineHeight > MusicCompactLayout.lyricPrimaryFontSize)
    #expect(!MusicCompactLayout.showsTranslationInCompact)
    #expect(MusicCompactLayout.lyricVerticalSafeInset >= 4)
    #expect(MusicCompactLayout.lyricContentFitsTopBand(33))
    #expect(MusicCompactLayout.lyricContentHeight + MusicCompactLayout.lyricVerticalSafeInset * 2 <= 33)
}

@Test("展开歌词栏到达后使用带歌词高度，空歌词不预留面板")
func expandedMusicLayoutReservesLyricShelfOnlyForDisplayableLines() {
    #expect(MusicExpandedLayout.bodyHeight(lines: ["当前句"]) == 144)
    #expect(MusicExpandedLayout.bodyHeight(lines: ["纯音乐，请欣赏"]) == 116)
    #expect(MusicExpandedLayout.bodyHeight(lines: [], heightAdjustment: -200) == 112)
}

@Test("歌词媒体发布节拍不慢于 AX 歌词读取节拍")
func lyricPublicationCadenceMatchesReader() {
    #expect(MusicPresentationTimingPolicy.mediaPublicationInterval == 0.18)
    #expect(MusicPresentationTimingPolicy.mediaPublicationInterval <= 0.18)
}

@Test("歌词文本变化后旧文本的滚动宽度不可沿用")
func marqueeMeasurementMustBelongToCurrentText() {
    let oldMeasurement = MarqueeTextMeasurement(text: "A very long previous lyric", width: 420)
    #expect(MarqueeTextLayoutPolicy.overflow(
        for: "短句",
        measurement: oldMeasurement,
        viewportWidth: 260
    ) == 0)
    #expect(MarqueeTextLayoutPolicy.overflow(
        for: oldMeasurement.text,
        measurement: oldMeasurement,
        viewportWidth: 260
    ) == 160)
    let shortMeasurement = MarqueeTextMeasurement(text: "短句", width: 32)
    #expect(MarqueeTextLayoutPolicy.overflow(
        for: shortMeasurement.text,
        measurement: shortMeasurement,
        viewportWidth: 260
    ) == 0)
}

@Test("中英相邻歌词合并为当前句译文，译文索引不会被误当成下一句")
func bilingualLyricsPairWithTranslation() {
    let lines = [
        "Feels like I'm waiting",
        "感觉我在等候",
        "Like I'm watching",
        "像我在看"
    ]

    let first = MusicLyricPresentation.currentAndNextPairs(lines: lines, index: 0)
    #expect(first.current == LyricPair(primary: "Feels like I'm waiting", translation: "感觉我在等候"))
    #expect(first.next == LyricPair(primary: "Like I'm watching", translation: "像我在看"))

    let translationIndex = MusicLyricPresentation.currentAndNextPairs(lines: lines, index: 1)
    #expect(translationIndex.current == first.current)
    #expect(translationIndex.next == first.next)
}

@Test("歌词呈现状态机在不同入口返回同一当前句")
func lyricPresentationStateKeepsPrimaryAndTranslationTogether() {
    let state = MusicLyricPresentation.state(
        lines: ["First line", "第一句", "Next line", "下一句"],
        index: 1
    )
    #expect(state == .current(primary: "First line", translation: "第一句"))
    #expect(state.primary == "First line")
    #expect(state.translation == "第一句")
    #expect(state.isAvailable)
    #expect(MusicLyricPresentation.state(lines: ["纯音乐，请欣赏"], index: 0) == .unavailable)
}

@Test("歌词状态变化即使保持有歌词也会产生可比较的状态值")
func lyricPresentationStateChangesWhenCurrentLineChanges() {
    let first = MusicLyricPresentation.state(lines: ["First", "第一句"], index: 0)
    let second = MusicLyricPresentation.state(lines: ["Second", "第二句"], index: 0)
    #expect(first.isAvailable && second.isAvailable)
    #expect(first != second)
}

@Test("同语言连续歌词不被错误合并")
func sameLanguageLyricsRemainSeparate() {
    let lines = ["第一句", "第二句", "第三句"]
    let result = MusicLyricPresentation.currentAndNextPairs(lines: lines, index: 0)
    #expect(result.current == LyricPair(primary: "第一句", translation: ""))
    #expect(result.next == LyricPair(primary: "第二句", translation: ""))
}

@Test("桌面歌词快照不把当前句和下一句误标成翻译")
func desktopLyricRowsRemainCurrentAndNext() {
    let result = MusicLyricPresentation.currentAndNextPairs(
        lines: ["第一句", "第二句"],
        index: 0,
        pairMixedLanguageLines: false
    )
    #expect(result.current == LyricPair(primary: "第一句", translation: ""))
    #expect(result.next == LyricPair(primary: "第二句", translation: ""))
}

@Test("marquee 短句不移动，长句先停留再单向滚动并回到起点")
func marqueeTimelineHasStableShortTextAndBoundedLongText() {
    #expect(MusicMarqueeTimeline.offset(elapsed: 10, overflow: 0) == 0)
    let middle = MusicMarqueeTimeline.offset(elapsed: 0.5, overflow: 52)
    #expect(middle > 0 && middle < 52)
    let travel = Double(52 / MusicMarqueeTimeline.speed(for: 52))
    let endOfTravel = MusicMarqueeTimeline.holdDuration + travel
    #expect(MusicMarqueeTimeline.offset(elapsed: endOfTravel, overflow: 52) == 52)
    let cycle = MusicMarqueeTimeline.holdDuration + travel + MusicMarqueeTimeline.holdDuration
    #expect(MusicMarqueeTimeline.offset(elapsed: cycle + 0.01, overflow: 52) == 0)
    #expect(MusicMarqueeTimeline.speed(for: 52) == 72)
    #expect(MusicMarqueeTimeline.speed(for: 280) == 150)
    #expect(MusicMarqueeTimeline.speed(for: 500) == 150)
}

@Test("逐字歌词按当前句逐步高亮，且没有时间戳时只做可见回退")
func karaokeHighlightPolicyRevealsCharactersWithoutInventingTiming() {
    #expect(KaraokeHighlightPolicy.highlightedCharacterCount(elapsed: 0, text: "歌词") == 0)
    #expect(KaraokeHighlightPolicy.highlightedCharacterCount(elapsed: 0.8, text: "歌词") >= 1)
    #expect(KaraokeHighlightPolicy.highlightedCharacterCount(elapsed: 20, text: "歌词") == 2)
    #expect(KaraokeHighlightPolicy.progress(elapsed: -1, characterCount: 3) == 0)
    #expect(KaraokeHighlightPolicy.progress(elapsed: 20, characterCount: 3) == 1)
    #expect(KaraokeHighlightPolicy.duration(characterCount: 0) == KaraokeHighlightPolicy.minimumDuration)
    #expect(KaraokeHighlightPolicy.duration(characterCount: 100) == KaraokeHighlightPolicy.maximumDuration)
}

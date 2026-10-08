import Foundation
import CoreGraphics

enum MusicCompactLayout {
    static let standardWingWidth: CGFloat = 96
    // Lyrics are a first-class compact state. The previous 320pt wing left
    // only ~277pt for glyphs after the artwork and padding, which made a
    // readable 18pt line feel cramped as soon as the sentence was long.
    static let lyricLeadingWingWidth: CGFloat = 344
    static let lyricTrailingWingWidth: CGFloat = standardWingWidth
    // The attached top band is normally 33pt high. Compact mode therefore
    // renders one deliberately prominent current line. Translation and the
    // next line belong to the expanded lyric shelf, where they have room to
    // be read instead of competing for a clipped two-row frame.
    static let lyricPrimaryFontSize: CGFloat = 19
    static let lyricPrimaryLineHeight: CGFloat = 25
    static let lyricContentHeight: CGFloat = lyricPrimaryLineHeight
    static let lyricVerticalSafeInset: CGFloat = 4
    static let showsTranslationInCompact = false
    // Long lyrics keep the selected type size and move through a bounded
    // viewport. A longer travel and hold period prevents the line from
    // looking like a ticker while still making overflow discoverable.
    static let lyricMarqueeSpeed: CGFloat = 72
    static let lyricMarqueeMaximumSpeed: CGFloat = 150
    static let lyricMarqueeTargetTravelDuration: TimeInterval = 1.6
    static let lyricMarqueeHoldDuration: TimeInterval = 0.42

    static func wingWidth(hasCurrentLyric: Bool) -> CGFloat {
        hasCurrentLyric ? lyricLeadingWingWidth : standardWingWidth
    }

    static func leadingWingWidth(hasCurrentLyric: Bool) -> CGFloat {
        hasCurrentLyric ? lyricLeadingWingWidth : standardWingWidth
    }

    static func trailingWingWidth(hasCurrentLyric: Bool) -> CGFloat {
        hasCurrentLyric ? lyricTrailingWingWidth : standardWingWidth
    }

    static func compactWidth(notchWidth: CGFloat, hasCurrentLyric: Bool) -> CGFloat {
        notchWidth
            + leadingWingWidth(hasCurrentLyric: hasCurrentLyric)
            + trailingWingWidth(hasCurrentLyric: hasCurrentLyric)
    }

    static func lyricContentFitsTopBand(_ topBandHeight: CGFloat) -> Bool {
        lyricContentHeight + lyricVerticalSafeInset * 2 <= topBandHeight
    }
}

enum MusicExpandedLayout {
    static let noLyricsBodyHeight: CGFloat = 116
    // Lyrics are a reading surface, not a taller copy of the control card.
    // Keep enough vertical room for a strong current line, translation and
    // next-line context while staying within one horizontal capsule.
    static let lyricsBodyHeight: CGFloat = 144
    static let minimumBodyHeight: CGFloat = 112

    static func bodyHeight(lines: [String], heightAdjustment: CGFloat = 0) -> CGFloat {
        let baseHeight = MusicLyricPresentation.hasDisplayableLines(lines)
            ? lyricsBodyHeight
            : noLyricsBodyHeight
        return max(minimumBodyHeight, baseHeight + heightAdjustment)
    }
}

enum MusicPresentationTimingPolicy {
    // Admit a newly active AX row promptly while keeping the existing
    // single-in-flight reader bound. Song identity and corpus gates remain.
    static let mediaPublicationInterval: TimeInterval = 0.18
}

enum MusicMarqueeTimeline {
    static let speed = MusicCompactLayout.lyricMarqueeSpeed
    static let holdDuration = MusicCompactLayout.lyricMarqueeHoldDuration

    static func speed(for overflow: CGFloat) -> CGFloat {
        guard overflow > 0 else { return speed }
        return min(
            MusicCompactLayout.lyricMarqueeMaximumSpeed,
            max(speed, overflow / MusicCompactLayout.lyricMarqueeTargetTravelDuration)
        )
    }

    static func offset(
        elapsed: TimeInterval,
        overflow: CGFloat,
        speed: CGFloat = speed,
        holdDuration: TimeInterval = holdDuration
    ) -> CGFloat {
        guard overflow > 0, speed > 0 else { return 0 }
        let travel = TimeInterval(overflow / speed)
        let cycle = holdDuration + travel + holdDuration
        let phase = elapsed.truncatingRemainder(dividingBy: cycle)
        if phase < holdDuration { return 0 }
        if phase < holdDuration + travel {
            return CGFloat((phase - holdDuration) / travel) * overflow
        }
        return overflow
    }
}

struct LyricPair: Equatable {
    let primary: String
    let translation: String

    var isEmpty: Bool {
        primary.isEmpty
    }
}

enum MusicLyricPresentationState: Equatable {
    case unavailable
    case current(primary: String, translation: String)

    var primary: String {
        switch self {
        case .unavailable:
            return ""
        case let .current(primary, _):
            return primary
        }
    }

    var translation: String {
        switch self {
        case .unavailable:
            return ""
        case let .current(_, translation):
            return translation
        }
    }

    var isAvailable: Bool {
        if case .current = self { return true }
        return false
    }
}

struct MarqueeTextMeasurement: Equatable {
    let text: String
    let width: CGFloat
}

/// A visual-only karaoke fallback for sources that expose the active lyric
/// line but do not expose per-character timestamps. The active-row transition
/// remains the source of truth; this policy only reveals characters smoothly
/// inside that already-verified row and never invents the next lyric.
enum KaraokeHighlightPolicy {
    static let minimumDuration: TimeInterval = 1.6
    static let maximumDuration: TimeInterval = 5.4
    static let secondsPerCharacter: TimeInterval = 0.12

    static func duration(characterCount: Int) -> TimeInterval {
        guard characterCount > 0 else { return minimumDuration }
        return min(
            maximumDuration,
            max(minimumDuration, 0.65 + Double(characterCount) * secondsPerCharacter)
        )
    }

    static func progress(elapsed: TimeInterval, characterCount: Int) -> Double {
        guard characterCount > 0 else { return 1 }
        return min(max(elapsed / duration(characterCount: characterCount), 0), 1)
    }

    static func highlightedCharacterCount(elapsed: TimeInterval, text: String) -> Int {
        let characters = text.count
        guard characters > 0 else { return 0 }
        return min(
            characters,
            Int(ceil(progress(elapsed: elapsed, characterCount: characters) * Double(characters)))
        )
    }
}

enum MarqueeTextLayoutPolicy {
    static func overflow(
        for text: String,
        measurement: MarqueeTextMeasurement?,
        viewportWidth: CGFloat
    ) -> CGFloat {
        guard let measurement, measurement.text == text else { return 0 }
        return max(measurement.width - viewportWidth, 0)
    }
}

/// Presentation of supplied lyric lines only. This does not infer timing or loop a song.
enum MusicLyricPresentation {
    static func emptyStateText(lines: [String], lyricsEnabled: Bool) -> String {
        // Missing lyrics are not evidence that a track is instrumental.
        // Playback stays the main experience; technical status belongs in diagnostics.
        lyricsEnabled && isConfirmedInstrumental(lines)
            ? "纯音乐，请欣赏"
            : "聆听音乐"
    }

    static func sourceCreditLines(_ lines: [String]) -> [String] {
        lines
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.range(of: metadataLinePattern, options: .regularExpression) != nil }
            .prefix(2)
            .map { line in
                guard let colon = line.firstIndex(where: { $0 == "：" || $0 == ":" }) else { return line }
                return String(line[..<colon]) + " · " + line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
    }

    static func isConfirmedInstrumental(_ lines: [String]) -> Bool {
        lines.contains { ["纯音乐，请欣赏", "纯音乐请欣赏"].contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            && clean(lines).isEmpty
    }
    private static let unavailableLines: Set<String> = [
        "汽水窗口已同步，暂未暴露可见歌词", "来自汽水音乐直接适配源",
        "暂无歌词，请欣赏", "纯音乐，请欣赏", "纯音乐请欣赏", "正在加载歌词"
    ]
    private static let diagnosticTokens = [
        "MediaRemote", "Adapter", "来源：", "播放态：", "已发送", "已请求",
        "实时同步", "同步来源", "辅助功能", "控制中心", "手动诊断", "适配器", "PID "
    ]
    private static let metadataLinePattern = #"^(作词|作曲|编曲|制作人|监制|演唱|混音|母带|录音|出品|歌词贡献者|歌词提供者|词|曲)\s*[:：]"#

    static func clean(_ lines: [String]) -> [String] {
        // AX can expose an original/translation pair as one static-text value
        // containing an embedded newline. Flatten it before attribution and
        // presentation; otherwise the collapsed island treats the pair as one
        // lyric and SwiftUI wraps it into two rows inside a 33pt top band.
        lines
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty && !unavailableLines.contains(line)
                    && !diagnosticTokens.contains { line.localizedCaseInsensitiveContains($0) }
                    && line.range(of: metadataLinePattern, options: .regularExpression) == nil
            }
    }

    static func hasDisplayableLines(_ lines: [String]) -> Bool {
        !clean(lines).isEmpty
    }

    static func currentAndNext(lines: [String], index: Int) -> (current: String, next: String) {
        guard lines.indices.contains(index) else { return ("", "") }
        let next = index + 1
        return (lines[index], lines.indices.contains(next) ? lines[next] : "")
    }

    /// Resolves an adapter index against the source array before removing
    /// metadata and placeholder rows. AX lyric trees frequently contain both,
    /// so applying the source index directly to `clean(lines)` shifts the
    /// visible lyric as soon as one such row appears before the active line.
    static func sourceCurrentAndNextPairs(
        lines: [String],
        index: Int,
        pairMixedLanguageLines: Bool = true
    ) -> (current: LyricPair, next: LyricPair) {
        guard lines.indices.contains(index), !clean([lines[index]]).isEmpty else {
            return (LyricPair(primary: "", translation: ""), LyricPair(primary: "", translation: ""))
        }
        let normalizedIndex = lines[..<index]
            .reduce(into: 0) { count, rawLine in
                count += clean([rawLine]).count
            }
        let cleanedLines = clean(lines)
        guard cleanedLines.indices.contains(normalizedIndex) else {
            return (LyricPair(primary: "", translation: ""), LyricPair(primary: "", translation: ""))
        }
        return currentAndNextPairs(
            lines: cleanedLines,
            index: normalizedIndex,
            pairMixedLanguageLines: pairMixedLanguageLines
        )
    }

    static func state(
        lines: [String],
        index: Int,
        pairMixedLanguageLines: Bool = true
    ) -> MusicLyricPresentationState {
        guard lines.indices.contains(index) else { return .unavailable }

        // Adapters keep lyricIndex in the source array's coordinate space, but
        // clean(_:) can remove metadata/placeholders or split an embedded
        // original/translation newline. Remap the current raw row before
        // pairing, otherwise a filtered row shifts the visible lyric by one.
        let currentRawLines = clean([lines[index]])
        guard !currentRawLines.isEmpty else { return .unavailable }
        let normalizedIndex = lines[..<index]
            .reduce(into: 0) { count, rawLine in
                count += clean([rawLine]).count
            }
        let cleanedLines = clean(lines)
        guard cleanedLines.indices.contains(normalizedIndex) else { return .unavailable }
        let pairs = currentAndNextPairs(
            lines: cleanedLines,
            index: normalizedIndex,
            pairMixedLanguageLines: pairMixedLanguageLines
        )
        guard !pairs.current.primary.isEmpty else { return .unavailable }
        return .current(
            primary: pairs.current.primary,
            translation: pairs.current.translation
        )
    }

    static func currentAndNextPairs(
        lines: [String],
        index: Int,
        pairMixedLanguageLines: Bool = true
    ) -> (current: LyricPair, next: LyricPair) {
        guard lines.indices.contains(index) else {
            return (LyricPair(primary: "", translation: ""), LyricPair(primary: "", translation: ""))
        }

        guard pairMixedLanguageLines else {
            let current = LyricPair(primary: lines[index], translation: "")
            let nextIndex = index + 1
            let next = lines.indices.contains(nextIndex)
                ? LyricPair(primary: lines[nextIndex], translation: "")
                : LyricPair(primary: "", translation: "")
            return (current, next)
        }

        let currentIndex: Int
        if index > lines.startIndex,
           isTranslationPair(lines[index - 1], lines[index]),
           containsCJK(lines[index]) {
            currentIndex = index - 1
        } else {
            currentIndex = index
        }

        let current = pair(at: currentIndex, in: lines)
        let nextIndex = currentIndex + (isTranslationPairAt(currentIndex, in: lines) ? 2 : 1)
        let next = lines.indices.contains(nextIndex)
            ? pair(at: nextIndex, in: lines)
            : LyricPair(primary: "", translation: "")
        return (current, next)
    }

    private static func pair(at index: Int, in lines: [String]) -> LyricPair {
        guard lines.indices.contains(index) else {
            return LyricPair(primary: "", translation: "")
        }
        let translationIndex = index + 1
        guard lines.indices.contains(translationIndex),
              isTranslationPair(lines[index], lines[translationIndex]) else {
            return LyricPair(primary: lines[index], translation: "")
        }
        return LyricPair(primary: lines[index], translation: lines[translationIndex])
    }

    private static func isTranslationPairAt(_ index: Int, in lines: [String]) -> Bool {
        let next = index + 1
        return lines.indices.contains(next) && isTranslationPair(lines[index], lines[next])
    }

    private static func isTranslationPair(_ lhs: String, _ rhs: String) -> Bool {
        containsCJK(lhs) != containsCJK(rhs)
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}

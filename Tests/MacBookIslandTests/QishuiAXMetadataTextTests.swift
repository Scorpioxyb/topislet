import Testing
import Foundation
@testable import MacBookIsland

@Test("汽水一字歌名保留为标题，不让歌手和歌词顶替")
func qishuiAcceptsSingleCharacterSongTitles() {
    let reader = QishuiAXReader(imagePrefixes: [])
    #expect(reader.isLikelySongOrArtistText("雨"))
    #expect(reader.isLikelySongOrArtistText("愛"))
    #expect(reader.isLikelySongOrArtistText("X"))
    #expect(!reader.isLikelySongOrArtistText(" "))
    #expect(!reader.isLikelySongOrArtistText("7"))
    #expect(!reader.isLikelySongOrArtistText("00:00 / 03:16"))
    #expect(!reader.isLikelySongOrArtistText("/"))
}

@Test("封面右侧歌词列不参与歌手候选，长歌手文本起点仍在封面列内")
func qishuiArtistCandidatesExcludeAdjacentLyricsColumn() {
    let reader = QishuiAXReader(imagePrefixes: [])
    let cover = CGRect(x: 200, y: 100, width: 400, height: 400)
    #expect(reader.isInArtistColumn(CGRect(x: 200, y: 550, width: 800, height: 20), coverFrame: cover))
    #expect(!reader.isInArtistColumn(CGRect(x: 660, y: 550, width: 350, height: 20), coverFrame: cover))
    #expect(!reader.isInArtistColumn(CGRect(x: 50, y: 550, width: 100, height: 20), coverFrame: cover))
}

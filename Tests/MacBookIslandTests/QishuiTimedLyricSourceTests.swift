import Foundation
import Testing
@testable import MacBookIsland

private func lyricSourceFixture(ambiguous: Bool = false, detailTitle: String = "Song") -> (Data, Data) {
    let candidate: [String: Any] = ["title": "Song", "author_info": ["name": "A/B"], "duration": 100, "item_id": "1234567890123"]
    let search = try! JSONSerialization.data(withJSONObject: ["data": ["list": ambiguous ? [candidate, candidate] : [candidate]]])
    let detail = try! JSONSerialization.data(withJSONObject: [
        "seo_track": ["track": ["name": detailTitle, "artists": [["name": "A"], ["name": "B"]], "duration": 100000]],
        "lyric": ["content": "[1000,1000]<0,1000,0>Hello"]
    ])
    return (search, detail)
}

@Test("非有限时长在联网前被拒绝")
func timedLyricSourceRejectsInvalidDurationBeforeNetwork() async {
    let source = QishuiTimedLyricSource(readData: { _ in
        Issue.record("Invalid duration must not contact lyric provider")
        return nil
    })
    #expect(await source.fetch(title: "Song", artist: "Singer", duration: .infinity).isEmpty)
    #expect(await source.fetch(title: "Song", artist: "Singer", duration: .nan).isEmpty)
    #expect(await source.fetch(title: "Song", artist: "Singer", duration: 0).isEmpty)
}

@Test("歌词查询搜索与详情均核验后才返回时间轴")
func timedLyricSourceRequiresBothVerifiedResponses() async {
    let (search, detail) = lyricSourceFixture()
    let source = QishuiTimedLyricSource(readData: { url in
        url.host == "api-vehicle.volcengine.com" ? search : detail
    })
    let lines = await source.fetch(title: "Song", artist: "A, B", duration: 100)
    #expect(lines.first?.text == "Hello")
    #expect(lines.first?.words.first?.start == 1)
}

@Test("搜索命中但详情换成其他歌曲时拒绝歌词")
func timedLyricSourceRejectsWrongDetailIdentity() async {
    let (search, detail) = lyricSourceFixture(detailTitle: "Other")
    let source = QishuiTimedLyricSource(readData: { url in
        url.host == "api-vehicle.volcengine.com" ? search : detail
    })
    #expect(await source.fetch(title: "Song", artist: "A, B", duration: 100).isEmpty)
}

@Test("同名相同时长版本无法区分时不猜测歌词")
func timedLyricSourceRejectsAmbiguousSearchVersions() async {
    let (search, detail) = lyricSourceFixture(ambiguous: true)
    let source = QishuiTimedLyricSource(readData: { url in
        url.host == "api-vehicle.volcengine.com" ? search : detail
    })
    #expect(await source.fetch(title: "Song", artist: "A, B", duration: 100).isEmpty)
}

@Test("请求途中取消，即使输送层返回数据也不能发布歌词")
func timedLyricSourceRejectsCancelledTransportResult() async {
    let (search, detail) = lyricSourceFixture()
    let source = QishuiTimedLyricSource(readData: { url in
        withUnsafeCurrentTask { $0?.cancel() }
        return url.host == "api-vehicle.volcengine.com" ? search : detail
    })
    let task = Task { await source.fetch(title: "Song", artist: "A, B", duration: 100) }
    #expect(await task.value.isEmpty)
}

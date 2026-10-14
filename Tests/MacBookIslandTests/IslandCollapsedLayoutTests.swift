import CoreGraphics
import Testing
@testable import MacBookIsland

@Test("空闲默认态不占用摄像头区域两侧菜单栏")
func idleCollapsedStateHasNoWings() {
    #expect(IslandCollapsedLayout.wingWidth(feature: .activityCenter, hasCurrentMusicTrack: false) == 0)
    #expect(IslandCollapsedLayout.wingWidth(feature: .activityCenter, hasCurrentMusicTrack: true) == 0)
    #expect(IslandCollapsedLayout.wingWidth(feature: .music, hasCurrentMusicTrack: false) == 0)
}

@Test("音乐封面有安全间隔且折叠宽度仍保持现有小翼宽")
func collapsedArtworkFitsOutsideCameraHousing() {
    let wing = IslandCollapsedLayout.wingWidth(feature: .music, hasCurrentMusicTrack: true)
    #expect(wing == 22)
    #expect((wing - IslandCollapsedLayout.artworkSize) / 2 >= 3)
    for height in [CGFloat(30), 32, 38, 52] {
        #expect((height - IslandCollapsedLayout.artworkSize) / 2 >= 7)
    }
    for feature in [IslandFeature.timer, .notification] {
        #expect(IslandCollapsedLayout.wingWidth(feature: feature, hasCurrentMusicTrack: false) == wing)
    }
}

@Test("后台音乐到达保留默认折叠状态")
func musicArrivalPreservesCollapsedMode() {
    #expect(IslandCollapsedLayout.musicArrivalMode(currentMode: .collapsed) == .collapsed)
    #expect(IslandCollapsedLayout.musicArrivalMode(currentMode: .compact) == .compact)
}

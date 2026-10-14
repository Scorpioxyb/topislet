import AppKit
import Testing
@testable import MacBookIsland

@Test("岛内点击延后处理时不会跟随已经移到岛外的指针")
func capturedClickRemainsInsideAfterPointerMoves() {
    let regions = IslandInteractionRegions.make(
        panelFrame: NSRect(x: 730, y: 889, width: 460, height: 189),
        mode: .expanded,
        headerWidth: 253,
        topBandHeight: 33,
        expandedBodyHeight: 148,
        expandedPanelTopGap: 8
    )
    let click = IslandOutsideClickLocation(
        windowServerPoint: CGPoint(x: 960, y: 150), primaryDisplayHeight: 1107
    )
    let pointerAfterClick = CGPoint(x: 100, y: 100)
    #expect(!regions.contains(pointerAfterClick))
    #expect(regions.contains(click.appKitPoint))
}

@Test("岛外点击即使指针随后移回岛内也保持岛外归属")
func capturedOutsideClickRemainsOutside() {
    let body = NSRect(x: 730, y: 889, width: 460, height: 148)
    let click = IslandOutsideClickLocation(
        windowServerPoint: CGPoint(x: 100, y: 1000), primaryDisplayHeight: 1107
    )
    let pointerAfterClick = CGPoint(x: 960, y: 957)
    #expect(body.contains(pointerAfterClick))
    #expect(!body.contains(click.appKitPoint))
}

@Test("副屏点击使用主显示器坐标原点且保留负坐标")
func outsideClickCoordinatesOnSecondaryDisplays() {
    let left = IslandOutsideClickLocation(
        windowServerPoint: CGPoint(x: -500, y: 100), primaryDisplayHeight: 1107
    )
    #expect(left.appKitPoint == CGPoint(x: -500, y: 1007))
    let above = IslandOutsideClickLocation(
        windowServerPoint: CGPoint(x: 500, y: -300), primaryDisplayHeight: 1107
    )
    #expect(above.appKitPoint == CGPoint(x: 500, y: 1407))
}

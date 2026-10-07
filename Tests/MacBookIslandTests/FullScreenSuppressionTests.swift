import AppKit
import Testing
@testable import MacBookIsland

@Test("其他应用覆盖目标屏幕时抑制顶屿")
func fullScreenWindowSuppressesIsland() {
    #expect(IslandFullScreenSuppressionPolicy.shouldSuppress(
        frontmostIsTopIslet: false,
        hasCoveringWindow: true
    ))
}

@Test("没有覆盖窗口时不抑制，顶屿前台不能豁免全屏隐藏")
func nonFullScreenStateKeepsIslandEligible() {
    #expect(!IslandFullScreenSuppressionPolicy.shouldSuppress(
        frontmostIsTopIslet: false,
        hasCoveringWindow: false
    ))
    #expect(IslandFullScreenSuppressionPolicy.shouldSuppress(
        frontmostIsTopIslet: true,
        hasCoveringWindow: true
    ))
    #expect(!IslandFullScreenSuppressionPolicy.shouldSuppress(
        frontmostIsTopIslet: true,
        hasCoveringWindow: false
    ))
}

@Test("只有覆盖目标显示器的大窗口才算全屏候选")
func coveringWindowRequiresDisplaySizedBounds() {
    let display = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
    #expect(IslandFullScreenSuppressionPolicy.coversDisplay(
        windowFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
        displayFrame: display
    ))
    #expect(!IslandFullScreenSuppressionPolicy.coversDisplay(
        windowFrame: CGRect(x: 100, y: 100, width: 1_200, height: 800),
        displayFrame: display
    ))
    #expect(!IslandFullScreenSuppressionPolicy.coversDisplay(
        windowFrame: CGRect(x: 1_920, y: 0, width: 1_920, height: 1_080),
        displayFrame: display
    ))
    #expect(!IslandFullScreenSuppressionPolicy.coversDisplay(
        windowFrame: CGRect(x: 1_800, y: 0, width: 1_920, height: 1_080),
        displayFrame: display
    ))
}

@Test("全屏可以保留菜单栏，但必须覆盖普通放大窗口留下的 Dock 区域")
func playerCoverageDistinguishesPseudoFullscreen() {
    let displayFrame = CGRect(x: 0, y: 0, width: 1_710, height: 1_107)

    #expect(IslandFullScreenSuppressionPolicy.coversPlayerDisplay(
        windowFrame: CGRect(x: 0, y: 34, width: 1_710, height: 1_073),
        displayFrame: displayFrame,
        menuBarHeight: 34
    ))
    #expect(!IslandFullScreenSuppressionPolicy.coversPlayerDisplay(
        windowFrame: CGRect(x: 0, y: 34, width: 1_710, height: 991),
        displayFrame: displayFrame,
        menuBarHeight: 34
    ))
}

@Test("主屏与上下左右外接屏的 AppKit 坐标统一转换为 WindowServer 坐标")
func windowServerCoordinatesIncludeDisplayOffsets() {
    let frames = [
        (CGRect(x: 0, y: 0, width: 1_710, height: 1_107), CGRect(x: 0, y: 0, width: 1_710, height: 1_107)),
        (CGRect(x: 0, y: 1_107, width: 1_920, height: 1_080), CGRect(x: 0, y: -1_080, width: 1_920, height: 1_080)),
        (CGRect(x: -1_920, y: -200, width: 1_920, height: 1_080), CGRect(x: -1_920, y: 227, width: 1_920, height: 1_080))
    ]
    for (appKitFrame, expected) in frames {
        #expect(IslandFullScreenSuppressionPolicy.windowServerFrame(
            for: appKitFrame,
            primaryDisplayHeight: 1_107
        ) == expected)
    }
}

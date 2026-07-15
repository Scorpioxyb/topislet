import AppKit
import Testing
@testable import MacBookIsland

@Test("岛的三种窗口状态始终保持顶边和水平中心不变")
func islandWindowFramesStayTopAnchoredAndCentered() {
    let screenFrame = NSRect(x: 0, y: 0, width: 1_920, height: 1_080)
    let yOffset: CGFloat = 2
    let sizes = IslandMode.allTestModes.map {
        IslandWindowLayout.size(
            for: $0,
            collapsedWidth: 245,
            compactWidth: 377,
            expandedWidth: 460,
            expandedHeight: 189,
            topBandHeight: 33
        )
    }
    let frames = sizes.map {
        IslandWindowLayout.frame(for: $0, in: screenFrame, yOffset: yOffset)
    }

    #expect(frames.map(\.midX).allSatisfy { $0 == screenFrame.midX })
    #expect(frames.map(\.maxY).allSatisfy { $0 == screenFrame.maxY - yOffset })
    #expect(frames[0].height == 33)
    #expect(frames[1].height == 33)
    #expect(frames[2].height == 189)
}

@Test("连续反向切换窗口不会产生水平漂移")
func rapidIslandModeReversalNeverChangesCenter() {
    let screenFrame = NSRect(x: -1_440, y: 0, width: 1_440, height: 900)
    let sequence: [IslandMode] = [
        .collapsed, .compact, .expanded, .compact, .expanded, .collapsed
    ]
    let centers = sequence.map { mode in
        let size = IslandWindowLayout.size(
            for: mode,
            collapsedWidth: 245,
            compactWidth: 377,
            expandedWidth: 460,
            expandedHeight: 189,
            topBandHeight: 33
        )
        return IslandWindowLayout.frame(
            for: size,
            in: screenFrame,
            yOffset: 0
        ).midX
    }

    #expect(centers.allSatisfy { $0 == screenFrame.midX })
}

@Test("动画画布只扩展透明窗口，不会裁切可见岛形")
func animationCanvasContainsCurrentAndTargetGeometry() {
    let expansionCanvas = IslandWindowLayout.animationCanvasSize(
        current: NSSize(width: 377, height: 34),
        target: NSSize(width: 460, height: 190)
    )
    let collapseCanvas = IslandWindowLayout.animationCanvasSize(
        current: NSSize(width: 460, height: 190),
        target: NSSize(width: 377, height: 34)
    )
    let compactPromotionCanvas = IslandWindowLayout.animationCanvasSize(
        current: NSSize(width: 245, height: 34),
        target: NSSize(width: 377, height: 34)
    )

    #expect(expansionCanvas == NSSize(width: 460, height: 190))
    #expect(collapseCanvas == NSSize(width: 460, height: 190))
    #expect(compactPromotionCanvas == NSSize(width: 377, height: 34))
}

@Test("展开交互区域精确区分顶部主体和透明肩部")
func expandedInteractionRegionsExcludeTransparentShoulders() throws {
    let panelFrame = NSRect(x: 730, y: 889, width: 460, height: 189)
    let regions = IslandInteractionRegions.make(
        panelFrame: panelFrame,
        mode: .expanded,
        headerWidth: 253,
        topBandHeight: 33,
        expandedBodyHeight: 148,
        expandedPanelTopGap: 8
    )
    let body = try #require(regions.body)
    let bridge = try #require(regions.bridge)

    #expect(regions.header.midX == panelFrame.midX)
    #expect(regions.header.maxY == panelFrame.maxY)
    #expect(body.minY == panelFrame.minY)
    #expect(regions.header.minY - body.maxY == 8)
    #expect(bridge.width == regions.header.width)
    #expect(regions.contains(CGPoint(x: panelFrame.midX, y: panelFrame.maxY - 1)))
    #expect(regions.contains(CGPoint(x: panelFrame.midX, y: body.midY)))
    #expect(regions.contains(CGPoint(x: panelFrame.midX, y: bridge.midY)))
    #expect(!regions.contains(CGPoint(x: panelFrame.minX + 1, y: regions.header.midY)))
}

@Test("收起状态不会保留展开主体交互区")
func compactInteractionRegionsExposeOnlyHeader() {
    let compactFrame = NSRect(x: 771.5, y: 1_045, width: 377, height: 33)
    let regions = IslandInteractionRegions.make(
        panelFrame: compactFrame,
        mode: .compact,
        headerWidth: 377,
        topBandHeight: 33,
        expandedBodyHeight: 148,
        expandedPanelTopGap: 8
    )

    #expect(regions.body == nil)
    #expect(regions.bridge == nil)
    #expect(regions.header == compactFrame)
}

@Test("乱序动画完成不能覆盖最新窗口状态")
func onlyLatestAnimationCompletionOwnsFinalGeometry() {
    var gate = IslandAnimationCompletionGate()
    let firstAnimationID = gate.beginAnimation()
    let latestAnimationID = gate.beginAnimation()
    let staleCompletion = gate.claimCompletion(
        animationID: firstAnimationID,
        targetMode: .expanded,
        currentMode: .expanded
    )
    let wrongModeCompletion = gate.claimCompletion(
        animationID: latestAnimationID,
        targetMode: .compact,
        currentMode: .expanded
    )
    let acceptedCompletion = gate.claimCompletion(
        animationID: latestAnimationID,
        targetMode: .expanded,
        currentMode: .expanded
    )
    let duplicateCompletion = gate.claimCompletion(
        animationID: latestAnimationID,
        targetMode: .expanded,
        currentMode: .expanded
    )

    #expect(!staleCompletion)
    #expect(!wrongModeCompletion)
    #expect(acceptedCompletion)
    #expect(!duplicateCompletion)
}

private extension IslandMode {
    static let allTestModes: [IslandMode] = [.collapsed, .compact, .expanded]
}

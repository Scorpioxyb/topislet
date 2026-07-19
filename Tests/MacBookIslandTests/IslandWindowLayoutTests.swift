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

@Test("窗口插值全过程保持顶部和中心锚定")
func interpolatedWindowFramesStayTopAnchoredAndCentered() {
    let screenFrame = NSRect(x: 0, y: 0, width: 1_920, height: 1_080)
    let frames = (0...20).map { step in
        let progress = CGFloat(step) / 20
        let size = NSSize(
            width: 377 + (460 - 377) * progress,
            height: 34 + (190 - 34) * progress
        )
        return IslandWindowLayout.frame(
            for: size,
            in: screenFrame,
            yOffset: 2
        )
    }

    #expect(frames.map(\.midX).allSatisfy { $0 == screenFrame.midX })
    #expect(frames.map(\.maxY).allSatisfy { $0 == screenFrame.maxY - 2 })
    #expect(frames.map(\.width) == frames.map(\.width).sorted())
    #expect(frames.map(\.height) == frames.map(\.height).sorted())
}

@Test("MacBook 机型矩阵使用系统刘海宽度和高度")
func macBookDisplayMatrixUsesSystemCameraHousingGeometry() {
    let profiles = [
        MacBookDisplayProfile(name: "MacBook Air 13", width: 1_470, height: 956, topInset: 32, notchWidth: 180),
        MacBookDisplayProfile(name: "MacBook Air 15", width: 1_710, height: 1_107, topInset: 33, notchWidth: 185),
        MacBookDisplayProfile(name: "MacBook Pro 14", width: 1_512, height: 982, topInset: 32, notchWidth: 180),
        MacBookDisplayProfile(name: "MacBook Pro 16", width: 1_728, height: 1_117, topInset: 32, notchWidth: 180)
    ]

    for profile in profiles {
        let geometry = profile.geometry()
        #expect(geometry.hasCameraHousing, Comment(rawValue: profile.name))
        #expect(geometry.notchWidth == profile.notchWidth, Comment(rawValue: profile.name))
        #expect(geometry.topBandHeight == profile.topInset + 1, Comment(rawValue: profile.name))
        #expect(geometry.islandAnchorX == profile.frame.midX, Comment(rawValue: profile.name))

        let panelFrame = IslandWindowLayout.frame(
            for: NSSize(width: geometry.notchWidth + 192, height: geometry.topBandHeight),
            in: profile.frame,
            yOffset: 0,
            anchorX: geometry.islandAnchorX
        )
        #expect(panelFrame.midX == geometry.islandAnchorX, Comment(rawValue: profile.name))
        #expect(panelFrame.maxY == profile.frame.maxY, Comment(rawValue: profile.name))
    }
}

@Test("岛锚定真实摄像头区域中心而不是假定屏幕绝对中心")
func islandAnchorsToDetectedCameraHousingCenter() throws {
    let screenFrame = NSRect(x: -1_710, y: 120, width: 1_710, height: 1_107)
    let left = NSRect(x: -1_710, y: 1_194, width: 770, height: 33)
    let right = NSRect(x: -756, y: 1_194, width: 756, height: 33)
    let geometry = IslandDisplayGeometry.resolve(
        screenFrame: screenFrame,
        safeAreaTop: 33,
        auxiliaryTopLeftArea: left,
        auxiliaryTopRightArea: right,
        backingScaleFactor: 2,
        notchHeightAdjustment: 1
    )
    let cameraHousingFrame = try #require(geometry.cameraHousingFrame)
    let panelFrame = IslandWindowLayout.frame(
        for: NSSize(width: 376, height: geometry.topBandHeight),
        in: screenFrame,
        yOffset: 2,
        anchorX: geometry.islandAnchorX
    )

    #expect(cameraHousingFrame.width == 184)
    #expect(cameraHousingFrame.midX != screenFrame.midX)
    #expect(panelFrame.midX == cameraHousingFrame.midX)
    #expect(panelFrame.maxY == screenFrame.maxY - 2)
}

@Test("无刘海外接屏使用顶部居中胶囊而不伪造物理刘海")
func externalDisplayUsesSyntheticCenteredGeometry() {
    let screenFrame = NSRect(x: 1_710, y: 0, width: 2_560, height: 1_440)
    let geometry = IslandDisplayGeometry.resolve(
        screenFrame: screenFrame,
        safeAreaTop: 0,
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil,
        backingScaleFactor: 2,
        notchHeightAdjustment: 1
    )

    #expect(!geometry.hasCameraHousing)
    #expect(geometry.cameraHousingFrame == nil)
    #expect(geometry.notchWidth == IslandDisplayGeometry.syntheticNotchWidth)
    #expect(geometry.topBandHeight == 33)
    #expect(geometry.islandAnchorX == screenFrame.midX)
}

@Test("异常辅助区域不会被误判为摄像头刘海")
func malformedAuxiliaryAreasFallBackToSyntheticGeometry() {
    let screenFrame = NSRect(x: 0, y: 0, width: 1_710, height: 1_107)
    let geometry = IslandDisplayGeometry.resolve(
        screenFrame: screenFrame,
        safeAreaTop: 0,
        auxiliaryTopLeftArea: NSRect(x: 0, y: 900, width: 760, height: 33),
        auxiliaryTopRightArea: NSRect(x: 950, y: 900, width: 760, height: 33),
        backingScaleFactor: 2,
        notchHeightAdjustment: 1
    )

    #expect(!geometry.hasCameraHousing)
    #expect(geometry.islandAnchorX == screenFrame.midX)
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

private struct MacBookDisplayProfile {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let topInset: CGFloat
    let notchWidth: CGFloat

    var frame: NSRect {
        NSRect(x: 0, y: 0, width: width, height: height)
    }

    func geometry() -> IslandDisplayGeometry {
        let sideWidth = (width - notchWidth) / 2
        let topY = height - topInset
        return IslandDisplayGeometry.resolve(
            screenFrame: frame,
            safeAreaTop: topInset,
            auxiliaryTopLeftArea: NSRect(x: 0, y: topY, width: sideWidth, height: topInset),
            auxiliaryTopRightArea: NSRect(x: sideWidth + notchWidth, y: topY, width: sideWidth, height: topInset),
            backingScaleFactor: 2,
            notchHeightAdjustment: 1
        )
    }
}

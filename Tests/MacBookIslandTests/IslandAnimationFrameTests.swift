import Foundation
import Testing
@testable import MacBookIsland

@Test("AppKit窗口插值在提交前固定顶边和中心，避免半点高度取整漂移")
func fractionalAppKitFramesAreAnchoredBeforeSubmission() {
    let target = CGRect(x: 625, y: 917, width: 460, height: 191)
    for step in 0...1000 {
        let progress = Double(step) / 1000
        let proposed = CGRect(x: 666.5 - 41.5 * progress,
                              y: 1073 - 156 * progress,
                              width: 377 + 83 * progress,
                              height: 35 + 156 * progress)
        let frame = IslandAnimationFrame.anchored(proposed, to: target)
        #expect(frame.midX == 855)
        #expect(frame.maxY == 1108)
        #expect(frame.width == frame.width.rounded())
        #expect(frame.height == frame.height.rounded())
        #expect((377...460).contains(frame.width))
        #expect((35...191).contains(frame.height))
    }
}

@Test("展开紧凑折叠及外接屏目标帧不在正常完成时再次位移")
func integerEndpointsAndExternalScreenAnchorsArePreserved() {
    for target in [
        CGRect(x: 625, y: 917, width: 460, height: 191),
        CGRect(x: 666.5, y: 1073, width: 377, height: 35),
        CGRect(x: 732.5, y: 1073, width: 245, height: 35),
        CGRect(x: -1090, y: 709, width: 460, height: 191)
    ] {
        #expect(IslandAnimationFrame.anchored(target, to: target) == target)
        let fractional = CGRect(x: 123, y: 234, width: 388.6, height: 39.4)
        let frame = IslandAnimationFrame.anchored(fractional, to: target)
        #expect(frame.midX == target.midX)
        #expect(frame.maxY == target.maxY)
    }
}

@Test("收起插值宽度与目标同奇偶：原点始终是整点，胶囊不再左右抖半点")
func collapseFramesKeepTheTargetParity() {
    // Measured on device 2026-11-15: collapsing 660×192 → 229×35 at x 740,
    // odd and even widths alternated and the pill's left edge moved between
    // 740.0 and 740.5.
    let target = CGRect(x: 740, y: 1073, width: 229, height: 35)
    for proposedWidth in stride(from: 660.0, through: 229.0, by: -0.37) {
        let proposed = CGRect(x: 0, y: 0, width: proposedWidth, height: 100.4)
        let frame = IslandAnimationFrame.anchored(proposed, to: target)
        #expect(frame.minX == frame.minX.rounded())
        #expect(frame.midX == target.midX)
        #expect(frame.width >= 229 && frame.width <= 660)
        #expect(Int(frame.width) % 2 == 1)
    }
    // Widths stay between the proposal and the target, in both directions.
    #expect(IslandAnimationFrame.parityMatchedWidth(594, targetWidth: 229) == 593)
    #expect(IslandAnimationFrame.parityMatchedWidth(230, targetWidth: 229) == 229)
    #expect(IslandAnimationFrame.parityMatchedWidth(229.4, targetWidth: 660) == 230)
    #expect(IslandAnimationFrame.parityMatchedWidth(659, targetWidth: 660) == 660)
}

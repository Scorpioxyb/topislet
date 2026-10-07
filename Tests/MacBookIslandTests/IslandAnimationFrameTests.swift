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

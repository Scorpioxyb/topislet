import AppKit
import QuartzCore
import Testing
@testable import MacBookIsland

@Test("岛窗口使用当前媒体时钟配置frame动画，清理不删除其他动画")
@MainActor
func islandWindowFrameAnimationOwnsOnlyFrameKey() {
    let panel = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 32),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let opacity = CABasicAnimation(keyPath: "alphaValue")
    panel.animations["alphaValue"] = opacity
    IslandWindowFrameAnimation.install(on: panel, duration: 0.24,
                                       controlPoints: (0.2, 0.85, 0.25, 1), startTime: 42)
    let animation = panel.animation(forKey: "frame") as? CABasicAnimation
    #expect(animation?.duration == 0.24)
    #expect(animation?.beginTime == 42)
    #expect(animation?.keyPath == "frame")
    IslandWindowFrameAnimation.remove(from: panel)
    #expect(panel.animations["frame"] == nil)
    #expect(panel.animations["alphaValue"] != nil)
    #expect(!panel.isVisible)
}

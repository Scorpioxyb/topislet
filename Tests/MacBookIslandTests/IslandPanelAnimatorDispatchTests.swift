import AppKit
import Testing
@testable import MacBookIsland

@Test("AppKit动画代理必须转发到真实岛窗口后才能读取锚定状态")
@MainActor
func islandPanelAnimatorUsesRealWindowStorage() {
    let panel = IslandPanel(
        contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 32),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
    )
    let target = NSRect(x: -10120, y: -10148, width: 440, height: 180)
    panel.frameAnimationTarget = target
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        panel.animator().setFrame(target, display: false)
    }
    #expect(panel.frame == target)
    #expect(!panel.isVisible)
    panel.frameAnimationTarget = nil
}

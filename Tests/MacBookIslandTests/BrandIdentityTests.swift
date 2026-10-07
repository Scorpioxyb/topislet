import AppKit
import Testing
@testable import MacBookIsland

@Test("顶屿菜单栏使用无底板的墨镜轮廓模板图")
@MainActor
func menuBarBrandUsesSystemTintAndCompactDimensions() {
    let image = BrandIdentity.menuBarImage()
    #expect(image.isTemplate)
    #expect(image.size == NSSize(width: 20, height: 8))
    #expect(image.accessibilityDescription == "顶屿")
}

@Test("品牌轮廓保留开放鼻梁切口而不是胶囊或闭合空心环")
@MainActor
func brandVisorHasAnOpenBridgeNotch() {
    let path = BrandIdentity.visorPath()
    #expect(path.contains(NSPoint(x: 10, y: 5)))
    #expect(path.contains(NSPoint(x: 4, y: 2)))
    #expect(!path.contains(NSPoint(x: 10, y: 1)))
    #expect(!path.contains(NSPoint(x: -1, y: 4)))
}

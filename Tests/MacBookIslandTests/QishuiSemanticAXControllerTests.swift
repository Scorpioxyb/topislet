import Testing
@testable import MacBookIsland

@Test("汽水 Chromium 手动辅助功能开启成功后允许扫描")
func manualAccessibilitySuccessAllowsScanning() {
    #expect(QishuiSemanticAXController.canProceedAfterManualAccessibility(
        setResult: .success,
        isEnabled: true
    ))
}

@Test("属性已开启时容忍重复设置返回非成功")
func existingManualAccessibilityAllowsScanning() {
    #expect(QishuiSemanticAXController.canProceedAfterManualAccessibility(
        setResult: .notImplemented,
        isEnabled: true
    ))
    #expect(!QishuiSemanticAXController.canProceedAfterManualAccessibility(
        setResult: .notImplemented,
        isEnabled: false
    ))
}

@Test("正常可见主窗口底部播放器栏满足安全门禁")
func visibleMainBottomPlayerIsEligible() {
    let facts = QishuiSemanticAXController.CandidateFacts(
        windowIsNormal: true,
        windowIsMainOrFocused: true,
        windowIsVisible: true,
        windowIsMinimized: false,
        containerIsVisible: true,
        controlsAreEnabled: true,
        controlsAreInsideWindow: true,
        relativeY: 0.939,
        hasPlaybackTimeContext: true
    )

    #expect(QishuiSemanticAXController.isEligibleCandidate(facts))
}

@Test("隐藏最小化和非底部重复组不能参与唯一性竞争")
func hiddenOrOffPlayerCandidatesAreRejected() {
    func facts(
        visible: Bool = true,
        minimized: Bool = false,
        relativeY: Double = 0.939
    ) -> QishuiSemanticAXController.CandidateFacts {
        .init(
            windowIsNormal: true,
            windowIsMainOrFocused: true,
            windowIsVisible: visible,
            windowIsMinimized: minimized,
            containerIsVisible: true,
            controlsAreEnabled: true,
            controlsAreInsideWindow: true,
            relativeY: relativeY,
            hasPlaybackTimeContext: true
        )
    }

    #expect(!QishuiSemanticAXController.isEligibleCandidate(
        facts(visible: false)
    ))
    #expect(!QishuiSemanticAXController.isEligibleCandidate(
        facts(minimized: true)
    ))
    #expect(!QishuiSemanticAXController.isEligibleCandidate(
        facts(relativeY: 0.42)
    ))
}

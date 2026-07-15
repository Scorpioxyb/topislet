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

@Test("汽水 AX 不完整树允许两次有界重试")
func sparseAXDiscoveryUsesBoundedRetries() {
    #expect(QishuiSemanticAXController.shouldRetrySparseDiscovery(
        scannedNodeCount: 2,
        candidateCount: 0,
        attempt: 0
    ))
    #expect(QishuiSemanticAXController.shouldRetrySparseDiscovery(
        scannedNodeCount: 189,
        candidateCount: 0,
        attempt: 1
    ))
    #expect(!QishuiSemanticAXController.shouldRetrySparseDiscovery(
        scannedNodeCount: 2,
        candidateCount: 0,
        attempt: 2
    ))
    #expect(!QishuiSemanticAXController.shouldRetrySparseDiscovery(
        scannedNodeCount: 257,
        candidateCount: 0,
        attempt: 0
    ))
    #expect(!QishuiSemanticAXController.shouldRetrySparseDiscovery(
        scannedNodeCount: 2,
        candidateCount: 1,
        attempt: 0
    ))
}

@Test("正常可见主窗口底部播放器栏满足安全门禁")
func visibleMainBottomPlayerIsEligible() {
    let facts = QishuiSemanticAXController.CandidateFacts(
        windowIsNormal: true,
        windowIsPrimary: true,
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
            windowIsPrimary: true,
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

@Test("唯一最小化标准窗口允许后台临时恢复")
func onlyUniqueMinimizedWindowCanBeTemporarilyRestored() {
    #expect(QishuiSemanticAXController.shouldTemporarilyUnminimize(
        standardWindowCount: 1,
        isMinimized: true
    ))
    #expect(!QishuiSemanticAXController.shouldTemporarilyUnminimize(
        standardWindowCount: 2,
        isMinimized: true
    ))
    #expect(!QishuiSemanticAXController.shouldTemporarilyUnminimize(
        standardWindowCount: 1,
        isMinimized: false
    ))
}

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

@Test("已验证的唯一最小化窗口控件可复用健康状态")
func cachedMinimizedControlsRemainHealthy() {
    let minimized = QishuiSemanticAXController.CandidateFacts(
        windowIsNormal: true,
        windowIsPrimary: true,
        windowIsVisible: false,
        windowIsMinimized: true,
        containerIsVisible: false,
        controlsAreEnabled: true,
        controlsAreInsideWindow: true,
        relativeY: 0.9,
        hasPlaybackTimeContext: true
    )
    #expect(!QishuiSemanticAXController.isEligibleCandidate(minimized))
    #expect(QishuiSemanticAXController.isEligibleHealthCandidate(minimized))

    let duplicateWindow = QishuiSemanticAXController.CandidateFacts(
        windowIsNormal: true,
        windowIsPrimary: false,
        windowIsVisible: false,
        windowIsMinimized: true,
        containerIsVisible: false,
        controlsAreEnabled: true,
        controlsAreInsideWindow: true,
        relativeY: 0.9,
        hasPlaybackTimeContext: true
    )
    #expect(!QishuiSemanticAXController.isEligibleHealthCandidate(duplicateWindow))
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
        standardWindowCount: 0,
        isMinimized: false
    ))
    #expect(!QishuiSemanticAXController.shouldTemporarilyUnminimize(
        standardWindowCount: 1,
        isMinimized: false
    ))
}

@Test("汽水窗口状态区分关闭、异常控件树和读取失败")
func qishuiWindowAvailabilityUsesDefiniteWindowEvidence() {
    #expect(QishuiSemanticAXController.resolveWindowAvailability(
        isRunning: false,
        accessibilityTrusted: true,
        windowReadSucceeded: true,
        reportedWindowCount: 1,
        standardWindowCount: 1
    ) == .notRunning)
    #expect(QishuiSemanticAXController.resolveWindowAvailability(
        isRunning: true,
        accessibilityTrusted: false,
        windowReadSucceeded: true,
        reportedWindowCount: 1,
        standardWindowCount: 1
    ) == .accessibilityRequired)
    #expect(QishuiSemanticAXController.resolveWindowAvailability(
        isRunning: true,
        accessibilityTrusted: true,
        windowReadSucceeded: false,
        reportedWindowCount: 0,
        standardWindowCount: 0
    ) == .unknown)
    #expect(QishuiSemanticAXController.resolveWindowAvailability(
        isRunning: true,
        accessibilityTrusted: true,
        windowReadSucceeded: true,
        reportedWindowCount: 0,
        standardWindowCount: 0
    ) == .windowClosed)
    #expect(QishuiSemanticAXController.resolveWindowAvailability(
        isRunning: true,
        accessibilityTrusted: true,
        windowReadSucceeded: true,
        reportedWindowCount: 1,
        standardWindowCount: 1
    ) == .available)
    #expect(QishuiSemanticAXController.resolveWindowAvailability(
        isRunning: true,
        accessibilityTrusted: true,
        windowReadSucceeded: true,
        reportedWindowCount: 1,
        standardWindowCount: 0
    ) == .controlTreeUnavailable)
}

@Test("只有唯一语义播放控件组允许发送控制")
func qishuiControlAvailabilityRequiresUniqueSemanticCandidate() {
    #expect(QishuiSemanticAXController.resolveSemanticControlAvailability(
        windowAvailability: .available,
        candidateCount: 1
    ) == .available)
    #expect(QishuiSemanticAXController.resolveSemanticControlAvailability(
        windowAvailability: .available,
        candidateCount: 0
    ) == .controlTreeUnavailable)
    #expect(QishuiSemanticAXController.resolveSemanticControlAvailability(
        windowAvailability: .available,
        candidateCount: 2
    ) == .controlTreeUnavailable)
    #expect(QishuiSemanticAXController.resolveSemanticControlAvailability(
        windowAvailability: .controlTreeUnavailable,
        candidateCount: 1
    ) == .available)
    #expect(QishuiSemanticAXController.resolveSemanticControlAvailability(
        windowAvailability: .available,
        candidateCount: nil
    ) == .unknown)
    #expect(QishuiSemanticAXController.resolveSemanticControlAvailability(
        windowAvailability: .windowClosed,
        candidateCount: 1
    ) == .windowClosed)

    #expect(QishuiControlAvailability.available.allowsControl)
    #expect(!QishuiControlAvailability.unknown.allowsControl)
    #expect(!QishuiControlAvailability.controlTreeUnavailable.allowsControl)
    #expect(!QishuiControlAvailability.windowClosed.allowsControl)
}

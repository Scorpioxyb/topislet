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

@Test("唯一最小化窗口控件可直接使用且无需恢复窗口")
func minimizedControlsRemainEligibleWithoutWindowMutation() {
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

@Test("已验证汽水控件跳过重复预检，其他状态仍需重新确认")
func qishuiControlPreflightReusesOnlyVerifiedAvailability() {
    #expect(!QishuiControlAvailability.available.requiresPreflightBeforeControl)
    #expect(QishuiControlAvailability.windowClosed.requiresPreflightBeforeControl)
    #expect(QishuiControlAvailability.controlTreeUnavailable.requiresPreflightBeforeControl)
    #expect(QishuiControlAvailability.accessibilityRequired.requiresPreflightBeforeControl)
    #expect(QishuiControlAvailability.notRunning.requiresPreflightBeforeControl)
    #expect(QishuiControlAvailability.unknown.requiresPreflightBeforeControl)
}

@Test("只有已验证汽水控件在切歌后允许事件驱动预热")
func qishuiControlPrewarmRequiresVerifiedAvailability() {
    #expect(QishuiControlAvailability.available.allowsCachePrewarmAfterTrackChange)
    #expect(!QishuiControlAvailability.windowClosed.allowsCachePrewarmAfterTrackChange)
    #expect(!QishuiControlAvailability.controlTreeUnavailable.allowsCachePrewarmAfterTrackChange)
    #expect(!QishuiControlAvailability.accessibilityRequired.allowsCachePrewarmAfterTrackChange)
    #expect(!QishuiControlAvailability.notRunning.allowsCachePrewarmAfterTrackChange)
    #expect(!QishuiControlAvailability.unknown.allowsCachePrewarmAfterTrackChange)
}

@Test("汽水进程定位优先使用已验证的 MediaRemote PID")
func qishuiProcessSelectionPrefersVerifiedMediaRemotePID() {
    #expect(QishuiProcessSelectionPolicy.preferredProcessIdentifier(
        verifiedMediaRemoteProcessIdentifier: 222,
        directSnapshotProcessIdentifier: 111,
        runningProcessIdentifiers: [111, 222]
    ) == 222)
    #expect(QishuiProcessSelectionPolicy.preferredProcessIdentifier(
        verifiedMediaRemoteProcessIdentifier: 999,
        directSnapshotProcessIdentifier: 111,
        runningProcessIdentifiers: [111, 222]
    ) == 111)
    #expect(QishuiProcessSelectionPolicy.preferredProcessIdentifier(
        verifiedMediaRemoteProcessIdentifier: nil,
        directSnapshotProcessIdentifier: nil,
        runningProcessIdentifiers: [111, 222]
    ) == nil)
    #expect(QishuiProcessSelectionPolicy.preferredProcessIdentifier(
        verifiedMediaRemoteProcessIdentifier: nil,
        directSnapshotProcessIdentifier: nil,
        runningProcessIdentifiers: [222]
    ) == 222)
}

import Testing
@testable import MacBookIsland
import Foundation

@Test("恢复探测只接受当前进程和当前任务的完成结果")
func recoveryProbeRejectsResultsAfterRestartResetOrCancellation() {
    #expect(MusicControlRecoveryPolicy.acceptsVerification(
        requestedGeneration: 7, currentGeneration: 7,
        requestedProcess: 100, currentProcess: 100, isCancelled: false
    ))
    #expect(!MusicControlRecoveryPolicy.acceptsVerification(
        requestedGeneration: 7, currentGeneration: 8,
        requestedProcess: 100, currentProcess: 100, isCancelled: false
    ))
    #expect(!MusicControlRecoveryPolicy.acceptsVerification(
        requestedGeneration: 7, currentGeneration: 7,
        requestedProcess: 100, currentProcess: 101, isCancelled: false
    ))
    #expect(!MusicControlRecoveryPolicy.acceptsVerification(
        requestedGeneration: 7, currentGeneration: 7,
        requestedProcess: 100, currentProcess: nil, isCancelled: false
    ))
    #expect(!MusicControlRecoveryPolicy.acceptsVerification(
        requestedGeneration: 7, currentGeneration: 7,
        requestedProcess: 100, currentProcess: 100, isCancelled: true
    ))
}

@Test("已可用控件仍定期检查健康，避免窗口关闭事件丢失后永久保留旧状态")
func readyQishuiControlsRequireBoundedHealthChecks() {
    let now = Date(timeIntervalSince1970: 100)
    #expect(MusicControlRecoveryPolicy.needsHealthCheck(lastCheck: nil, now: now))
    #expect(!MusicControlRecoveryPolicy.needsHealthCheck(lastCheck: now, now: now.addingTimeInterval(1.9)))
    #expect(MusicControlRecoveryPolicy.needsHealthCheck(lastCheck: now, now: now.addingTimeInterval(2)))
}

@Test("重启期间即使来源暂时消失也持续显示连接反馈")
func activeRecoveryRemainsVisibleDuringRestartGap() {
    #expect(MusicControlRecoveryPolicy.shouldPresentRecovery(
        isRecovering: true, hasRecoveryAction: false
    ))
    #expect(MusicControlRecoveryPolicy.shouldPresentRecovery(
        isRecovering: true, hasRecoveryAction: true
    ))
    #expect(MusicControlRecoveryPolicy.shouldPresentRecovery(
        isRecovering: false, hasRecoveryAction: true
    ))
    #expect(!MusicControlRecoveryPolicy.shouldPresentRecovery(
        isRecovering: false, hasRecoveryAction: false
    ))
}

@Test("重启间隙、权限失效和未发现控件都不能判定汽水恢复成功")
func qishuiRecoveryRequiresVerifiedControls() {
    for availability: QishuiControlAvailability in [
        .notRunning, .accessibilityRequired, .unknown,
        .windowClosed, .controlTreeUnavailable
    ] {
        #expect(!MusicControlRecoveryPolicy.hasVerifiedQishuiControls(availability))
    }
    #expect(MusicControlRecoveryPolicy.hasVerifiedQishuiControls(.available))
}

@Test("恢复跨越进程消失与来源切换，直到重启后验证成功才结束")
func activeQishuiRecoverySurvivesMissingUIAction() {
    for availability: QishuiControlAvailability in [
        .notRunning, .accessibilityRequired, .unknown,
        .windowClosed, .controlTreeUnavailable
    ] {
        for hasAction in [false, true] {
            #expect(MusicControlRecoveryPolicy.refreshDisposition(
                isRecovering: true, awaitingVerification: true,
                qishuiAvailability: availability, hasRecoveryAction: hasAction
            ) == .keepWaiting)
        }
    }
    #expect(MusicControlRecoveryPolicy.refreshDisposition(
        isRecovering: true, awaitingVerification: false,
        qishuiAvailability: .available, hasRecoveryAction: false
    ) == .keepWaiting)
    #expect(MusicControlRecoveryPolicy.refreshDisposition(
        isRecovering: true, awaitingVerification: true,
        qishuiAvailability: .available, hasRecoveryAction: true
    ) == .verified)
}

@Test("未请求重启时刷新只清理过期反馈，不声称恢复成功")
func passiveQishuiRefreshDoesNotClaimRecovery() {
    #expect(MusicControlRecoveryPolicy.refreshDisposition(
        isRecovering: false, awaitingVerification: false,
        qishuiAvailability: .available, hasRecoveryAction: false
    ) == .clearInactiveFeedback)
    #expect(MusicControlRecoveryPolicy.refreshDisposition(
        isRecovering: false, awaitingVerification: false,
        qishuiAvailability: .windowClosed, hasRecoveryAction: true
    ) == .unchanged)
}

@Test("辅助功能失效时汽水和网易云控制按钮提供恢复入口")
func accessibilityControlledMusicSourcesOfferPermissionRecovery() {
    #expect(MusicControlPermissionRecoveryPolicy.allowsRecovery(
        sourceBundleIdentifier: "com.soda.music",
        accessibilityTrusted: false
    ))
    #expect(MusicControlPermissionRecoveryPolicy.allowsRecovery(
        sourceBundleIdentifier: "com.netease.163music",
        accessibilityTrusted: false
    ))
}

@Test("已授权或非 AX 音乐来源不提供辅助功能恢复入口")
func unrelatedMusicSourcesDoNotOfferPermissionRecovery() {
    #expect(!MusicControlPermissionRecoveryPolicy.allowsRecovery(
        sourceBundleIdentifier: "com.soda.music",
        accessibilityTrusted: true
    ))
    #expect(!MusicControlPermissionRecoveryPolicy.allowsRecovery(
        sourceBundleIdentifier: "com.apple.Music",
        accessibilityTrusted: false
    ))
    #expect(!MusicControlPermissionRecoveryPolicy.allowsRecovery(
        sourceBundleIdentifier: nil,
        accessibilityTrusted: false
    ))
}

@Test("汽水窗口关闭时提供窗口恢复动作")
func closedQishuiWindowOffersWindowRecovery() {
    #expect(MusicControlRecoveryPolicy.action(
        sourceBundleIdentifier: "com.soda.music",
        qishuiAvailability: .windowClosed
    ) == .reopenQishuiWindow)
}

@Test("汽水控件树退化或读取异常时也提供恢复动作")
func degradedQishuiControlTreeOffersRecovery() {
    #expect(MusicControlRecoveryPolicy.action(
        sourceBundleIdentifier: "com.soda.music",
        qishuiAvailability: .controlTreeUnavailable
    ) == .reopenQishuiWindow)
    #expect(MusicControlRecoveryPolicy.action(
        sourceBundleIdentifier: "com.soda.music",
        qishuiAvailability: .unknown
    ) == .reopenQishuiWindow)
}

@Test("权限问题和非汽水来源不触发窗口恢复")
func unrelatedControlFailuresDoNotOfferWindowRecovery() {
    #expect(MusicControlRecoveryPolicy.action(
        sourceBundleIdentifier: "com.soda.music",
        qishuiAvailability: .accessibilityRequired
    ) == nil)
    #expect(MusicControlRecoveryPolicy.action(
        sourceBundleIdentifier: "com.apple.Music",
        qishuiAvailability: .windowClosed
    ) == nil)
}

@Test("只有用户明确操作才能打开汽水音乐")
func qishuiWindowRecoveryRequiresUserIntent() {
    #expect(MusicControlRecoveryPolicy.shouldOpenApplication(for: .userInitiated))
    #expect(!MusicControlRecoveryPolicy.shouldOpenApplication(for: .backgroundStatusRefresh))
}

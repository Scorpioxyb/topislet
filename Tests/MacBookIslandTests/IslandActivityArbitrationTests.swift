import Testing
@testable import MacBookIsland

@Test("音乐到达不能抢走已展开活动中心或尚未结束的操作")
func musicArrivalRespectsPresentationOwnership() {
    for mode in [IslandMode.collapsed, .compact, .expanded] {
        for blocked in [false, true] {
            #expect(IslandActivityArbitrationPolicy.shouldMusicTakeOver(
                activeFeature: .activityCenter,
                currentMode: mode,
                becameAvailable: true,
                timerIsRunning: false,
                hasPendingNotification: false,
                isInteractionBlocked: blocked
            ) == (mode != .expanded && !blocked))
        }
    }
    for feature in [IslandFeature.music, .timer, .notification] {
        #expect(!IslandActivityArbitrationPolicy.shouldMusicTakeOver(
            activeFeature: feature, currentMode: .collapsed,
            becameAvailable: true, timerIsRunning: false,
            hasPendingNotification: false, isInteractionBlocked: false
        ))
    }
}

@Test("自动与显式提醒均不能覆盖尚未结束的播放控制")
func notificationsWaitForPendingInteraction() {
    for mode in [IslandMode.collapsed, .compact, .expanded] {
        for urgent in [false, true] {
            for explicit in [false, true] {
                for blocked in [false, true] {
                    #expect(IslandActivityArbitrationPolicy.shouldPresentNotification(
                        isUrgent: urgent, currentMode: mode,
                        isInteractionBlocked: blocked, explicitlyRequested: explicit
                    ) == (!blocked && (explicit || urgent || mode != .expanded)))
                }
            }
        }
    }
}

@Test("提醒结束后恢复用户展开的活动中心而不是新出现的音乐")
func notificationRestoresUserActivityCenter() {
    #expect(IslandActivityArbitrationPolicy.featureAfterNotification(
        returnFeature: .activityCenter, returnMode: .expanded,
        timerIsRunning: false, hasCurrentMusicTrack: true
    ) == .activityCenter)
    #expect(IslandActivityArbitrationPolicy.featureAfterNotification(
        returnFeature: .activityCenter, returnMode: .collapsed,
        timerIsRunning: false, hasCurrentMusicTrack: true
    ) == .music)
}

@Test("接管提醒再恢复时保持计时器优先与音乐退出回退")
func activityRoundTripUsesLiveSources() {
    #expect(IslandActivityArbitrationPolicy.shouldPresentNotification(
        isUrgent: true, currentMode: .compact,
        isInteractionBlocked: false, explicitlyRequested: false
    ))
    #expect(IslandActivityArbitrationPolicy.featureAfterNotification(
        returnFeature: .timer, returnMode: .compact,
        timerIsRunning: true, hasCurrentMusicTrack: true
    ) == .timer)
    #expect(IslandActivityArbitrationPolicy.featureAfterNotification(
        returnFeature: .timer, returnMode: .compact,
        timerIsRunning: false, hasCurrentMusicTrack: true
    ) == .music)
    #expect(IslandActivityArbitrationPolicy.featureAfterNotification(
        returnFeature: .music, returnMode: .expanded,
        timerIsRunning: false, hasCurrentMusicTrack: false
    ) == .activityCenter)
}

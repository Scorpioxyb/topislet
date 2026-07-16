import Foundation
import Testing
@testable import MacBookIsland

@Test("Apple Music 时间线关联控制、通知、快照和 UI 发布")
@MainActor
func appleMusicTransitionTimelineCorrelatesNativeStages() throws {
    var uptime: TimeInterval = 100
    let timeline = AppleMusicTransitionTimeline(
        wallClock: { Date(timeIntervalSince1970: 1_000) },
        uptime: { uptime }
    )

    let controlTrace = timeline.beginControl(
        command: "下一首",
        baseline: "Old Song - Artist"
    )
    let staleNotificationTrace = timeline.notePlayerInfo(
        candidateSignature: "Old Song",
        detail: "track=Old Song stale-notification",
        observedUptime: 99.9
    )
    uptime += 0.08
    let playerInfoTrace = timeline.notePlayerInfo(
        candidateSignature: "New Song",
        detail: "track=New Song artist=Artist"
    )
    uptime += 0.12
    timeline.record(
        .metadataReadCompleted,
        detail: "result=success track=New Song artworkBytes=0"
    )
    timeline.notePlayerInfo(
        candidateSignature: "New Song",
        detail: "track=New Song delayed-handler",
        observedUptime: 100.15
    )
    uptime += 0.04
    timeline.record(
        .uiPublished,
        detail: "track=New Song artworkBytes=0"
    )

    let report = timeline.report()
    #expect(controlTrace == playerInfoTrace)
    #expect(controlTrace == staleNotificationTrace)
    #expect(!report.contains("stale-notification"))
    #expect(report.contains("+0ms control-issued"))
    #expect(report.contains("+80ms player-info-received"))
    #expect(report.contains("+200ms metadata-read-completed"))
    #expect(report.contains("+240ms ui-published"))
    let delayedNotification = try #require(
        report.range(of: "+150ms player-info-received")
    )
    let metadataCompletion = try #require(
        report.range(of: "+200ms metadata-read-completed")
    )
    #expect(delayedNotification.lowerBound < metadataCompletion.lowerBound)
}

@Test("Apple Music 时间线对不同外部曲目建立新跟踪并限制容量")
@MainActor
func appleMusicTransitionTimelineSeparatesTracksAndBoundsHistory() {
    var uptime: TimeInterval = 10
    let timeline = AppleMusicTransitionTimeline(
        maximumTraceCount: 2,
        wallClock: { Date(timeIntervalSince1970: 2_000) },
        uptime: { uptime }
    )

    let first = timeline.notePlayerInfo(
        candidateSignature: "Track A",
        detail: "track=A"
    )
    uptime += 0.1
    let second = timeline.notePlayerInfo(
        candidateSignature: "Track B",
        detail: "track=B"
    )
    uptime += 0.1
    let third = timeline.notePlayerInfo(
        candidateSignature: "Track C",
        detail: "track=C"
    )

    let report = timeline.report()
    #expect(first != second)
    #expect(second != third)
    #expect(!report.contains("trace=\(first) "))
    #expect(report.contains("trace=\(second) "))
    #expect(report.contains("trace=\(third) "))
    #expect(!timeline.latestReport().contains("trace=\(second) "))
    #expect(timeline.latestReport().contains("trace=\(third) "))
}

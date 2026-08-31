import Foundation
@testable import MacBookIsland
import Testing

@Test("日常诊断心跳每十五分钟最多记录一次")
func musicUsageHeartbeatUsesFifteenMinuteBoundary() {
    let start = Date(timeIntervalSince1970: 10_000)
    #expect(!MusicUsageHeartbeatPolicy.shouldRecord(
        lastRecordedAt: start,
        now: start.addingTimeInterval(899)
    ))
    #expect(MusicUsageHeartbeatPolicy.shouldRecord(
        lastRecordedAt: start,
        now: start.addingTimeInterval(900)
    ))
    #expect(MusicUsageHeartbeatPolicy.shouldRecord(
        lastRecordedAt: nil,
        now: start
    ))
}

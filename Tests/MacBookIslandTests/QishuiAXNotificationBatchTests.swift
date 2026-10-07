import Testing
@testable import MacBookIsland

@Test("窗口销毁后歌词数值通知不能覆盖结构重查")
func qishuiWindowCloseSurvivesValueNotifications() {
    var batch = QishuiAXNotificationBatch()
    batch.append("AXUIElementDestroyed")
    batch.append("AXValueChanged")
    batch.append("AXTitleChanged")
    #expect(batch.drain() == "AXUIElementDestroyed")
    #expect(batch.drain() == nil)
}

@Test("窗口重建与最小化通知在同一批次保留结构语义")
func qishuiWindowStructureSurvivesOrdinaryNotifications() {
    for notification in QishuiAXNotificationBatch.structuralNotifications {
        var batch = QishuiAXNotificationBatch()
        batch.append("AXValueChanged")
        batch.append(notification)
        batch.append("AXLayoutChanged")
        #expect(batch.drain() == notification)
    }
}

@Test("批次排空不把旧结构通知带入后续普通更新")
func qishuiNotificationBatchResetsAfterDelivery() {
    var batch = QishuiAXNotificationBatch()
    batch.append("AXWindowCreated")
    #expect(batch.drain() == "AXWindowCreated")
    batch.append("AXValueChanged")
    #expect(batch.drain() == "AXValueChanged")
}

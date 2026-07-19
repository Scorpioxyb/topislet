import CoreGraphics
import Testing
@testable import MacBookIsland

@Test("高频指针事件只安排一次投递并保留最新位置")
func pointerEventsCoalesceToLatestPosition() {
    var coalescer = LatestEventCoalescer<CGPoint>()

    let firstScheduled = coalescer.submit(CGPoint(x: 10, y: 20))
    let secondScheduled = coalescer.submit(CGPoint(x: 30, y: 40))
    let thirdScheduled = coalescer.submit(CGPoint(x: 50, y: 60))
    #expect(firstScheduled)
    #expect(!secondScheduled)
    #expect(!thirdScheduled)
    #expect(coalescer.isDeliveryScheduled)
    #expect(coalescer.pendingValue == CGPoint(x: 50, y: 60))

    let delivered = coalescer.consume()
    #expect(delivered == CGPoint(x: 50, y: 60))
    #expect(!coalescer.isDeliveryScheduled)
    #expect(coalescer.pendingValue == nil)
}

@Test("上一批投递完成后新事件可以立即安排下一批")
func pointerEventCoalescerReschedulesAfterDelivery() {
    var coalescer = LatestEventCoalescer<CGPoint>()

    let firstScheduled = coalescer.submit(.zero)
    let firstDelivered = coalescer.consume()
    let secondScheduled = coalescer.submit(CGPoint(x: 1, y: 1))
    #expect(firstScheduled)
    #expect(firstDelivered == .zero)
    #expect(secondScheduled)
}

@Test("取消合并事件会清除待投递状态")
func pointerEventCoalescerCancellationClearsPendingState() {
    var coalescer = LatestEventCoalescer<CGPoint>()

    let firstScheduled = coalescer.submit(CGPoint(x: 5, y: 5))
    #expect(firstScheduled)
    coalescer.cancel()

    #expect(!coalescer.isDeliveryScheduled)
    #expect(coalescer.pendingValue == nil)
    let scheduledAfterCancellation = coalescer.submit(CGPoint(x: 6, y: 6))
    #expect(scheduledAfterCancellation)
}

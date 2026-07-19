import Foundation

struct LatestEventCoalescer<Value> {
    private(set) var pendingValue: Value?
    private(set) var isDeliveryScheduled = false

    mutating func submit(_ value: Value) -> Bool {
        pendingValue = value
        guard !isDeliveryScheduled else { return false }
        isDeliveryScheduled = true
        return true
    }

    mutating func consume() -> Value? {
        let value = pendingValue
        pendingValue = nil
        isDeliveryScheduled = false
        return value
    }

    mutating func cancel() {
        pendingValue = nil
        isDeliveryScheduled = false
    }
}

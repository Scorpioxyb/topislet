import EventKit
import Foundation

enum EventKitAccessState: String, Equatable {
    case notDetermined
    case fullAccess
    case denied
    case restricted
    case writeOnly

    var canRead: Bool {
        self == .fullAccess
    }

    var displayName: String {
        switch self {
        case .notDetermined:
            return "未请求"
        case .fullAccess:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "受系统限制"
        case .writeOnly:
            return "仅写入，无法读取"
        }
    }

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .authorized, .fullAccess:
            self = .fullAccess
        case .writeOnly:
            self = .writeOnly
        @unknown default:
            self = .denied
        }
    }
}

struct EventKitActivityStatus: Equatable {
    var calendarAccess: EventKitAccessState
    var remindersAccess: EventKitAccessState
    var lastRefreshAt: Date?
    var detail: String

    static var current: EventKitActivityStatus {
        EventKitActivityStatus(
            calendarAccess: EventKitAccessState(EKEventStore.authorizationStatus(for: .event)),
            remindersAccess: EventKitAccessState(EKEventStore.authorizationStatus(for: .reminder)),
            lastRefreshAt: nil,
            detail: "日历和提醒事项尚未启用。"
        )
    }
}

struct EventKitIslandEvent: Equatable {
    let identifier: String
    let title: String
    let body: String
    let source: String
    let sourceBundleIdentifier: String
}

private struct EventKitCalendarRecord: Sendable {
    let identifier: String
    let title: String
    let startDate: Date
    let location: String?
}

private struct EventKitReminderRecord: Sendable {
    let identifier: String
    let title: String
    let dueDate: Date
}

@MainActor
final class EventKitActivitySource {
    typealias EventHandler = @MainActor (EventKitIslandEvent) -> Void
    typealias CancellationHandler = @MainActor (String) -> Void
    typealias StatusHandler = @MainActor (EventKitActivityStatus) -> Void

    private enum DefaultsKey {
        static let deliveredEvents = "MacBookIsland.EventKit.deliveredEvents"
    }

    private let store = EKEventStore()
    private let defaults: UserDefaults
    private var deliveredEvents: [String: TimeInterval]
    private var deliveredEventsDirty = false
    private var liveCalendarIdentifiers: Set<String> = []
    private var liveReminderIdentifiers: Set<String> = []
    private var calendarEnabled = false
    private var remindersEnabled = false
    private var loopTask: Task<Void, Never>?
    private var refreshInFlight = false
    private var refreshQueued = false
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var settingsGeneration = 0
    private var onEvent: EventHandler?
    private var onCancel: CancellationHandler?
    private var onStatus: StatusHandler?

    private let calendarLeadTime: TimeInterval = 10 * 60
    private let calendarLookback: TimeInterval = 2 * 60
    private let reminderLookback: TimeInterval = 5 * 60
    private let pollIntervalNanoseconds: UInt64 = 30_000_000_000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deliveredEvents = defaults.dictionary(forKey: DefaultsKey.deliveredEvents)?
            .compactMapValues { value in
                if let number = value as? NSNumber {
                    return number.doubleValue
                }
                return value as? Double
            } ?? [:]
        pruneDeliveredEvents(now: Date())
    }

    func start(
        calendarEnabled: Bool,
        remindersEnabled: Bool,
        onEvent: @escaping EventHandler,
        onCancel: @escaping CancellationHandler,
        onStatus: @escaping StatusHandler
    ) {
        self.calendarEnabled = calendarEnabled
        self.remindersEnabled = remindersEnabled
        self.onEvent = onEvent
        self.onCancel = onCancel
        self.onStatus = onStatus
        publishStatus(detail: statusDetail())

        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.calendarEnabled || self.remindersEnabled {
                    await refreshNow()
                }
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
    }

    func stop() {
        settingsGeneration += 1
        loopTask?.cancel()
        loopTask = nil
        onEvent = nil
        onCancel = nil
        onStatus = nil
    }

    func update(calendarEnabled: Bool, remindersEnabled: Bool) {
        settingsGeneration += 1
        self.calendarEnabled = calendarEnabled
        self.remindersEnabled = remindersEnabled
        if !calendarEnabled {
            cancelLiveEvents(&liveCalendarIdentifiers)
        }
        if !remindersEnabled {
            cancelLiveEvents(&liveReminderIdentifiers)
        }
        Task { [weak self] in
            await self?.refreshNow()
        }
    }

    func requestCalendarAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            publishStatus(detail: granted ? "日历访问已授权。" : "日历访问未授权。")
            await refreshNow()
            return granted
        } catch {
            publishStatus(detail: "日历授权失败：\(error.localizedDescription)")
            return false
        }
    }

    func requestRemindersAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToReminders()
            publishStatus(detail: granted ? "提醒事项访问已授权。" : "提醒事项访问未授权。")
            await refreshNow()
            return granted
        } catch {
            publishStatus(detail: "提醒事项授权失败：\(error.localizedDescription)")
            return false
        }
    }

    func refreshNow() async {
        guard !refreshInFlight else {
            refreshQueued = true
            await withCheckedContinuation { continuation in
                refreshWaiters.append(continuation)
            }
            return
        }
        refreshInFlight = true

        let now = Date()
        let generation = settingsGeneration
        let calendarAccess = EventKitAccessState(EKEventStore.authorizationStatus(for: .event))
        let remindersAccess = EventKitAccessState(EKEventStore.authorizationStatus(for: .reminder))

        if calendarEnabled, calendarAccess.canRead {
            let records = await Self.fetchCalendarRecords(
                now: now,
                lookback: calendarLookback,
                leadTime: calendarLeadTime
            )
            let stillAuthorized = EventKitAccessState(
                EKEventStore.authorizationStatus(for: .event)
            ).canRead
            if generation == settingsGeneration, calendarEnabled, stillAuthorized {
                refreshCalendarEvents(records, now: now)
            } else {
                cancelLiveEvents(&liveCalendarIdentifiers)
            }
        } else {
            cancelLiveEvents(&liveCalendarIdentifiers)
        }

        if remindersEnabled, remindersAccess.canRead {
            let reminders = await Self.fetchDueReminders(
                now: now,
                lookback: reminderLookback
            )
            let stillAuthorized = EventKitAccessState(
                EKEventStore.authorizationStatus(for: .reminder)
            ).canRead
            if generation == settingsGeneration, remindersEnabled, stillAuthorized {
                refreshReminders(reminders, now: now)
            } else {
                cancelLiveEvents(&liveReminderIdentifiers)
            }
        } else {
            cancelLiveEvents(&liveReminderIdentifiers)
        }

        pruneDeliveredEvents(now: now)
        persistDeliveredEvents()
        let finalCalendarAccess = EventKitAccessState(
            EKEventStore.authorizationStatus(for: .event)
        )
        let finalRemindersAccess = EventKitAccessState(
            EKEventStore.authorizationStatus(for: .reminder)
        )
        if calendarEnabled, !finalCalendarAccess.canRead {
            cancelLiveEvents(&liveCalendarIdentifiers)
        }
        if remindersEnabled, !finalRemindersAccess.canRead {
            cancelLiveEvents(&liveReminderIdentifiers)
        }
        publishStatus(
            checkedAt: now,
            detail: statusDetail(
                calendarAccess: finalCalendarAccess,
                remindersAccess: finalRemindersAccess
            )
        )

        refreshInFlight = false
        if refreshQueued {
            refreshQueued = false
            await refreshNow()
        }
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    nonisolated private static func fetchCalendarRecords(
        now: Date,
        lookback: TimeInterval,
        leadTime: TimeInterval
    ) async -> [EventKitCalendarRecord] {
        await Task.detached(priority: .utility) {
            let eventStore = EKEventStore()
            let predicate = eventStore.predicateForEvents(
                withStart: now.addingTimeInterval(-lookback),
                end: now.addingTimeInterval(leadTime),
                calendars: nil
            )
            return eventStore.events(matching: predicate)
                .filter { !$0.isAllDay && $0.status != .canceled }
                .sorted { $0.startDate < $1.startDate }
                .compactMap { event -> EventKitCalendarRecord? in
                    guard let startDate = event.startDate else { return nil }
                    let itemIdentifier = event.eventIdentifier ?? event.calendarItemIdentifier
                    let identifier = "eventkit:calendar:\(itemIdentifier):\(Int(startDate.timeIntervalSince1970.rounded()))"
                    let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return EventKitCalendarRecord(
                        identifier: identifier,
                        title: title?.isEmpty == false ? title! : "未命名日程",
                        startDate: startDate,
                        location: event.location
                    )
                }
        }.value
    }

    nonisolated private static func fetchDueReminders(
        now: Date,
        lookback: TimeInterval
    ) async -> [EventKitReminderRecord] {
        await Task.detached(priority: .utility) {
            await withCheckedContinuation { continuation in
                let eventStore = EKEventStore()
                let predicate = eventStore.predicateForIncompleteReminders(
                    withDueDateStarting: now.addingTimeInterval(-lookback),
                    ending: now,
                    calendars: nil
                )
                eventStore.fetchReminders(matching: predicate) { reminders in
                    let records = (reminders ?? [])
                        .compactMap { reminder -> EventKitReminderRecord? in
                            guard let components = reminder.dueDateComponents,
                                  components.hour != nil || components.minute != nil else { return nil }
                            var calendar = Calendar.current
                            if let timeZone = components.timeZone {
                                calendar.timeZone = timeZone
                            }
                            guard let dueDate = calendar.date(from: components) else { return nil }
                            let identifier = "eventkit:reminder:\(reminder.calendarItemIdentifier):\(Int(dueDate.timeIntervalSince1970.rounded()))"
                            return EventKitReminderRecord(
                                identifier: identifier,
                                title: reminder.title,
                                dueDate: dueDate
                            )
                        }
                        .filter {
                            $0.dueDate >= now.addingTimeInterval(-lookback)
                                && $0.dueDate <= now
                        }
                        .sorted { $0.dueDate < $1.dueDate }
                    withExtendedLifetime(eventStore) {
                        continuation.resume(returning: records)
                    }
                }
            }
        }.value
    }

    private func refreshCalendarEvents(_ events: [EventKitCalendarRecord], now: Date) {
        var currentIdentifiers: Set<String> = []
        for event in events.prefix(12) {
            let identifier = event.identifier
            currentIdentifiers.insert(identifier)
            guard markDeliveredIfNeeded(identifier, now: now) else { continue }

            onEvent?(
                EventKitIslandEvent(
                    identifier: identifier,
                    title: event.title,
                    body: calendarBody(for: event, now: now),
                    source: "日历",
                    sourceBundleIdentifier: "com.apple.iCal"
                )
            )
        }

        cancelMissingEvents(previous: liveCalendarIdentifiers, current: currentIdentifiers)
        liveCalendarIdentifiers = currentIdentifiers
    }

    private func refreshReminders(_ reminders: [EventKitReminderRecord], now: Date) {
        var currentIdentifiers: Set<String> = []
        for reminder in reminders.prefix(12) {
            let identifier = reminder.identifier
            currentIdentifiers.insert(identifier)
            guard markDeliveredIfNeeded(identifier, now: now) else { continue }

            let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            onEvent?(
                EventKitIslandEvent(
                    identifier: identifier,
                    title: title.isEmpty ? "未命名提醒" : title,
                    body: reminderBody(dueDate: reminder.dueDate, now: now),
                    source: "提醒事项",
                    sourceBundleIdentifier: "com.apple.reminders"
                )
            )
        }

        cancelMissingEvents(previous: liveReminderIdentifiers, current: currentIdentifiers)
        liveReminderIdentifiers = currentIdentifiers
    }

    private func calendarBody(for event: EventKitCalendarRecord, now: Date) -> String {
        let seconds = event.startDate.timeIntervalSince(now)
        let time = timeText(event.startDate)
        let timing: String
        if seconds <= 60 {
            timing = "现在开始 · \(time)"
        } else {
            timing = "\(max(Int(ceil(seconds / 60)), 1)) 分钟后 · \(time)"
        }
        guard let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty else { return timing }
        return "\(timing) · \(location)"
    }

    private func reminderBody(dueDate: Date, now: Date) -> String {
        let overdueMinutes = max(Int(now.timeIntervalSince(dueDate) / 60), 0)
        return overdueMinutes == 0 ? "现在到期" : "已逾期 \(overdueMinutes) 分钟"
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func markDeliveredIfNeeded(_ identifier: String, now: Date) -> Bool {
        guard deliveredEvents[identifier] == nil else { return false }
        deliveredEvents[identifier] = now.timeIntervalSince1970
        deliveredEventsDirty = true
        return true
    }

    private func cancelMissingEvents(previous: Set<String>, current: Set<String>) {
        for identifier in previous.subtracting(current) {
            onCancel?(identifier)
        }
    }

    private func cancelLiveEvents(_ identifiers: inout Set<String>) {
        for identifier in identifiers {
            onCancel?(identifier)
        }
        identifiers.removeAll()
    }

    private func pruneDeliveredEvents(now: Date) {
        let previousCount = deliveredEvents.count
        let cutoff = now.addingTimeInterval(-48 * 60 * 60).timeIntervalSince1970
        deliveredEvents = deliveredEvents.filter { $0.value >= cutoff }
        if deliveredEvents.count > 512 {
            deliveredEvents = Dictionary(
                uniqueKeysWithValues: deliveredEvents
                    .sorted { $0.value > $1.value }
                    .prefix(512)
                    .map { ($0.key, $0.value) }
            )
        }
        if deliveredEvents.count != previousCount {
            deliveredEventsDirty = true
        }
    }

    private func persistDeliveredEvents() {
        guard deliveredEventsDirty else { return }
        defaults.set(deliveredEvents, forKey: DefaultsKey.deliveredEvents)
        deliveredEventsDirty = false
    }

    private func publishStatus(checkedAt: Date? = nil, detail: String) {
        onStatus?(
            EventKitActivityStatus(
                calendarAccess: EventKitAccessState(EKEventStore.authorizationStatus(for: .event)),
                remindersAccess: EventKitAccessState(EKEventStore.authorizationStatus(for: .reminder)),
                lastRefreshAt: checkedAt,
                detail: detail
            )
        )
    }

    private func statusDetail(
        calendarAccess: EventKitAccessState? = nil,
        remindersAccess: EventKitAccessState? = nil
    ) -> String {
        let calendarAccess = calendarAccess
            ?? EventKitAccessState(EKEventStore.authorizationStatus(for: .event))
        let remindersAccess = remindersAccess
            ?? EventKitAccessState(EKEventStore.authorizationStatus(for: .reminder))
        var states: [String] = []
        if calendarEnabled {
            states.append(calendarAccess.canRead ? "日历已启用" : "日历等待授权")
        }
        if remindersEnabled {
            states.append(remindersAccess.canRead ? "提醒事项已启用" : "提醒事项等待授权")
        }
        return states.isEmpty ? "日历和提醒事项尚未启用。" : states.joined(separator: "；")
    }
}

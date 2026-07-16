import Foundation

enum AppleMusicTimelineStage: String, Equatable {
    case controlIssued = "control-issued"
    case controlCompleted = "control-completed"
    case playerInfoReceived = "player-info-received"
    case metadataReadStarted = "metadata-read-started"
    case metadataReadCompleted = "metadata-read-completed"
    case artworkReadStarted = "artwork-read-started"
    case artworkReadCompleted = "artwork-read-completed"
    case snapshotApplied = "snapshot-applied"
    case snapshotRejected = "snapshot-rejected"
    case uiPublished = "ui-published"
}

@MainActor
final class AppleMusicTransitionTimeline {
    private struct Event {
        let stage: AppleMusicTimelineStage
        let elapsedMilliseconds: Int
        let detail: String
    }

    private struct Trace {
        let id: UInt64
        let origin: String
        let startedAt: Date
        let startedUptime: TimeInterval
        var candidateSignature: String?
        var events: [Event]
    }

    private let maximumTraceCount: Int
    private let maximumEventCount: Int
    private let activeTraceLifetime: TimeInterval
    private let wallClock: () -> Date
    private let uptime: () -> TimeInterval
    private var nextTraceID: UInt64 = 0
    private var traces: [Trace] = []
    private var currentTraceID: UInt64?

    init(
        maximumTraceCount: Int = 4,
        maximumEventCount: Int = 24,
        activeTraceLifetime: TimeInterval = 8,
        wallClock: @escaping () -> Date = Date.init,
        uptime: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.maximumTraceCount = max(maximumTraceCount, 1)
        self.maximumEventCount = max(maximumEventCount, 1)
        self.activeTraceLifetime = max(activeTraceLifetime, 0.1)
        self.wallClock = wallClock
        self.uptime = uptime
    }

    @discardableResult
    func beginControl(command: String, baseline: String) -> UInt64 {
        beginTrace(
            origin: "control:\(command)",
            candidateSignature: nil,
            stage: .controlIssued,
            detail: "command=\(command) baseline=\(baseline)"
        )
    }

    @discardableResult
    func notePlayerInfo(
        candidateSignature: String?,
        detail: String,
        observedAt: Date? = nil,
        observedUptime: TimeInterval? = nil
    ) -> UInt64 {
        let nowUptime = observedUptime ?? uptime()
        if let currentTraceID,
           let index = traces.lastIndex(where: { $0.id == currentTraceID }),
           nowUptime < traces[index].startedUptime {
            return currentTraceID
        }
        if let index = currentTraceIndex(at: nowUptime) {
            let currentCandidate = traces[index].candidateSignature
            if currentCandidate == nil
                || candidateSignature == nil
                || currentCandidate == candidateSignature {
                if let candidateSignature {
                    traces[index].candidateSignature = candidateSignature
                }
                append(
                    stage: .playerInfoReceived,
                    detail: detail,
                    toTraceAt: index,
                    nowUptime: nowUptime
                )
                return traces[index].id
            }
        }

        return beginTrace(
            origin: "player-info",
            candidateSignature: candidateSignature,
            stage: .playerInfoReceived,
            detail: detail,
            startedAt: observedAt,
            startedUptime: nowUptime
        )
    }

    func record(_ stage: AppleMusicTimelineStage, detail: String) {
        let nowUptime = uptime()
        guard let index = currentTraceIndex(at: nowUptime) else { return }
        append(
            stage: stage,
            detail: detail,
            toTraceAt: index,
            nowUptime: nowUptime
        )
    }

    func report() -> String {
        guard !traces.isEmpty else {
            return "no Apple Music transition recorded"
        }
        return render(traces)
    }

    func latestReport() -> String {
        guard let trace = traces.last else {
            return "no Apple Music transition recorded"
        }
        return render([trace])
    }

    private func render(_ traces: [Trace]) -> String {
        traces.map { trace in
            let header = "trace=\(trace.id) origin=\(trace.origin) startedAt=\(trace.startedAt.ISO8601Format())"
            let events = trace.events.enumerated()
                .sorted { left, right in
                    if left.element.elapsedMilliseconds
                        == right.element.elapsedMilliseconds {
                        return left.offset < right.offset
                    }
                    return left.element.elapsedMilliseconds
                        < right.element.elapsedMilliseconds
                }
                .map { _, event in
                    "  +\(event.elapsedMilliseconds)ms \(event.stage.rawValue) \(event.detail)"
                }
            return ([header] + events).joined(separator: "\n")
        }
        .joined(separator: "\n")
    }

    private func beginTrace(
        origin: String,
        candidateSignature: String?,
        stage: AppleMusicTimelineStage,
        detail: String,
        startedAt: Date? = nil,
        startedUptime: TimeInterval? = nil
    ) -> UInt64 {
        nextTraceID &+= 1
        let nowUptime = startedUptime ?? uptime()
        let trace = Trace(
            id: nextTraceID,
            origin: sanitize(origin),
            startedAt: startedAt ?? wallClock(),
            startedUptime: nowUptime,
            candidateSignature: candidateSignature,
            events: [Event(
                stage: stage,
                elapsedMilliseconds: 0,
                detail: sanitize(detail)
            )]
        )
        traces.append(trace)
        if traces.count > maximumTraceCount {
            traces.removeFirst(traces.count - maximumTraceCount)
        }
        currentTraceID = trace.id
        return trace.id
    }

    private func currentTraceIndex(at nowUptime: TimeInterval) -> Int? {
        guard let currentTraceID,
              let index = traces.lastIndex(where: { $0.id == currentTraceID }),
              nowUptime - traces[index].startedUptime <= activeTraceLifetime else {
            self.currentTraceID = nil
            return nil
        }
        return index
    }

    private func append(
        stage: AppleMusicTimelineStage,
        detail: String,
        toTraceAt index: Int,
        nowUptime: TimeInterval
    ) {
        let sanitizedDetail = sanitize(detail)
        if traces[index].events.contains(where: {
            $0.stage == stage && $0.detail == sanitizedDetail
        }) {
            return
        }
        let elapsed = max(
            0,
            Int(((nowUptime - traces[index].startedUptime) * 1_000).rounded())
        )
        traces[index].events.append(Event(
            stage: stage,
            elapsedMilliseconds: elapsed,
            detail: sanitizedDetail
        ))
        if traces[index].events.count > maximumEventCount {
            traces[index].events.removeFirst(
                traces[index].events.count - maximumEventCount
            )
        }
    }

    private func sanitize(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(singleLine.prefix(240))
    }
}

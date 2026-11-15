import Foundation

/// Infers Qishui play / pause from direct AX snapshots when the snapshot carries no
/// explicit playback flag: progress that moves means playing; progress that stays put
/// for 1.35 seconds (away from the start and end of the track) means paused.
///
/// Moved out of `MusicAdapterCoordinator` unchanged (coordinator split step 4.1).
struct QishuiPlaybackInference {
    private(set) var inferredIsPlaying: Bool?
    private var stationarySince: Date?
    private var previousProgress: QishuiProgressSample?

    mutating func update(track: QishuiDirectTrack, checkedAt: Date) {
        let signature = Self.signature(track)
        if let isPlaying = track.isPlaying {
            inferredIsPlaying = isPlaying
            stationarySince = isPlaying ? nil : checkedAt
        } else if let previous = previousProgress,
                  previous.signature == signature,
                  let currentProgress = track.progress,
                  checkedAt.timeIntervalSince(previous.checkedAt) >= 0.15 {
            let progressDelta = currentProgress - previous.progress
            if progressDelta > 0.0005 {
                inferredIsPlaying = true
                stationarySince = nil
            } else if progressDelta < -0.01 {
                stationarySince = nil
            } else if abs(progressDelta) <= 0.0002,
                      currentProgress > 0,
                      currentProgress < 0.995 {
                let since = stationarySince ?? previous.checkedAt
                stationarySince = since
                if checkedAt.timeIntervalSince(since) >= 1.35 {
                    inferredIsPlaying = false
                }
            } else {
                stationarySince = nil
            }
        } else {
            stationarySince = nil
            inferredIsPlaying = nil
        }

        if let progress = track.progress {
            previousProgress = QishuiProgressSample(
                signature: signature,
                progress: progress,
                checkedAt: checkedAt
            )
        }
    }

    mutating func reset() {
        previousProgress = nil
        stationarySince = nil
        inferredIsPlaying = nil
    }

    func label(for track: QishuiDirectTrack) -> String {
        if let isPlaying = track.isPlaying ?? inferredIsPlaying {
            return isPlaying ? "播放中" : "已暂停"
        }
        return "等待进度变化确认"
    }

    static func signature(_ track: QishuiDirectTrack) -> String {
        "\(track.title)\u{1f}\(track.artist)"
    }
}

private struct QishuiProgressSample {
    let signature: String
    let progress: Double
    let checkedAt: Date
}

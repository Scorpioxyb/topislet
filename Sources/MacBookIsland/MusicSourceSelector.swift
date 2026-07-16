import Foundation

enum MusicSourceID: Equatable, Sendable {
    case qishui
    case appleMusic

    init?(bundleIdentifier: String?) {
        switch bundleIdentifier {
        case "com.soda.music":
            self = .qishui
        case "com.apple.Music":
            self = .appleMusic
        default:
            return nil
        }
    }
}

struct DisplayedMusicControlBinding: Equatable, Sendable {
    let source: MusicSourceID
    let bundleIdentifier: String

    init?(displayedSourceBundleIdentifier: String?) {
        guard let source = MusicSourceID(
            bundleIdentifier: displayedSourceBundleIdentifier
        ), let displayedSourceBundleIdentifier else {
            return nil
        }
        self.source = source
        bundleIdentifier = displayedSourceBundleIdentifier
    }
}

enum MusicSourcePlaybackLevel: Equatable, Sendable {
    case playing
    case paused
    case unknown
}

struct MusicSourceCandidate: Equatable, Sendable {
    let source: MusicSourceID
    let isAvailable: Bool
    let hasTrack: Bool
    let playback: MusicSourcePlaybackLevel
    let isCached: Bool

    var isSelectable: Bool {
        isAvailable && hasTrack
    }
}

struct MusicSourceSelection: Equatable, Sendable {
    let source: MusicSourceID?
    let generation: UInt64
}

final class MusicSourceSelector {
    static let qishuiSwitchDelay: TimeInterval = 0.2
    static let appleMusicSwitchDelay: TimeInterval = 0.4

    private(set) var selection = MusicSourceSelection(source: nil, generation: 0)
    private var pendingSource: MusicSourceID?
    private var pendingSince: Date?

    func update(
        qishui: MusicSourceCandidate,
        appleMusic: MusicSourceCandidate,
        foregroundSource: MusicSourceID? = nil,
        at now: Date = Date()
    ) -> MusicSourceSelection {
        let currentCandidate = candidate(
            for: selection.source,
            qishui: qishui,
            appleMusic: appleMusic
        )
        let preferred = preferredSource(
            current: selection.source,
            qishui: qishui,
            appleMusic: appleMusic,
            foregroundSource: foregroundSource
        )

        if preferred == foregroundSource, preferred != nil {
            return commit(preferred)
        }
        if selection.source == nil || currentCandidate?.isSelectable != true {
            return commit(preferred)
        }
        guard preferred != selection.source else {
            clearPending()
            return selection
        }
        guard let preferred else {
            return commit(nil)
        }

        if pendingSource != preferred {
            pendingSource = preferred
            pendingSince = now
            return selection
        }
        let delay = preferred == .qishui
            ? Self.qishuiSwitchDelay
            : Self.appleMusicSwitchDelay
        guard let pendingSince,
              now.timeIntervalSince(pendingSince) >= delay else {
            return selection
        }
        return commit(preferred)
    }

    private func preferredSource(
        current: MusicSourceID?,
        qishui: MusicSourceCandidate,
        appleMusic: MusicSourceCandidate,
        foregroundSource: MusicSourceID?
    ) -> MusicSourceID? {
        if let foregroundSource,
           candidate(
               for: foregroundSource,
               qishui: qishui,
               appleMusic: appleMusic
           )?.isAvailable == true {
            return foregroundSource
        }

        let qishuiPlaying = qishui.isSelectable
            && qishui.playback == .playing
            && !qishui.isCached
        let appleMusicPlaying = appleMusic.isSelectable
            && appleMusic.playback == .playing

        if qishuiPlaying {
            return .qishui
        }
        if appleMusicPlaying {
            return .appleMusic
        }

        if let current,
           candidate(
               for: current,
               qishui: qishui,
               appleMusic: appleMusic
           )?.isSelectable == true {
            return current
        }
        if qishui.isSelectable {
            return .qishui
        }
        if appleMusic.isSelectable {
            return .appleMusic
        }
        return nil
    }

    private func candidate(
        for source: MusicSourceID?,
        qishui: MusicSourceCandidate,
        appleMusic: MusicSourceCandidate
    ) -> MusicSourceCandidate? {
        switch source {
        case .qishui:
            return qishui
        case .appleMusic:
            return appleMusic
        case nil:
            return nil
        }
    }

    private func commit(_ source: MusicSourceID?) -> MusicSourceSelection {
        clearPending()
        guard source != selection.source else { return selection }
        selection = MusicSourceSelection(
            source: source,
            generation: selection.generation &+ 1
        )
        return selection
    }

    private func clearPending() {
        pendingSource = nil
        pendingSince = nil
    }
}

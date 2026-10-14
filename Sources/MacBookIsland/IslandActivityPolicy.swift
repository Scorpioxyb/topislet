enum IslandMode: String {
    case collapsed
    case compact
    case expanded
}

enum IslandFeature: String, Hashable {
    case activityCenter
    case music
    case timer
    case notification

    var iconName: String {
        switch self {
        case .activityCenter:
            return "square.grid.2x2.fill"
        case .music:
            return "music.note"
        case .timer:
            return "timer"
        case .notification:
            return "bell"
        }
    }

}

enum IslandExpansionPolicy {
    static func allowsExpansion(
        activeFeature: IslandFeature,
        hasCurrentMusicTrack: Bool,
        hasPendingNotification: Bool
    ) -> Bool {
        switch activeFeature {
        case .activityCenter:
            return false
        case .music:
            return hasCurrentMusicTrack
        case .timer:
            return true
        case .notification:
            return hasPendingNotification
        }
    }
}

struct IslandPresentationDestination: Equatable {
    let feature: IslandFeature
    let mode: IslandMode
}

enum CollapsedIslandTapPolicy {
    static func destination(
        activeFeature: IslandFeature,
        hasCurrentMusicTrack: Bool,
        musicControlsAvailable: Bool = true,
        hasPendingNotification: Bool,
        musicExpansionMode: MusicExpansionMode = .hover
    ) -> IslandPresentationDestination {
        let canPresentMusic = hasCurrentMusicTrack && musicControlsAvailable
        let musicMode: IslandMode = musicExpansionMode == .hover ? .compact : .expanded
        switch activeFeature {
        case .activityCenter:
            return canPresentMusic
                ? IslandPresentationDestination(feature: .music, mode: musicMode)
                : IslandPresentationDestination(feature: .activityCenter, mode: .expanded)
        case .music:
            return canPresentMusic
                ? IslandPresentationDestination(feature: .music, mode: musicMode)
                : IslandPresentationDestination(feature: .activityCenter, mode: .expanded)
        case .timer:
            return IslandPresentationDestination(feature: .timer, mode: .compact)
        case .notification:
            return hasPendingNotification
                ? IslandPresentationDestination(feature: .notification, mode: .compact)
                : IslandPresentationDestination(feature: .activityCenter, mode: .expanded)
        }
    }
}

// Music arrival and notification takeover/restoration share this policy.
// Explicit user actions select their destination directly, without AppKit here.
enum IslandActivityArbitrationPolicy {
    static func shouldMusicTakeOver(
        activeFeature: IslandFeature,
        currentMode: IslandMode = .collapsed,
        becameAvailable: Bool,
        timerIsRunning: Bool,
        hasPendingNotification: Bool,
        isInteractionBlocked: Bool = false
    ) -> Bool {
        activeFeature == .activityCenter
            && currentMode != .expanded
            && becameAvailable
            && !timerIsRunning
            && !hasPendingNotification
            && !isInteractionBlocked
    }

    static func shouldPresentNotification(
        isUrgent: Bool,
        currentMode: IslandMode,
        isInteractionBlocked: Bool,
        explicitlyRequested: Bool
    ) -> Bool {
        // Force can bypass expanded presentation, never a pending control.
        !isInteractionBlocked
            && (explicitlyRequested || isUrgent || currentMode != .expanded)
    }

    static func featureAfterNotification(
        returnFeature: IslandFeature?,
        returnMode: IslandMode? = nil,
        timerIsRunning: Bool,
        hasCurrentMusicTrack: Bool
    ) -> IslandFeature {
        if returnFeature == .timer, timerIsRunning {
            return .timer
        }
        if returnFeature == .activityCenter, returnMode == .expanded {
            return .activityCenter
        }
        return hasCurrentMusicTrack ? .music : .activityCenter
    }
}

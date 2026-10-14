import CoreGraphics

enum IslandCollapsedLayout {
    static let activityWingWidth: CGFloat = 22
    static let artworkSize: CGFloat = 16

    static func wingWidth(feature: IslandFeature, hasCurrentMusicTrack: Bool) -> CGFloat {
        switch feature {
        case .activityCenter:
            return 0
        case .music:
            return hasCurrentMusicTrack ? activityWingWidth : 0
        case .timer, .notification:
            return activityWingWidth
        }
    }

    static func musicArrivalMode(currentMode: IslandMode) -> IslandMode {
        currentMode == .collapsed ? .collapsed : .compact
    }
}

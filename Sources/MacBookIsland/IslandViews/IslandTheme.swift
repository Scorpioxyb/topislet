import SwiftUI

// Visual constants of the island, gathered in one place (frontend redesign
// D0, Docs/design/FRONTEND_REDESIGN_2026-11.md section 7). Every value here is
// the exact literal the views used before; nothing changes on screen. Names
// describe the role at each site so D1 can re-point roles to the new five-step
// type scale and four text levels from this file alone.
enum IslandTheme {
    /// The island body and its edges.
    enum Surface {
        static let bodyCornerRadius: CGFloat = 24
        /// Black overlay on the music glass.
        static let musicGlassDim: Double = 0.30
        static let musicStrokeOpacity: Double = 0.12
        static let musicShadowOpacity: Double = 0.18
        static let strokeWidth: CGFloat = 0.65
        static let shadowRadius: CGFloat = 14
        static let shadowOffsetY: CGFloat = 8
        /// Backdrop behind the source-app badge glyph.
        static let badgeBackdrop: Double = 0.9
    }

    /// Opacity of white text and glyphs, by role.
    enum Ink {
        static let musicTitle: Double = 0.96
        static let lyricHighlighted: Double = 0.98
        static let lyricUnhighlighted: Double = 0.34
        static let lyricTranslation: Double = 0.62
        static let lyricNext: Double = 0.38
        static let musicArtist: Double = 0.55
        static let musicStatus: Double = 0.58
        static let musicPlaceholderIcon: Double = 0.38
        static let timeReadout: Double = 0.52
        static let compactSubtitle: Double = 0.58
        static let headerIcon: Double = 0.72
        static let collapsedPauseGlyph: Double = 0.55
        static let pendingChip: Double = 0.78
        static let windowButton: Double = 0.68
        static let toggleOn: Double = 0.95
        static let toggleOff: Double = 0.55
        static let controlGlyph: Double = 0.9
        static let disabledControl: Double = 0.38
        static let artworkGlyph: Double = 0.86
        static let sectionHeading: Double = 0.86
        static let sectionTitle: Double = 0.72
        static let rowTitle: Double = 0.86
        static let rowDetail: Double = 0.48
        static let rowIcon: Double = 0.72
        static let notificationSource: Double = 0.48
        static let notificationBody: Double = 0.62
    }

    /// Opacity of white fills, by role.
    enum Fill {
        static let quietButton: Double = 0.06
        static let chip: Double = 0.08
        static let divider: Double = 0.08
        static let presetChip: Double = 0.09
        static let button: Double = 0.1
        static let buttonHover: Double = 0.16
        static let toggleOn: Double = 0.16
        static let selected: Double = 0.12
        static let musicColumnDivider: Double = 0.12
        static let timerRingTrack: Double = 0.12
        static let progressTrack: Double = 0.13
        static let progressTrackProminent: Double = 0.19
        static let progressPill: Double = 0.065
        static let artworkFallbackTop: Double = 0.13
        static let artworkFallbackBottom: Double = 0.05
        static let artworkGlyphBackdrop: Double = 0.18
    }

    /// Opacity applied to the artwork accent color, by role.
    enum Accent {
        static let lyricBar: Double = 0.95
        static let progressFill: Double = 0.92
    }

    enum Radius {
        static let recoveryButton: CGFloat = 12
        static let presetChip: CGFloat = 7
        static let progressPill: CGFloat = 15
        static let notificationIcon: CGFloat = 17
    }

    /// Fonts by role.
    enum Typeface {
        // Collapsed and expanded header
        static let collapsedIcon: Font = .system(size: 11, weight: .semibold)
        static let collapsedPauseGlyph: Font = .system(size: 9, weight: .medium)
        static let expandedHeaderIcon: Font = .system(size: 11, weight: .bold)
        static let chipLabel: Font = .system(size: 10, weight: .medium)
        static let windowButton: Font = .system(size: 12, weight: .semibold)
        static let windowButtonBold: Font = .system(size: 12, weight: .bold)

        // Compact
        static let compactTitle: Font = .system(size: 12, weight: .semibold)
        static let compactSubtitle: Font = .system(size: 10, weight: .medium)
        static let compactBody: Font = .system(size: 10)
        static let compactTimerIcon: Font = .system(size: 13, weight: .semibold)
        static let compactTimerTime: Font = .system(size: 13, weight: .semibold, design: .rounded)
        static let compactBadge: Font = .system(size: 8, weight: .bold)

        // Expanded music
        static let musicTitle: Font = .system(size: 13, weight: .semibold)
        static let musicArtist: Font = .system(size: 11, weight: .medium)
        static let musicPlaceholderIcon: Font = .system(size: 13, weight: .regular)
        static let musicStatus: Font = .system(size: 12, weight: .medium)
        static let recoveryLabel: Font = .system(size: 11, weight: .medium)
        static let lyricCurrent: Font = .system(size: 23, weight: .semibold)
        static let lyricTranslation: Font = .system(size: 14, weight: .regular)
        static let lyricNext: Font = .system(size: 16, weight: .medium)
        static let timeReadout: Font = .system(size: 11, weight: .medium, design: .rounded)

        // Controls
        static let badgeGlyph: Font = .system(size: 8, weight: .bold)
        static let textButtonIcon: Font = .system(size: 12, weight: .bold)
        static let textButtonLabel: Font = .system(size: 12, weight: .semibold)

        // Activity center
        static let sectionHeading: Font = .system(size: 13, weight: .semibold)
        static let smallButtonIcon: Font = .system(size: 11, weight: .bold)
        static let presetLabel: Font = .system(size: 11, weight: .semibold, design: .rounded)
        static let rowTitle: Font = .system(size: 12, weight: .medium)
        static let rowDetail: Font = .system(size: 10, weight: .regular)
        static let rowDetailMedium: Font = .system(size: 10, weight: .medium)
        static let pillLabel: Font = .system(size: 11, weight: .semibold)
        static let rowIcon: Font = .system(size: 14, weight: .semibold)

        // Timer and notification
        static let timerDisplay: Font = .system(size: 20, weight: .semibold, design: .rounded)
        static let timerStatus: Font = .system(size: 16, weight: .semibold)
        static let notificationIcon: Font = .system(size: 24, weight: .semibold)
        static let notificationSource: Font = .system(size: 11, weight: .medium)
        static let notificationTitle: Font = .system(size: 17, weight: .semibold)
        static let notificationBody: Font = .system(size: 12)
    }
}

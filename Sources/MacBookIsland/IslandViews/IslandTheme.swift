import SwiftUI

// Visual constants of the island (Docs/design/FRONTEND_REDESIGN_2026-11.md).
// D0 gathered every literal here under a role name; D1 points the roles at the
// redesign scale:
//   text   primary 0.96 · secondary 0.62 · tertiary 0.40 · disabled 0.30
//   fill   0.08 · hover 0.14 · separator 0.10
//   type   caption 11 · body 13 · title 15 · lyric 21 · display 28
// Font roles of the compact, timer, notification and activity-center views
// keep their previous sizes until those layouts are redone (D4, D5); only
// their text and fill opacities move to the shared levels here. Expanded music
// keeps its left-rail + lyric-column composition on the black surface.
enum IslandTheme {
    enum Level {
        static let primary: Double = 0.96
        static let secondary: Double = 0.62
        static let tertiary: Double = 0.40
        static let disabled: Double = 0.30
        static let fill: Double = 0.08
        static let fillHover: Double = 0.14
        static let separator: Double = 0.10
    }

    /// The island body and its edges.
    enum Surface {
        static let bodyCornerRadius: CGFloat = 24
        static let musicBodyCornerRadius: CGFloat = 28
        /// Artwork-colored glow behind the cover on the black music surface.
        static let musicGlowOpacity: Double = 0.22
        static let musicGlowRadius: CGFloat = 260
        /// Blurred cover spread from the panel's left edge (direction C).
        static let musicWashOpacity: Double = 0.62
        static let musicWashSize = CGSize(width: 440, height: 300)
        static let musicWashOffset = CGSize(width: -70, height: -10)
        static let musicCoverShadowOpacity: Double = 0.45
        static let strokeWidth: CGFloat = 0.65
        static let shadowRadius: CGFloat = 14
        static let shadowOffsetY: CGFloat = 8
        /// Backdrop behind the source-app badge glyph.
        static let badgeBackdrop: Double = 0.9
    }

    /// Opacity of white text and glyphs, by role.
    enum Ink {
        static let musicTitle = Level.primary
        static let lyricHighlighted = Level.primary
        static let lyricUnhighlighted: Double = 0.34
        static let lyricTranslation = Level.secondary
        static let lyricNext = Level.tertiary
        static let musicArtist = Level.secondary
        static let musicSource = Level.tertiary
        static let musicStatus = Level.tertiary
        static let timeReadout = Level.secondary
        static let compactSubtitle = Level.secondary
        static let headerIcon = Level.secondary
        static let collapsedPauseGlyph = Level.secondary
        static let pendingChip = Level.secondary
        static let windowButton = Level.secondary
        static let controlGlyph = Level.primary
        static let disabledControl = Level.disabled
        static let toggleOn: Double = 0.95
        static let toggleOff: Double = 0.55
        static let artworkGlyph = Level.secondary
        static let sectionHeading = Level.primary
        static let sectionTitle = Level.secondary
        static let rowTitle = Level.primary
        static let rowDetail = Level.tertiary
        static let rowIcon = Level.secondary
        static let notificationSource = Level.tertiary
        static let notificationBody = Level.secondary
    }

    /// Opacity of white fills, by role.
    enum Fill {
        static let quietButton = Level.fill
        static let chip = Level.fill
        static let divider = Level.separator
        static let presetChip = Level.fill
        static let button = Level.fill
        static let buttonHover = Level.fillHover
        static let selected = Level.fillHover
        static let timerRingTrack = Level.fillHover
        static let progressTrack = Level.fillHover
        static let progressTrackProminent = Level.fillHover
        static let progressHairlineTrack: Double = 0.12
        static let toggleOn: Double = 0.16
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
        static let presetChip: CGFloat = 7
        static let notificationIcon: CGFloat = 17
        static let recoveryButton: CGFloat = 12
    }

    /// Fonts by role.
    enum Typeface {
        // Redesign scale
        static let caption: Font = .system(size: 11, weight: .medium)
        static let body: Font = .system(size: 13, weight: .regular)
        static let title: Font = .system(size: 15, weight: .semibold)
        static let lyric: Font = .system(size: 21, weight: .semibold)
        static let display: Font = .system(size: 28, weight: .semibold, design: .rounded)

        // Collapsed and expanded header
        static let collapsedIcon: Font = .system(size: 11, weight: .semibold)
        static let collapsedPauseGlyph: Font = .system(size: 9, weight: .medium)
        static let expandedHeaderIcon: Font = .system(size: 11, weight: .bold)
        static let chipLabel: Font = .system(size: 10, weight: .medium)
        static let windowButton: Font = .system(size: 12, weight: .semibold)
        static let windowButtonBold: Font = .system(size: 12, weight: .bold)

        // Compact (D4)
        static let compactTitle: Font = .system(size: 12, weight: .semibold)
        static let compactSubtitle: Font = .system(size: 10, weight: .medium)
        static let compactBody: Font = .system(size: 10)
        static let compactTimerIcon: Font = .system(size: 13, weight: .semibold)
        static let compactTimerTime: Font = .system(size: 13, weight: .semibold, design: .rounded)
        static let compactBadge: Font = .system(size: 8, weight: .bold)

        // Expanded music, direction C (build 187): cover beside one reading
        // column. Title and artist share one line above the lyrics; without
        // lyrics they move up to the lyric sizes.
        static let musicTitle: Font = .system(size: 13, weight: .semibold)
        static let musicArtist: Font = .system(size: 13, weight: .regular)
        static let musicStageTitle: Font = .system(size: 26, weight: .semibold)
        static let musicStageArtist: Font = .system(size: 16, weight: .regular)
        static let musicSource = caption
        static let musicStatus: Font = .system(size: 12, weight: .medium)
        static let recoveryLabel: Font = .system(size: 11, weight: .medium)
        static let lyricCurrentSize: CGFloat = 26
        static let lyricCurrent: Font = lyricCurrent(size: lyricCurrentSize)
        static func lyricCurrent(size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
        static let lyricTranslation: Font = .system(size: 15, weight: .regular)
        static let lyricNext: Font = .system(size: 16, weight: .medium)
        static let timeReadout: Font = .system(size: 11, weight: .medium, design: .rounded)

        // Controls
        static let badgeGlyph: Font = .system(size: 8, weight: .bold)
        static let textButtonIcon: Font = .system(size: 12, weight: .bold)
        static let textButtonLabel: Font = .system(size: 12, weight: .semibold)

        // Activity center (D5)
        static let sectionHeading: Font = .system(size: 13, weight: .semibold)
        static let smallButtonIcon: Font = .system(size: 11, weight: .bold)
        static let presetLabel: Font = .system(size: 11, weight: .semibold, design: .rounded)
        static let rowTitle: Font = .system(size: 12, weight: .medium)
        static let rowDetail: Font = .system(size: 10, weight: .regular)
        static let rowDetailMedium: Font = .system(size: 10, weight: .medium)
        static let pillLabel: Font = .system(size: 11, weight: .semibold)
        static let rowIcon: Font = .system(size: 14, weight: .semibold)

        // Timer and notification (D5)
        static let timerDisplay: Font = .system(size: 20, weight: .semibold, design: .rounded)
        static let timerStatus: Font = .system(size: 16, weight: .semibold)
        static let notificationIcon: Font = .system(size: 24, weight: .semibold)
        static let notificationSource: Font = .system(size: 11, weight: .medium)
        static let notificationTitle: Font = .system(size: 17, weight: .semibold)
        static let notificationBody: Font = .system(size: 12)
    }
}

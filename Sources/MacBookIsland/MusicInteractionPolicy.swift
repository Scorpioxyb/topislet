enum MusicExpansionMode: String, CaseIterable, Identifiable {
    case hover
    case click
    case pinned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hover: "悬停展开"
        case .click: "点击展开"
        case .pinned: "保持展开"
        }
    }

    var explanation: String {
        switch self {
        case .hover: "鼠标移入音乐岛时展开，移开后收起；在面板里点按后移开也会收起。"
        case .click: "鼠标经过时保持原样，点击音乐岛即可展开。"
        case .pinned: "音乐出现时展开，移开鼠标或点击其他窗口仍保持；可随时手动收起。"
        }
    }
}

enum MusicInteractionPolicy {
    static func allowsHover(feature: IslandFeature, expansion: MusicExpansionMode) -> Bool {
        feature != .music || expansion == .hover
    }

    /// Whether a click or control press inside a hover-expanded panel ends
    /// the hover presentation (the panel then stays until an outside click or
    /// a manual collapse). Music in hover mode keeps following the pointer:
    /// pressing play and then moving away still collapses it.
    static func interactionEndsHoverPresentation(feature: IslandFeature, expansion: MusicExpansionMode) -> Bool {
        !(feature == .music && expansion == .hover)
    }

    static func allowsOutsideCollapse(feature: IslandFeature, expansion: MusicExpansionMode) -> Bool {
        feature != .music || expansion != .pinned
    }

    static func arrivalMode(currentMode: IslandMode, expansion: MusicExpansionMode) -> IslandMode {
        expansion == .pinned ? .expanded : IslandCollapsedLayout.musicArrivalMode(currentMode: currentMode)
    }

    static func shouldOpenOnPreferenceChange(
        feature: IslandFeature, hasTrack: Bool, expansion: MusicExpansionMode
    ) -> Bool {
        feature == .music && hasTrack && expansion == .pinned
    }
}

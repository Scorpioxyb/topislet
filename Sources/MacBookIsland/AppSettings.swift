import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let prefix = "MacBookIsland.AppSettings."
        static let showIslandOnLaunch = "showIslandOnLaunch"
        static let autoCollapseExpandedIsland = "autoCollapseExpandedIsland"
        static let showMusicDiagnostics = "showMusicDiagnostics"
    }

    private let defaults: UserDefaults
    private var isLoading = false

    @Published var showIslandOnLaunch: Bool {
        didSet { persist(Key.showIslandOnLaunch, showIslandOnLaunch) }
    }

    @Published var autoCollapseExpandedIsland: Bool {
        didSet { persist(Key.autoCollapseExpandedIsland, autoCollapseExpandedIsland) }
    }

    @Published var showMusicDiagnostics: Bool {
        didSet { persist(Key.showMusicDiagnostics, showMusicDiagnostics) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showIslandOnLaunch = Self.bool(
            named: Key.showIslandOnLaunch,
            in: defaults,
            fallback: true
        )
        autoCollapseExpandedIsland = Self.bool(
            named: Key.autoCollapseExpandedIsland,
            in: defaults,
            fallback: true
        )
        showMusicDiagnostics = Self.bool(
            named: Key.showMusicDiagnostics,
            in: defaults,
            fallback: false
        )
    }

    func resetToDefaults() {
        showIslandOnLaunch = true
        autoCollapseExpandedIsland = true
        showMusicDiagnostics = false
    }

    private func persist(_ name: String, _ value: Bool) {
        guard !isLoading else { return }
        defaults.set(value, forKey: storageKey(name))
    }

    private static func bool(named name: String, in defaults: UserDefaults, fallback: Bool) -> Bool {
        let key = storageKey(name)
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    private static func storageKey(_ name: String) -> String {
        "\(Key.prefix)\(name)"
    }

    private func storageKey(_ name: String) -> String {
        Self.storageKey(name)
    }
}

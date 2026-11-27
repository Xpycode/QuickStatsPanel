import Foundation

#if DEBUG

/// Fixture sets of the floating-tile prototype (`--floating-tiles-fixture=`). Wave 1 proves the
/// interaction loop with CPU and Network; the full eleven-stat set belongs to a later wave.
enum FloatingTileFixtureName: String, CaseIterable, Sendable {
    case cpuNetwork = "cpu-network"
    case networkCPU = "network-cpu"

    /// Saved order of the enabled stats; the first is the large tile.
    var enabledKinds: [StatKind] {
        switch self {
        case .cpuNetwork: return [.cpu, .network]
        case .networkCPU: return [.network, .cpu]
        }
    }

    /// Full saved order: the enabled stats first, the rest after them (disabled).
    var statOrder: [StatKind] {
        enabledKinds + StatKind.allCases.filter { !enabledKinds.contains($0) }
    }
}

/// Builds the prototype's isolated launch state. Nothing here touches the standard defaults
/// domain or the retained history location.
enum FloatingTileFixtures {

    /// A fresh isolated defaults suite seeded with the fixture's stat choices. Any earlier content
    /// under the same (per-launch unique) name is discarded first. Returns nil only if the suite
    /// cannot be created, in which case the caller must not fall back to standard defaults.
    static func isolatedDefaults(for options: FloatingTilePrototypeOptions) -> UserDefaults? {
        guard let defaults = UserDefaults(suiteName: options.defaultsSuiteName) else { return nil }
        defaults.removePersistentDomain(forName: options.defaultsSuiteName)
        AppSettings.seedPrototypeDefaults(defaults, statOrder: options.fixture.statOrder,
                                          enabled: options.fixture.enabledKinds, anchor: .screenCenter)
        return defaults
    }

    /// Removes the isolated defaults suite (called once the app no longer writes settings).
    static func removeIsolatedDefaults(for options: FloatingTilePrototypeOptions) {
        UserDefaults(suiteName: options.defaultsSuiteName)?.removePersistentDomain(forName: options.defaultsSuiteName)
        do { try FileManager.default.removeItem(at: options.defaultsFile) }
        catch CocoaError.fileNoSuchFile {}
        catch { NSLog("Isolated prototype defaults not removed: %@", error.localizedDescription) }
    }

    /// Disposable store: no samplers, deterministic readings, a transfer-history root of its own
    /// that is removed after the termination flush, and history period queries that publish on
    /// selection although automatic scheduling is off.
    @MainActor
    static func makeStore(options: FloatingTilePrototypeOptions) -> StatsStore {
        let root = options.historyRoot
        let store = StatsStore(transferHistoryRoot: root, transferHistoryAutomaticallySchedules: false,
                               publishesTransferQueriesOnSelection: true)
        store.disposableTransferHistoryRoot = root
        store.seedRingFixture(unavailable: [])
        store.startTransferHistory()
        return store
    }
}

#endif

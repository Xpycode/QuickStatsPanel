import Foundation
import Observation

/// App-wide, persisted user preferences. Single source of truth shared by the
/// imperative side (`AppDelegate` → `store` / `panel` / `hotKey`) and the
/// declarative side (the `Settings` scene's `SettingsView`).
///
/// **Why a singleton:** the `Settings` scene is built in `QuickStatsPanelApp`,
/// completely separate from the object graph `AppDelegate` owns. A shared
/// instance lets both edit the same state without threading a reference through
/// SwiftUI's scene environment.
///
/// **Reads vs. side-effects.** Most settings are *read* lazily at the right
/// moment — `anchor` and `stripHeight` are consulted when the panel is summoned,
/// `statOrder`/`enabledStats` are read inside the strip's `body` (Observation
/// tracks them). But two settings need an *imperative* reaction the moment they
/// change: rebinding the global hotkey, and restarting the samplers at a new
/// interval. Those fire the `onHotKeyChanged` / `onIntervalChanged` closures,
/// which `AppDelegate` wires up at launch.
@Observable
@MainActor
final class AppSettings {

    /// Shared instance. Created on first access on the main actor.
    static let shared = AppSettings()

    // MARK: - Stat selection & order

    /// Canonical display order of *all* stats. The Settings list reorders this;
    /// `visibleStats` walks it and keeps the ones that are enabled + available.
    var statOrder: [StatKind] {
        didSet { persistStatOrder(); onStatsChanged?() }
    }

    /// Which stats the user has switched on. Availability (e.g. battery on a
    /// desktop Mac) is a *separate* filter applied in `visibleStats`.
    var enabledStats: Set<StatKind> {
        didSet { persistEnabledStats(); onStatsChanged?() }
    }

    // MARK: - Sampling

    /// Seconds between sampler refreshes. Slider-bounded to a sane range in the UI.
    var interval: TimeInterval {
        didSet { defaults.set(interval, forKey: Keys.interval); onIntervalChanged?() }
    }

    // MARK: - Panel placement & size

    var anchor: PanelAnchor {
        didSet { defaults.set(anchor.rawValue, forKey: Keys.anchor) }
    }

    /// Strip height in points (D-006: ~22–44). Read at summon time.
    var stripHeight: CGFloat {
        didSet { defaults.set(Double(stripHeight), forKey: Keys.stripHeight) }
    }

    // MARK: - Hotkey

    var hotKey: HotKeyService.Binding {
        didSet {
            defaults.set(Int(hotKey.keyCode), forKey: Keys.hotKeyCode)
            defaults.set(Int(hotKey.modifiers), forKey: Keys.hotKeyModifiers)
            onHotKeyChanged?()
        }
    }

    // MARK: - First-run

    /// Whether the one-time first-run hint card has been shown. Policy (user
    /// choice): set `true` the first time the hint appears, so it never returns —
    /// even if the user missed it. A `Bool` default reads as `false` when absent,
    /// which is exactly "brand-new install → show the hint once".
    var hasSeenHint: Bool {
        didSet { defaults.set(hasSeenHint, forKey: Keys.hasSeenHint) }
    }

    // MARK: - Side-effect hooks (set by AppDelegate at launch)

    /// Re-register the global hotkey with the new binding.
    var onHotKeyChanged: (() -> Void)?
    /// Restart the samplers so they tick at the new interval.
    var onIntervalChanged: (() -> Void)?
    /// Stat set/order changed (currently informational — the strip re-reads on
    /// next summon; kept as a hook for live refresh later).
    var onStatsChanged: (() -> Void)?

    // MARK: - Init (loads from UserDefaults; falls back to defaults)

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Stat order: stored as rawValue strings; any new StatKind added to the
        // enum later is appended so it isn't silently lost.
        if let raw = defaults.array(forKey: Keys.statOrder) as? [String] {
            let restored = raw.compactMap(StatKind.init(rawValue:))
            let missing = StatKind.allCases.filter { !restored.contains($0) }
            self.statOrder = restored + missing
        } else {
            self.statOrder = StatKind.allCases
        }

        // Enabled set: absent on first run → everything on.
        //
        // Migration for stats added in a later version: a *disabled* stat and a
        // *brand-new* stat are both simply absent from the stored enabled set
        // (persistence stores only the on ones), so we can't tell them apart from
        // that alone. `knownStats` records every kind the app has shown the user;
        // a kind in `allCases` but not in `known` is genuinely new → default it ON,
        // while honoring stats the user deliberately switched off.
        if let raw = defaults.array(forKey: Keys.enabledStats) as? [String] {
            var enabled = Set(raw.compactMap(StatKind.init(rawValue:)))
            // On the first launch after `knownStats` was introduced there's no
            // record, so seed it with the five stats that shipped before it — that
            // way only the genuinely newer kinds (load/uptime/top-process) light up.
            let legacyKnown: Set<StatKind> = [.cpu, .memory, .disk, .network, .battery]
            let known = (defaults.array(forKey: Keys.knownStats) as? [String])
                .map { Set($0.compactMap(StatKind.init(rawValue:))) } ?? legacyKnown
            enabled.formUnion(StatKind.allCases.filter { !known.contains($0) })
            self.enabledStats = enabled
        } else {
            self.enabledStats = Set(StatKind.allCases)
        }
        // Record that the user has now "seen" every current stat.
        defaults.set(StatKind.allCases.map(\.rawValue), forKey: Keys.knownStats)

        let storedInterval = defaults.double(forKey: Keys.interval)
        self.interval = storedInterval > 0 ? storedInterval : 1.0

        self.anchor = (defaults.string(forKey: Keys.anchor)
            .flatMap(PanelAnchor.init(rawValue:))) ?? .cursor

        let storedHeight = defaults.double(forKey: Keys.stripHeight)
        self.stripHeight = storedHeight > 0 ? CGFloat(storedHeight) : 36

        if defaults.object(forKey: Keys.hotKeyCode) != nil {
            self.hotKey = HotKeyService.Binding(
                keyCode: UInt32(defaults.integer(forKey: Keys.hotKeyCode)),
                modifiers: UInt32(defaults.integer(forKey: Keys.hotKeyModifiers))
            )
        } else {
            self.hotKey = .default
        }

        self.hasSeenHint = defaults.bool(forKey: Keys.hasSeenHint)
    }

    // MARK: - Convenience

    func isEnabled(_ kind: StatKind) -> Bool { enabledStats.contains(kind) }

    func setEnabled(_ kind: StatKind, _ on: Bool) {
        if on { enabledStats.insert(kind) } else { enabledStats.remove(kind) }
    }

    // MARK: - Persistence helpers

    private func persistStatOrder() {
        defaults.set(statOrder.map(\.rawValue), forKey: Keys.statOrder)
    }
    private func persistEnabledStats() {
        defaults.set(enabledStats.map(\.rawValue), forKey: Keys.enabledStats)
    }

    private enum Keys {
        static let statOrder      = "statOrder"
        static let enabledStats   = "enabledStats"
        static let knownStats     = "knownStats"
        static let interval       = "interval"
        static let anchor         = "anchor"
        static let stripHeight    = "stripHeight"
        static let hotKeyCode     = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hasSeenHint    = "hasSeenHint"
    }
}

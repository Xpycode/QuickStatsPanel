import Foundation

// MARK: - Band

/// At-a-glance severity for a stat. Mapped to a color by the theme layer (a
/// preset may render these in full color, a single mono tint, or with emphasis).
enum Band: Sendable, Equatable { case calm, busy, hot }

// MARK: - BandZones

/// Band thresholds in PERCENT (0...100), matching the `loadPercent` the stats
/// already produce. Default mirrors today's behavior (calm < 50, busy < 80, hot ≥ 80).
struct BandZones: Sendable, Equatable {
    var busy: Double   // ≥ this → busy
    var hot: Double    // ≥ this → hot
    static let `default` = BandZones(busy: 50, hot: 80)
}

// MARK: - resolveBand

/// Resolve the band for a reading, applying hysteresis against the PREVIOUS band
/// so transitions need the value to cross a boundary by `margin` (percent) before
/// the color steps — killing per-tick flicker. No reference stats tool does this
/// on the live color (they rely on coarse sampling); it's our edge.
///
/// - Parameters:
///   - percent: Raw reading in 0…100.
///   - zones: Band thresholds (default: busy ≥ 50, hot ≥ 80).
///   - reversed: For "less is worse" metrics (battery charge) — invert so LOW reads as HOT.
///   - previous: Last band shown for this tile; nil on first sample (no hysteresis yet).
///   - margin: Hysteresis dead-zone half-width in percent (default 5).
///     To step UP into a hotter band, `v` must reach `threshold + margin`.
///     To step DOWN into a cooler band, `v` must fall below `threshold - margin`.
///     Within the dead zone, `previous` is returned unchanged.
func resolveBand(
    percent: Double,
    zones: BandZones = .default,
    reversed: Bool = false,
    previous: Band?,
    margin: Double = 5
) -> Band {
    // Normalize: battery charge feeds reversed=true so that 8% charge becomes v=92
    // (clearly hot) while 90% charge becomes v=10 (clearly calm). Every band
    // comparison below operates on this unified "higher = worse" scale.
    let v = reversed ? (100 - percent) : percent

    // First sample: no prior band, so no dead-zone exists yet. Plain stepped
    // thresholds give an immediate accurate reading without requiring two ticks.
    guard let previous else {
        return plainBand(v: v, zones: zones)
    }

    // Hysteresis: asymmetric thresholds prevent flicker at boundaries.
    // The dead zones are [busy-margin, busy+margin) and [hot-margin, hot+margin).
    // A value already in a band must leave its dead zone before transitioning;
    // a value crossing two dead zones in a single tick still lands in the correct
    // destination band (calm → hot is possible if v ≥ hot+margin).
    switch previous {
    case .calm:
        // Calm → hot requires clearing BOTH boundaries, otherwise calm → busy.
        // Stepping up always requires exceeding threshold + margin.
        if v >= zones.hot + margin  { return .hot  }
        if v >= zones.busy + margin { return .busy }
        return .calm

    case .busy:
        if v >= zones.hot + margin  { return .hot  }   // promoted
        if v < zones.busy - margin  { return .calm }   // demoted
        return .busy                                   // inside dead zone → hold

    case .hot:
        // Hot → calm skips through busy if v is far enough below busy-margin,
        // mirroring the calm → hot two-band jump.
        if v < zones.busy - margin { return .calm }   // crossed both downward
        if v < zones.hot - margin  { return .busy }   // stepped down one
        return .hot                                   // inside dead zone → hold
    }
}

// MARK: - Helpers

/// Plain stepped band with no hysteresis — used only on the first sample and
/// as the building block for the hysteresis logic above.
private func plainBand(v: Double, zones: BandZones) -> Band {
    if v >= zones.hot  { return .hot  }
    if v >= zones.busy { return .busy }
    return .calm
}

// MARK: - Debug Self-Check

#if DEBUG
/// Call manually in a test harness or LLDB to verify the logic.
/// Uses `assert` so failures surface immediately in debug builds without
/// polluting the production binary or auto-running at startup.
func _statusBandSelfCheck() {

    // 1. First sample — no previous, plain thresholds apply.
    assert(resolveBand(percent: 85, previous: nil) == .hot,  "85% first sample → .hot")
    assert(resolveBand(percent: 60, previous: nil) == .busy, "60% first sample → .busy")
    assert(resolveBand(percent: 10, previous: nil) == .calm, "10% first sample → .calm")

    // 2. Hysteresis around the busy/hot boundary (default zones, margin 5).
    //    previous = .busy, value approaching hot threshold (80).
    //    81 is inside the [75, 85) dead zone for the hot boundary → stays .busy.
    assert(resolveBand(percent: 81, previous: .busy) == .busy, "v=81 in dead zone → hold .busy")
    //    86 exceeds 80+5=85 → crosses into .hot.
    assert(resolveBand(percent: 86, previous: .busy) == .hot,  "v=86 clears hot+margin → .hot")

    //    previous = .hot, value retreating toward busy threshold (80).
    //    79 is inside the [75, 85) dead zone for the hot boundary → stays .hot.
    assert(resolveBand(percent: 79, previous: .hot) == .hot,  "v=79 in dead zone → hold .hot")
    //    74 is below 80-5=75 → steps down to .busy.
    assert(resolveBand(percent: 74, previous: .hot) == .busy, "v=74 clears hot-margin → .busy")

    // 3. Reversed (battery): low charge reads as hot.
    //    percent=8 → v=92 (≥ 80) → .hot; no previous so plain threshold applies.
    assert(resolveBand(percent: 8,  reversed: true, previous: nil) == .hot,
           "8% battery (reversed) first sample → .hot")
    //    percent=90 → v=10 (< 50) → .calm.
    assert(resolveBand(percent: 90, reversed: true, previous: nil) == .calm,
           "90% battery (reversed) first sample → .calm")

    // Bonus: calm → hot jump in a single tick (far enough past both thresholds).
    assert(resolveBand(percent: 91, previous: .calm) == .hot,
           "v=91 from calm clears hot+margin → .hot (two-band jump)")

    // Bonus: hot → calm jump (v well below busy-margin).
    assert(resolveBand(percent: 20, previous: .hot) == .calm,
           "v=20 from hot clears busy-margin downward → .calm (two-band jump)")
}
#endif

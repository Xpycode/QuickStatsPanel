import Foundation

/// Per-stat tile configuration: **which** value a tile headlines and **how** it's
/// drawn. Deliberately two orthogonal settings rather than one flat enum — both
/// reference products (iStat Menus, exelban/stats) separate the two, and folding
/// them together would produce a combinatorial enum that grows every time either
/// axis gains a case.
///
/// Neither reference product offers a "free *or* used" radio — iStat's element is
/// literally `USED/FREE` and Stats' Speed widget is `output/input | input/output |
/// input | output`. So the value axis is **pick-one-or-both**, matching that shape.
///
/// See D-025.

// MARK: - Value: which number the tile headlines

/// Which of a stat's two candidate values the tile shows, for the stats that have
/// a meaningful pair (Memory, Disk, Network). Stats with a single headline
/// (`StatKind.valuePair == nil`) ignore this entirely.
enum TileValueMode: String, CaseIterable, Identifiable, Sendable {
    /// Both, in the stat's natural order (Memory `Used Free`, Network `↓ ↑`).
    case both
    /// Both, swapped — for users who read the second value as the important one.
    case bothReversed
    /// The first value only.
    case first
    /// The second value only.
    case second

    var id: String { rawValue }

    /// Menu title. `pair` supplies the stat's own words so the menu reads
    /// "Used and Free" / "Down and Up" rather than generic "Both".
    func displayName(pair: (first: String, second: String)) -> String {
        switch self {
        case .both:         return "\(pair.first) and \(pair.second)"
        case .bothReversed: return "\(pair.second) and \(pair.first)"
        case .first:        return pair.first
        case .second:       return pair.second
        }
    }

    /// Whether this mode renders two sections (drives the marker prefixes below).
    var isCombined: Bool { self == .both || self == .bothReversed }
}

// MARK: - Style: how the tile is drawn

/// How a graph-capable tile renders in the **strip**. The detail card always
/// shows the graph for a graph-capable stat (matching iStat, whose dropdown
/// always carries it) — this axis governs the strip only, where width is scarce.
enum TileStyle: String, CaseIterable, Identifiable, Sendable {
    case text
    case textAndGraph
    case graph

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text:         return "Text"
        case .textAndGraph: return "Text + graph"
        case .graph:        return "Graph only"
        }
    }

    var showsText: Bool { self != .graph }
    var showsGraph: Bool { self != .text }
}

// MARK: - One renderable value section

/// A single value section of a tile, pre-formatted. `marker` is shown **only** in
/// the combined modes, where two numbers sit side by side and would otherwise be
/// ambiguous ("16,85 GB  617,24 GB" — which is which?). In single-value modes the
/// tile is unambiguous by construction, so the marker is dropped and the strip
/// stays as narrow as it is today.
struct TileValue {
    /// Full word for the Settings menu and the detail card ("Used", "Download").
    let label: String
    /// Compact prefix used in combined modes ("U", "F", "↓", "↑").
    let marker: String
    /// The formatted number ("16,85 GB").
    let text: String
    /// Worst-case width template for this section (D-008 — see `StatTileView`).
    let widest: String

    /// The string the tile draws, with the marker only when combined.
    func rendered(combined: Bool) -> String {
        combined ? "\(marker) \(text)" : text
    }

    /// Matching worst-case template, so the reserved slot grows with the marker.
    func renderedWidest(combined: Bool) -> String {
        combined ? "\(marker) \(widest)" : widest
    }
}

// MARK: - Per-stat capability

extension StatKind {

    /// The two values this stat can headline, or `nil` when it has only one.
    ///
    /// Power's `8·4 W` CPU·GPU split is deliberately absent: it is a single
    /// pre-formatted string from `PowerSampler`, and re-plumbing its formatter to
    /// fit this model would change nothing a user can see.
    var valuePair: (first: String, second: String)? {
        switch self {
        case .memory:  return ("Used", "Free")
        case .disk:    return ("Free", "Used")
        case .network: return ("Down", "Up")
        default:       return nil
        }
    }

    /// The mode a stat starts on — chosen to **reproduce today's strip exactly**,
    /// so upgrading users see no change until they ask for one. (Research found
    /// combined is the norm in both reference products; defaulting to it here
    /// would silently widen every existing user's strip on upgrade, which D-008's
    /// width discipline makes a visible event rather than a cosmetic one.)
    var defaultValueMode: TileValueMode {
        switch self {
        case .network: return .both    // ships showing ↓ and ↑ today
        default:       return .first   // Memory → Used, Disk → Free
        }
    }

    /// Whether this stat keeps history worth plotting. Rates and utilization
    /// percentages change tick-to-tick; capacity and uptime do not — a graph of
    /// free disk space is a flat line, and of uptime a diagonal one.
    var supportsGraph: Bool {
        switch self {
        case .cpu, .gpu, .memory, .network, .disk: return true
        default: return false
        }
    }

    /// How a graph for this stat is scaled vertically.
    var graphScale: GraphScale {
        switch self {
        // Already bounded 0–100 — a rebasing scale could only mislead.
        case .cpu, .gpu, .memory: return .fixed(100)
        // Byte rates have no ceiling, so each series normalizes to its own peak
        // and the graph prints that peak beside it (see `ActivityGraphView`).
        case .network, .disk:     return .perSeriesPeak
        default:                  return .fixed(100)
        }
    }
}

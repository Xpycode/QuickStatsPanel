import CoreGraphics
import Foundation

/// What a point on the ring surface selects. Rendering, hit testing, accessibility
/// and the pointer-hover highlight all speak this one vocabulary.
///
/// Geometry itself lives in `RingSizePreset`, `RingSector` and `RingLayout`; the summon
/// snapshot (`RingSnapshot`) maps a layout target onto this vocabulary.
enum RingTarget: Hashable, Sendable {
    case wedge(StatKind)
    /// The More wedge at six o'clock.
    case more
    /// The hub's gear.
    case settings
    /// The rest of the hub disc, which moves the whole ring. Never selects a stat.
    case drag
}

import CoreGraphics
import Foundation

/// Content rungs of a wedge, richest first in the spec's ladder. Raw values rank richness.
enum RingContentRung: Int, Comparable, CaseIterable, Sendable {
    case icon = 0
    case iconValue = 1
    case labelValue = 2
    case labelValueSecondary = 3

    static func < (lhs: RingContentRung, rhs: RingContentRung) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The Wedge text preference: the richest rung a wedge may use.
enum RingTextCap: Sendable {
    /// Up to label + value + secondary.
    case label
    /// Up to icon + value.
    case iconValue
    /// Icon only.
    case icon

    var maxRung: RingContentRung {
        switch self {
        case .label: return .labelValueSecondary
        case .iconValue: return .iconValue
        case .icon: return .icon
        }
    }
}

/// Measured size of a wedge's content at each rung, taken against the stat's widest
/// strings (D-008). Inputs only: the kit measures nothing itself.
struct RingRungSizes: Equatable, Sendable {
    /// `nil` when the stat has no secondary line; that rung is then skipped.
    var labelValueSecondary: CGSize?
    var labelValue: CGSize
    var iconValue: CGSize
    var icon: CGSize

    func size(for rung: RingContentRung) -> CGSize? {
        switch rung {
        case .labelValueSecondary: return labelValueSecondary
        case .labelValue: return labelValue
        case .iconValue: return iconValue
        case .icon: return icon
        }
    }
}

struct RingFavouriteInput: Equatable, Sendable {
    let kind: StatKind
    let sizes: RingRungSizes
}

/// What a point on the frozen layout selects. Hub, separators and the inactive
/// annulus select nothing (`nil`).
enum RingLayoutTarget: Equatable, Hashable, Sendable {
    /// Zero-based favourite order (favourite 1 is `0`).
    case favourite(Int)
    case more
    case gear
}

/// Frozen geometry of one summon: favourite wedges with their chosen rung and text
/// frame, the optional More wedge and the hub. Sample ticks never rebuild it.
///
/// Uses `RingSector`'s angle convention (radians clockwise from twelve o'clock, y down).
///
/// Tiling. Each sector's drawn span is its slot minus a 4-point separator, taken as an
/// angle at the sector's mid radius. With a More wedge, More is drawn 24 degrees centred
/// on six o'clock; favourites share the rest of the circle in equal slots clockwise from
/// More's trailing edge. Favourite 1 is the first slot whose centre lies at or past
/// twelve o'clock; order continues clockwise and skips More. Without More, favourites
/// share the full circle with favourite 1 centred on twelve. A lone favourite is a
/// 60-degree wedge at twelve o'clock, with or without More.
struct RingLayout: Equatable, Sendable {

    static let maxFavourites = 8
    static let moreSpan: Double = 24 * .pi / 180
    static let singleSpan: Double = 60 * .pi / 180
    static let textPadding: CGFloat = 6
    /// Gap between the gear target's glyph area and the "Settings" word.
    static let gearWordGap: CGFloat = 4

    struct Favourite: Equatable, Sendable {
        let kind: StatKind
        /// Zero-based order; favourite 1 is `0`.
        let order: Int
        let sector: RingSector
        let rung: RingContentRung
        /// Frame of the chosen rung's content, centred on the sector's centre line.
        let textFrame: CGRect
        /// False only when even the icon-only rung cannot fit with padding. The text is
        /// never shrunk; `textFrame` is then the unfitted icon frame at the mid radius.
        let fits: Bool
    }

    struct MoreWedge: Equatable, Sendable {
        let sector: RingSector
        /// Enabled non-favourite stats reachable through More.
        let count: Int
        /// Where the icon and count sit.
        let contentFrame: CGRect
        let fits: Bool
    }

    struct Hub: Equatable, Sendable {
        let center: CGPoint
        let discRadius: CGFloat
        /// At least 28 x 28 points and wholly inside the disc.
        let gearFrame: CGRect
        let showsSettingsWord: Bool

        func contains(_ point: CGPoint) -> Bool {
            hypot(point.x - center.x, point.y - center.y) <= discRadius
        }
    }

    let preset: RingSizePreset
    let center: CGPoint
    let favourites: [Favourite]
    let more: MoreWedge?
    let hub: Hub

    /// Favourites whose icon-only rung could not fit; empty when every wedge fits.
    var unfitFavourites: [Favourite] { favourites.filter { !$0.fits } }

    /// - Parameters:
    ///   - center: ring centre; defaults to the middle of the preset's footprint with band.
    ///   - favourites: ordered favourites; only the first eight are used.
    ///   - moreCount: enabled non-favourite stats; More exists when this is above zero.
    ///   - moreContentSize: measured icon + count block shown in the More wedge.
    ///   - settingsWordWidth: measured width of the word "Settings" (used only when the
    ///     preset shows it).
    init(preset: RingSizePreset,
         center: CGPoint? = nil,
         favourites inputs: [RingFavouriteInput],
         moreCount: Int,
         cap: RingTextCap = .label,
         moreContentSize: CGSize = .zero,
         settingsWordWidth: CGFloat = 0) {
        let origin = center ?? CGPoint(x: preset.footprintWithBand.width / 2,
                                       y: preset.footprintWithBand.height / 2)
        self.preset = preset
        self.center = origin

        let inner = preset.innerRadius, outer = preset.outerRadius
        let gap = Double(RingSizePreset.separator / ((inner + outer) / 2))
        let hasMore = moreCount > 0
        let used = Array(inputs.prefix(Self.maxFavourites))
        let n = used.count

        var moreWedge: MoreWedge?
        if hasMore {
            let sector = RingSector(center: origin, innerRadius: inner, outerRadius: outer,
                                    centerAngle: .pi, halfSpan: Self.moreSpan / 2)
            let frame = sector.frame(of: moreContentSize, atRadius: sector.midRadius)
            moreWedge = MoreWedge(sector: sector, count: moreCount, contentFrame: frame,
                                  fits: sector.contains(rect: frame, padding: Self.textPadding))
        }
        self.more = moreWedge

        // Slot centres and drawn half spans in geometric (clockwise) order, then the
        // favourite order that starts at the first centre at or past twelve o'clock.
        var geometric: [(center: Double, halfSpan: Double)] = []
        if n == 1 {
            geometric = [(0, Self.singleSpan / 2)]
        } else if n >= 2 {
            if hasMore {
                let moreSlot = Self.moreSpan + gap
                let slot = (2 * .pi - moreSlot) / Double(n)
                geometric = (0..<n).map { i in
                    (.pi + moreSlot / 2 + (Double(i) + 0.5) * slot, slot / 2 - gap / 2)
                }
            } else {
                let slot = 2 * .pi / Double(n)
                geometric = (0..<n).map { i in (Double(i) * slot, slot / 2 - gap / 2) }
            }
        }
        var firstIndex = 0
        if n >= 2 && hasMore {
            firstIndex = geometric.firstIndex { $0.center >= 2 * .pi - 1e-9 } ?? 0
        }
        var placed: [Favourite] = []
        for order in 0..<n {
            let slot = geometric[(firstIndex + order) % n]
            let sector = RingSector(center: origin, innerRadius: inner, outerRadius: outer,
                                    centerAngle: slot.center, halfSpan: slot.halfSpan)
            let choice = Self.choose(sizes: used[order].sizes, sector: sector, cap: cap)
            placed.append(Favourite(kind: used[order].kind, order: order, sector: sector,
                                    rung: choice.rung, textFrame: choice.frame, fits: choice.fits))
        }
        self.favourites = placed

        let disc = preset.hubDiscRadius
        let word = preset.showsSettingsWord
        var width = RingSizePreset.minGearTarget
        if word { width += Self.gearWordGap + max(0, settingsWordWidth) }
        let height = RingSizePreset.minGearTarget
        // Keep the whole target inside the disc.
        let maxWidth = 2 * (disc * disc - (height / 2) * (height / 2)).squareRoot()
        width = max(RingSizePreset.minGearTarget, min(width, maxWidth))
        self.hub = Hub(center: origin, discRadius: disc,
                       gearFrame: CGRect(x: origin.x - width / 2, y: origin.y - height / 2,
                                         width: width, height: height),
                       showsSettingsWord: word)
    }

    /// Richest rung allowed by `cap` whose frame fits with padding. If none fits the
    /// icon-only rung is returned unfitted: text is never shrunk, rotated or truncated.
    static func choose(sizes: RingRungSizes, sector: RingSector, cap: RingTextCap)
        -> (rung: RingContentRung, frame: CGRect, fits: Bool) {
        for rung in RingContentRung.allCases.reversed() where rung <= cap.maxRung {
            guard let size = sizes.size(for: rung) else { continue }
            if let frame = sector.textFrame(fitting: size, padding: textPadding) {
                return (rung, frame, true)
            }
        }
        return (.icon, sector.frame(of: sizes.icon, atRadius: sector.midRadius), false)
    }

    // MARK: Hit testing

    /// The target under `point`, or `nil` for the hub outside the gear, separators and
    /// the inactive annulus. The rest of the hub disc drags; ask `hub.contains`.
    func target(at point: CGPoint) -> RingLayoutTarget? {
        if hub.gearFrame.contains(point) { return .gear }
        if hub.contains(point) { return nil }
        if let more, more.sector.contains(point) { return .more }
        for favourite in favourites where favourite.sector.contains(point) {
            return .favourite(favourite.order)
        }
        return nil
    }

    /// The sector of a target, for highlights and travel regions.
    func sector(of target: RingLayoutTarget) -> RingSector? {
        switch target {
        case .favourite(let order): return favourites.indices.contains(order) ? favourites[order].sector : nil
        case .more: return more?.sector
        case .gear: return nil
        }
    }
}

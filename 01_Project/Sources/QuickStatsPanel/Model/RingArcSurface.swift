import CoreGraphics
import Foundation

// What a native outer-band arc needs beyond `RingArcLayout`: the surface it owns (the 6-point
// gap included), the caption slot reserved at summon, the panel's ring-space geometry, the
// route from the rendered arc and per-part gauges and accessibility. Pure values, so the
// hostless tests cover everything the arc panel draws or resolves.

// MARK: - Surface

extension RingArcLayout {
    /// The surface an open arc owns, in ring space: from the ring's outer edge to the arc's
    /// outer edge over its span, so the gap between the ring and the band belongs to the
    /// branch. The hit resolver, the arc panel frame and the travel route all read it.
    var surface: RingSector {
        RingSector(center: center, innerRadius: preset.outerRadius, outerRadius: outerRadius,
                   centerAngle: parentMidAngle, halfSpan: span / 2)
    }
}

/// A disc in screen coordinates: the favourites ring that a route from an arc never covers.
struct RingDisc: Equatable, Sendable {
    let center: CGPoint
    let radius: CGFloat

    func contains(_ point: CGPoint) -> Bool {
        hypot(point.x - center.x, point.y - center.y) < radius
    }
}

// MARK: - Caption slot

/// The hover caption of a sub-ring segment. Its slot is reserved once per summon from the
/// widest caption of the frozen part list, so showing, changing or hiding a caption never
/// resizes or moves anything.
///
/// The slot sits along the top or bottom edge of the band footprint, on the parent's side,
/// centred on the parent's direction and clamped to the footprint. The band footprint is
/// sized for the deeper More arc, so a sub-ring leaves a 20-point strip there that no arc,
/// favourite or detail card uses while the sub-ring is open.
enum RingCaption {
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 1
    /// Minimum distance between the slot and the sub-ring's outer edge.
    static let clearance: CGFloat = 1

    /// One caption line: the part's name and value, plus the collapse rule for a segment
    /// that stands for a collapsed group (AC-35).
    static func text(for part: RingPart, stat: StatKind) -> String {
        let base = "\(part.name) \(part.valueText)"
        guard part.id.hasSuffix(RingPartBuilder.collapsedSuffix), part.memberCount > 1 else { return base }
        return "\(base) \u{00B7} \(stat == .temps ? "hottest" : "highest") of \(part.memberCount)"
    }

    /// Slot size for measured caption lines: the widest plus padding.
    static func slotSize(lines: [CGSize]) -> CGSize {
        CGSize(width: ceil((lines.map(\.width).max() ?? 0) + 2 * horizontalPadding),
               height: ceil((lines.map(\.height).max() ?? 0) + 2 * verticalPadding))
    }

    /// Slot of `size` for `arc`, in ring space; `nil` when it cannot fit the footprint strip
    /// outside the arc (the sub-ring is then omitted and the card opens alone).
    static func slot(size: CGSize, arc: RingArcLayout) -> CGRect? {
        let preset = arc.preset
        let half = preset.footprintWithBand.width / 2
        let c = arc.center
        guard size.width > 0, size.height > 0, size.width <= 2 * half else { return nil }
        let top = cos(arc.parentMidAngle) >= 0
        let y = top ? c.y - half : c.y + half - size.height
        let towards = c.x + arc.outerRadius * CGFloat(sin(arc.parentMidAngle))
        let x = min(max(towards - size.width / 2, c.x - half), c.x + half - size.width)
        let slot = CGRect(x: x, y: y, width: size.width, height: size.height)
        let nearestX = max(slot.minX - c.x, 0, c.x - slot.maxX)
        let nearestY = max(slot.minY - c.y, 0, c.y - slot.maxY)
        guard hypot(nearestX, nearestY) >= arc.outerRadius + clearance else { return nil }
        return slot
    }
}

// MARK: - Panel geometry

/// Maps ring space (the base panel's top-left origin, y down) into an arc panel's own view
/// space, so the arc is drawn from the same sectors the resolver hits.
struct RingArcPanelGeometry: Equatable, Sendable {
    /// Top-left of the arc panel in ring space.
    let origin: CGPoint
    let size: CGSize

    /// - Parameters:
    ///   - panel: the arc panel's screen frame (`RingPlan.arcFrames`).
    ///   - base: the base ring panel's screen frame.
    init(panel: CGRect, base: CGRect) {
        origin = CGPoint(x: panel.minX - base.minX, y: base.maxY - panel.maxY)
        size = panel.size
    }

    func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    func local(_ sector: RingSector) -> RingSector {
        RingSector(center: local(sector.center), innerRadius: sector.innerRadius, outerRadius: sector.outerRadius,
                   centerAngle: sector.centerAngle, halfSpan: sector.halfSpan)
    }
}

// MARK: - Parts as gauges and accessibility

extension RingPart {
    /// The segment's gauge on its parent's scale and colour basis: usage (CPU) or used
    /// fraction (Disk) as a single level, download and upload halves on the log scale
    /// (Network), or the heat ramp (Temperature). A missing part draws the empty track.
    func gauge(stat: StatKind) -> RingGauge {
        guard isAvailable, let fraction else { return .unavailable(stat) }
        switch stat {
        case .network:
            return RingGauge(stat: stat, halves: RingHalves(left: fraction, right: secondFraction ?? 0,
                                                             leftPeak: nil, rightPeak: nil))
        case .temps:
            return RingGauge(stat: stat, components: [RingFillComponent(component: .level, fraction: fraction)],
                             usesHeatRamp: true)
        default:
            return RingGauge(stat: stat, components: [RingFillComponent(component: .level, fraction: fraction)])
        }
    }

    /// Read-only accessibility of the segment: name (with its group), value and the range of
    /// the scale it is drawn on.
    func accessibility(stat: StatKind) -> (label: String, value: String, range: String) {
        (label: "\(name), \(group)",
         value: isAvailable ? valueText : "Unavailable",
         range: stat.ringPartRange)
    }
}

extension StatKind {
    /// Range of a sub-ring segment's scale, in words.
    var ringPartRange: String {
        switch self {
        case .cpu: return "0 to 100 percent of the core"
        case .disk: return "0 to 100 percent of the volume used"
        case .network: return "1 KB/s to 1 GB/s on a log scale, download and upload"
        case .temps: return "30 to 100 \u{00B0}C"
        default: return ""
        }
    }
}

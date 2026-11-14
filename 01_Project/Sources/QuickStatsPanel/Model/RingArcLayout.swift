import CoreGraphics
import Foundation

/// Which child arc occupies the outer band; the kind fixes the band depth.
enum RingArcKind: Sendable {
    /// A stat's parts (cores, volumes, interfaces, sensors): 44 points deep.
    case subRing
    /// The More arc, which carries text: 64 points deep.
    case more

    var depth: CGFloat {
        switch self {
        case .subRing: return RingSizePreset.subRingDepth
        case .more: return RingSizePreset.moreArcDepth
        }
    }
}

/// One entry of an outer-band arc.
struct RingArcEntry: Equatable, Sendable {
    /// Entries of different groups are separated by the wider group gap.
    var group: Int
    /// Measured label + value block, or `nil` when the entry is never labelled.
    var labelSize: CGSize?

    init(group: Int = 0, labelSize: CGSize? = nil) {
        self.group = group
        self.labelSize = labelSize
    }
}

/// One placed entry.
struct RingArcSegment: Equatable, Sendable {
    let index: Int
    let group: Int
    let sector: RingSector
    /// Set only when the entry's measured text fits inside its sector with padding;
    /// otherwise the segment is an unlabelled sliver.
    let textFrame: CGRect?
    var isLabelled: Bool { textFrame != nil }
}

/// Layout of one arc in the outer band, computed once per summon from measured
/// entries. Uses `RingSector`'s angle convention.
///
/// Span. Each entry needs an angle: a labelled entry needs its horizontal text block's
/// projection on the segment's tangent (width and height weighted by the segment's tilt)
/// plus padding, measured at the band's inner radius (the narrowest chord); an unlabelled
/// sliver needs 8 points at that radius. A label is kept only if the block then fits
/// inside its sector, which also limits it by the band depth. The arc spans the entries' needs plus separator and
/// wider group gaps, at least the parent's span and at most a full circle, centred on
/// the parent's mid-angle. Spare span beyond the needs is shared evenly in proportion.
/// When the needs exceed a full circle, labelled entries fall back to slivers
/// (largest need first) if `allowsSlivers`; if that still does not fit, or slivers are
/// not allowed, the layout reports `.cannotFit` and places nothing. Text is never
/// shrunk.
struct RingArcLayout: Equatable, Sendable {

    enum Status: Equatable, Sendable {
        case fits
        case cannotFit
    }

    static let minSliverWidth: CGFloat = 8
    /// Gap between groups, in points at the band's inner radius (three separators).
    static let groupGap: CGFloat = 12

    let preset: RingSizePreset
    let kind: RingArcKind
    let center: CGPoint
    let parentMidAngle: Double
    let parentSpan: Double
    let status: Status
    /// Angle covered by the arc; 0 when there are no entries or the arc cannot fit.
    let span: Double
    /// Sum of needs and gaps before the parent-span minimum is applied.
    let requiredSpan: Double
    let segments: [RingArcSegment]

    var startAngle: Double { parentMidAngle - span / 2 }
    var innerRadius: CGFloat { preset.bandInnerRadius }
    var outerRadius: CGFloat { preset.bandInnerRadius + kind.depth }
    var labelledCount: Int { segments.filter(\.isLabelled).count }

    /// - Parameters:
    ///   - parentMidAngle: centre angle of the parent wedge (pi for the More arc).
    ///   - parentSpan: the parent wedge's full angular span.
    ///   - allowsSlivers: sub-rings allow unlabelled slivers; the More arc does not.
    init(preset: RingSizePreset,
         kind: RingArcKind,
         center: CGPoint? = nil,
         parentMidAngle: Double,
         parentSpan: Double,
         entries: [RingArcEntry],
         allowsSlivers: Bool = true) {
        let origin = center ?? CGPoint(x: preset.footprintWithBand.width / 2,
                                       y: preset.footprintWithBand.height / 2)
        self.preset = preset
        self.kind = kind
        self.center = origin
        self.parentMidAngle = parentMidAngle
        self.parentSpan = parentSpan

        let rIn = preset.bandInnerRadius
        let rOut = rIn + kind.depth
        let separator = Double(RingSizePreset.separator / rIn)
        let groupGap = Double(Self.groupGap / rIn)
        let sliver = Double(Self.minSliverWidth / rIn)
        let limit = 2 * Double.pi - separator
        let padding = RingLayout.textPadding

        guard !entries.isEmpty else {
            self.status = .fits
            self.span = 0
            self.requiredSpan = 0
            self.segments = []
            return
        }

        let gaps: [Double] = entries.indices.map { i in
            i == 0 ? 0 : (entries[i].group == entries[i - 1].group ? separator : groupGap)
        }
        let gapTotal = gaps.reduce(0, +)
        var labelEligible = entries.map { $0.labelSize != nil }

        // Angle a horizontal text block needs on the band's narrowest chord when its
        // segment sits at `angle`: the block's projection on the tangent, plus padding.
        func need(_ index: Int, at angle: Double) -> Double {
            guard labelEligible[index], let size = entries[index].labelSize else { return sliver }
            let along = Double(size.width) * abs(cos(angle)) + Double(size.height) * abs(sin(angle))
            return max(sliver, (along + 2 * Double(padding)) / Double(rIn))
        }

        // Centres, widths and span for given needs, centred on the parent.
        func place(_ needs: [Double]) -> (centres: [Double], widths: [Double], span: Double, total: Double) {
            let sum = needs.reduce(0, +)
            let total = sum + gapTotal
            let span = min(2 * Double.pi, max(total, parentSpan))
            let full = span >= 2 * Double.pi - 1e-9
            let scale = max(0, span - gapTotal - (full ? separator : 0)) / sum
            var cursor = parentMidAngle - span / 2
            var centres: [Double] = [], widths: [Double] = []
            for i in needs.indices {
                cursor += gaps[i]
                let width = needs[i] * scale
                centres.append(cursor + width / 2)
                widths.append(width)
                cursor += width
            }
            return (centres, widths, span, total)
        }

        // Needs depend on where a segment lands and placement depends on the needs;
        // a few passes settle it (needs only grow with tilt, so the estimate converges).
        func solve() -> [Double] {
            var angles = [Double](repeating: parentMidAngle, count: entries.count)
            var needs = entries.indices.map { need($0, at: angles[$0]) }
            for _ in 0..<4 {
                angles = place(needs).centres
                needs = entries.indices.map { need($0, at: angles[$0]) }
            }
            return needs
        }

        var needs = solve()
        var total = needs.reduce(0, +) + gapTotal
        if total > limit && allowsSlivers {
            // Largest labelled need gives way first, then re-solve with the new tilts.
            while total > limit, let widest = needs.indices.filter({ labelEligible[$0] }).max(by: { needs[$0] < needs[$1] }) {
                labelEligible[widest] = false
                needs = solve()
                total = needs.reduce(0, +) + gapTotal
            }
        }
        if total > limit {
            self.status = .cannotFit
            self.span = 0
            self.requiredSpan = total
            self.segments = []
            return
        }

        let layout = place(needs)
        var placed: [RingArcSegment] = []
        for i in entries.indices {
            let sector = RingSector(center: origin, innerRadius: rIn, outerRadius: rOut,
                                    centerAngle: layout.centres[i], halfSpan: layout.widths[i] / 2)
            var frame: CGRect?
            if labelEligible[i], let size = entries[i].labelSize {
                frame = sector.textFrame(fitting: size, padding: padding)
            }
            placed.append(RingArcSegment(index: i, group: entries[i].group, sector: sector, textFrame: frame))
        }
        let span = layout.span

        if !allowsSlivers && placed.contains(where: { !$0.isLabelled }) {
            self.status = .cannotFit
            self.span = 0
            self.requiredSpan = total
            self.segments = []
            return
        }
        self.status = .fits
        self.span = span
        self.requiredSpan = total
        self.segments = placed
    }

    /// Index of the entry under `point`; `nil` for gaps and everything outside the arc.
    func entry(at point: CGPoint) -> Int? {
        segments.first { $0.sector.contains(point) }?.index
    }
}

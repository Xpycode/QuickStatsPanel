import CoreGraphics
import Foundation

/// What a point on the ring surface selects. Rendering, hit testing, accessibility
/// and the pointer-hover highlight all speak this one vocabulary.
enum RingTarget: Hashable, Sendable {
    case wedge(StatKind)
    case more
    case settings
    /// Dedicated hub area that moves the whole ring. Never selects a stat.
    case drag
}

/// Immutable geometry for one summon of the favourite ring (D-034 review baseline:
/// 100/260-point radii, 520 x 520 footprint, text centred at radius 185).
///
/// Coordinates are the ring view's own space: origin top-left, y grows downward, so
/// the SwiftUI drawing and the flipped AppKit input view consume the values
/// unchanged. Angles are radians measured clockwise from twelve o'clock.
///
/// Rendering and hit testing both read this value; nothing re-resolves it on a
/// sample tick. Stat identity and slot positions depend only on the ordered kinds
/// given at construction, never on readings.
struct RingGeometry: Equatable, Sendable {

    static let innerRadius: CGFloat = 100
    static let outerRadius: CGFloat = 260
    static let textRadius: CGFloat = 185
    static let footprint = CGSize(width: 520, height: 520)
    static let maxFavourites = 8
    /// Separator between neighbouring wedges, in points at the text radius.
    static let separatorGap: CGFloat = 4
    /// A lone favourite occupies a 60-degree wedge at twelve o'clock.
    static let singleWedgeSpan: Double = .pi / 3
    /// Clearance kept between a text block and every wedge edge.
    static let textPadding: CGFloat = 6
    /// Hub disc; the strip between it and the inner radius selects nothing.
    static let hubRadius: CGFloat = innerRadius - 8
    static let minTargetHeight: CGFloat = 28

    struct Wedge: Equatable, Sendable {
        let kind: StatKind
        let slot: Int
        /// Slot centre angle. Frozen for the summon.
        let centerAngle: Double
        /// Half of the drawn/hit angular extent (slot span minus separator gap).
        let halfSpan: Double
        /// Measured horizontal text block, centred at `textRadius` on `centerAngle`.
        let textRect: CGRect

        var startAngle: Double { centerAngle - halfSpan }
        var endAngle: Double { centerAngle + halfSpan }
    }

    let size: CGSize
    let center: CGPoint
    let wedges: [Wedge]
    /// `nil` when no enabled non-favourite stat remains.
    let moreFrame: CGRect?
    let settingsFrame: CGRect
    let moreCount: Int

    /// - Parameters:
    ///   - favourites: ordered kinds (at most eight are used) with the measured
    ///     size of each one's worst-case text block.
    ///   - moreCount: enabled non-favourite stats reachable through More.
    init(favourites: [(kind: StatKind, textSize: CGSize)], moreCount: Int) {
        let size = Self.footprint
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        self.size = size
        self.center = center
        self.moreCount = moreCount

        let used = Array(favourites.prefix(Self.maxFavourites))
        let n = used.count
        let slotSpan = n >= 2 ? 2 * Double.pi / Double(n) : Self.singleWedgeSpan
        let halfSpan: Double = n >= 2
            ? slotSpan / 2 - Double(Self.separatorGap / Self.textRadius) / 2
            : Self.singleWedgeSpan / 2
        self.wedges = used.enumerated().map { index, entry in
            let angle = n >= 2 ? slotSpan * Double(index) : 0
            let anchor = Self.point(center: center, angle: angle, radius: Self.textRadius)
            let rect = CGRect(x: anchor.x - entry.textSize.width / 2,
                              y: anchor.y - entry.textSize.height / 2,
                              width: entry.textSize.width, height: entry.textSize.height)
            return Wedge(kind: entry.kind, slot: index, centerAngle: angle,
                         halfSpan: halfSpan, textRect: rect)
        }

        // Hub controls: disjoint, each at least 28 points high, fully inside the hub
        // disc. Settings keeps its position whether or not More exists.
        self.moreFrame = moreCount > 0
            ? CGRect(x: center.x - 52, y: center.y - 38, width: 104, height: 32) : nil
        self.settingsFrame = CGRect(x: center.x - 40, y: center.y + 2, width: 80, height: 30)
    }

    // MARK: Hit testing

    func target(at point: CGPoint) -> RingTarget? {
        let dx = point.x - center.x, dy = point.y - center.y
        let radius = hypot(dx, dy)
        if radius <= Self.hubRadius {
            if let moreFrame, moreFrame.contains(point) { return .more }
            if settingsFrame.contains(point) { return .settings }
            return .drag
        }
        for wedge in wedges where contains(point, in: wedge) { return .wedge(wedge.kind) }
        return nil
    }

    /// Whether `point` lies in the drawn annular sector of `wedge`: the single
    /// definition used by hit testing and the text-containment check.
    func contains(_ point: CGPoint, in wedge: Wedge) -> Bool {
        let dx = point.x - center.x, dy = point.y - center.y
        let radius = hypot(dx, dy)
        guard radius >= Self.innerRadius, radius <= Self.outerRadius else { return false }
        let angle = atan2(dx, -dy)
        return abs(Self.wrapped(angle - wedge.centerAngle)) <= wedge.halfSpan
    }

    /// True when the padded text block lies entirely inside the wedge. The wedge is
    /// simply connected, so a boundary that stays inside encloses an inside interior;
    /// the perimeter is sampled every point.
    func textFits(_ wedge: Wedge, padding: CGFloat = RingGeometry.textPadding) -> Bool {
        let rect = wedge.textRect.insetBy(dx: -padding, dy: -padding)
        let step: CGFloat = 1
        var x = rect.minX
        while x <= rect.maxX + 0.001 {
            if !contains(CGPoint(x: x, y: rect.minY), in: wedge) { return false }
            if !contains(CGPoint(x: x, y: rect.maxY), in: wedge) { return false }
            x += step
        }
        var y = rect.minY
        while y <= rect.maxY + 0.001 {
            if !contains(CGPoint(x: rect.minX, y: y), in: wedge) { return false }
            if !contains(CGPoint(x: rect.maxX, y: y), in: wedge) { return false }
            y += step
        }
        return true
    }

    // MARK: Drawing and frames

    /// Closed polygon of the wedge (outer arc then inner arc back), 2-degree steps.
    func outline(of wedge: Wedge) -> [CGPoint] {
        let steps = max(2, Int((2 * wedge.halfSpan / (Double.pi / 90)).rounded(.up)))
        var points: [CGPoint] = []
        for i in 0...steps {
            let t = wedge.startAngle + (wedge.endAngle - wedge.startAngle) * Double(i) / Double(steps)
            points.append(Self.point(center: center, angle: t, radius: Self.outerRadius))
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let t = wedge.startAngle + (wedge.endAngle - wedge.startAngle) * Double(i) / Double(steps)
            points.append(Self.point(center: center, angle: t, radius: Self.innerRadius))
        }
        return points
    }

    /// Frame of a target in ring space; the reserved parent frame for detail placement.
    func frame(of target: RingTarget) -> CGRect? {
        switch target {
        case .wedge(let kind):
            guard let wedge = wedges.first(where: { $0.kind == kind }) else { return nil }
            let points = outline(of: wedge)
            guard let first = points.first else { return nil }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for p in points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .more: return moreFrame
        case .settings: return settingsFrame
        case .drag: return CGRect(x: center.x - Self.hubRadius, y: center.y - Self.hubRadius,
                                  width: Self.hubRadius * 2, height: Self.hubRadius * 2)
        }
    }

    // MARK: Helpers

    static func point(center: CGPoint, angle: Double, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(sin(angle)),
                y: center.y - radius * CGFloat(cos(angle)))
    }

    /// Normalise to (-pi, pi].
    static func wrapped(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi } else if a <= -.pi { a += 2 * .pi }
        return a
    }
}

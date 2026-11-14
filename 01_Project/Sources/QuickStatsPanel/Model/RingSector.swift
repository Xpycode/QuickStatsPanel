import CoreGraphics
import Foundation

/// Size preset for the gauge ring (D-035). A preset fixes geometry only; text is
/// 13/16/12 points in every preset and never scales.
enum RingSizePreset: String, CaseIterable, Sendable {
    case small, medium, large

    /// Outer diameter of the favourites ring alone.
    var outerDiameter: CGFloat {
        switch self {
        case .small: return 260
        case .medium: return 360
        case .large: return 460
        }
    }

    var outerRadius: CGFloat { outerDiameter / 2 }
    /// 36 % of the outer radius, rounded to whole points (47 / 65 / 83).
    var innerRadius: CGFloat { (outerRadius * Self.innerRadiusFraction).rounded() }
    var wedgeDepth: CGFloat { outerRadius - innerRadius }

    static let innerRadiusFraction: CGFloat = 0.36
    /// Gap between neighbouring sectors, measured along the arc at the sector's mid radius.
    static let separator: CGFloat = 4
    /// The outer band starts this far outside the favourites ring.
    static let bandGap: CGFloat = 6
    static let subRingDepth: CGFloat = 44
    static let moreArcDepth: CGFloat = 64
    /// Hub disc radius is the inner radius minus this much.
    static let hubInset: CGFloat = 6
    static let minGearTarget: CGFloat = 28
    /// The word "Settings" appears beside the gear only when the disc is at least this large.
    static let settingsWordMinDiscRadius: CGFloat = 58
    static let labelTextSize: CGFloat = 13
    static let valueTextSize: CGFloat = 16
    static let secondaryTextSize: CGFloat = 12

    var bandInnerRadius: CGFloat { outerRadius + Self.bandGap }
    var hubDiscRadius: CGFloat { innerRadius - Self.hubInset }
    var showsSettingsWord: Bool { hubDiscRadius >= Self.settingsWordMinDiscRadius }

    /// Square footprint of the favourites ring alone.
    var footprintRingOnly: CGSize { CGSize(width: outerDiameter, height: outerDiameter) }
    /// Square footprint reserving the deepest outer band (the More arc): 400 / 500 / 600.
    var footprintWithBand: CGSize {
        let side = 2 * (outerRadius + Self.bandGap + Self.moreArcDepth)
        return CGSize(width: side, height: side)
    }
}

/// An annular sector: the one primitive behind wedges, partial fills, the Disk rim,
/// left/right halves and outer-band segments. Rendering and hit testing read the same
/// value.
///
/// Angle convention: radians, measured **clockwise from twelve o'clock**. Coordinates
/// are view space with the origin top-left and y growing downward, so a point at angle
/// `a` and radius `r` is `(cx + r*sin(a), cy - r*cos(a))`. The sector covers
/// `centerAngle - halfSpan ... centerAngle + halfSpan` and `innerRadius ... outerRadius`,
/// boundaries included. A `halfSpan` of pi is a full annulus.
struct RingSector: Equatable, Sendable {

    /// Halves of a sector, split along its centre line and named as seen from the
    /// centre looking outward: `left` is the counter-clockwise half (smaller angles),
    /// `right` the clockwise half.
    enum Half: Sendable { case left, right }

    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let centerAngle: Double
    let halfSpan: Double

    /// Largest angular step between outline vertices (2 degrees).
    static let outlineStep: Double = .pi / 90
    private static let epsilon: CGFloat = 1e-6

    init(center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat,
         centerAngle: Double, halfSpan: Double) {
        let outer = max(0, outerRadius)
        self.center = center
        self.outerRadius = outer
        self.innerRadius = min(max(0, innerRadius), outer)
        self.centerAngle = centerAngle
        self.halfSpan = min(max(0, halfSpan), .pi)
    }

    var startAngle: Double { centerAngle - halfSpan }
    var endAngle: Double { centerAngle + halfSpan }
    var span: Double { 2 * halfSpan }
    var depth: CGFloat { outerRadius - innerRadius }
    var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }
    var isFullCircle: Bool { halfSpan >= .pi - 1e-9 }
    /// Geometric area; for an equal-area fill the fraction of this area is the fraction filled.
    var area: Double { halfSpan * Double(outerRadius * outerRadius - innerRadius * innerRadius) }

    // MARK: Hit testing

    func contains(_ point: CGPoint) -> Bool {
        let dx = point.x - center.x, dy = point.y - center.y
        let radius = hypot(dx, dy)
        guard radius >= innerRadius - Self.epsilon, radius <= outerRadius + Self.epsilon else { return false }
        return containsAngle(of: dx, dy)
    }

    private func containsAngle(of dx: CGFloat, _ dy: CGFloat) -> Bool {
        if isFullCircle { return true }
        if dx == 0 && dy == 0 { return true }
        let angle = atan2(Double(dx), Double(-dy))
        return abs(Self.wrapped(angle - centerAngle)) <= halfSpan + 1e-12
    }

    /// True when `rect`, grown by `padding` on every side, lies wholly inside the sector.
    func contains(rect: CGRect, padding: CGFloat = 0) -> Bool {
        let r = rect.insetBy(dx: -padding, dy: -padding)
        guard !r.isNull, !r.isInfinite, r.width >= 0, r.height >= 0 else { return false }
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        for corner in corners where hypot(corner.x - center.x, corner.y - center.y) > outerRadius + Self.epsilon {
            return false
        }
        let nearestX = max(r.minX - center.x, 0, center.x - r.maxX)
        let nearestY = max(r.minY - center.y, 0, center.y - r.maxY)
        if hypot(nearestX, nearestY) < innerRadius - Self.epsilon { return false }
        if isFullCircle { return true }
        if halfSpan <= .pi / 2 {
            // A wedge of at most 90 degrees is convex: its corners decide.
            return corners.allSatisfy { containsAngle(of: $0.x - center.x, $0.y - center.y) }
        }
        // Wider wedges are not convex; sample the perimeter every point.
        var x = r.minX
        while x <= r.maxX + 0.001 {
            if !containsAngle(of: x - center.x, r.minY - center.y) { return false }
            if !containsAngle(of: x - center.x, r.maxY - center.y) { return false }
            x += 1
        }
        var y = r.minY
        while y <= r.maxY + 0.001 {
            if !containsAngle(of: r.minX - center.x, y - center.y) { return false }
            if !containsAngle(of: r.maxX - center.x, y - center.y) { return false }
            y += 1
        }
        return true
    }

    /// A frame of `size`, centred on the sector's centre line, that fits inside the
    /// sector with `padding` clearance. Prefers the mid radius and moves outward and
    /// inward in one-point steps; `nil` when no position fits.
    func textFrame(fitting size: CGSize, padding: CGFloat) -> CGRect? {
        let steps = Int((depth / 2).rounded(.up))
        for step in 0...max(0, steps) {
            for sign in (step == 0 ? [CGFloat(1)] : [1, -1]) {
                let radius = midRadius + sign * CGFloat(step)
                guard radius >= innerRadius, radius <= outerRadius else { continue }
                let candidate = frame(of: size, atRadius: radius)
                if contains(rect: candidate, padding: padding) { return candidate }
            }
        }
        return nil
    }

    /// A frame of `size` centred on the centre line at `radius`.
    func frame(of size: CGSize, atRadius radius: CGFloat) -> CGRect {
        let anchor = Self.point(center: center, angle: centerAngle, radius: radius)
        return CGRect(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    // MARK: Drawing and frames

    /// Closed polygon: the outer arc in increasing angle, then the inner arc back,
    /// at most 2 degrees per step. Drawing uses this same polygon.
    var outline: [CGPoint] {
        let steps = max(2, Int((span / Self.outlineStep).rounded(.up)))
        var points: [CGPoint] = []
        points.reserveCapacity(2 * (steps + 1))
        for i in 0...steps {
            let t = startAngle + span * Double(i) / Double(steps)
            points.append(Self.point(center: center, angle: t, radius: outerRadius))
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let t = startAngle + span * Double(i) / Double(steps)
            points.append(Self.point(center: center, angle: t, radius: innerRadius))
        }
        return points
    }

    /// `outline` as a closed path in the same coordinates.
    var cgPath: CGPath {
        let path = CGMutablePath()
        let points = outline
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    /// Exact bounding box of the sector (corners plus the axis crossings of the outer arc).
    var boundingFrame: CGRect {
        var points = [
            Self.point(center: center, angle: startAngle, radius: outerRadius),
            Self.point(center: center, angle: endAngle, radius: outerRadius),
            Self.point(center: center, angle: startAngle, radius: innerRadius),
            Self.point(center: center, angle: endAngle, radius: innerRadius),
        ]
        for k in 0..<4 {
            let axis = Double(k) * .pi / 2
            if isFullCircle || abs(Self.wrapped(axis - centerAngle)) <= halfSpan {
                points.append(Self.point(center: center, angle: axis, radius: outerRadius))
            }
        }
        var minX = points[0].x, maxX = points[0].x, minY = points[0].y, maxY = points[0].y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: Constructors

    /// Same angles, radial sub-range (clamped to this sector's radii).
    func subSector(innerRadius inner: CGFloat, outerRadius outer: CGFloat) -> RingSector {
        let lo = min(max(inner, innerRadius), outerRadius)
        let hi = min(max(outer, lo), outerRadius)
        return RingSector(center: center, innerRadius: lo, outerRadius: hi,
                          centerAngle: centerAngle, halfSpan: halfSpan)
    }

    /// The part of the sector from the inner edge out to the fill reached by `fraction`.
    func filled(to fraction: Double, scale: RingFillScale) -> RingSector {
        let r = scale.radius(fraction: fraction, inner: innerRadius, outer: outerRadius)
        return subSector(innerRadius: innerRadius, outerRadius: r)
    }

    /// The thin outer strip of `thickness` points (the Disk I/O rim).
    func rim(thickness: CGFloat) -> RingSector {
        subSector(innerRadius: outerRadius - thickness, outerRadius: outerRadius)
    }

    /// One half of the sector, split along its centre line.
    func half(_ side: Half) -> RingSector {
        let quarter = halfSpan / 2
        let offset = side == .left ? -quarter : quarter
        return RingSector(center: center, innerRadius: innerRadius, outerRadius: outerRadius,
                          centerAngle: centerAngle + offset, halfSpan: quarter)
    }

    /// Same radii and centre angle with a different half span.
    func withHalfSpan(_ newHalfSpan: Double) -> RingSector {
        RingSector(center: center, innerRadius: innerRadius, outerRadius: outerRadius,
                   centerAngle: centerAngle, halfSpan: newHalfSpan)
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

/// How a gauge fraction maps to a radius inside a sector.
enum RingFillScale: String, CaseIterable, Sendable {
    /// Filled annulus area ÷ total annulus area equals the fraction (default).
    case area
    /// Filled depth ÷ total depth equals the fraction.
    case linear

    static let referenceFractions: [Double] = [0.25, 0.5, 0.75]
    /// Adjacent reference arcs closer than this leave only the 50 % arc.
    static let minReferenceSpacing: CGFloat = 8

    /// Clamp to 0...1; NaN counts as 0.
    static func clamped(_ fraction: Double) -> Double {
        fraction.isNaN ? 0 : min(max(fraction, 0), 1)
    }

    func radius(fraction: Double, inner: CGFloat, outer: CGFloat) -> CGFloat {
        let f = Self.clamped(fraction)
        let r0 = Double(inner), r1 = Double(max(outer, inner))
        switch self {
        case .area: return CGFloat((r0 * r0 + f * (r1 * r1 - r0 * r0)).squareRoot())
        case .linear: return CGFloat(r0 + f * (r1 - r0))
        }
    }

    /// Outer radius of each prefix of a stack of component fractions. Components
    /// accumulate; the stack's reach is clamped at the outer edge.
    func cumulativeRadii(fractions: [Double], inner: CGFloat, outer: CGFloat) -> [CGFloat] {
        var total = 0.0
        return fractions.map { component in
            total = min(1, total + Self.clamped(component))
            return radius(fraction: total, inner: inner, outer: outer)
        }
    }

    /// Radii of the dotted reference arcs at 25/50/75 %. When any two adjacent arcs
    /// would be less than 8 points apart only the 50 % arc remains.
    func referenceRadii(inner: CGFloat, outer: CGFloat) -> [CGFloat] {
        let radii = Self.referenceFractions.map { radius(fraction: $0, inner: inner, outer: outer) }
        for i in 1..<radii.count where radii[i] - radii[i - 1] < Self.minReferenceSpacing {
            return [radii[1]]
        }
        return radii
    }
}

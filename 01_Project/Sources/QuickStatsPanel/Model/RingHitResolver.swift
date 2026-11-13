import CoreGraphics
import Foundation

/// Hub controls that are not expansion nodes.
enum RingSpecial: Equatable, Sendable {
    case settings
    case drag
}

/// Pure resolution of a screen point against the frozen plan and the panels' actual
/// frames. Kept out of the panel controller so the inert/outside distinction is testable.
///
/// Inert space (separator gaps, the band between hub and inner radius, the inactive
/// annulus, gaps between More entries) selects nothing but is still inside the HUD: only
/// points beyond the outer radius (or outside every panel) are "outside".
struct RingHitResolver {
    var plan: RingPlan
    /// Actual screen frame of the base panel (ring or whole list).
    var baseFrame: CGRect
    var geometry: RingGeometry
    var openDetailKind: StatKind?
    var moreOpen: Bool
    var moreGeometry: RingMoreGeometry?
    var sideList: RingListLayout?
    var wholeList: RingListLayout?

    func resolve(_ p: CGPoint) -> (hit: RingHit, special: RingSpecial?) {
        if let kind = openDetailKind, let frame = plan.detailFrames[kind], frame.contains(p) {
            return (.detail, nil)
        }
        func local(_ frame: CGRect) -> CGPoint { CGPoint(x: p.x - frame.minX, y: frame.maxY - p.y) }

        if plan.mode == .wholeList {
            guard let layout = wholeList, baseFrame.contains(p) else { return (.none, nil) }
            switch layout.hit(at: local(baseFrame)) {
            case .drag?: return (.inert, .drag)
            case .settings?: return (.inert, .settings)
            case .node(let node)?: return (.node(node), nil)
            case nil: return (.inert, nil)
            }
        }

        if moreOpen, let surface = plan.moreSurface, surface.contains(p) {
            let point = local(surface)
            if plan.mode == .sideList, let layout = sideList {
                if case .node(let node)? = layout.hit(at: point) { return (.node(node), nil) }
                return (.moreSurface, nil)
            }
            if plan.mode == .outerRing, let ring = moreGeometry {
                if let kind = ring.target(at: point) { return (.node(.moreItem(kind)), nil) }
            }
        }

        if baseFrame.contains(p) {
            let point = local(baseFrame)
            if hypot(point.x - geometry.center.x, point.y - geometry.center.y) <= RingGeometry.outerRadius {
                switch geometry.target(at: point) {
                case .wedge(let kind)?: return (.node(.wedge(kind)), nil)
                case .more?: return (.node(.more), nil)
                case .settings?: return (.inert, .settings)
                case .drag?: return (.inert, .drag)
                case nil: return (.inert, nil)
                }
            }
        }

        // Between the base ring and the More ring, and its gaps: inside the open branch.
        if moreOpen, plan.mode == .outerRing, let surface = plan.moreSurface, surface.contains(p),
           let ring = moreGeometry {
            let point = local(surface)
            if hypot(point.x - ring.center.x, point.y - ring.center.y) <= RingMoreGeometry.outerRadius {
                return (.moreSurface, nil)
            }
        }
        return (.none, nil)
    }
}

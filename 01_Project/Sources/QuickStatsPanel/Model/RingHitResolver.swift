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
/// annulus) selects nothing but is still inside the HUD: only
/// points beyond the outer radius (or outside every panel) are "outside".
struct RingHitResolver {
    var plan: RingPlan
    /// Actual screen frame of the base panel (ring or whole list).
    var baseFrame: CGRect
    /// The summon snapshot: its frozen layout answers every ring-space hit.
    var snapshot: RingSnapshot
    var openDetailKind: StatKind?
    var moreOpen: Bool
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
        }

        if baseFrame.contains(p) {
            let point = local(baseFrame)
            let layout = snapshot.layout
            if hypot(point.x - layout.center.x, point.y - layout.center.y) <= layout.preset.outerRadius {
                switch snapshot.target(at: point) {
                case .wedge(let kind)?: return (.node(.wedge(kind)), nil)
                case .more?: return (.node(.more), nil)
                case .settings?: return (.inert, .settings)
                case .drag?: return (.inert, .drag)
                case nil: return (.inert, nil)
                }
            }
        }

        return (.none, nil)
    }
}

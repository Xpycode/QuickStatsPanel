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
/// points beyond the outer radius (or outside every panel) are "outside". An open arc
/// adds its surface from the ring's outer edge to the arc's outer edge over its span, so the
/// gap between parent and arc is inside its branch.
struct RingHitResolver {
    var plan: RingPlan
    /// Actual screen frame of the base panel (ring or whole list).
    var baseFrame: CGRect
    /// The summon snapshot: its frozen layout and arcs answer every ring-space hit.
    var snapshot: RingSnapshot
    var openDetailKind: StatKind?
    /// Owner of the open arc (or of the side More list).
    var openArc: RingArcOwner?
    var sideList: RingListLayout?
    var wholeList: RingListLayout?

    init(plan: RingPlan, baseFrame: CGRect, snapshot: RingSnapshot, openDetailKind: StatKind?,
         openArc: RingArcOwner?, sideList: RingListLayout?, wholeList: RingListLayout?) {
        self.plan = plan
        self.baseFrame = baseFrame
        self.snapshot = snapshot
        self.openDetailKind = openDetailKind
        self.openArc = openArc
        self.sideList = sideList
        self.wholeList = wholeList
    }

    func resolveBranch(_ p: CGPoint) -> (hit: RingBranchHit, special: RingSpecial?) {
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

        if openArc == .more, let surface = plan.moreSurface, surface.contains(p), let layout = sideList {
            if case .node(let node)? = layout.hit(at: local(surface)) { return (.node(node), nil) }
            return (.arc(.more), nil)
        }

        let point = local(baseFrame)
        let layout = snapshot.layout
        if baseFrame.contains(p),
           hypot(point.x - layout.center.x, point.y - layout.center.y) <= layout.preset.outerRadius {
            switch snapshot.target(at: point) {
            case .wedge(let kind)?: return (.node(.wedge(kind)), nil)
            case .more?: return (.node(.more), nil)
            case .settings?: return (.inert, .settings)
            case .drag?: return (.inert, .drag)
            case nil: return (.inert, nil)
            }
        }

        if let owner = openArc, plan.arcFrames[owner] != nil, let arc = snapshot.arcs[owner],
           let hit = arcHit(owner: owner, arc: arc, at: point) {
            return (hit, nil)
        }

        return (.none, nil)
    }

    /// `point` is in the base panel's ring space, which is also the arc's.
    private func arcHit(owner: RingArcOwner, arc: RingArcLayout, at point: CGPoint) -> RingBranchHit? {
        guard arc.span > 0 else { return nil }
        let surface = RingSector(center: arc.center, innerRadius: snapshot.preset.outerRadius,
                                 outerRadius: arc.outerRadius, centerAngle: arc.parentMidAngle,
                                 halfSpan: arc.span / 2)
        guard surface.contains(point) else { return nil }
        if let index = arc.entry(at: point) {
            switch owner {
            case .more:
                if snapshot.moreKinds.indices.contains(index) { return .node(.moreItem(snapshot.moreKinds[index])) }
            case .stat(let kind):
                return .segment(RingSegmentRef(stat: kind, index: index))
            }
        }
        return .arc(owner)
    }
}

// MARK: - Compatibility for RingPanelController (removed by 4.1)

extension RingHitResolver {
    init(plan: RingPlan, baseFrame: CGRect, snapshot: RingSnapshot, openDetailKind: StatKind?,
         moreOpen: Bool, sideList: RingListLayout?, wholeList: RingListLayout?) {
        self.init(plan: plan, baseFrame: baseFrame, snapshot: snapshot, openDetailKind: openDetailKind,
                  openArc: moreOpen ? .more : nil, sideList: sideList, wholeList: wholeList)
    }

    func resolve(_ p: CGPoint) -> (hit: RingHit, special: RingSpecial?) {
        let resolved = resolveBranch(p)
        return (RingHit(resolved.hit), resolved.special)
    }
}

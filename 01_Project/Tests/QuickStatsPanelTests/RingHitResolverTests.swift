import XCTest

/// Hostless checks that inert ring space stays inside the HUD and only true outside is "none".
final class RingHitResolverTests: XCTestCase {

    private let base = CGRect(x: 100, y: 100, width: 360, height: 360)

    private func reading(_ kind: StatKind) -> RingReading {
        RingReading(value: "42%", widestValue: kind.ringFallbackWidest)
    }

    private func resolver(_ kinds: [StatKind], favourites: [StatKind]? = nil, moreOpen: Bool = false,
                          preset: RingSizePreset = .medium) -> (RingHitResolver, RingSnapshot) {
        let s = RingSnapshot.make(enabledKinds: kinds, favourites: favourites, preset: preset, reading: reading)
        let sizes = Dictionary(uniqueKeysWithValues: kinds.map { ($0, CGSize(width: 300, height: 300)) })
        let visible = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        let plan = RingPlacement.resolve(.init(snapshot: s, visible: visible, preferredBase: base, detailSizes: sizes))
        var list: RingListLayout?
        if let surface = plan.moreSurface {
            list = RingListLayout(size: surface.size, rows: s.moreKinds.map { .moreItem($0) }, hasChrome: false)
        }
        return (RingHitResolver(plan: plan, baseFrame: plan.baseFrame, snapshot: s, openDetailKind: nil,
                                moreOpen: moreOpen, sideList: list, wholeList: nil), s)
    }

    private func screen(_ r: RingHitResolver, degrees: Double, radius: CGFloat) -> CGPoint {
        let local = RingSector.point(center: r.snapshot.layout.center, angle: degrees * .pi / 180, radius: radius)
        return CGPoint(x: r.baseFrame.minX + local.x, y: r.baseFrame.maxY - local.y)
    }

    func testSeparatorGapInnerBandAndInactiveAnnulusAreInertNotOutside() {
        let (six, _) = resolver([.cpu, .memory, .disk, .network, .gpu, .temps])
        XCTAssertEqual(six.resolve(screen(six, degrees: 0, radius: 120)).hit, .node(.wedge(.cpu)))
        XCTAssertEqual(six.resolve(screen(six, degrees: 30, radius: 120)).hit, .inert, "separator gap")
        // Medium: hub disc 59, inner radius 65; the band between them selects nothing.
        XCTAssertEqual(six.resolve(screen(six, degrees: 0, radius: 62)).hit, .inert, "band between hub and inner radius")

        let (one, _) = resolver([.cpu])
        XCTAssertEqual(one.resolve(screen(one, degrees: 180, radius: 120)).hit, .inert, "inactive annulus")
    }

    func testOnlyBeyondTheOuterRadiusOrOutsideTheFrameIsNone() {
        for preset in RingSizePreset.allCases {
            let (r, _) = resolver([.cpu, .memory, .disk, .network, .gpu, .temps], preset: preset)
            XCTAssertEqual(r.resolve(screen(r, degrees: 45, radius: preset.outerRadius + 5)).hit, .none, "\(preset)")
            XCTAssertEqual(r.resolve(CGPoint(x: r.baseFrame.minX + 3, y: r.baseFrame.minY + 3)).hit, .none,
                           "\(preset): transparent corner")
        }
        let (r, _) = resolver([.cpu])
        XCTAssertEqual(r.resolve(CGPoint(x: -50, y: -50)).hit, .none)
    }

    func testHubOffersOnlyTheGearAndTheDragArea() {
        for preset in RingSizePreset.allCases {
            let (r, s) = resolver([.cpu, .memory], preset: preset)
            let c = CGPoint(x: r.baseFrame.midX, y: r.baseFrame.midY)
            XCTAssertEqual(r.resolve(c).special, .settings, "\(preset): gear")
            XCTAssertEqual(r.resolve(c).hit, .inert, "a hub control is never an expansion node")
            let drag = CGPoint(x: c.x, y: c.y - (s.layout.hub.gearFrame.height / 2 + 4))
            XCTAssertEqual(r.resolve(drag).special, .drag, "\(preset): rest of the disc drags")
            XCTAssertEqual(r.resolve(drag).hit, .inert)
        }
    }

    func testMoreWedgeAtSixOClockIsAnExpansionNode() {
        let all = Array(StatKind.allCases)
        for favourites in [0, 1, 6, 8] {
            let (r, s) = resolver(all, favourites: Array(all.prefix(favourites)))
            XCTAssertEqual(s.moreKinds.count, all.count - favourites)
            let mid = (r.snapshot.preset.innerRadius + r.snapshot.preset.outerRadius) / 2
            XCTAssertEqual(r.resolve(screen(r, degrees: 180, radius: mid)).hit, .node(.more), "\(favourites) favourites")
            XCTAssertEqual(r.resolve(screen(r, degrees: 180, radius: r.snapshot.preset.outerRadius + 5)).hit, .none)
        }
    }

    func testSideListRowsAndTheirGapsAreInsideTheOpenBranchOnly() throws {
        let all = Array(StatKind.allCases)
        let (open, s) = resolver(all, favourites: Array(all.prefix(6)), moreOpen: true)
        XCTAssertEqual(open.plan.mode, .sideList)
        let surface = try XCTUnwrap(open.plan.moreSurface)
        let first = try XCTUnwrap(s.moreKinds.first)
        let row = CGPoint(x: surface.minX + 20, y: surface.maxY - (RingListLayout.padding + RingListLayout.rowHeight / 2))
        XCTAssertEqual(open.resolve(row).hit, .node(.moreItem(first)))
        let padding = CGPoint(x: surface.minX + 20, y: surface.maxY - 1)
        XCTAssertEqual(open.resolve(padding).hit, .moreSurface, "list padding is inside the open branch")

        var closed = open
        closed.moreOpen = false
        XCTAssertEqual(closed.resolve(row).hit, .none, "More closed: the list area is outside")
    }

    func testAnOpenDetailFrameWinsOverEverythingBeneathIt() throws {
        var (r, _) = resolver([.cpu, .memory])
        r.openDetailKind = .cpu
        let frame = try XCTUnwrap(r.plan.detailFrames[.cpu])
        XCTAssertEqual(r.resolve(CGPoint(x: frame.midX, y: frame.midY)).hit, .detail)
    }
}

import XCTest

/// Hostless checks that inert ring space stays inside the HUD and only true outside is "none".
final class RingHitResolverTests: XCTestCase {

    private let base = CGRect(x: 100, y: 100, width: 360, height: 360)

    private func reading(_ kind: StatKind) -> RingReading {
        RingReading(value: "42%", widestValue: kind.ringFallbackWidest)
    }

    private func resolver(_ kinds: [StatKind], favourites: [StatKind]? = nil, openArc: RingArcOwner? = nil,
                          preset: RingSizePreset = .medium) -> (RingHitResolver, RingSnapshot) {
        let s = RingSnapshot.make(enabledKinds: kinds, favourites: favourites, preset: preset, reading: reading)
        let sizes = Dictionary(uniqueKeysWithValues: kinds.map { ($0, CGSize(width: 300, height: 300)) })
        let visible = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        // The side-list geometry alone: the band is exercised by `bandResolver`.
        let plan = RingPlacement.resolve(.init(snapshot: s, visible: visible, preferredBase: base, detailSizes: sizes,
                                               allowsOuterBand: false))
        var list: RingListLayout?
        if let surface = plan.moreSurface {
            list = RingListLayout(size: surface.size, rows: s.moreKinds.map { .moreItem($0) }, hasChrome: false)
        }
        return (RingHitResolver(plan: plan, baseFrame: plan.baseFrame, snapshot: s, openDetailKind: nil,
                                openArc: openArc, sideList: list, wholeList: nil), s)
    }

    private func screen(_ r: RingHitResolver, degrees: Double, radius: CGFloat) -> CGPoint {
        let local = RingSector.point(center: r.snapshot.layout.center, angle: degrees * .pi / 180, radius: radius)
        return CGPoint(x: r.baseFrame.minX + local.x, y: r.baseFrame.maxY - local.y)
    }

    func testSeparatorGapInnerBandAndInactiveAnnulusAreInertNotOutside() {
        let (six, _) = resolver([.cpu, .memory, .disk, .network, .gpu, .temps])
        XCTAssertEqual(six.resolveBranch(screen(six, degrees: 0, radius: 120)).hit, .node(.wedge(.cpu)))
        XCTAssertEqual(six.resolveBranch(screen(six, degrees: 30, radius: 120)).hit, .inert, "separator gap")
        // Medium: hub disc 59, inner radius 65; the band between them selects nothing.
        XCTAssertEqual(six.resolveBranch(screen(six, degrees: 0, radius: 62)).hit, .inert, "band between hub and inner radius")

        let (one, _) = resolver([.cpu])
        XCTAssertEqual(one.resolveBranch(screen(one, degrees: 180, radius: 120)).hit, .inert, "inactive annulus")
    }

    func testOnlyBeyondTheOuterRadiusOrOutsideTheFrameIsNone() {
        for preset in RingSizePreset.allCases {
            let (r, _) = resolver([.cpu, .memory, .disk, .network, .gpu, .temps], preset: preset)
            XCTAssertEqual(r.resolveBranch(screen(r, degrees: 45, radius: preset.outerRadius + 5)).hit, .none, "\(preset)")
            XCTAssertEqual(r.resolveBranch(CGPoint(x: r.baseFrame.minX + 3, y: r.baseFrame.minY + 3)).hit, .none,
                           "\(preset): transparent corner")
        }
        let (r, _) = resolver([.cpu])
        XCTAssertEqual(r.resolveBranch(CGPoint(x: -50, y: -50)).hit, .none)
    }

    func testHubOffersOnlyTheGearAndTheDragArea() {
        for preset in RingSizePreset.allCases {
            let (r, s) = resolver([.cpu, .memory], preset: preset)
            let c = CGPoint(x: r.baseFrame.midX, y: r.baseFrame.midY)
            XCTAssertEqual(r.resolveBranch(c).special, .settings, "\(preset): gear")
            XCTAssertEqual(r.resolveBranch(c).hit, .inert, "a hub control is never an expansion node")
            let drag = CGPoint(x: c.x, y: c.y - (s.layout.hub.gearFrame.height / 2 + 4))
            XCTAssertEqual(r.resolveBranch(drag).special, .drag, "\(preset): rest of the disc drags")
            XCTAssertEqual(r.resolveBranch(drag).hit, .inert)
        }
    }

    func testMoreWedgeAtSixOClockIsAnExpansionNode() {
        let all = Array(StatKind.allCases)
        for favourites in [0, 1, 6, 8] {
            let (r, s) = resolver(all, favourites: Array(all.prefix(favourites)))
            XCTAssertEqual(s.moreKinds.count, all.count - favourites)
            let mid = (r.snapshot.preset.innerRadius + r.snapshot.preset.outerRadius) / 2
            XCTAssertEqual(r.resolveBranch(screen(r, degrees: 180, radius: mid)).hit, .node(.more), "\(favourites) favourites")
            XCTAssertEqual(r.resolveBranch(screen(r, degrees: 180, radius: r.snapshot.preset.outerRadius + 5)).hit, .none)
        }
    }

    func testSideListRowsAndTheirGapsAreInsideTheOpenBranchOnly() throws {
        let all = Array(StatKind.allCases)
        let (open, s) = resolver(all, favourites: Array(all.prefix(6)), openArc: .more)
        XCTAssertEqual(open.plan.mode, .sideList)
        let surface = try XCTUnwrap(open.plan.moreSurface)
        let first = try XCTUnwrap(s.moreKinds.first)
        let row = CGPoint(x: surface.minX + 20, y: surface.maxY - (RingListLayout.padding + RingListLayout.rowHeight / 2))
        XCTAssertEqual(open.resolveBranch(row).hit, .node(.moreItem(first)))
        let padding = CGPoint(x: surface.minX + 20, y: surface.maxY - 1)
        XCTAssertEqual(open.resolveBranch(padding).hit, .arc(.more), "list padding is inside the open branch")

        var closed = open
        closed.openArc = nil
        XCTAssertEqual(closed.resolveBranch(row).hit, .none, "More closed: the list area is outside")
    }

    func testAnOpenDetailFrameWinsOverEverythingBeneathIt() throws {
        var (r, _) = resolver([.cpu, .memory])
        r.openDetailKind = .cpu
        let frame = try XCTUnwrap(r.plan.detailFrames[.cpu])
        XCTAssertEqual(r.resolveBranch(CGPoint(x: frame.midX, y: frame.midY)).hit, .detail)
    }

    // MARK: Outer band

    private func bandResolver(_ kinds: [StatKind], favourites: [StatKind]? = nil, openArc: RingArcOwner?,
                              preset: RingSizePreset = .medium) throws -> RingHitResolver {
        let set = RingPartFixtures.make(.typical)
        let s = RingSnapshot.make(enabledKinds: kinds, favourites: favourites, preset: preset, reading: reading,
                                  parts: { kind in
                                      switch kind {
                                      case .cpu: return set.cpuParts
                                      case .temps: return set.temperatureParts
                                      default: return nil
                                      }
                                  })
        let sizes = Dictionary(uniqueKeysWithValues: kinds.map { ($0, CGSize(width: 300, height: 300)) })
        let visible = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        let preferred = CGRect(x: 1000, y: 800, width: s.size.width, height: s.size.height)
        let plan = RingPlacement.resolve(.init(snapshot: s, visible: visible, preferredBase: preferred,
                                               detailSizes: sizes, allowsOuterBand: true))
        XCTAssertEqual(plan.mode, .outerBand)
        return RingHitResolver(plan: plan, baseFrame: plan.baseFrame, snapshot: s, openDetailKind: nil,
                               openArc: openArc, sideList: nil, wholeList: nil)
    }

    func testOpenSubRingResolvesItsSegmentsAndTheGapAndNothingWhenClosed() throws {
        for preset in RingSizePreset.allCases {
            let six: [StatKind] = [.cpu, .memory, .disk, .network, .gpu, .temps]
            let open = try bandResolver(six, openArc: .stat(.temps), preset: preset)
            let arc = try XCTUnwrap(open.snapshot.arcs[.stat(.temps)])
            for segment in arc.segments {
                let p = screen(open, degrees: segment.sector.centerAngle * 180 / .pi, radius: segment.sector.midRadius)
                XCTAssertEqual(open.resolveBranch(p).hit, .segment(RingSegmentRef(stat: .temps, index: segment.index)),
                               "\(preset) segment \(segment.index)")
            }
            let mid = arc.parentMidAngle * 180 / .pi
            let gap = screen(open, degrees: mid, radius: preset.outerRadius + RingSizePreset.bandGap / 2)
            XCTAssertEqual(open.resolveBranch(gap).hit, .arc(.stat(.temps)), "\(preset): the gap belongs to the branch")
            let beyond = screen(open, degrees: mid, radius: arc.outerRadius + 3)
            XCTAssertEqual(open.resolveBranch(beyond).hit, .none, "\(preset): beyond the arc is outside")
            let ring = screen(open, degrees: mid, radius: (preset.innerRadius + preset.outerRadius) / 2)
            XCTAssertEqual(open.resolveBranch(ring).hit, .node(.wedge(.temps)), "\(preset): the ring is unchanged")

            var closed = open
            closed.openArc = nil
            XCTAssertEqual(closed.resolveBranch(gap).hit, .none, "\(preset): a closed arc is outside")
            var other = open
            other.openArc = .stat(.cpu)
            let first = try XCTUnwrap(arc.segments.first)
            let p = screen(open, degrees: first.sector.centerAngle * 180 / .pi, radius: first.sector.midRadius)
            XCTAssertNotEqual(other.resolveBranch(p).hit, .segment(RingSegmentRef(stat: .temps, index: first.index)),
                              "\(preset): only the open owner's segments resolve")
        }
    }

    func testMoreArcEntriesResolveToMoreItems() throws {
        let all = Array(StatKind.allCases)
        let r = try bandResolver(all, favourites: Array(all.prefix(6)), openArc: .more)
        let arc = try XCTUnwrap(r.snapshot.arcs[.more])
        XCTAssertNil(r.plan.moreSurface)
        for segment in arc.segments {
            let p = screen(r, degrees: segment.sector.centerAngle * 180 / .pi, radius: segment.sector.midRadius)
            XCTAssertEqual(r.resolveBranch(p).hit, .node(.moreItem(r.snapshot.moreKinds[segment.index])))
        }
        let gap = screen(r, degrees: 180, radius: r.snapshot.preset.outerRadius + 3)
        XCTAssertEqual(r.resolveBranch(gap).hit, .arc(.more))
    }
}

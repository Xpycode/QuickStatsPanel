import XCTest

/// Hostless checks that inert ring space stays inside the HUD and only true outside is "none".
final class RingHitResolverTests: XCTestCase {

    private let base = CGRect(x: 100, y: 100, width: 520, height: 520)

    private func reading(_ kind: StatKind) -> RingReading {
        RingReading(value: "42%", widestValue: kind.ringFallbackWidest)
    }

    private func resolver(_ kinds: [StatKind], moreOpen: Bool = false) -> (RingHitResolver, RingSnapshot) {
        let s = RingSnapshot.make(enabledKinds: kinds, reading: reading)
        let sizes = Dictionary(uniqueKeysWithValues: kinds.map { ($0, CGSize(width: 300, height: 300)) })
        let visible = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        let plan = RingPlacement.resolve(.init(snapshot: s, visible: visible, preferredBase: base, detailSizes: sizes))
        let moreGeometry = s.moreKinds.isEmpty ? nil : RingMoreGeometry(items: s.moreEntries.map {
            (kind: $0.kind, textSize: s.moreTextSizes[$0.kind] ?? .zero)
        })
        return (RingHitResolver(plan: plan, baseFrame: plan.baseFrame, geometry: s.geometry, openDetailKind: nil,
                                moreOpen: moreOpen, moreGeometry: moreGeometry, sideList: nil, wholeList: nil), s)
    }

    private func screen(_ r: RingHitResolver, degrees: Double, radius: CGFloat) -> CGPoint {
        let local = RingGeometry.point(center: r.geometry.center, angle: degrees * .pi / 180, radius: radius)
        return CGPoint(x: r.baseFrame.minX + local.x, y: r.baseFrame.maxY - local.y)
    }

    func testSeparatorGapInnerBandAndInactiveAnnulusAreInertNotOutside() {
        let (six, _) = resolver([.cpu, .memory, .disk, .network, .gpu, .temps])
        XCTAssertEqual(six.resolve(screen(six, degrees: 0, radius: 185)).hit, .node(.wedge(.cpu)))
        XCTAssertEqual(six.resolve(screen(six, degrees: 30, radius: 185)).hit, .inert, "separator gap")
        XCTAssertEqual(six.resolve(screen(six, degrees: 0, radius: 96)).hit, .inert, "band between hub and inner radius")

        let (one, _) = resolver([.cpu])
        XCTAssertEqual(one.resolve(screen(one, degrees: 180, radius: 180)).hit, .inert, "inactive annulus")
    }

    func testOnlyBeyondTheOuterRadiusOrOutsideTheFrameIsNone() {
        let (r, _) = resolver([.cpu, .memory, .disk, .network, .gpu, .temps])
        XCTAssertEqual(r.resolve(screen(r, degrees: 45, radius: RingGeometry.outerRadius + 5)).hit, .none)
        XCTAssertEqual(r.resolve(CGPoint(x: r.baseFrame.minX + 3, y: r.baseFrame.minY + 3)).hit, .none, "transparent corner")
        XCTAssertEqual(r.resolve(CGPoint(x: -50, y: -50)).hit, .none)
    }

    func testHubSpecialsAreInertWithTheirSpecialSet() {
        let (r, _) = resolver([.cpu, .memory])
        let c = CGPoint(x: r.baseFrame.midX, y: r.baseFrame.midY)
        XCTAssertEqual(r.resolve(CGPoint(x: c.x + 60, y: c.y)).special, .drag)
        XCTAssertEqual(r.resolve(CGPoint(x: c.x, y: c.y - 15)).special, .settings)
    }

    func testMoreRingGapsAndTheBandBeforeItAreInsideTheOpenBranch() throws {
        let (r, s) = resolver(Array(StatKind.allCases), moreOpen: true)
        XCTAssertEqual(r.plan.mode, .outerRing)
        let surface = try XCTUnwrap(r.plan.moreSurface)
        func at(_ degrees: Double, _ radius: CGFloat) -> CGPoint {
            let l = RingGeometry.point(center: CGPoint(x: 410, y: 410), angle: degrees * .pi / 180, radius: radius)
            return CGPoint(x: surface.minX + l.x, y: surface.maxY - l.y)
        }
        let first = try XCTUnwrap(s.moreKinds.first)
        XCTAssertEqual(r.resolve(at(0, 342)).hit, .node(.moreItem(first)))
        let slot = 360.0 / Double(s.moreKinds.count)
        XCTAssertEqual(r.resolve(at(slot / 2, 342)).hit, .moreSurface, "gap between More entries")
        XCTAssertEqual(r.resolve(at(slot / 2, 267)).hit, .moreSurface, "band between the two rings")
        XCTAssertEqual(r.resolve(at(slot / 2, 430)).hit, .none, "beyond the More ring")
        let closed = RingHitResolver(plan: r.plan, baseFrame: r.baseFrame, geometry: r.geometry, openDetailKind: nil,
                                     moreOpen: false, moreGeometry: nil, sideList: nil, wholeList: nil)
        XCTAssertEqual(closed.resolve(at(slot / 2, 342)).hit, .none, "More closed: its area is outside")
    }
}

import XCTest

#if DEBUG
/// Frozen floating-tile geometry: packing, footprint enlargement, a switcher anchored at the
/// footprint's right edge, detail limits, column reduction and visual-neighbour navigation.
final class FloatingTileLayoutTests: XCTestCase {

    private let roomy = CGSize(width: 1400, height: 860)
    private let details: [StatKind: CGSize] = [.cpu: CGSize(width: 244, height: 330),
                                               .network: CGSize(width: 284, height: 560)]

    private func plan(_ kinds: [StatKind] = [.cpu, .network], details: [StatKind: CGSize]? = nil,
                      available: CGSize? = nil) -> FloatingTilePlan {
        FloatingTilePlan.make(kinds: kinds, detailSizes: details ?? self.details, available: available ?? roomy)
    }

    func testCPUNetworkOverviewPacksFirstLargeThenWide() {
        let p = plan()
        XCTAssertEqual(p.columns, 4)
        XCTAssertEqual(p.metrics.columnWidth, 111)
        XCTAssertEqual(p.tileFrames[.cpu], CGRect(x: 0, y: 40, width: 234, height: 212))
        XCTAssertEqual(p.tileFrames[.network], CGRect(x: 246, y: 40, width: 234, height: 100))
        XCTAssertEqual(p.size.width, 480, "narrow details keep the mockup's 480-point footprint")
        XCTAssertTrue(p.fits)
    }

    func testElevenStatsPackInSavedOrderWithoutOverlap() {
        let p = plan(StatKind.allCases, details: [:])
        let frames = StatKind.allCases.compactMap { p.tileFrames[$0] }
        XCTAssertEqual(frames.count, 11)
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] { XCTAssertFalse(a.intersects(b), "\(a) overlaps \(b)") }
        }
        XCTAssertEqual(p.tileFrames[.disk]?.size, CGSize(width: 234, height: 100), "second and third are 2×1")
        XCTAssertEqual(p.tileFrames[.network]?.size, CGSize(width: 111, height: 100), "the rest are 1×1")
    }

    func testSwitcherIsAnchoredAtTheFootprintRightEdgeAndNeverOverlapsDetail() {
        let p = plan()
        XCTAssertEqual(p.switcherFrame.maxX, p.size.width)
        XCTAssertEqual(p.switcherFrame.width, 106)
        XCTAssertEqual(p.barFrame.maxX, p.size.width)
        for kind in p.kinds {
            let detail = try! XCTUnwrap(p.detailFrames[kind])
            XCTAssertEqual(detail.origin, p.contentOrigin, "detail top-left is the overview origin")
            XCTAssertLessThanOrEqual(detail.maxX + 12, p.switcherFrame.minX, "detail keeps the gap to the switcher")
        }
        for (target, frame) in p.switcherItemFrames {
            XCTAssertTrue(p.switcherFrame.contains(frame), "\(target) inside the switcher")
        }
    }

    func testWideDetailEnlargesTheFootprintOnceAtSummon() {
        let p = plan(details: [.cpu: CGSize(width: 244, height: 300), .network: CGSize(width: 400, height: 300)])
        XCTAssertEqual(p.size.width, 400 + 12 + 106)
        XCTAssertEqual(p.detailFrames[.network]?.width, 400)
        XCTAssertEqual(p.switcherFrame.minX, 400 + 12, "one switcher position for every detail")
    }

    func testOversizedDetailIsHeightLimitedAndOnlyItScrolls() {
        let p = plan(available: CGSize(width: 1400, height: 500))
        XCTAssertEqual(p.detailFrames[.network]?.height, 500 - 40)
        XCTAssertEqual(p.scrollingDetails, [.network])
        XCTAssertEqual(p.detailFrames[.cpu]?.height, 330, "a card that fits keeps its measured height")
        XCTAssertLessThanOrEqual(p.size.height, 500)
        XCTAssertTrue(p.fits)
    }

    func testNarrowDisplayReducesColumnsAtSummon() {
        let p = plan([.cpu, .network, .memory, .disk, .gpu], details: [:], available: CGSize(width: 420, height: 900))
        XCTAssertEqual(p.columns, 2)
        XCTAssertLessThanOrEqual(p.size.width, 420)
        XCTAssertEqual(p.tileFrames[.cpu], CGRect(x: 0, y: 40, width: 234, height: 212))
        XCTAssertEqual(p.tileFrames[.network], CGRect(x: 0, y: 264, width: 234, height: 100))
        XCTAssertTrue(p.fits)
    }

    func testTooNarrowForTheMinimumIsReported() {
        let p = plan(available: CGSize(width: 300, height: 900))
        XCTAssertFalse(p.fits, "the stop condition is visible, not silently clipped")
        XCTAssertEqual(p.columns, 2)
    }

    func testSamePlanForSameInput() {
        XCTAssertEqual(plan(), plan(), "the plan depends only on identities and measured sizes, not readings")
    }

    func testOverviewArrowsFollowVisualNeighbours() {
        let p = plan()
        XCTAssertEqual(p.neighbour(of: .tile(.cpu), .right, detail: false), .tile(.network))
        XCTAssertEqual(p.neighbour(of: .tile(.network), .left, detail: false), .tile(.cpu))
        XCTAssertNil(p.neighbour(of: .tile(.cpu), .left, detail: false))
        XCTAssertNil(p.neighbour(of: .tile(.cpu), .down, detail: false))
        if case .tile = p.neighbour(of: .tile(.network), .up, detail: false) { XCTFail("nothing above but the bar") }
        XCTAssertNotNil(p.neighbour(of: .tile(.network), .up, detail: false), "the group bar is above Network")
    }

    func testSwitcherArrowsFollowItsTwoColumnGrid() {
        let p = plan()
        XCTAssertEqual(p.neighbour(of: .switcher(.cpu), .right, detail: true), .switcher(.network))
        XCTAssertEqual(p.neighbour(of: .switcher(.network), .left, detail: true), .switcher(.cpu))
        XCTAssertEqual(p.neighbour(of: .switcher(.cpu), .down, detail: true), .allStatistics)
        XCTAssertEqual(p.neighbour(of: .switcher(.network), .down, detail: true), .allStatistics)
        XCTAssertNil(p.neighbour(of: .tile(.cpu), .right, detail: true), "tiles are not targets in detail")
    }

    func testElevenStatOverviewNeighboursAreGeometric() {
        let p = plan(StatKind.allCases, details: [:])
        // Row 0: CPU (0-1, 2 rows), Memory (2-3). Row 1: Disk (2-3). Row 2: Network, Battery, GPU, Fans.
        XCTAssertEqual(p.neighbour(of: .tile(.memory), .down, detail: false), .tile(.disk))
        XCTAssertEqual(p.neighbour(of: .tile(.cpu), .right, detail: false), .tile(.memory))
        XCTAssertEqual(p.neighbour(of: .tile(.network), .up, detail: false), .tile(.cpu))
        XCTAssertEqual(p.neighbour(of: .tile(.gpu), .up, detail: false), .tile(.disk))
    }
}
#endif

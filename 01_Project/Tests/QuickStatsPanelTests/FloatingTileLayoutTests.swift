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

    // MARK: Task 2.1 — hierarchy, identity counts and frozen constants

    func testPrototypeConstantsAreFrozen() {
        let m = FloatingTileMetrics()
        XCTAssertEqual(m.baseWidth, 480)
        XCTAssertEqual(m.columns, 4)
        XCTAssertEqual(m.rowHeight, 100)
        XCTAssertEqual(m.gap, 12)
        XCTAssertEqual(m.switcherWidth, 106)
        XCTAssertEqual(m.minimumColumns, 2)
    }

    func testSavedOrderDrivesHierarchyAndSwitcher() {
        let order: [StatKind] = [.uptime, .gpu, .memory, .cpu, .fan]
        let p = plan(order, details: [:])
        XCTAssertEqual(p.tileFrames[.uptime]?.size, CGSize(width: 234, height: 212), "first is the large tile")
        XCTAssertEqual(p.tileFrames[.gpu]?.size, CGSize(width: 234, height: 100))
        XCTAssertEqual(p.tileFrames[.memory]?.size, CGSize(width: 234, height: 100))
        XCTAssertEqual(p.tileFrames[.cpu]?.size, CGSize(width: 111, height: 100), "the rest are 1×1")
        XCTAssertEqual(p.tileFrames[.cpu]?.origin.y, p.tileFrames[.fan]?.origin.y)
        XCTAssertLessThan(try! XCTUnwrap(p.tileFrames[.cpu]).minX, try! XCTUnwrap(p.tileFrames[.fan]).minX)
        // The switcher lists the same saved order, two per row, row-major.
        let items = order.map { try! XCTUnwrap(p.switcherItemFrames[.switcher($0)]) }
        XCTAssertEqual(items[0].minY, items[1].minY)
        XCTAssertLessThan(items[0].minX, items[1].minX)
        XCTAssertEqual(items[2].minY, items[3].minY)
        XCTAssertGreaterThan(items[2].minY, items[0].minY)
        XCTAssertGreaterThan(items[4].minY, items[2].minY)
    }

    func testReorderingChangesTheLargeTileButNothingElseDependsOnReadings() {
        let a = plan(StatKind.allCases, details: [:])
        let b = plan(StatKind.allCases.reversed(), details: [:])
        XCTAssertEqual(a.tileFrames[.cpu]?.size, CGSize(width: 234, height: 212))
        XCTAssertEqual(b.tileFrames[.uptime]?.size, CGSize(width: 234, height: 212))
        XCTAssertEqual(a.size, b.size, "the footprint depends on the count, not the order")
    }

    func testElevenStatFootprintFitsAComfortableDisplayAndStaysInsideItself() {
        let p = plan(StatKind.allCases, details: [:], available: CGSize(width: 1400, height: 860))
        XCTAssertTrue(p.fits)
        let all = Array(p.tileFrames.values) + [p.switcherFrame, p.barFrame]
        let bounds = CGRect(origin: .zero, size: p.size)
        for frame in all { XCTAssertTrue(bounds.contains(frame), "\(frame) inside \(bounds)") }
        for kind in StatKind.allCases {
            XCTAssertNotNil(p.switcherItemFrames[.switcher(kind)], "\(kind) reachable in the switcher")
            XCTAssertNotNil(p.tileFrames[kind], "\(kind) has a tile")
        }
        XCTAssertNil(p.emptyStateFrame)
    }

    func testOneStatKeepsTheLargeTileAndTheSwitcher() {
        let p = plan([.memory], details: [:])
        XCTAssertEqual(p.tileFrames[.memory]?.size, CGSize(width: 234, height: 212))
        XCTAssertEqual(p.tileFrames.count, 1)
        XCTAssertNotNil(p.switcherItemFrames[.switcher(.memory)])
        XCTAssertNotNil(p.switcherItemFrames[.allStatistics])
        XCTAssertTrue(p.fits)
    }

    func testEmptyPlanHasACompactEmptyStateAndReachableBar() {
        let p = plan([], details: [:])
        XCTAssertTrue(p.tileFrames.isEmpty)
        let empty = try! XCTUnwrap(p.emptyStateFrame)
        XCTAssertEqual(empty.height, 100, "compact: one row")
        XCTAssertEqual(empty.origin, p.contentOrigin)
        XCTAssertTrue(p.fits)
        for target in [FloatingTileTarget.handle, .settings, .quit] {
            let frame = try! XCTUnwrap(p.barItemFrames[target], "\(target)")
            XCTAssertTrue(CGRect(origin: .zero, size: p.size).contains(frame))
            XCTAssertFalse(frame.intersects(empty), "\(target) is not covered by the empty state")
        }
    }

    func testSubsetStatsPackWithoutGaps() {
        let p = plan([.disk, .battery, .uptime, .memory, .temps], details: [:])
        XCTAssertEqual(p.tileFrames.count, 5)
        XCTAssertEqual(p.tileFrames[.disk]?.size, CGSize(width: 234, height: 212))
        let frames = Array(p.tileFrames.values)
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] { XCTAssertFalse(a.intersects(b)) }
        }
    }
}
#endif

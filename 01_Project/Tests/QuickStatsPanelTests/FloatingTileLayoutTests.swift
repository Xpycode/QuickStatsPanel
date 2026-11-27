import XCTest

#if DEBUG
/// Frozen floating-tile geometry: packing, a fixed core (bar, overview), details opening sideways
/// from their primary toward the larger part of the old overview (D-044), column reduction and
/// visual-neighbour navigation. Core-relative frames use `c(_:_:)` because details to the
/// left/top shift the core inside the host.
final class FloatingTileLayoutTests: XCTestCase {

    private let roomy = CGSize(width: 1400, height: 860)
    private let details: [StatKind: CGSize] = [.cpu: CGSize(width: 244, height: 330),
                                               .network: CGSize(width: 284, height: 560)]

    private func plan(_ kinds: [StatKind] = [.cpu, .network], details: [StatKind: CGSize]? = nil,
                      available: CGSize? = nil) -> FloatingTilePlan {
        FloatingTilePlan.make(kinds: kinds, detailSizes: details ?? self.details, available: available ?? roomy)
    }

    /// A frame relative to the core's top-left.
    private func c(_ p: FloatingTilePlan, _ r: CGRect?) -> CGRect? {
        r?.offsetBy(dx: -p.coreFrame.minX, dy: -p.coreFrame.minY)
    }

    func testCPUNetworkOverviewPacksFirstLargeThenWide() {
        let p = plan()
        XCTAssertEqual(p.columns, 4)
        XCTAssertEqual(p.metrics.columnWidth, 111)
        XCTAssertEqual(c(p, p.tileFrames[.cpu]), CGRect(x: 0, y: 40, width: 234, height: 212))
        XCTAssertEqual(c(p, p.tileFrames[.network]), CGRect(x: 246, y: 40, width: 234, height: 100))
        XCTAssertEqual(p.coreFrame.width, 480, "just the overview: no switcher column (D-044)")
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

    func testBarSitsAboveTheOverviewsRightEdgeAndNoDetailCoversItOrItsPrimary() {
        let p = plan()
        XCTAssertEqual(p.barFrame.maxX, p.contentOrigin.x + 480, "the bar sits above the overview's right edge")
        XCTAssertEqual(p.barFrame.width, 106)
        XCTAssertEqual(p.overviewFrame, CGRect(origin: p.contentOrigin, size: CGSize(width: 480, height: 212)))
        for kind in p.kinds {
            let detail = try! XCTUnwrap(p.detailFrames[kind])
            XCTAssertFalse(detail.intersects(p.barFrame.insetBy(dx: -11, dy: -11)), "\(kind) detail keeps clear of the bar")
            XCTAssertFalse(detail.intersects(try! XCTUnwrap(p.tileFrames[kind]).insetBy(dx: -11, dy: 0)),
                           "\(kind) detail sits beside its primary, with the gap")
            XCTAssertTrue(CGRect(origin: .zero, size: p.size).contains(detail))
        }
    }

    func testWideDetailNeverResizesTheCore() {
        let p = plan(details: [.cpu: CGSize(width: 244, height: 300), .network: CGSize(width: 400, height: 300)])
        XCTAssertEqual(p.coreFrame.width, 480)
        XCTAssertEqual(p.detailFrames[.network]?.width, 400)
    }

    func testOversizedDetailIsHeightLimitedAndOnlyItScrolls() {
        let p = plan(available: CGSize(width: 1400, height: 500))
        XCTAssertEqual(p.detailFrames[.network]?.height, 500, "limited to the display region beside the core")
        XCTAssertEqual(p.scrollingDetails, [.network])
        XCTAssertEqual(p.detailFrames[.cpu]?.height, 330, "a card that fits keeps its measured height")
        XCTAssertLessThanOrEqual(p.size.height, 500)
        XCTAssertTrue(p.fits)
    }

    func testNarrowDisplayReducesColumnsAtSummon() {
        let p = plan([.cpu, .network, .memory, .disk, .gpu], details: [:], available: CGSize(width: 420, height: 900))
        XCTAssertEqual(p.columns, 2)
        XCTAssertLessThanOrEqual(p.coreFrame.width, 420)
        XCTAssertEqual(c(p, p.tileFrames[.cpu]), CGRect(x: 0, y: 40, width: 234, height: 212))
        XCTAssertEqual(c(p, p.tileFrames[.network]), CGRect(x: 0, y: 264, width: 234, height: 100))
        XCTAssertTrue(p.fits)
    }

    func testTooNarrowForTheMinimumIsReported() {
        let p = plan(available: CGSize(width: 200, height: 900))
        XCTAssertFalse(p.fits, "the stop condition is visible, not silently clipped")
        XCTAssertEqual(p.columns, 2)
    }

    func testSamePlanForSameInput() {
        XCTAssertEqual(plan(), plan(), "the plan depends only on identities and measured sizes, not readings")
    }

    func testOverviewArrowsFollowVisualNeighbours() {
        let p = plan()
        XCTAssertEqual(p.neighbour(of: .tile(.cpu), .right, open: nil), .tile(.network))
        XCTAssertEqual(p.neighbour(of: .tile(.network), .left, open: nil), .tile(.cpu))
        XCTAssertNil(p.neighbour(of: .tile(.cpu), .left, open: nil))
        XCTAssertNil(p.neighbour(of: .tile(.cpu), .down, open: nil))
        if case .tile = p.neighbour(of: .tile(.network), .up, open: nil) { XCTFail("nothing above but the bar") }
        XCTAssertNotNil(p.neighbour(of: .tile(.network), .up, open: nil), "the group bar is above Network")
    }

    func testOpenDetailLeavesOnlyItsPrimaryAndTheBarAsTargets() {
        let p = plan(StatKind.allCases, details: details)
        XCTAssertEqual(Set(p.targetFrames(open: .network).keys), [.tile(.network), .handle, .settings, .quit],
                       "the other primaries are hidden, and there is no switcher")
        XCTAssertEqual(Set(p.targetFrames(open: nil).keys).count, 11 + 3, "every primary plus the bar in the overview")
        XCTAssertNotEqual(p.neighbour(of: .tile(.cpu), .right, open: .cpu), .tile(.memory), "hidden primaries are skipped")
        let up = p.neighbour(of: .tile(.memory), .up, open: .memory)
        XCTAssertTrue([FloatingTileTarget.handle, .settings, .quit].contains(up), "the bar stays reachable")
    }

    func testElevenStatOverviewNeighboursAreGeometric() {
        let p = plan(StatKind.allCases, details: [:])
        // Row 0: CPU (0-1, 2 rows), Memory (2-3). Row 1: Disk (2-3). Row 2: Network, Battery, GPU, Fans.
        XCTAssertEqual(p.neighbour(of: .tile(.memory), .down, open: nil), .tile(.disk))
        XCTAssertEqual(p.neighbour(of: .tile(.cpu), .right, open: nil), .tile(.memory))
        XCTAssertEqual(p.neighbour(of: .tile(.network), .up, open: nil), .tile(.cpu))
        XCTAssertEqual(p.neighbour(of: .tile(.gpu), .up, open: nil), .tile(.disk))
    }

    // MARK: Task 2.1 — hierarchy, identity counts and frozen constants

    func testPrototypeConstantsAreFrozen() {
        let m = FloatingTileMetrics()
        XCTAssertEqual(m.baseWidth, 480)
        XCTAssertEqual(m.columns, 4)
        XCTAssertEqual(m.rowHeight, 100)
        XCTAssertEqual(m.gap, 12)
        XCTAssertEqual(m.barWidth, 106)
        XCTAssertEqual(m.minimumColumns, 2)
    }

    func testSavedOrderDrivesHierarchy() {
        let order: [StatKind] = [.uptime, .gpu, .memory, .cpu, .fan]
        let p = plan(order, details: [:])
        XCTAssertEqual(p.tileFrames[.uptime]?.size, CGSize(width: 234, height: 212), "first is the large tile")
        XCTAssertEqual(p.tileFrames[.gpu]?.size, CGSize(width: 234, height: 100))
        XCTAssertEqual(p.tileFrames[.memory]?.size, CGSize(width: 234, height: 100))
        XCTAssertEqual(p.tileFrames[.cpu]?.size, CGSize(width: 111, height: 100), "the rest are 1×1")
        XCTAssertEqual(p.tileFrames[.cpu]?.origin.y, p.tileFrames[.fan]?.origin.y)
        XCTAssertLessThan(try! XCTUnwrap(p.tileFrames[.cpu]).minX, try! XCTUnwrap(p.tileFrames[.fan]).minX)
    }

    func testReorderingChangesTheLargeTileButNothingElseDependsOnReadings() {
        let a = plan(StatKind.allCases, details: [:])
        let b = plan(StatKind.allCases.reversed(), details: [:])
        XCTAssertEqual(a.tileFrames[.cpu]?.size, CGSize(width: 234, height: 212))
        XCTAssertEqual(b.tileFrames[.uptime]?.size, CGSize(width: 234, height: 212))
        XCTAssertEqual(a.coreFrame.size, b.coreFrame.size, "the core depends on the count, not the order")
    }

    func testElevenStatFootprintFitsAComfortableDisplayAndStaysInsideItself() {
        let p = plan(StatKind.allCases, details: [:], available: CGSize(width: 1400, height: 860))
        XCTAssertTrue(p.fits)
        let all = Array(p.tileFrames.values) + [p.barFrame] + Array(p.detailFrames.values)
        let bounds = CGRect(origin: .zero, size: p.size)
        for frame in all { XCTAssertTrue(bounds.contains(frame), "\(frame) inside \(bounds)") }
        for kind in StatKind.allCases {
            XCTAssertNotNil(p.tileFrames[kind], "\(kind) has a tile")
            XCTAssertNotNil(p.detailFrames[kind], "\(kind) has a frozen detail frame")
        }
        XCTAssertNil(p.emptyStateFrame)
    }

    func testOneStatKeepsTheLargeTileAndOpensRight() {
        let p = plan([.memory], details: [:])
        XCTAssertEqual(p.tileFrames[.memory]?.size, CGSize(width: 234, height: 212))
        XCTAssertEqual(p.tileFrames.count, 1)
        XCTAssertEqual(p.detailSides[.memory], .right, "left half of the overview opens right")
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

    // MARK: Task 3.1 — constrained displays, scroll bars and placement

    func testFootprintHeightIsBarPlusTallestContent() {
        let p = plan(StatKind.allCases, details: [:])
        // Four 100-point rows with three 12-point gaps below the 28-point bar and its gap.
        XCTAssertEqual(p.coreFrame.height, 40 + 436, "no transparent band below the overview")
        XCTAssertNil(p.overviewViewport, "a comfortable display never scrolls the overview")
    }

    func testTooShortForTheOverviewScrollsItWithNavigationOutside() {
        let available = CGSize(width: 420, height: 600)
        let p = plan(StatKind.allCases, details: details, available: available)
        XCTAssertEqual(p.columns, 2)
        let viewport = try! XCTUnwrap(p.overviewViewport, "eleven stats in two columns are taller than 600")
        XCTAssertEqual(viewport.origin, p.contentOrigin)
        XCTAssertEqual(viewport.height, 600 - 40)
        XCTAssertLessThanOrEqual(p.size.height, available.height)
        XCTAssertTrue(p.fits, "navigation (the bar) still fits")
        XCTAssertFalse(viewport.intersects(p.barFrame), "the bar stays outside the scrolling overview")
        XCTAssertEqual(p.tileFrames[.cpu]?.size, CGSize(width: 234, height: 212), "type and tile sizes never shrink")
    }

    func testLegacyScrollBarReserveWidensOnlyScrollingContent() {
        let short = CGSize(width: 1400, height: 500)
        let overlay = plan(details: details, available: short)
        let legacy = FloatingTilePlan.make(kinds: [.cpu, .network], detailSizes: details, available: short,
                                           scrollerReserve: 15)
        XCTAssertEqual(overlay.detailFrames[.network]?.width, 284)
        XCTAssertEqual(legacy.detailFrames[.network]?.width, 284 + 15, "the scrolling card gets the scroll bar's width")
        XCTAssertEqual(legacy.detailFrames[.cpu]?.width, 244, "a card that fits keeps its measured width")
        XCTAssertFalse(try! XCTUnwrap(legacy.detailFrames[.network]).intersects(try! XCTUnwrap(legacy.tileFrames[.network])))
        let wide = FloatingTilePlan.make(kinds: [.cpu, .network], detailSizes: [.network: CGSize(width: 400, height: 560)],
                                         available: short, scrollerReserve: 15)
        XCTAssertEqual(wide.detailFrames[.network]?.width, 400 + 15, "the reserve widens only the scrolling card")
        XCTAssertEqual(wide.coreFrame.width, 480, "and never the core")
        XCTAssertEqual(legacy.scrollingDetails, [.network])
        let roomyLegacy = FloatingTilePlan.make(kinds: [.cpu, .network], detailSizes: details, available: roomy,
                                                scrollerReserve: 15)
        XCTAssertEqual(roomyLegacy, plan().withReserve(15), "nothing scrolls, so nothing is reserved")
    }

    func testShortAndLongDetailsAreEachContentSized() {
        let p = plan(StatKind.allCases, details: [.cpu: CGSize(width: 244, height: 330),
                                                  .network: CGSize(width: 284, height: 560),
                                                  .uptime: CGSize(width: 200, height: 90)],
                     available: CGSize(width: 1400, height: 500))
        XCTAssertEqual(p.scrollingDetails, [.network], "only the oversized card scrolls")
        XCTAssertEqual(p.detailFrames[.uptime]?.height, 90, "a short card stays content-sized")
        for kind in [StatKind.cpu, .network, .uptime] {
            let detail = try! XCTUnwrap(p.detailFrames[kind])
            XCTAssertFalse(detail.intersects(try! XCTUnwrap(p.tileFrames[kind])), "\(kind) never covers its primary")
            XCTAssertFalse(detail.intersects(p.barFrame), "\(kind) never covers the bar")
        }
    }

    func testRegionIsTheVisibleFrameOrACentredSimulatedOne() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        XCTAssertEqual(FloatingTilePlacement.region(visible: visible, simulated: nil), visible)
        let r = FloatingTilePlacement.region(visible: visible, simulated: CGSize(width: 420, height: 500))
        XCTAssertEqual(r.size, CGSize(width: 420, height: 500))
        XCTAssertTrue(visible.contains(r))
        XCTAssertEqual(r.midX, visible.midX, accuracy: 1)
        let capped = FloatingTilePlacement.region(visible: visible, simulated: CGSize(width: 5000, height: 5000))
        XCTAssertEqual(capped, visible, "never larger than the real display")
        XCTAssertEqual(FloatingTilePlacement.available(in: r), CGSize(width: 404, height: 484))
    }

    func testCornerPlacementClampsTheWholeFootprintOnScreen() {
        let visible = CGRect(x: 100, y: 25, width: 1200, height: 800)
        let size = CGSize(width: 520, height: 600)
        for edge in FloatingTileEdge.allCases {
            let o = FloatingTilePlacement.origin(size: size, anchor: .screenCenter, cursor: .zero,
                                                 visible: visible, edge: edge)
            let frame = CGRect(origin: o, size: size)
            XCTAssertTrue(visible.contains(frame), "\(edge): \(frame) inside \(visible)")
        }
        let topRight = FloatingTilePlacement.origin(size: size, anchor: .screenCenter, cursor: .zero,
                                                    visible: visible, edge: .topRight)
        XCTAssertEqual(topRight, CGPoint(x: visible.maxX - size.width, y: visible.maxY - size.height))
        let cursorAtCorner = FloatingTilePlacement.origin(size: size, anchor: .cursor,
                                                          cursor: CGPoint(x: 1299, y: 30), visible: visible)
        XCTAssertTrue(visible.contains(CGRect(origin: cursorAtCorner, size: size)), "cursor anchor at a corner")
    }

    func testOversizedFootprintKeepsItsTopLeftOnScreen() {
        let visible = CGRect(x: 0, y: 0, width: 300, height: 400)
        let o = FloatingTilePlacement.clamp(origin: CGPoint(x: 50, y: 50), size: CGSize(width: 402, height: 500), in: visible)
        XCTAssertEqual(o, CGPoint(x: 0, y: 400 - 500), "top-left (bar row) stays visible")
    }

    func testDisplayChangeReclampsTheGroupAsOneUnit() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let side = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        // Mostly on the side display, which is then removed: the group moves wholly onto main.
        let frame = CGRect(x: 1700, y: 300, width: 520, height: 600)
        let moved = try! XCTUnwrap(FloatingTilePlacement.reclamp(frame: frame, visibleFrames: [main]))
        XCTAssertTrue(main.contains(CGRect(origin: moved, size: frame.size)))
        XCTAssertEqual(moved, CGPoint(x: 1440 - 520, y: 275))
        // Still on its display: unchanged.
        XCTAssertEqual(FloatingTilePlacement.reclamp(frame: frame, visibleFrames: [main, side]), frame.origin)
        // The frozen footprint no longer fits the remaining display: the caller dismisses.
        XCTAssertNil(FloatingTilePlacement.reclamp(frame: CGRect(x: 1500, y: 0, width: 900, height: 1000),
                                                   visibleFrames: [main]))
        XCTAssertNil(FloatingTilePlacement.reclamp(frame: frame, visibleFrames: []))
    }

    // MARK: Detail opens inward from a stationary primary (D-044)

    private let even: [StatKind: CGSize] = Dictionary(uniqueKeysWithValues: StatKind.allCases.map { ($0, CGSize(width: 250, height: 150)) })

    // Eleven stats, four columns: CPU 2×2 (cols 0–1, rows 0–1); Memory, Disk 2×1 (cols 2–3, rows
    // 0, 1); row 2 Network, Battery, GPU, Fans; row 3 Power, Temperature, Load, Uptime.

    func testSideFollowsTheHalfOfTheOverviewThePrimaryIsIn() {
        let p = plan(StatKind.allCases, details: even)
        for kind in [StatKind.cpu, .network, .battery, .power, .temps] {
            XCTAssertEqual(p.detailSides[kind], .right, "\(kind) is in the left half: opens right")
        }
        for kind in [StatKind.memory, .disk, .gpu, .fan, .loadAverage, .uptime] {
            XCTAssertEqual(p.detailSides[kind], .left, "\(kind) is in the right half: opens left")
        }
        XCTAssertEqual(FloatingTilePlan.preferredSide(tile: CGRect(x: 0, y: 0, width: 100, height: 10),
                                                      overview: CGRect(x: 0, y: 0, width: 100, height: 10)),
                       .right, "a full-width primary opens right")
    }

    func testRowEdgeAlignment() {
        let p = plan(StatKind.allCases, details: even)
        for kind in [StatKind.cpu, .memory, .disk] {
            XCTAssertEqual(p.detailAlignments[kind], .top)
            XCTAssertEqual(p.detailFrames[kind]?.minY, p.tileFrames[kind]?.minY, "\(kind): top edges level")
        }
        for kind in [StatKind.network, .fan, .power, .uptime] {
            XCTAssertEqual(p.detailAlignments[kind], .bottom)
            XCTAssertEqual(p.detailFrames[kind]?.maxY, p.tileFrames[kind]?.maxY, "\(kind): bottom edges level")
        }
        let cpu = try! XCTUnwrap(p.detailFrames[.cpu]), cpuTile = try! XCTUnwrap(p.tileFrames[.cpu])
        XCTAssertEqual(cpu.minX, cpuTile.maxX + 12, "opens into the space the other primaries left")
        let memory = try! XCTUnwrap(p.detailFrames[.memory]), memoryTile = try! XCTUnwrap(p.tileFrames[.memory])
        XCTAssertEqual(memory.maxX + 12, memoryTile.minX)
        XCTAssertEqual(cpu.height, 150, "height fits the content: no padding to the primary's height")
    }

    func testFlipsToTheOppositeSideWithoutRoom() {
        // Display edge exactly at the overview's right edge: right-opening details do not fit.
        let bounds = CGRect(x: -900, y: -200, width: 1380, height: 1000)
        let p = FloatingTilePlan.make(kinds: StatKind.allCases, detailSizes: even, available: roomy, bounds: bounds)
        XCTAssertEqual(p.detailSides[.cpu], .left)
        XCTAssertEqual(p.detailSides[.battery], .left)
        XCTAssertEqual(p.detailSides[.memory], .left, "left-opening details are unaffected")
        let cpu = try! XCTUnwrap(p.detailFrames[.cpu]), cpuTile = try! XCTUnwrap(p.tileFrames[.cpu])
        XCTAssertEqual(cpu.maxX + 12, cpuTile.minX)
        XCTAssertEqual(cpu.minY, cpuTile.minY, "alignment is kept after a flip")
        let region = bounds.offsetBy(dx: p.coreFrame.minX, dy: p.coreFrame.minY)
        for kind in StatKind.allCases {
            XCTAssertTrue(region.contains(try! XCTUnwrap(p.detailFrames[kind])), "\(kind) stays on the display")
        }
    }

    func testNeitherSideFitsUsesTheRoomierSideOnTheDisplay() {
        // A display exactly as wide as the overview.
        let bounds = CGRect(x: 0, y: -200, width: 480, height: 1000)
        let p = FloatingTilePlan.make(kinds: StatKind.allCases, detailSizes: even, available: roomy, bounds: bounds)
        XCTAssertEqual(p.coreFrame.minX, 0, "nothing extends past the display")
        XCTAssertEqual(p.detailSides[.cpu], .right, "234 points on the right beats none on the left")
        XCTAssertEqual(p.detailSides[.memory], .left)
        let region = bounds.offsetBy(dx: p.coreFrame.minX, dy: p.coreFrame.minY)
        for kind in StatKind.allCases {
            let detail = try! XCTUnwrap(p.detailFrames[kind])
            XCTAssertTrue(region.contains(detail), "\(kind) clamped onto the display")
            XCTAssertEqual(detail.width, 250, "\(kind) keeps its measured width; text never shrinks")
        }
    }

    func testTallDetailScrollsWithinTheRegionAndClearsTheBar() {
        let bounds = CGRect(x: -600, y: -300, width: 1800, height: 700)
        let p = FloatingTilePlan.make(kinds: [.cpu, .network], detailSizes: [.cpu: CGSize(width: 244, height: 900)],
                                      available: roomy, bounds: bounds)
        XCTAssertEqual(p.scrollingDetails, [.cpu])
        let region = bounds.offsetBy(dx: p.coreFrame.minX, dy: p.coreFrame.minY)
        let cpu = try! XCTUnwrap(p.detailFrames[.cpu])
        XCTAssertTrue(region.contains(cpu))
        XCTAssertFalse(cpu.intersects(p.barFrame), "Settings and Quit stay reachable")
        XCTAssertLessThan(cpu.height, 900)
    }

    func testBottomAlignedTallDetailStartsBelowTheBar() {
        let p = plan(StatKind.allCases, details: [.network: CGSize(width: 250, height: 400)])
        let network = try! XCTUnwrap(p.detailFrames[.network])
        XCTAssertFalse(network.intersects(p.barFrame.insetBy(dx: -11, dy: -11)))
        XCTAssertEqual(network.minY, p.contentOrigin.y)
        XCTAssertEqual(network.height, 400, "room below the bar: nothing scrolls")
        XCTAssertTrue(p.scrollingDetails.isEmpty)
    }

    func testPrimaryFramesAreTheSameWhereverDetailsGo() {
        let centred = plan(StatKind.allCases, details: even)
        let corner = FloatingTilePlan.make(kinds: StatKind.allCases, detailSizes: even, available: roomy,
                                           bounds: CGRect(x: 0, y: 0, width: 1400, height: 860))
        let tall = plan(StatKind.allCases, details: [.cpu: CGSize(width: 600, height: 800)])
        for kind in StatKind.allCases {
            XCTAssertEqual(c(centred, centred.tileFrames[kind]), c(corner, corner.tileFrames[kind]))
            XCTAssertEqual(c(centred, centred.tileFrames[kind]), c(tall, tall.tileFrames[kind]),
                           "\(kind): opening any detail never moves a primary")
            XCTAssertFalse(try! XCTUnwrap(centred.detailFrames[kind]).intersects(try! XCTUnwrap(centred.tileFrames[kind])))
        }
        XCTAssertEqual(c(centred, centred.barFrame), c(corner, corner.barFrame))
    }

    func testHostCoversTheCoreAndEveryDetail() {
        let p = plan(StatKind.allCases, details: even)
        let host = CGRect(origin: .zero, size: p.size)
        XCTAssertTrue(host.contains(p.coreFrame))
        for kind in StatKind.allCases { XCTAssertTrue(host.contains(try! XCTUnwrap(p.detailFrames[kind]))) }
        XCTAssertEqual(p.detailFrames.values.reduce(p.coreFrame) { $0.union($1) }, host, "and no more")
    }

    func testBoundsAndHostFrameConvertBetweenScreenAndCore() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let coreOrigin = CGPoint(x: 100, y: 200), coreSize = CGSize(width: 598, height: 476)
        XCTAssertEqual(FloatingTilePlacement.bounds(coreOrigin: coreOrigin, coreSize: coreSize, visible: visible),
                       CGRect(x: -92, y: 200 + 476 - 892, width: 1424, height: 884))
        let p = plan(StatKind.allCases, details: even)
        let host = FloatingTilePlacement.hostFrame(coreOrigin: coreOrigin, plan: p)
        XCTAssertEqual(host.minX + p.coreFrame.minX, coreOrigin.x, "core lands where it was placed")
        XCTAssertEqual(host.maxY - p.coreFrame.minY, coreOrigin.y + p.coreFrame.height)
        XCTAssertEqual(host.size, p.size)
    }
}

private extension FloatingTilePlan {
    /// The same plan with only the reserve value changed (frames equal when nothing scrolls).
    func withReserve(_ reserve: CGFloat) -> FloatingTilePlan {
        FloatingTilePlan(kinds: kinds, metrics: metrics, columns: columns, size: size, coreFrame: coreFrame,
                         overviewFrame: overviewFrame, barFrame: barFrame, barItemFrames: barItemFrames,
                         tileFrames: tileFrames, detailFrames: detailFrames, detailSides: detailSides,
                         detailAlignments: detailAlignments, scrollingDetails: scrollingDetails,
                         overviewViewport: overviewViewport, scrollerReserve: reserve,
                         emptyStateFrame: emptyStateFrame, fits: fits)
    }
}
#endif

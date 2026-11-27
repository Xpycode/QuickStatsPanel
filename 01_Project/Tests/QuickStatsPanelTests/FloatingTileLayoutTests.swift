import XCTest

#if DEBUG
/// Frozen floating-tile geometry: packing, a fixed core (bar, overview), a host envelope sized at
/// summon, details placed when opened from their measured size, sideways from their primary
/// toward the larger part of the old overview (D-044), all sharing the overview's top edge with a
/// 6-point gap (D-045), column reduction and visual-neighbour navigation. Core-relative frames use
/// `c(_:_:)` because the envelope to the left shifts the core inside the host.
final class FloatingTileLayoutTests: XCTestCase {

    private let roomy = CGSize(width: 1400, height: 860)
    private let details: [StatKind: CGSize] = [.cpu: CGSize(width: 244, height: 330),
                                               .network: CGSize(width: 284, height: 560)]

    private func plan(_ kinds: [StatKind] = [.cpu, .network], available: CGSize? = nil,
                      bounds: CGRect? = nil, reserve: CGFloat = 0) -> FloatingTilePlan {
        FloatingTilePlan.make(kinds: kinds, available: available ?? roomy, bounds: bounds, scrollerReserve: reserve)
    }

    /// Opens `kind` with the given measured size (D-045: measured at open); 250×150 by default.
    private func open(_ p: FloatingTilePlan, _ kind: StatKind, _ size: CGSize? = nil) -> FloatingTileDetailPlacement {
        p.detailPlacement(for: kind, measured: size ?? CGSize(width: 250, height: 150))
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
        let p = plan(StatKind.allCases)
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
            let detail = open(p, kind).frame
            XCTAssertFalse(detail.intersects(p.barFrame.insetBy(dx: -11, dy: -11)), "\(kind) detail keeps clear of the bar")
            XCTAssertFalse(detail.intersects(try! XCTUnwrap(p.tileFrames[kind]).insetBy(dx: -5, dy: 0)),
                           "\(kind) detail sits beside its primary, with the gap")
            XCTAssertTrue(CGRect(origin: .zero, size: p.size).contains(detail))
        }
    }
    func testWideDetailNeverResizesTheCoreOrTheHost() {
        let p = plan()
        let before = p
        XCTAssertEqual(open(p, .network, CGSize(width: 400, height: 300)).frame.width, 400)
        XCTAssertEqual(p.coreFrame.width, 480)
        XCTAssertEqual(p, before, "opening computes a placement; the summon's plan is unchanged")
    }
    func testOversizedDetailIsHeightLimitedAndOnlyItScrolls() {
        let p = plan(available: CGSize(width: 1400, height: 500))
        // Centred core (252 tall) in 500: the display bottom is 124 below the core; the detail
        // starts at the overview's top (40), so 336 points are available.
        let network = open(p, .network, details[.network])
        XCTAssertEqual(network.frame.minY, p.overviewFrame.minY)
        XCTAssertEqual(network.frame.height, 336, "limited to the display's bottom")
        XCTAssertTrue(network.scrolls)
        let cpu = open(p, .cpu, details[.cpu])
        XCTAssertEqual(cpu.frame.height, 330, "a card that fits keeps its measured height")
        XCTAssertFalse(cpu.scrolls)
        XCTAssertLessThanOrEqual(p.size.height, 500)
        XCTAssertTrue(p.fits)
    }
    func testNarrowDisplayReducesColumnsAtSummon() {
        let p = plan([.cpu, .network, .memory, .disk, .gpu], available: CGSize(width: 420, height: 900))
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
        XCTAssertEqual(plan(), plan(), "the plan depends only on identities and the display, not readings")
        XCTAssertEqual(open(plan(), .cpu), open(plan(), .cpu), "the same measured size places the same frame")
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
        let p = plan(StatKind.allCases)
        XCTAssertEqual(Set(p.targetFrames(open: .network).keys), [.tile(.network), .handle, .settings, .quit],
                       "the other primaries are hidden, and there is no switcher")
        XCTAssertEqual(Set(p.targetFrames(open: nil).keys).count, 11 + 3, "every primary plus the bar in the overview")
        XCTAssertNotEqual(p.neighbour(of: .tile(.cpu), .right, open: .cpu), .tile(.memory), "hidden primaries are skipped")
        let up = p.neighbour(of: .tile(.memory), .up, open: .memory)
        XCTAssertTrue([FloatingTileTarget.handle, .settings, .quit].contains(up), "the bar stays reachable")
    }
    func testElevenStatOverviewNeighboursAreGeometric() {
        let p = plan(StatKind.allCases)
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
        XCTAssertEqual(m.gap, 12, "between primaries")
        XCTAssertEqual(m.detailGap, 6, "between an open primary and its detail (D-045)")
        XCTAssertEqual(m.detailEnvelopeWidth, 480)
        XCTAssertEqual(m.barWidth, 106)
        XCTAssertEqual(m.minimumColumns, 2)
    }

    func testSavedOrderDrivesHierarchy() {
        let order: [StatKind] = [.uptime, .gpu, .memory, .cpu, .fan]
        let p = plan(order)
        XCTAssertEqual(p.tileFrames[.uptime]?.size, CGSize(width: 234, height: 212), "first is the large tile")
        XCTAssertEqual(p.tileFrames[.gpu]?.size, CGSize(width: 234, height: 100))
        XCTAssertEqual(p.tileFrames[.memory]?.size, CGSize(width: 234, height: 100))
        XCTAssertEqual(p.tileFrames[.cpu]?.size, CGSize(width: 111, height: 100), "the rest are 1×1")
        XCTAssertEqual(p.tileFrames[.cpu]?.origin.y, p.tileFrames[.fan]?.origin.y)
        XCTAssertLessThan(try! XCTUnwrap(p.tileFrames[.cpu]).minX, try! XCTUnwrap(p.tileFrames[.fan]).minX)
    }

    func testReorderingChangesTheLargeTileButNothingElseDependsOnReadings() {
        let a = plan(StatKind.allCases)
        let b = plan(StatKind.allCases.reversed())
        XCTAssertEqual(a.tileFrames[.cpu]?.size, CGSize(width: 234, height: 212))
        XCTAssertEqual(b.tileFrames[.uptime]?.size, CGSize(width: 234, height: 212))
        XCTAssertEqual(a.coreFrame.size, b.coreFrame.size, "the core depends on the count, not the order")
    }

    func testElevenStatFootprintFitsAComfortableDisplayAndStaysInsideItself() {
        let p = plan(StatKind.allCases, available: CGSize(width: 1400, height: 860))
        XCTAssertTrue(p.fits)
        let bounds = CGRect(origin: .zero, size: p.size)
        for frame in Array(p.tileFrames.values) + [p.barFrame] {
            XCTAssertTrue(bounds.contains(frame), "\(frame) inside \(bounds)")
        }
        for kind in StatKind.allCases {
            XCTAssertNotNil(p.tileFrames[kind], "\(kind) has a tile")
            XCTAssertTrue(bounds.contains(open(p, kind).frame), "\(kind) opens inside the host")
        }
        XCTAssertNil(p.emptyStateFrame)
    }
    func testOneStatKeepsTheLargeTileAndOpensRight() {
        let p = plan([.memory])
        XCTAssertEqual(p.tileFrames[.memory]?.size, CGSize(width: 234, height: 212))
        XCTAssertEqual(p.tileFrames.count, 1)
        XCTAssertEqual(open(p, .memory).side, .right, "left half of the overview opens right")
        XCTAssertTrue(p.fits)
    }
    func testEmptyPlanHasACompactEmptyStateAndReachableBar() {
        let p = plan([])
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
        let p = plan([.disk, .battery, .uptime, .memory, .temps])
        XCTAssertEqual(p.tileFrames.count, 5)
        XCTAssertEqual(p.tileFrames[.disk]?.size, CGSize(width: 234, height: 212))
        let frames = Array(p.tileFrames.values)
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] { XCTAssertFalse(a.intersects(b)) }
        }
    }

    // MARK: Task 3.1 — constrained displays, scroll bars and placement

    func testFootprintHeightIsBarPlusTallestContent() {
        let p = plan(StatKind.allCases)
        // Four 100-point rows with three 12-point gaps below the 28-point bar and its gap.
        XCTAssertEqual(p.coreFrame.height, 40 + 436, "no transparent band below the overview")
        XCTAssertNil(p.overviewViewport, "a comfortable display never scrolls the overview")
    }

    func testTooShortForTheOverviewScrollsItWithNavigationOutside() {
        let available = CGSize(width: 420, height: 600)
        let p = plan(StatKind.allCases, available: available)
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
        let overlay = plan(available: short)
        let legacy = plan(available: short, reserve: 15)
        XCTAssertEqual(open(overlay, .network, details[.network]).frame.width, 284)
        XCTAssertEqual(open(legacy, .network, details[.network]).frame.width, 284 + 15, "the scrolling card gets the scroll bar's width")
        XCTAssertTrue(open(legacy, .network, details[.network]).scrolls)
        XCTAssertEqual(open(legacy, .cpu, details[.cpu]).frame.width, 244, "a card that fits keeps its measured width")
        XCTAssertFalse(open(legacy, .network, details[.network]).frame.intersects(try! XCTUnwrap(legacy.tileFrames[.network])))
        XCTAssertEqual(open(legacy, .network, CGSize(width: 400, height: 560)).frame.width, 400 + 15,
                       "the reserve widens only the scrolling card")
        XCTAssertEqual(legacy.coreFrame.width, 480, "and never the core")
        XCTAssertEqual(c(legacy, legacy.tileFrames[.cpu]), c(overlay, overlay.tileFrames[.cpu]))
    }
    func testShortAndLongDetailsAreEachContentSized() {
        let p = plan(StatKind.allCases, available: CGSize(width: 1400, height: 600))
        let sizes: [StatKind: CGSize] = [.cpu: CGSize(width: 244, height: 330),
                                         .network: CGSize(width: 284, height: 900),
                                         .uptime: CGSize(width: 200, height: 90)]
        XCTAssertTrue(open(p, .network, sizes[.network]).scrolls, "the oversized card scrolls")
        XCTAssertFalse(open(p, .cpu, sizes[.cpu]).scrolls)
        XCTAssertEqual(open(p, .uptime, sizes[.uptime]).frame.height, 90, "a short card stays content-sized")
        for kind in [StatKind.cpu, .network, .uptime] {
            let detail = open(p, kind, sizes[kind]).frame
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

    // MARK: Detail opens inward from a stationary primary (D-044), one top line, 6-point gap (D-045)

    // Eleven stats, four columns: CPU 2×2 (cols 0–1, rows 0–1); Memory, Disk 2×1 (cols 2–3, rows
    // 0, 1); row 2 Network, Battery, GPU, Fans; row 3 Power, Temperature, Load, Uptime.

    func testSideFollowsTheHalfOfTheOverviewThePrimaryIsIn() {
        let p = plan(StatKind.allCases)
        for kind in [StatKind.cpu, .network, .battery, .power, .temps] {
            XCTAssertEqual(open(p, kind).side, .right, "\(kind) is in the left half: opens right")
        }
        for kind in [StatKind.memory, .disk, .gpu, .fan, .loadAverage, .uptime] {
            XCTAssertEqual(open(p, kind).side, .left, "\(kind) is in the right half: opens left")
        }
        XCTAssertEqual(FloatingTilePlan.preferredSide(tile: CGRect(x: 0, y: 0, width: 100, height: 10),
                                                      overview: CGRect(x: 0, y: 0, width: 100, height: 10)),
                       .right, "a full-width primary opens right")
    }
    func testEveryDetailSharesTheOverviewTopWithASixPointGap() {
        let p = plan(StatKind.allCases)
        for kind in StatKind.allCases {
            XCTAssertEqual(open(p, kind).frame.minY, p.overviewFrame.minY, "\(kind): top = overview top (D-045)")
        }
        let cpu = open(p, .cpu).frame, cpuTile = try! XCTUnwrap(p.tileFrames[.cpu])
        XCTAssertEqual(cpu.minX, cpuTile.maxX + 6, "opens into the space the other primaries left, 6 points away")
        let memory = open(p, .memory).frame, memoryTile = try! XCTUnwrap(p.tileFrames[.memory])
        XCTAssertEqual(memory.maxX + 6, memoryTile.minX)
        XCTAssertEqual(cpu.height, 150, "height fits the content: no padding to the primary's height")
        let network = try! XCTUnwrap(p.tileFrames[.network]), battery = try! XCTUnwrap(p.tileFrames[.battery])
        XCTAssertEqual(battery.minX - network.maxX, 12, "gaps between primaries stay 12 points")
    }

    func testBottomRowPrimariesAlsoTopAlign() {
        let p = plan(StatKind.allCases)
        // Row 3 (the bottom row): Power, Temperature, Load, Uptime.
        for kind in [StatKind.power, .temps, .loadAverage, .uptime] {
            let tile = try! XCTUnwrap(p.tileFrames[kind])
            XCTAssertEqual(tile.maxY, p.overviewFrame.maxY, "\(kind) is in the bottom row")
            let detail = open(p, kind, CGSize(width: 250, height: 400)).frame
            XCTAssertEqual(detail.minY, p.overviewFrame.minY, "\(kind): top edge at the overview's top, not the tile's")
            XCTAssertNotEqual(detail.maxY, tile.maxY, "no bottom alignment")
            XCTAssertEqual(detail.height, 400, "room below: nothing scrolls")
        }
    }
    func testFlipsToTheOppositeSideWithoutRoom() {
        // Display edge exactly at the overview's right edge: right-opening details do not fit.
        let bounds = CGRect(x: -900, y: -200, width: 1380, height: 1000)
        let p = plan(StatKind.allCases, bounds: bounds)
        XCTAssertEqual(open(p, .cpu).side, .left)
        XCTAssertEqual(open(p, .battery).side, .left)
        XCTAssertEqual(open(p, .memory).side, .left, "left-opening details are unaffected")
        let cpu = open(p, .cpu).frame, cpuTile = try! XCTUnwrap(p.tileFrames[.cpu])
        XCTAssertEqual(cpu.maxX + 6, cpuTile.minX)
        XCTAssertEqual(cpu.minY, p.overviewFrame.minY, "the top line is kept after a flip")
        let region = bounds.offsetBy(dx: p.coreFrame.minX, dy: p.coreFrame.minY)
        for kind in StatKind.allCases {
            XCTAssertTrue(region.contains(open(p, kind).frame), "\(kind) stays on the display")
        }
    }
    func testNeitherSideFitsUsesTheRoomierSideOnTheDisplay() {
        // A display exactly as wide as the overview.
        let bounds = CGRect(x: 0, y: -200, width: 480, height: 1000)
        let p = plan(StatKind.allCases, bounds: bounds)
        XCTAssertEqual(p.coreFrame.minX, 0, "nothing extends past the display")
        XCTAssertEqual(p.size.width, 480, "the envelope is clamped to the display")
        XCTAssertEqual(open(p, .cpu).side, .right, "240 points on the right beats none on the left")
        XCTAssertEqual(open(p, .memory).side, .left)
        let region = bounds.offsetBy(dx: p.coreFrame.minX, dy: p.coreFrame.minY)
        for kind in StatKind.allCases {
            let detail = open(p, kind).frame
            XCTAssertTrue(region.contains(detail), "\(kind) clamped onto the display")
            XCTAssertEqual(detail.width, 250, "\(kind) keeps its measured width; text never shrinks")
        }
    }
    func testTallDetailScrollsWithinTheRegionAndClearsTheBar() {
        let bounds = CGRect(x: -600, y: -300, width: 1800, height: 700)
        let p = plan(bounds: bounds)
        let cpu = open(p, .cpu, CGSize(width: 244, height: 900))
        XCTAssertTrue(cpu.scrolls)
        let region = bounds.offsetBy(dx: p.coreFrame.minX, dy: p.coreFrame.minY)
        XCTAssertTrue(region.contains(cpu.frame))
        XCTAssertFalse(cpu.frame.intersects(p.barFrame), "Settings and Quit stay reachable")
        XCTAssertEqual(cpu.frame.minY, p.overviewFrame.minY)
        XCTAssertEqual(cpu.frame.maxY, region.maxY, "runs to the display's bottom, then scrolls")
    }
    func testTooTallFromTheTopLineScrollsEvenForABottomRowPrimary() {
        // The display ends 100 points below the overview's bottom.
        let p0 = plan(StatKind.allCases)
        let overviewBottom = c(p0, p0.overviewFrame)!.maxY
        let bounds = CGRect(x: -600, y: -300, width: 1800, height: 300 + overviewBottom + 100)
        let p = plan(StatKind.allCases, bounds: bounds)
        let uptime = open(p, .uptime, CGSize(width: 250, height: 700))
        XCTAssertEqual(uptime.frame.minY, p.overviewFrame.minY)
        XCTAssertEqual(uptime.frame.height, p.overviewFrame.height + 100, "from the top line to the display's bottom")
        XCTAssertTrue(uptime.scrolls)
        XCTAssertFalse(open(p, .uptime, CGSize(width: 250, height: p.overviewFrame.height + 100)).scrolls,
                       "exactly fitting does not scroll")
    }
    func testPrimaryFramesAreTheSameWhereverDetailsGo() {
        let centred = plan(StatKind.allCases)
        let corner = plan(StatKind.allCases, bounds: CGRect(x: 0, y: 0, width: 1400, height: 860))
        let snapshot = centred
        for kind in StatKind.allCases {
            _ = open(centred, kind, CGSize(width: 600, height: 800))
            XCTAssertEqual(c(centred, centred.tileFrames[kind]), c(corner, corner.tileFrames[kind]))
            XCTAssertFalse(open(centred, kind).frame.intersects(try! XCTUnwrap(centred.tileFrames[kind])))
        }
        XCTAssertEqual(centred, snapshot, "opening any detail never moves a primary or resizes the host")
        XCTAssertEqual(c(centred, centred.barFrame), c(corner, corner.barFrame))
    }

    func testPlacementFollowsTheCurrentDisplayAfterADrag() {
        let p = plan(StatKind.allCases)
        // The group was dragged so the display now ends at the overview's right edge.
        let display = CGRect(x: 0, y: 0, width: p.overviewFrame.maxX, height: p.size.height)
        let cpu = p.detailPlacement(for: .cpu, measured: CGSize(width: 250, height: 150), display: display)
        XCTAssertEqual(cpu.side, .left, "no room on the right of the current display: flips")
        XCTAssertTrue(display.contains(cpu.frame))
    }
    func testHostIsTheCorePlusTheEnvelopeAndCoversEveryDetail() {
        // A display with more than the envelope's room on both sides.
        let p = plan(StatKind.allCases, bounds: CGRect(x: -1000, y: -200, width: 2480, height: 1200))
        let host = CGRect(origin: .zero, size: p.size)
        XCTAssertTrue(host.contains(p.coreFrame))
        XCTAssertEqual(p.coreFrame.minX, 6 + 480, "room for the widest detail on the left")
        XCTAssertEqual(host.maxX - p.coreFrame.maxX, 6 + 480, "and on the right")
        XCTAssertEqual(p.coreFrame.minY, 0, "nothing opens above the overview's top")
        XCTAssertEqual(host.maxY, p.detailRegion.maxY, "down to the display's bottom")
        for kind in StatKind.allCases {
            XCTAssertTrue(host.contains(open(p, kind).frame))
            XCTAssertTrue(host.contains(open(p, kind, CGSize(width: 480, height: 2000)).frame), "\(kind) widest")
        }
    }
    func testBoundsAndHostFrameConvertBetweenScreenAndCore() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let coreOrigin = CGPoint(x: 100, y: 200), coreSize = CGSize(width: 598, height: 476)
        XCTAssertEqual(FloatingTilePlacement.bounds(coreOrigin: coreOrigin, coreSize: coreSize, visible: visible),
                       CGRect(x: -92, y: 200 + 476 - 892, width: 1424, height: 884))
        let p = plan(StatKind.allCases)
        let host = FloatingTilePlacement.hostFrame(coreOrigin: coreOrigin, plan: p)
        XCTAssertEqual(host.minX + p.coreFrame.minX, coreOrigin.x, "core lands where it was placed")
        XCTAssertEqual(host.maxY - p.coreFrame.minY, coreOrigin.y + p.coreFrame.height)
        XCTAssertEqual(host.size, p.size)
    }
}
#endif

import XCTest

#if DEBUG
/// Frozen floating-tile geometry: packing, a fixed core (bar, overview, switcher column), detail
/// cards beside the core on the side nearest their tile, column reduction and visual-neighbour
/// navigation. Core-relative frames use `c(_:_:)` because cards to the left/top shift the core.
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
        XCTAssertEqual(p.coreFrame.width, 480 + 12 + 106, "the 480-point overview plus the reserved switcher column")
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

    func testSwitcherSitsRightOfTheOverviewAndNoCardOverlapsTheCore() {
        let p = plan()
        XCTAssertEqual(p.switcherFrame.maxX, p.coreFrame.maxX)
        XCTAssertEqual(p.switcherFrame.minX, p.contentOrigin.x + 480 + 12)
        XCTAssertEqual(p.switcherFrame.width, 106)
        XCTAssertEqual(p.barFrame.maxX, p.contentOrigin.x + 480, "the bar sits above the overview's right edge")
        for kind in p.kinds {
            let detail = try! XCTUnwrap(p.detailFrames[kind])
            XCTAssertFalse(detail.intersects(p.coreFrame.insetBy(dx: -11, dy: -11)), "\(kind) card keeps the gap to the core")
            XCTAssertTrue(CGRect(origin: .zero, size: p.size).contains(detail))
        }
        for (target, frame) in p.switcherItemFrames {
            XCTAssertTrue(p.switcherFrame.contains(frame), "\(target) inside the switcher")
        }
    }

    func testWideDetailNeverResizesTheCore() {
        let p = plan(details: [.cpu: CGSize(width: 244, height: 300), .network: CGSize(width: 400, height: 300)])
        XCTAssertEqual(p.coreFrame.width, 480 + 12 + 106)
        XCTAssertEqual(p.detailFrames[.network]?.width, 400)
        XCTAssertEqual(c(p, p.switcherFrame)?.minX, 480 + 12, "one switcher position for every detail")
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
        XCTAssertEqual(p.neighbour(of: .tile(.cpu), .right, detail: true), .tile(.network),
                       "the overview stays reachable while a card is open")
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
        XCTAssertEqual(a.coreFrame.size, b.coreFrame.size, "the core depends on the count, not the order")
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
        XCTAssertLessThanOrEqual(viewport.maxX + 12, p.switcherFrame.minX, "the switcher never overlaps the overview")
        XCTAssertTrue(p.fits, "navigation (bar and switcher) still fits")
        XCTAssertTrue(CGRect(origin: .zero, size: p.size).contains(p.switcherFrame))
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
        XCTAssertEqual(legacy.switcherFrame.maxX, legacy.coreFrame.maxX, "one switcher position, chosen at summon")
        XCTAssertFalse(try! XCTUnwrap(legacy.detailFrames[.network]).intersects(legacy.coreFrame))
        let wide = FloatingTilePlan.make(kinds: [.cpu, .network], detailSizes: [.network: CGSize(width: 400, height: 560)],
                                         available: short, scrollerReserve: 15)
        XCTAssertEqual(wide.detailFrames[.network]?.width, 400 + 15, "the reserve widens only the scrolling card")
        XCTAssertEqual(wide.coreFrame.width, 480 + 12 + 106, "and never the core")
        XCTAssertEqual(legacy.scrollingDetails, [.network])
        let roomyLegacy = FloatingTilePlan.make(kinds: [.cpu, .network], detailSizes: details, available: roomy,
                                                scrollerReserve: 15)
        XCTAssertEqual(roomyLegacy, plan().withReserve(15), "nothing scrolls, so nothing is reserved")
    }

    func testShortAndLongCardsShareOneSwitcher() {
        let p = plan(StatKind.allCases, details: [.cpu: CGSize(width: 244, height: 330),
                                                  .network: CGSize(width: 284, height: 560),
                                                  .uptime: CGSize(width: 200, height: 90)],
                     available: CGSize(width: 1400, height: 500))
        XCTAssertEqual(p.scrollingDetails, [.network], "only the oversized card scrolls")
        XCTAssertEqual(p.detailFrames[.uptime]?.height, 90, "a short card stays content-sized")
        for kind in [StatKind.cpu, .network, .uptime] {
            XCTAssertFalse(try! XCTUnwrap(p.detailFrames[kind]).intersects(p.coreFrame), "\(kind) never covers the core")
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

    func testDetailArrowsReachBarTilesAndSwitcher() {
        let p = plan(StatKind.allCases, details: details)
        let up = p.neighbour(of: .switcher(.cpu), .up, detail: true)
        XCTAssertTrue([FloatingTileTarget.handle, .settings, .quit].contains(up), "above the switcher is the bar")
        let targets = p.targetFrames(detail: true).keys
        for kind in StatKind.allCases {
            XCTAssertTrue(targets.contains(.tile(kind)), "\(kind) tile stays a target")
            XCTAssertTrue(targets.contains(.switcher(kind)), "\(kind) switcher item is a target")
        }
        XCTAssertFalse(p.targetFrames(detail: false).keys.contains(.switcher(.cpu)), "the switcher is hidden in the overview")
        XCTAssertEqual(p.neighbour(of: .tile(.fan), .right, detail: true).map { p.switcherFrame.contains(p.targetFrames(detail: true)[$0]!) }, true,
                       "right of the overview is the switcher")
    }

    // MARK: Detail beside the overview (E1 case B revision)

    private let even: [StatKind: CGSize] = Dictionary(uniqueKeysWithValues: StatKind.allCases.map { ($0, CGSize(width: 250, height: 150)) })

    func testCardOpensOnTheSideNearestItsTile() {
        let p = plan(StatKind.allCases, details: even)
        XCTAssertEqual(p.detailSides[.cpu], .left)
        XCTAssertEqual(p.detailSides[.memory], .top)
        XCTAssertEqual(p.detailSides[.disk], .right)
        XCTAssertEqual(p.detailSides[.network], .left)
        XCTAssertEqual(p.detailSides[.fan], .right)
        XCTAssertEqual(p.detailSides[.temps], .bottom)
        XCTAssertEqual(p.detailSides[.loadAverage], .bottom)
        XCTAssertEqual(p.detailSides[.uptime], .right, "a near-tie at a corner opens sideways")
        for kind in StatKind.allCases {
            let card = try! XCTUnwrap(p.detailFrames[kind])
            XCTAssertFalse(card.intersects(p.coreFrame), "\(kind) card is beside, not over, the overview")
        }
    }

    func testCardLinesUpWithItsTile() {
        let p = plan(StatKind.allCases, details: even)
        let cpu = try! XCTUnwrap(p.detailFrames[.cpu]), cpuTile = try! XCTUnwrap(p.tileFrames[.cpu])
        XCTAssertEqual(cpu.minY, cpuTile.minY, "side card top level with the tile top")
        XCTAssertEqual(cpu.maxX + 12, p.coreFrame.minX)
        let memory = try! XCTUnwrap(p.detailFrames[.memory]), memoryTile = try! XCTUnwrap(p.tileFrames[.memory])
        XCTAssertEqual(memory.minX, memoryTile.minX, "top card left edge level with the tile")
        XCTAssertEqual(memory.maxY + 12, p.coreFrame.minY)
        let disk = try! XCTUnwrap(p.detailFrames[.disk])
        XCTAssertEqual(disk.minX, p.coreFrame.maxX + 12, "right cards open past the switcher column")
    }

    func testCardFallsBackToTheOppositeSideWithoutRoom() {
        // Core pinned to the region's top-left corner: no room left or above.
        let bounds = CGRect(x: 0, y: 0, width: 1400, height: 860)
        let p = FloatingTilePlan.make(kinds: StatKind.allCases, detailSizes: even, available: roomy, bounds: bounds)
        XCTAssertEqual(p.detailSides[.cpu], .right)
        XCTAssertEqual(p.detailSides[.memory], .bottom)
        let region = bounds.offsetBy(dx: p.coreFrame.minX, dy: p.coreFrame.minY)
        for kind in StatKind.allCases {
            XCTAssertTrue(region.contains(try! XCTUnwrap(p.detailFrames[kind])), "\(kind) card stays on the display")
        }
        XCTAssertEqual(p.coreFrame.origin, .zero, "nothing extends left of or above the core")
    }

    func testTallCardIsClampedAndScrollsWithinTheRegion() {
        let bounds = CGRect(x: -600, y: -300, width: 1800, height: 700)
        let p = FloatingTilePlan.make(kinds: [.cpu, .network], detailSizes: [.cpu: CGSize(width: 244, height: 900)],
                                      available: roomy, bounds: bounds)
        XCTAssertEqual(p.scrollingDetails, [.cpu])
        let region = bounds.offsetBy(dx: p.coreFrame.minX, dy: p.coreFrame.minY)
        XCTAssertTrue(region.contains(try! XCTUnwrap(p.detailFrames[.cpu])))
        XCTAssertEqual(p.detailFrames[.cpu]?.height, 700)
    }

    func testTheCoreIsTheSameWhereverCardsGo() {
        let centred = plan(StatKind.allCases, details: even)
        let corner = FloatingTilePlan.make(kinds: StatKind.allCases, detailSizes: even, available: roomy,
                                           bounds: CGRect(x: 0, y: 0, width: 1400, height: 860))
        for kind in StatKind.allCases {
            XCTAssertEqual(c(centred, centred.tileFrames[kind]), c(corner, corner.tileFrames[kind]))
        }
        XCTAssertEqual(c(centred, centred.switcherFrame), c(corner, corner.switcherFrame))
        XCTAssertEqual(c(centred, centred.barFrame), c(corner, corner.barFrame))
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
                         barFrame: barFrame, barItemFrames: barItemFrames, tileFrames: tileFrames,
                         detailFrames: detailFrames, detailSides: detailSides, scrollingDetails: scrollingDetails, overviewViewport: overviewViewport,
                         scrollerReserve: reserve, emptyStateFrame: emptyStateFrame, switcherFrame: switcherFrame,
                         switcherItemFrames: switcherItemFrames, fits: fits)
    }
}
#endif

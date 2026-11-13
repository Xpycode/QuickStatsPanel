import XCTest

/// Hostless checks of pre-summon geometry selection: outer ring, side list, whole-list
/// fallback, edge fitting, negative display origins, pixel snapping and the scrolling
/// list model. Detail sizes are injected because `StatDetailView` lives outside the bundle.
final class RingPlacementTests: XCTestCase {

    private let v1024 = CGRect(x: 0, y: 0, width: 1024, height: 640)
    private let v1440 = CGRect(x: 0, y: 0, width: 1440, height: 900)
    /// A second display left of and below the main one: negative origin on both axes.
    private let vNegative = CGRect(x: -1440, y: -700, width: 1440, height: 900)
    private let vLarge = CGRect(x: 0, y: 0, width: 3000, height: 2000)

    private func reading(_ kind: StatKind) -> RingReading {
        RingReading(value: "42%", widestValue: kind.ringFallbackWidest)
    }

    private func snapshot(_ kinds: [StatKind], measure: ((StatKind, RingReading) -> CGSize)? = nil) -> RingSnapshot {
        if let measure {
            return RingSnapshot.make(enabledKinds: kinds, reading: reading, measure: measure)
        }
        return RingSnapshot.make(enabledKinds: kinds, reading: reading)
    }

    private func details(_ kinds: [StatKind], width: CGFloat = 300, height: CGFloat = 320) -> [StatKind: CGSize] {
        Dictionary(uniqueKeysWithValues: kinds.map { ($0, CGSize(width: width, height: height)) })
    }

    private func preferred(centeredAt p: CGPoint) -> CGRect {
        CGRect(x: p.x - 260, y: p.y - 260, width: 520, height: 520)
    }

    private func plan(_ s: RingSnapshot, visible: CGRect, at p: CGPoint? = nil,
                      detail: [StatKind: CGSize]? = nil, scale: CGFloat = 1,
                      canShift: Bool = true, allowWholeList: Bool = true) -> RingPlan {
        let center = p ?? CGPoint(x: visible.midX, y: visible.midY)
        return RingPlacement.resolve(.init(snapshot: s, visible: visible, preferredBase: preferred(centeredAt: center),
                                           detailSizes: detail ?? details(s.enabledKinds), scale: scale,
                                           canShift: canShift, allowWholeList: allowWholeList))
    }

    private func assertInside(_ plan: RingPlan, _ visible: CGRect, _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line) {
        let slack = visible.insetBy(dx: -0.001, dy: -0.001)
        for frame in plan.allFrames {
            XCTAssertTrue(slack.contains(frame), "\(message) frame \(frame) outside \(visible)", file: file, line: line)
        }
    }

    private let all = Array(StatKind.allCases)
    private let eight: [StatKind] = [.cpu, .memory, .disk, .network, .battery, .gpu, .power, .temps]

    // MARK: Mode selection

    func testLargeSyntheticFrameExercisesTheOuterRingPath() throws {
        let s = snapshot(all)
        XCTAssertGreaterThan(s.moreKinds.count, 0)
        let p = plan(s, visible: vLarge)
        XCTAssertEqual(p.mode, .outerRing)
        let surface = try XCTUnwrap(p.moreSurface)
        XCTAssertEqual(surface.size, CGSize(width: 820, height: 820))
        XCTAssertEqual(surface.midX, p.baseFrame.midX, accuracy: 0.001, "outer ring is concentric with the base")
        XCTAssertEqual(surface.midY, p.baseFrame.midY, accuracy: 0.001)
        for kind in s.moreKinds {
            let detail = try XCTUnwrap(p.detailFrames[kind])
            XCTAssertFalse(detail.intersects(surface), "\(kind) detail sits beside the outer ring")
            XCTAssertNotNil(p.nodeFrames[.moreItem(kind)])
        }
        assertInside(p, vLarge)
    }

    func testOuterRingNeedsAboutEightHundredTwentyPointsPlusTheDetail() {
        let s = snapshot(all)
        XCTAssertEqual(plan(s, visible: v1440).mode, .outerRing, "1440 x 900 holds 820 + a 300-point card")
        XCTAssertEqual(plan(s, visible: v1024).mode, .sideList, "1024 x 640 cannot hold 820")
        let tight = CGRect(x: 0, y: 0, width: 1100, height: 819)
        XCTAssertNotEqual(plan(s, visible: tight).mode, .outerRing, "819 points high cannot hold the 820 footprint")
    }

    func testOuterRingFallsBackWhenMoreTextCannotFitItsSectors() {
        let wide = snapshot(all) { kind, reading in
            self.snapshotMeasure(kind, reading, more: CGSize(width: 220, height: 60))
        }
        XCTAssertEqual(plan(wide, visible: vLarge).mode, .sideList)
    }

    private func snapshotMeasure(_ kind: StatKind, _ reading: RingReading, more: CGSize) -> CGSize {
        let favourites = Set(all.prefix(RingGeometry.maxFavourites))
        return favourites.contains(kind) ? RingTypography.blockSize(name: kind.displayName, reading: reading) : more
    }

    func testSideListAt1024x640KeepsListAboveDetailBesideTheBase() throws {
        let s = snapshot(all)
        let p = plan(s, visible: v1024)
        XCTAssertEqual(p.mode, .sideList)
        XCTAssertFalse(p.isClamped)
        let list = try XCTUnwrap(p.moreSurface)
        XCTAssertEqual(list.width, RingPlacement.sideAreaWidth)
        XCTAssertEqual(list.height, CGFloat(s.moreKinds.count) * RingListLayout.rowHeight + 2 * RingListLayout.padding)
        for kind in all {
            let detail = try XCTUnwrap(p.detailFrames[kind])
            XCTAssertFalse(detail.intersects(p.baseFrame), "\(kind) detail never covers the ring")
            XCTAssertLessThanOrEqual(detail.maxY, list.minY - RingPlacement.gap + 0.001, "\(kind) detail sits below the list")
        }
        XCTAssertFalse(list.intersects(p.baseFrame))
        assertInside(p, v1024)
    }

    func testSideListScrollsATallDetailInsteadOfClipping() throws {
        let s = snapshot(all)
        let tall = details(all, width: 300, height: 560)
        let p = plan(s, visible: v1024, detail: tall)
        XCTAssertEqual(p.mode, .sideList)
        XCTAssertEqual(p.scrollingDetails, Set(all), "560 > the 542 left under a three-row list")
        for frame in p.detailFrames.values { XCTAssertLessThanOrEqual(frame.height, 542.001) }
        assertInside(p, v1024)
    }

    func testWholeListFallbackWhenValuesCannotFitTheSideArea() throws {
        let s = snapshot(all)
        let p = plan(s, visible: v1024, detail: details(all, width: 500, height: 320))
        XCTAssertEqual(p.mode, .wholeList)
        XCTAssertEqual(p.baseFrame.width, RingPlacement.wholeListWidth)
        for kind in all {
            XCTAssertNotNil(p.nodeFrames[.wedge(kind)], "favourites first, then the rest, all rows")
            let detail = try XCTUnwrap(p.detailFrames[kind])
            XCTAssertFalse(detail.intersects(p.baseFrame))
        }
        XCTAssertNil(p.moreSurface)
        assertInside(p, v1024)
    }

    func testDraggedBaseThatCannotFitClampsEachSurfaceAndSaysSo() {
        let s = snapshot(all)
        let tooWide = details(all, width: 500, height: 320)
        let edge = CGPoint(x: v1024.maxX - 100, y: v1024.midY)
        let p = plan(s, visible: v1024, at: edge, detail: tooWide, canShift: false, allowWholeList: false)
        XCTAssertEqual(p.mode, .sideList)
        XCTAssertTrue(p.isClamped)
        XCTAssertEqual(p.baseFrame, preferred(centeredAt: edge), "a drag never moves the base")
        for frame in p.allFrames.dropFirst() { XCTAssertTrue(v1024.insetBy(dx: -0.001, dy: -0.001).contains(frame)) }
    }

    func testTallerThanTheDisplayWholeListScrollsDetail() {
        let s = snapshot(all)
        let p = plan(s, visible: v1024, detail: details(all, width: 500, height: 900))
        XCTAssertEqual(p.mode, .wholeList)
        XCTAssertEqual(p.scrollingDetails, Set(all))
        for frame in p.detailFrames.values { XCTAssertLessThanOrEqual(frame.height, v1024.height) }
    }

    func testNothingInMoreUsesTheBaseAloneAndNeedsNoSurface() {
        let s = snapshot(eight)
        XCTAssertTrue(s.moreKinds.isEmpty)
        let p = plan(s, visible: v1024)
        XCTAssertEqual(p.mode, .outerRing)
        XCTAssertNil(p.moreSurface)
        XCTAssertNil(p.nodeFrames[.more])
        assertInside(p, v1024)
    }

    func testZeroOneSixEightFavouritesAndTwelveEnabledAllPlace() {
        let six: [StatKind] = [.cpu, .memory, .disk, .network, .gpu, .temps]
        for kinds in [[StatKind](), [.cpu], six, eight, all] {
            for visible in [v1024, v1440] {
                let p = plan(snapshot(kinds), visible: visible)
                assertInside(p, visible, "\(kinds.count) stats on \(visible)")
            }
        }
    }

    // MARK: Edges, corners, displays

    private func positions(in v: CGRect) -> [CGPoint] {
        [v.minX, v.midX, v.maxX].flatMap { x in [v.minY, v.midY, v.maxY].map { CGPoint(x: x, y: $0) } }
    }

    func testAllEdgesAndCornersKeepEverySurfaceInsideAndOffTheParent() throws {
        let six: [StatKind] = [.cpu, .memory, .disk, .network, .gpu, .temps]
        for visible in [v1024, v1440, vNegative, vLarge] {
            for kinds in [six, eight, all] {
                let s = snapshot(kinds)
                for point in positions(in: visible) {
                    let p = plan(s, visible: visible, at: point)
                    let label = "\(kinds.count) stats at \(point) on \(visible) mode \(p.mode)"
                    assertInside(p, visible, label)
                    if p.mode != .wholeList {
                        XCTAssertEqual(p.baseFrame.size, CGSize(width: 520, height: 520), label)
                    }
                    for (kind, detail) in p.detailFrames {
                        XCTAssertFalse(detail.intersects(p.baseFrame), "\(label): \(kind) covers the ring")
                        if let surface = p.moreSurface, s.moreKinds.contains(kind) {
                            XCTAssertFalse(detail.intersects(surface), "\(label): \(kind) covers More")
                        }
                        if let parent = p.nodeFrames[.wedge(kind)] ?? p.nodeFrames[.moreItem(kind)] {
                            XCTAssertFalse(detail.intersects(parent) && p.mode == .outerRing, "\(label): \(kind) covers its parent")
                        }
                    }
                }
            }
        }
    }

    func testShiftMovesTheBaseTheLeastAndNeverWhenItAlreadyFits() {
        let s = snapshot(all)
        let centre = CGPoint(x: vLarge.midX, y: vLarge.midY)
        let fits = plan(s, visible: vLarge, at: centre)
        XCTAssertEqual(fits.baseFrame, preferred(centeredAt: centre), "no shift when everything fits")

        let nearLeft = plan(s, visible: vLarge, at: CGPoint(x: 100, y: centre.y))
        XCTAssertGreaterThanOrEqual(nearLeft.moreSurface?.minX ?? -1, 0, "ring pulled just inside the left edge")
        XCTAssertEqual(nearLeft.moreSurface?.minX ?? -1, 0, accuracy: 0.001, "and no further than needed")
    }

    func testFixedBaseDoesNotShift() {
        let s = snapshot(eight)
        let centre = CGPoint(x: v1440.midX, y: v1440.midY)
        let kept = plan(s, visible: v1440, at: centre, canShift: true)
        XCTAssertEqual(kept.baseFrame, preferred(centeredAt: centre))
        let edge = plan(s, visible: v1440, at: CGPoint(x: v1440.maxX, y: v1440.midY), canShift: false, allowWholeList: false)
        XCTAssertEqual(edge.baseFrame, preferred(centeredAt: CGPoint(x: v1440.maxX, y: v1440.midY)),
                       "canShift: false keeps the dragged position even when surfaces must clamp")
    }

    func testNegativeDisplayOriginPlacesInsideTheNegativeFrame() {
        let s = snapshot(eight)
        let p = plan(s, visible: vNegative, at: CGPoint(x: vNegative.minX, y: vNegative.minY))
        XCTAssertGreaterThanOrEqual(p.baseFrame.minX, vNegative.minX)
        XCTAssertGreaterThanOrEqual(p.baseFrame.minY, vNegative.minY)
        XCTAssertLessThan(p.baseFrame.maxX, 0, "stays on the display left of the origin")
        assertInside(p, vNegative)
    }

    func testPixelSnappingAtOneAndTwoTimes() {
        let s = snapshot(eight)
        let rawOrigin = CGPoint(x: 301.25, y: 101.25)
        for scale in [CGFloat(1), 2] {
            let input = RingPlacement.Input(snapshot: s, visible: v1440,
                                            preferredBase: CGRect(origin: rawOrigin, size: CGSize(width: 520, height: 520)),
                                            detailSizes: details(s.enabledKinds, width: 300.4, height: 320.6),
                                            scale: scale)
            let p = RingPlacement.resolve(input)
            for frame in p.allFrames {
                XCTAssertEqual(frame.minX * scale, (frame.minX * scale).rounded(), accuracy: 1e-6, "x on the \(scale)x grid")
                XCTAssertEqual(frame.minY * scale, (frame.minY * scale).rounded(), accuracy: 1e-6, "y on the \(scale)x grid")
            }
            XCTAssertEqual(abs(p.baseFrame.minX - rawOrigin.x) <= 0.5 / scale + 0.001, true)
            assertInside(p, v1440)
        }
        let one = RingPlacement.resolve(.init(snapshot: s, visible: v1440, preferredBase: CGRect(origin: rawOrigin, size: CGSize(width: 520, height: 520)),
                                              detailSizes: details(s.enabledKinds), scale: 1))
        let two = RingPlacement.resolve(.init(snapshot: s, visible: v1440, preferredBase: CGRect(origin: rawOrigin, size: CGSize(width: 520, height: 520)),
                                              detailSizes: details(s.enabledKinds), scale: 2))
        XCTAssertEqual(one.mode, two.mode, "scale changes pixels, never the chosen arrangement")
        XCTAssertEqual(one.baseFrame.minX, 301, accuracy: 0.001)
        XCTAssertEqual(two.baseFrame.minX, 301.5, accuracy: 0.001)
    }

    func testPlanIsFrozenAgainstSampleUpdates() {
        let quiet = snapshot(all)
        let busy = RingSnapshot.make(enabledKinds: all) { kind in
            RingReading(value: "99%", widestValue: kind.ringFallbackWidest, band: .hot)
        }
        XCTAssertEqual(plan(quiet, visible: v1440), plan(busy, visible: v1440),
                       "a changed live reading with the same worst case moves no frame")
    }

    func testReplanWithAnotherVisibleFrameKeepsChildrenInsideIt() {
        let s = snapshot(all)
        let other = CGRect(x: 2000, y: 100, width: 1024, height: 640)
        let base = CGRect(x: 2100, y: 150, width: 520, height: 520)
        let p = RingPlacement.resolve(.init(snapshot: s, visible: other, preferredBase: base,
                                            detailSizes: details(all), canShift: false, allowWholeList: false))
        XCTAssertEqual(p.baseFrame, base)
        for frame in p.allFrames.dropFirst() {
            XCTAssertTrue(other.insetBy(dx: -0.001, dy: -0.001).contains(frame), "\(frame) outside \(other)")
        }
    }

    func testWholeListReplanWithoutShiftKeepsTheDraggedFrame() {
        let s = snapshot(all)
        let dragged = CGRect(x: 700, y: 200, width: 300, height: 372)
        var input = RingPlacement.Input(snapshot: s, visible: v1024, preferredBase: dragged, detailSizes: details(all))
        input.canShift = false
        input.forceWholeList = true
        let p = RingPlacement.resolve(input)
        XCTAssertEqual(p.mode, .wholeList)
        XCTAssertEqual(p.baseFrame, dragged, "plan describes the real panel")
        for frame in p.detailFrames.values {
            XCTAssertFalse(frame.intersects(dragged), "reserved detail never overlaps the real list")
            XCTAssertTrue(v1024.insetBy(dx: -0.001, dy: -0.001).contains(frame))
        }
        let edge = CGRect(x: 724, y: 100, width: 300, height: 372)   // flush right: no room beside
        input.preferredBase = edge
        let clamped = RingPlacement.resolve(input)
        XCTAssertEqual(clamped.baseFrame, edge)
        XCTAssertTrue(clamped.isClamped || clamped.detailFrames.values.allSatisfy { !$0.intersects(edge) })
    }

    // MARK: Outer More geometry

    func testMoreRingHitsEntriesAndNeverTheGaps() throws {
        let items = StatKind.allCases.dropFirst(8).map { (kind: $0, textSize: CGSize(width: 90, height: 48)) }
        let g = RingMoreGeometry(items: items)
        XCTAssertEqual(g.entries.count, items.count)
        for entry in g.entries {
            let p = RingGeometry.point(center: g.center, angle: entry.centerAngle, radius: RingMoreGeometry.textRadius)
            XCTAssertEqual(g.target(at: p), entry.kind)
            XCTAssertNotNil(g.frame(of: entry.kind))
        }
        let gapAngle = g.entries[0].centerAngle + (2 * .pi / Double(items.count)) / 2
        XCTAssertNil(g.target(at: RingGeometry.point(center: g.center, angle: gapAngle, radius: RingMoreGeometry.textRadius)))
        XCTAssertNil(g.target(at: g.center), "hub area selects nothing in the outer ring")
        XCTAssertTrue(g.isOnRing(RingGeometry.point(center: g.center, angle: gapAngle, radius: RingMoreGeometry.textRadius)))
    }

    func testMoreRingHoldsTwelveEntriesAndDetectsOversizedText() {
        let twelve = (0..<12).map { (kind: StatKind.allCases[$0 % StatKind.allCases.count], textSize: CGSize(width: 90, height: 48)) }
        XCTAssertEqual(RingMoreGeometry(items: twelve).entries.count, 12)
        let big = RingMoreGeometry(items: [(.fan, CGSize(width: 260, height: 90))])
        XCTAssertFalse(big.allTextFits)
        let small = RingMoreGeometry(items: [(.fan, CGSize(width: 80, height: 40)), (.power, CGSize(width: 80, height: 40))])
        XCTAssertTrue(small.allTextFits)
    }

    // MARK: Scrolling list model

    func testListScrollsIndependentlyAndHitTestingFollowsTheOffset() {
        let rows = (0..<12).map { RingNode.moreItem(StatKind.allCases[$0 % StatKind.allCases.count]) }
        var list = RingListLayout(size: CGSize(width: 380, height: 224), rows: rows, hasChrome: false)
        XCTAssertEqual(list.contentHeight, 12 * 28 + 8)
        XCTAssertEqual(list.maxOffset, 120)
        XCTAssertEqual(list.hit(at: CGPoint(x: 10, y: 4 + 14)), .node(rows[0]))
        list.scroll(by: 56)
        XCTAssertEqual(list.hit(at: CGPoint(x: 10, y: 4 + 14)), .node(rows[2]), "two rows scrolled away")
        list.scroll(by: 10_000)
        XCTAssertEqual(list.offset, 120, "clamped at the end")
        list.scroll(by: -10_000)
        XCTAssertEqual(list.offset, 0)
        XCTAssertNil(list.hit(at: CGPoint(x: 400, y: 10)))
    }

    func testWholeListHasFixedDragHeaderAndSettingsRow() {
        let rows = StatKind.allCases.map { RingNode.wedge($0) }
        var list = RingListLayout(size: CGSize(width: 300, height: 200), rows: rows, hasChrome: true)
        XCTAssertEqual(list.hit(at: CGPoint(x: 10, y: 10)), .drag)
        XCTAssertEqual(list.hit(at: CGPoint(x: 10, y: 190)), .settings)
        list.scroll(by: 28)
        XCTAssertEqual(list.hit(at: CGPoint(x: 10, y: 10)), .drag, "header does not scroll")
        XCTAssertEqual(list.hit(at: CGPoint(x: 10, y: 190)), .settings, "Settings does not scroll")
        XCTAssertEqual(list.hit(at: CGPoint(x: 10, y: 28 + 4 + 14)), .node(rows[1]))
    }

    func testListRowsAreAtLeastTheMinimumTargetHeight() {
        XCTAssertGreaterThanOrEqual(RingListLayout.rowHeight, RingGeometry.minTargetHeight)
    }
}

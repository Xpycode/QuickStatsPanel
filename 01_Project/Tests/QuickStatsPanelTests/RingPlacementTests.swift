import XCTest

/// Hostless checks of pre-summon geometry selection: preset footprint, side list, whole-list
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

    private func snapshot(_ kinds: [StatKind], preset: RingSizePreset = .medium) -> RingSnapshot {
        RingSnapshot.make(enabledKinds: kinds, preset: preset, reading: reading)
    }

    private func details(_ kinds: [StatKind], width: CGFloat = 300, height: CGFloat = 320) -> [StatKind: CGSize] {
        Dictionary(uniqueKeysWithValues: kinds.map { ($0, CGSize(width: width, height: height)) })
    }

    /// Preferred base of the default (Medium) ring: its 360-point footprint centred on `p`.
    private func preferred(centeredAt p: CGPoint, side: CGFloat = 360) -> CGRect {
        CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side)
    }

    private func plan(_ s: RingSnapshot, visible: CGRect, at p: CGPoint? = nil,
                      detail: [StatKind: CGSize]? = nil, scale: CGFloat = 1,
                      canShift: Bool = true, allowWholeList: Bool = true) -> RingPlan {
        let center = p ?? CGPoint(x: visible.midX, y: visible.midY)
        // Ring-only geometry (side list, whole list): the band is exercised by `bandPlan`.
        return RingPlacement.resolve(.init(snapshot: s, visible: visible,
                                           preferredBase: preferred(centeredAt: center, side: s.size.width),
                                           detailSizes: detail ?? details(s.enabledKinds), scale: scale,
                                           canShift: canShift, allowWholeList: allowWholeList, allowsOuterBand: false))
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

    func testBasePanelIsThePresetFootprintAndSitsOnTheFrozenLayout() throws {
        for preset in RingSizePreset.allCases {
            let s = snapshot(all, preset: preset)
            let p = plan(s, visible: vLarge)
            XCTAssertEqual(p.baseFrame.size, preset.footprintRingOnly, "\(preset): ring-only footprint, no 520-point constant")
            XCTAssertEqual(s.layout.center, CGPoint(x: preset.outerRadius, y: preset.outerRadius))
            for favourite in s.layout.favourites {
                let frame = try XCTUnwrap(p.nodeFrames[.wedge(favourite.kind)])
                XCTAssertTrue(p.baseFrame.insetBy(dx: -0.001, dy: -0.001).contains(frame), "\(preset) \(favourite.kind)")
            }
            let more = try XCTUnwrap(p.nodeFrames[.more], "\(preset): the More wedge is a node")
            XCTAssertEqual(more.midX, p.baseFrame.midX, accuracy: 1, "\(preset): centred on six o'clock")
            XCTAssertLessThan(more.midY, p.baseFrame.midY, "\(preset): below the centre (screen y grows upward)")
        }
    }

    func testLargeFrameKeepsTheSideColumnAndNeverTheRemovedOuterRing() throws {
        let s = snapshot(all)
        XCTAssertGreaterThan(s.moreKinds.count, 0)
        let p = plan(s, visible: vLarge)
        XCTAssertEqual(p.mode, .sideList)
        let list = try XCTUnwrap(p.moreSurface)
        XCTAssertEqual(list.width, RingPlacement.sideAreaWidth)
        XCTAssertFalse(list.intersects(p.baseFrame))
        for kind in s.moreKinds {
            let detail = try XCTUnwrap(p.detailFrames[kind])
            XCTAssertFalse(detail.intersects(list), "\(kind) detail sits below the list")
            XCTAssertNotNil(p.nodeFrames[.moreItem(kind)])
        }
        assertInside(p, vLarge)
    }

    func testSideColumnNeedsTheRingPlusAboutThreeEightyPoints() {
        let s = snapshot(all)
        XCTAssertEqual(plan(s, visible: v1024).mode, .sideList, "1024 x 640 holds 360 + the 380-point side area")
        let narrow = CGRect(x: 0, y: 0, width: 700, height: 900)
        XCTAssertEqual(plan(s, visible: narrow).mode, .wholeList, "700 points wide cannot hold 360 + 6 + 380")
        let small = snapshot(all, preset: .small)
        XCTAssertEqual(plan(small, visible: CGRect(x: 0, y: 0, width: 660, height: 900)).mode, .sideList,
                       "Small needs 260 + 6 + 380")
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

    func testNothingInMoreHasNoListAndNoMoreNode() throws {
        let s = snapshot(eight)
        XCTAssertTrue(s.moreKinds.isEmpty)
        let p = plan(s, visible: v1024)
        XCTAssertEqual(p.mode, .sideList, "the column then holds the detail card alone")
        XCTAssertNil(p.moreSurface)
        XCTAssertNil(p.nodeFrames[.more])
        for kind in eight { XCTAssertFalse(try XCTUnwrap(p.detailFrames[kind]).intersects(p.baseFrame)) }
        assertInside(p, v1024)
    }

    func testNoStatsAndNoDetailsReserveNothingBesideTheRing() {
        let s = snapshot([])
        let p = plan(s, visible: v1024, detail: [:])
        XCTAssertEqual(p.mode, .sideList)
        XCTAssertEqual(p.allFrames, [p.baseFrame])
    }

    func testZeroOneSixEightFavouritesAndElevenEnabledPlaceInEveryPreset() {
        let six: [StatKind] = [.cpu, .memory, .disk, .network, .gpu, .temps]
        for preset in RingSizePreset.allCases {
            for kinds in [[StatKind](), [.cpu], six, eight, all] {
                for visible in [v1024, v1440] {
                    let p = plan(snapshot(kinds, preset: preset), visible: visible)
                    assertInside(p, visible, "\(preset) \(kinds.count) stats on \(visible)")
                }
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
                        XCTAssertEqual(p.baseFrame.size, s.size, label)
                    }
                    for (kind, detail) in p.detailFrames {
                        XCTAssertFalse(detail.intersects(p.baseFrame), "\(label): \(kind) covers the ring")
                        if let surface = p.moreSurface, s.moreKinds.contains(kind) {
                            XCTAssertFalse(detail.intersects(surface), "\(label): \(kind) covers More")
                        }
                        if let parent = p.nodeFrames[.wedge(kind)], p.mode != .wholeList {
                            XCTAssertFalse(detail.intersects(parent), "\(label): \(kind) covers its parent")
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
        XCTAssertGreaterThanOrEqual(nearLeft.baseFrame.minX, 0, "ring pulled just inside the left edge")
        XCTAssertEqual(nearLeft.baseFrame.minX, 0, accuracy: 0.001, "and no further than needed")
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
                                            preferredBase: CGRect(origin: rawOrigin, size: s.size),
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
        let one = RingPlacement.resolve(.init(snapshot: s, visible: v1440, preferredBase: CGRect(origin: rawOrigin, size: s.size),
                                              detailSizes: details(s.enabledKinds), scale: 1))
        let two = RingPlacement.resolve(.init(snapshot: s, visible: v1440, preferredBase: CGRect(origin: rawOrigin, size: s.size),
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
        let base = CGRect(x: 2100, y: 150, width: s.size.width, height: s.size.height)
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
        XCTAssertGreaterThanOrEqual(RingListLayout.rowHeight, RingSizePreset.minGearTarget)
    }

    // MARK: Snapshot arcs

    private func partLists(_ name: RingPartFixtureName) -> (StatKind) -> RingPartList? {
        let set = RingPartFixtures.make(name)
        return { kind in
            switch kind {
            case .cpu: return set.cpuParts
            case .disk: return set.diskParts
            case .network: return set.networkParts
            case .temps: return set.temperatureParts
            default: return nil
            }
        }
    }

    private func bandSnapshot(_ kinds: [StatKind], favourites: [StatKind]? = nil, preset: RingSizePreset = .medium,
                              parts: RingPartFixtureName = .typical, cap: RingTextCap = .label) -> RingSnapshot {
        RingSnapshot.make(enabledKinds: kinds, favourites: favourites, preset: preset, cap: cap, reading: reading,
                          parts: partLists(parts))
    }

    private func bandPlan(_ s: RingSnapshot, visible: CGRect, at p: CGPoint? = nil,
                          detail: [StatKind: CGSize]? = nil, scale: CGFloat = 1,
                          canShift: Bool = true, allowWholeList: Bool = true) -> RingPlan {
        let center = p ?? CGPoint(x: visible.midX, y: visible.midY)
        return RingPlacement.resolve(.init(snapshot: s, visible: visible,
                                           preferredBase: preferred(centeredAt: center, side: s.size.width),
                                           detailSizes: detail ?? details(s.enabledKinds), scale: scale,
                                           canShift: canShift, allowWholeList: allowWholeList, allowsOuterBand: true))
    }

    private let subRingKinds: [StatKind] = [.cpu, .disk, .network, .temps]

    func testSnapshotLaysOutASubRingForEachFavouriteWithTwoOrMoreParts() throws {
        for preset in RingSizePreset.allCases {
            let s = bandSnapshot(eight, preset: preset)
            for kind in subRingKinds {
                let arc = try XCTUnwrap(s.arcs[.stat(kind)], "\(preset) \(kind)")
                let wedge = try XCTUnwrap(s.layout.favourites.first { $0.kind == kind }).sector
                let parts = try XCTUnwrap(s.parts[kind])
                XCTAssertEqual(arc.status, .fits)
                XCTAssertEqual(arc.segments.count, parts.parts.count, "\(preset) \(kind): one segment per part")
                XCTAssertEqual(arc.parentMidAngle, wedge.centerAngle, accuracy: 1e-12, "centred on its parent")
                XCTAssertGreaterThanOrEqual(arc.span, wedge.span - 1e-9, "at least the parent's span")
                XCTAssertEqual(arc.center, s.layout.center, "in the ring's own space")
                XCTAssertEqual(arc.innerRadius, preset.outerRadius + RingSizePreset.bandGap, "6 points outside the ring")
            }
            for kind in eight where !subRingKinds.contains(kind) {
                XCTAssertNil(s.arcs[.stat(kind)], "\(preset) \(kind) has no parts")
            }
            XCTAssertNil(s.arcs[.more], "nothing in More")
        }
    }

    func testFewerThanTwoPartsOrRealDataGivesNoSubRing() {
        let minimal = bandSnapshot(eight, parts: .minimal)
        XCTAssertNotNil(minimal.arcs[.stat(.cpu)], "minimal still has ten cores")
        for kind in [StatKind.disk, .network, .temps] {
            XCTAssertNil(minimal.arcs[.stat(kind)], "\(kind): fewer than two parts, card only")
        }
        let real = snapshot(eight)
        XCTAssertTrue(real.arcs.isEmpty, "real data has no parts yet")
        XCTAssertTrue(real.parts.isEmpty)
    }

    func testAStatReachedThroughMoreNeverGetsASubRing() {
        let s = bandSnapshot(all, favourites: [.memory, .battery, .gpu])
        for kind in subRingKinds {
            XCTAssertNil(s.arcs[.stat(kind)], "\(kind) is in More")
            XCTAssertNil(s.parts[kind])
        }
        XCTAssertNotNil(s.arcs[.more])
    }

    func testMoreArcTakesTheRichestRungThatFitsAndIsAbsentWhenNoneFits() throws {
        for preset in RingSizePreset.allCases {
            for favourites in [0, 1, 6, 8] {
                let s = bandSnapshot(all, favourites: Array(all.prefix(favourites)), preset: preset)
                let arc = try XCTUnwrap(s.arcs[.more], "\(preset) \(favourites) favourites")
                let rung = try XCTUnwrap(s.moreArcRung)
                XCTAssertEqual(arc.segments.count, s.moreKinds.count, "every non-favourite is an entry")
                XCTAssertTrue(arc.segments.allSatisfy(\.isLabelled), "no More entry is a sliver")
                XCTAssertEqual(arc.parentMidAngle, .pi, accuracy: 1e-12, "centred on six o'clock")
                XCTAssertEqual(arc.kind, .more)
                // A richer rung that some entry has would not have fitted.
                let sizes = s.moreEntries.map { RingTypography.rungSizes(name: $0.name, reading: $0.initialReading) }
                if let richer = RingContentRung(rawValue: rung.rawValue + 1),
                   sizes.contains(where: { $0.size(for: richer) != nil }) {
                    let wider = RingArcLayout(preset: preset, kind: .more, center: s.layout.center,
                                              parentMidAngle: .pi, parentSpan: try XCTUnwrap(s.layout.more).sector.span,
                                              entries: sizes.map { RingArcEntry(labelSize: $0.size(for: richer) ?? $0.labelValue) },
                                              allowsSlivers: false)
                    XCTAssertEqual(wider.status, .cannotFit, "\(preset) \(favourites): \(richer) should not fit")
                }
            }
        }
        XCTAssertEqual(bandSnapshot(all, favourites: Array(all.prefix(6)), cap: .icon).moreArcRung, .icon)

        let huge = RingSnapshot.make(enabledKinds: all, favourites: Array(all.prefix(6)), reading: reading,
                                     measure: { _, _ in
                                         let big = CGSize(width: 400, height: 400)
                                         return RingRungSizes(labelValueSecondary: big, labelValue: big, iconValue: big, icon: big)
                                     })
        XCTAssertNil(huge.arcs[.more], "a More arc that cannot fit even icons is not laid out")
        XCTAssertNil(huge.moreArcRung)
    }

    // MARK: Outer band placement

    func testOuterBandReservesTheBandFootprintAroundTheUnmovedRing() throws {
        for preset in RingSizePreset.allCases {
            let s = bandSnapshot(all, favourites: eight, preset: preset)
            let ringOnly = plan(s, visible: vLarge)
            let p = bandPlan(s, visible: vLarge)
            XCTAssertEqual(p.mode, .outerBand, "\(preset)")
            XCTAssertEqual(p.baseFrame, ringOnly.baseFrame, "\(preset): reserving the band never moves the ring")
            XCTAssertEqual(p.baseFrame.size, preset.footprintRingOnly)
            let band = try XCTUnwrap(p.bandFrame)
            XCTAssertEqual(band.size, preset.footprintWithBand)
            XCTAssertEqual(band.midX, p.baseFrame.midX, accuracy: 0.001)
            XCTAssertEqual(band.midY, p.baseFrame.midY, accuracy: 0.001)
            for favourite in s.layout.favourites {
                XCTAssertEqual(p.nodeFrames[.wedge(favourite.kind)], ringOnly.nodeFrames[.wedge(favourite.kind)],
                               "\(preset) \(favourite.kind): the parent target never moves")
            }
            XCTAssertEqual(Set(p.arcFrames.keys), Set(s.arcs.keys), "\(preset): every laid-out arc has a frame")
            for (owner, frame) in p.arcFrames {
                XCTAssertTrue(band.insetBy(dx: -0.001, dy: -0.001).contains(frame), "\(preset) \(owner) inside the band")
            }
            XCTAssertNil(p.moreSurface, "\(preset): More opens as an arc")
            assertInside(p, vLarge)
        }
    }

    func testOuterBandCardsSitBesideTheBandNextToTheirParentAndNeverOverAnArc() throws {
        let s = bandSnapshot(all, favourites: Array(all.prefix(6)))
        let p = bandPlan(s, visible: vLarge)
        XCTAssertEqual(p.mode, .outerBand)
        let band = try XCTUnwrap(p.bandFrame)
        for kind in all {
            let card = try XCTUnwrap(p.detailFrames[kind], "\(kind)")
            XCTAssertFalse(card.intersects(band), "\(kind): beside the band footprint")
            XCTAssertEqual(card.minX, band.maxX + RingPlacement.gap, accuracy: 0.001, "\(kind): right of the band")
            for (owner, arc) in p.arcFrames { XCTAssertFalse(card.intersects(arc), "\(kind) over \(owner)'s arc") }
            let parentNode: RingNode = s.moreKinds.contains(kind) ? .moreItem(kind) : .wedge(kind)
            let parent = try XCTUnwrap(p.nodeFrames[parentNode])
            XCTAssertEqual(card.midY, parent.midY, accuracy: 0.5, "\(kind): vertically centred on its parent")
        }
        for kind in s.moreKinds {
            let entry = try XCTUnwrap(p.nodeFrames[.moreItem(kind)])
            XCTAssertTrue(try XCTUnwrap(p.arcFrames[.more]).insetBy(dx: -1, dy: -1).contains(entry),
                          "\(kind): its More-arc entry is its parent target")
        }
    }

    func testMoreArcThatCannotFitKeepsTheListAboveTheCardBesideTheBand() throws {
        let s = RingSnapshot.make(enabledKinds: all, favourites: eight, reading: reading,
                                  measure: { kind, reading in
                                      var sizes = RingTypography.rungSizes(name: kind.displayName, reading: reading)
                                      sizes.icon = CGSize(width: 400, height: 400)   // no More-arc rung fits
                                      sizes.iconValue = sizes.icon
                                      sizes.labelValue = sizes.icon
                                      sizes.labelValueSecondary = nil
                                      return sizes
                                  },
                                  parts: partLists(.typical))
        XCTAssertNil(s.arcs[.more])
        XCTAssertNotNil(s.arcs[.stat(.cpu)])
        let p = bandPlan(s, visible: vLarge)
        XCTAssertEqual(p.mode, .outerBand, "sub-rings still use the band")
        let band = try XCTUnwrap(p.bandFrame)
        let list = try XCTUnwrap(p.moreSurface, "More falls back to the side list")
        XCTAssertNil(p.arcFrames[.more])
        XCTAssertEqual(p.surfaceFrame(of: .more), list)
        XCTAssertFalse(list.intersects(band))
        for kind in all {
            let card = try XCTUnwrap(p.detailFrames[kind])
            XCTAssertFalse(card.intersects(band))
            XCTAssertLessThanOrEqual(card.maxY, list.minY - RingPlacement.gap + 0.001, "\(kind) below the list")
        }
        for kind in s.moreKinds { XCTAssertEqual(p.nodeFrames[.moreItem(kind)], list) }
        assertInside(p, vLarge)
    }

    func testBandThatCannotFitOmitsSubRingsAndUsesTheSideList() {
        let s = bandSnapshot(all, favourites: Array(all.prefix(6)))
        // 880 wide holds 360 + 6 + 380 but not the 500-point band footprint + 6 + 380.
        let narrow = CGRect(x: 0, y: 0, width: 880, height: 900)
        let side = bandPlan(s, visible: narrow)
        XCTAssertEqual(side.mode, .sideList)
        XCTAssertTrue(side.arcFrames.isEmpty, "no sub-ring and no More arc this summon")
        XCTAssertNil(side.bandFrame)
        XCTAssertNotNil(side.moreSurface)
        XCTAssertEqual(bandPlan(s, visible: CGRect(x: 0, y: 0, width: 886, height: 900)).mode, .outerBand,
                       "500 + 6 + 380 is exactly enough")
        // 480 tall holds the ring but not the band.
        XCTAssertEqual(bandPlan(s, visible: CGRect(x: 0, y: 0, width: 1440, height: 480)).mode, .sideList)
        XCTAssertEqual(bandPlan(s, visible: CGRect(x: 0, y: 0, width: 700, height: 900)).mode, .wholeList,
                       "the ring plus 380 points cannot fit either")
    }

    func testConvenienceInputChoosesTheBandByDefaultAndCanTurnItOff() {
        let s = bandSnapshot(all, favourites: eight)
        XCTAssertFalse(s.arcs.isEmpty)
        let preferred = preferred(centeredAt: CGPoint(x: vLarge.midX, y: vLarge.midY))
        let byDefault = RingPlacement.resolve(.init(snapshot: s, visible: vLarge, preferredBase: preferred,
                                                    detailSizes: details(s.enabledKinds)))
        XCTAssertEqual(byDefault.mode, .outerBand, "the native arcs exist: the band is on")
        XCTAssertEqual(plan(s, visible: vLarge).mode, .sideList, "explicitly off: the side list")
        XCTAssertEqual(bandPlan(s, visible: vLarge).mode, .outerBand)
        XCTAssertEqual(bandPlan(snapshot(eight), visible: vLarge).mode, .sideList, "no arcs: no band reserved")
    }

    func testOuterBandAtEveryEdgeCornerDisplayScaleAndPreset() throws {
        let six: [StatKind] = [.cpu, .memory, .disk, .network, .gpu, .temps]
        for preset in RingSizePreset.allCases {
            let s = bandSnapshot(all, favourites: six, preset: preset)
            for visible in [v1024, v1440, vNegative, vLarge] {
                XCTAssertEqual(bandPlan(s, visible: visible).mode, .outerBand,
                               "\(preset) centred on \(visible): the band fits the minimum workspace")
                for point in positions(in: visible) {
                    for scale in [CGFloat(1), 2] {
                        let p = bandPlan(s, visible: visible, at: point, scale: scale)
                        let label = "\(preset) at \(point) on \(visible) @\(scale)x mode \(p.mode)"
                        assertInside(p, visible, label)
                        for frame in p.allFrames {
                            XCTAssertEqual(frame.minX * scale, (frame.minX * scale).rounded(), accuracy: 1e-6, label)
                            XCTAssertEqual(frame.minY * scale, (frame.minY * scale).rounded(), accuracy: 1e-6, label)
                        }
                        guard p.mode == .outerBand else { continue }
                        let band = try XCTUnwrap(p.bandFrame, label)
                        XCTAssertEqual(p.baseFrame.size, s.size, label)
                        for (kind, card) in p.detailFrames {
                            XCTAssertFalse(card.intersects(band), "\(label): \(kind) over the band")
                        }
                        for (owner, frame) in p.arcFrames {
                            XCTAssertTrue(band.insetBy(dx: -0.001, dy: -0.001).contains(frame), "\(label): \(owner)")
                        }
                    }
                }
            }
        }
    }

    func testDraggedBaseKeepsTheBandWhereItFitsAndFallsBackWhereItDoesNot() {
        let s = bandSnapshot(all, favourites: eight)
        let centre = CGPoint(x: v1440.midX, y: v1440.midY)
        let kept = bandPlan(s, visible: v1440, at: centre, canShift: false, allowWholeList: false)
        XCTAssertEqual(kept.mode, .outerBand)
        XCTAssertEqual(kept.baseFrame, preferred(centeredAt: centre))
        let edge = CGPoint(x: v1440.maxX - 200, y: v1440.midY)
        let fallback = bandPlan(s, visible: v1440, at: edge, canShift: false, allowWholeList: false)
        XCTAssertNotEqual(fallback.mode, .outerBand, "the band would leave the display")
        XCTAssertEqual(fallback.baseFrame, preferred(centeredAt: edge), "a drag never moves the base")
        XCTAssertTrue(fallback.arcFrames.isEmpty)
    }

    func testBandPlanIsFrozenAgainstSampleUpdates() {
        let quiet = bandSnapshot(all, favourites: eight)
        let busy = RingSnapshot.make(enabledKinds: all, favourites: eight, reading: { kind in
            RingReading(value: "99%", widestValue: kind.ringFallbackWidest, band: .hot)
        }, parts: partLists(.typical))
        XCTAssertEqual(bandPlan(quiet, visible: v1440), bandPlan(busy, visible: v1440))
        XCTAssertEqual(quiet.arcs, busy.arcs, "arcs are laid out from worst-case strings, not live values")
    }
}

import XCTest

/// Hostless checks of the ring's pure geometry, snapshot and pointer-state logic.
/// Text measurement uses real AppKit fonts, which work without an application.
final class RingGeometryTests: XCTestCase {

    private let sixKinds: [StatKind] = [.cpu, .memory, .disk, .network, .gpu, .temps]
    private let eightKinds: [StatKind] = [.cpu, .memory, .disk, .network, .battery, .gpu, .power, .temps]

    private func reading(_ kind: StatKind) -> RingReading {
        RingReading(value: "42%", widestValue: kind.ringFallbackWidest)
    }

    private func snapshot(_ kinds: [StatKind], reading: ((StatKind) -> RingReading)? = nil) -> RingSnapshot {
        RingSnapshot.make(enabledKinds: kinds, reading: reading ?? self.reading)
    }

    private func geometry(_ kinds: [StatKind]) -> RingGeometry { snapshot(kinds).geometry }

    private func point(_ g: RingGeometry, degrees: Double, radius: CGFloat) -> CGPoint {
        RingGeometry.point(center: g.center, angle: degrees * .pi / 180, radius: radius)
    }

    // MARK: Counts and slots

    func testFavouriteCountsZeroOneSixEight() {
        XCTAssertEqual(geometry([]).wedges.count, 0)
        XCTAssertEqual(geometry([.cpu]).wedges.count, 1)
        XCTAssertEqual(geometry(sixKinds).wedges.count, 6)
        XCTAssertEqual(geometry(eightKinds).wedges.count, 8)
    }

    func testSingleFavouriteIsSixtyDegreesAtTwelveOClock() throws {
        let g = geometry([.cpu])
        let wedge = try XCTUnwrap(g.wedges.first)
        XCTAssertEqual(wedge.centerAngle, 0, accuracy: 1e-9)
        XCTAssertEqual((wedge.endAngle - wedge.startAngle) * 180 / .pi, 60, accuracy: 1e-6)
        XCTAssertEqual(g.target(at: point(g, degrees: 0, radius: 180)), .wedge(.cpu))
        XCTAssertEqual(g.target(at: point(g, degrees: 25, radius: 180)), .wedge(.cpu))
        XCTAssertNil(g.target(at: point(g, degrees: 35, radius: 180)), "remaining annulus is inactive")
        XCTAssertNil(g.target(at: point(g, degrees: 180, radius: 180)))
    }

    func testEqualSectorsClockwiseFromTwelveInOrder() {
        for kinds in [sixKinds, eightKinds] {
            let g = geometry(kinds)
            let span = 360.0 / Double(kinds.count)
            for (index, kind) in kinds.enumerated() {
                let wedge = g.wedges[index]
                XCTAssertEqual(wedge.kind, kind)
                XCTAssertEqual(wedge.slot, index)
                XCTAssertEqual(wedge.centerAngle * 180 / .pi, span * Double(index), accuracy: 1e-6)
                XCTAssertEqual(g.target(at: point(g, degrees: span * Double(index), radius: 185)), .wedge(kind))
            }
        }
    }

    func testMoreThanEightEnabledKeepsEightFavouritesAndCountsTheRest() {
        let s = snapshot(Array(StatKind.allCases))   // eleven kinds today
        XCTAssertEqual(s.favourites.count, 8)
        XCTAssertEqual(s.moreKinds, Array(StatKind.allCases.dropFirst(8)))
        XCTAssertEqual(s.geometry.moreCount, StatKind.allCases.count - 8)
        XCTAssertNotNil(s.geometry.moreFrame)
        XCTAssertNil(s.emptyMessage)
        XCTAssertNil(snapshot(eightKinds).geometry.moreFrame, "More is hidden when nothing remains")
    }

    func testNoEnabledStatsKeepsSettingsAndExplains() {
        let s = snapshot([])
        XCTAssertEqual(s.emptyMessage, "No stats enabled")
        XCTAssertTrue(s.geometry.wedges.isEmpty)
        XCTAssertNil(s.geometry.moreFrame)
        XCTAssertEqual(s.geometry.target(at: CGPoint(x: s.geometry.settingsFrame.midX, y: s.geometry.settingsFrame.midY)),
                       .settings)
    }

    // MARK: Boundaries, gaps, hub

    func testGapBetweenWedgesAndOutsideSelectNothing() {
        let g = geometry(sixKinds)
        // Slot boundary between wedge 0 and wedge 1 sits at 30 degrees.
        XCTAssertNil(g.target(at: point(g, degrees: 30, radius: 185)))
        XCTAssertEqual(g.target(at: point(g, degrees: 28, radius: 185)), .wedge(.cpu))
        XCTAssertEqual(g.target(at: point(g, degrees: 32, radius: 185)), .wedge(.memory))
        // Outside the outer radius and between hub and inner radius.
        XCTAssertNil(g.target(at: point(g, degrees: 0, radius: 265)))
        XCTAssertNil(g.target(at: point(g, degrees: 0, radius: 96)))
        XCTAssertEqual(g.target(at: point(g, degrees: 0, radius: 102)), .wedge(.cpu))
        XCTAssertNil(g.target(at: CGPoint(x: -5, y: -5)))
    }

    func testHubTargetsAreDisjointTallEnoughAndInsideTheHub() throws {
        let g = geometry(Array(StatKind.allCases))
        let more = try XCTUnwrap(g.moreFrame)
        XCTAssertFalse(more.intersects(g.settingsFrame))
        XCTAssertGreaterThanOrEqual(more.height, RingGeometry.minTargetHeight)
        XCTAssertGreaterThanOrEqual(g.settingsFrame.height, RingGeometry.minTargetHeight)
        for frame in [more, g.settingsFrame] {
            for corner in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                           CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)] {
                XCTAssertLessThan(hypot(corner.x - g.center.x, corner.y - g.center.y), RingGeometry.hubRadius)
            }
        }
        XCTAssertEqual(g.target(at: CGPoint(x: more.midX, y: more.midY)), .more)
        XCTAssertEqual(g.target(at: CGPoint(x: g.settingsFrame.midX, y: g.settingsFrame.midY)), .settings)
        XCTAssertEqual(g.target(at: CGPoint(x: g.center.x, y: g.center.y + 60)), .drag)
        XCTAssertEqual(g.target(at: CGPoint(x: g.center.x + 70, y: g.center.y)), .drag)
    }

    func testFootprintAndRadiiMatchReviewBaseline() {
        let g = geometry(sixKinds)
        XCTAssertEqual(g.size, CGSize(width: 520, height: 520))
        XCTAssertEqual(RingGeometry.innerRadius, 100)
        XCTAssertEqual(RingGeometry.outerRadius, 260)
        XCTAssertEqual(RingGeometry.textRadius, 185)
    }

    // MARK: Shared draw / hit geometry

    func testOutlineVerticesAndFramesAgreeWithHitTesting() throws {
        for kinds in [[StatKind.cpu], sixKinds, eightKinds] {
            let g = geometry(kinds)
            for wedge in g.wedges {
                let outline = g.outline(of: wedge)
                XCTAssertFalse(outline.isEmpty)
                let frame = try XCTUnwrap(g.frame(of: .wedge(wedge.kind)))
                for vertex in outline {
                    XCTAssertTrue(frame.insetBy(dx: -0.001, dy: -0.001).contains(vertex))
                    // A vertex nudged toward the wedge's text anchor is a hit on that wedge.
                    let anchor = RingGeometry.point(center: g.center, angle: wedge.centerAngle,
                                                    radius: RingGeometry.textRadius)
                    let nudged = CGPoint(x: vertex.x + (anchor.x - vertex.x) * 0.02,
                                         y: vertex.y + (anchor.y - vertex.y) * 0.02)
                    XCTAssertEqual(g.target(at: nudged), .wedge(wedge.kind))
                }
            }
        }
    }

    // MARK: Identity stability

    func testUnavailableEntryKeepsIdentityAndPosition() {
        let available = snapshot(eightKinds).geometry
        let withGap = snapshot(eightKinds) { kind in
            kind == .battery ? RingReading.unavailable(kind) : self.reading(kind)
        }
        XCTAssertEqual(withGap.favourites.map(\.kind), eightKinds)
        XCTAssertFalse(withGap.favourites[4].initialReading.isAvailable)
        for (a, b) in zip(available.wedges, withGap.geometry.wedges) {
            XCTAssertEqual(a.kind, b.kind)
            XCTAssertEqual(a.slot, b.slot)
            XCTAssertEqual(a.centerAngle, b.centerAngle)
            XCTAssertEqual(a.halfSpan, b.halfSpan)
        }
    }

    func testGeometryDoesNotDependOnLiveValuesOnlyWorstCase() {
        let quiet = snapshot(sixKinds) { RingReading(value: "1%", widestValue: $0.ringFallbackWidest) }
        let busy = snapshot(sixKinds) { RingReading(value: "99%", widestValue: $0.ringFallbackWidest) }
        XCTAssertEqual(quiet.geometry, busy.geometry, "a sample update changes no slot or text bound")
    }

    // MARK: Pointer state

    @MainActor
    func testHoverIsSuppressedUntilTheSummonPointerMovesAndTracksFrozenGeometry() {
        let g = geometry(sixKinds)
        let frame = CGRect(x: 100, y: 100, width: 520, height: 520)
        let state = RingPresentationState()
        let wedgeScreen = CGPoint(x: frame.minX + g.center.x,
                                  y: frame.maxY - (g.center.y - 185))   // twelve o'clock wedge
        state.beginSummon(pointer: wedgeScreen)
        state.updatePointer(screenPoint: wedgeScreen, ringFrame: frame, geometry: g)
        XCTAssertNil(state.hovered, "stationary pointer after summon never highlights")
        XCTAssertNil(state.pointerInRing)

        state.updatePointer(screenPoint: CGPoint(x: wedgeScreen.x + 5, y: wedgeScreen.y), ringFrame: frame, geometry: g)
        XCTAssertEqual(state.hovered, .wedge(.cpu))

        // Out in the gap beside the ring the position stays known, with nothing hovered.
        state.updatePointer(screenPoint: CGPoint(x: frame.maxX + 30, y: frame.midY), ringFrame: frame, geometry: g)
        XCTAssertNil(state.hovered)
        XCTAssertEqual(state.pointerInRing?.x ?? 0, 520 + 30, accuracy: 0.001)

        // The hub drag area never highlights.
        state.updatePointer(screenPoint: CGPoint(x: frame.midX + 70, y: frame.midY), ringFrame: frame, geometry: g)
        XCTAssertNil(state.hovered)
    }

    // MARK: Text containment

    #if DEBUG
    private func assertTextFits(_ fixtureName: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let fixture = try XCTUnwrap(RingFixture.named(fixtureName), file: file, line: line)
        let s = snapshot(fixture.enabledKinds) { fixture.reading(for: $0) }
        for wedge in s.geometry.wedges {
            XCTAssertTrue(s.geometry.textFits(wedge),
                          "\(fixtureName): \(wedge.kind) text \(wedge.textRect) outside sector",
                          file: file, line: line)
        }
    }

    func testMeasuredWorstCaseTextFitsSixAndEightWedges() throws {
        try assertTextFits("six")
        try assertTextFits("eight")
        try assertTextFits("paired")
        try assertTextFits("long")
        try assertTextFits("unavailable")
    }
    #endif

    func testTextFitsWithTypicalAndWorstCaseHeadlinesWithoutFixtures() {
        for kinds in [sixKinds, eightKinds] {
            let s = snapshot(kinds) { kind in
                RingReading(value: kind.ringFallbackWidest, secondary: kind.ringFallbackWidest,
                            widestValue: kind.ringFallbackWidest, widestSecondary: kind.ringFallbackWidest)
            }
            for wedge in s.geometry.wedges {
                XCTAssertTrue(s.geometry.textFits(wedge), "\(wedge.kind) with \(kinds.count) wedges")
            }
        }
    }

    func testMeasurementUsesWorstCaseNotCurrentReading() {
        let narrow = RingTypography.blockSize(name: "CPU", reading: RingReading(value: "1%", widestValue: "1%"))
        let wide = RingTypography.blockSize(name: "CPU", reading: RingReading(value: "1%", widestValue: "888,88 GB"))
        XCTAssertGreaterThan(wide.width, narrow.width)
        let paired = RingTypography.blockSize(name: "CPU", reading: RingReading(
            value: "1%", secondary: "2%", widestValue: "1%", widestSecondary: "2%"))
        XCTAssertGreaterThan(paired.height, narrow.height)
    }

    func testTextFitDetectsAnOversizedBlock() {
        let g = RingGeometry(favourites: sixKinds.map { (kind: $0, textSize: CGSize(width: 400, height: 40)) },
                             moreCount: 0)
        XCTAssertFalse(g.textFits(g.wedges[0]))
    }
}

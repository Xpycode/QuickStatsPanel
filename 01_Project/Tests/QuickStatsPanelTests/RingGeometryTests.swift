import XCTest

/// Hostless checks of the ring summon snapshot: preset geometry, favourite and More slots,
/// hub targets, frozen rungs and the gauge each reading carries. Text measurement uses real
/// AppKit fonts, which work without an application.
final class RingGeometryTests: XCTestCase {

    private let sixKinds: [StatKind] = [.cpu, .memory, .disk, .network, .gpu, .temps]
    private let eightKinds: [StatKind] = [.cpu, .memory, .disk, .network, .battery, .gpu, .power, .temps]
    private let allKinds = Array(StatKind.allCases)

    private func reading(_ kind: StatKind) -> RingReading {
        RingReading(value: "42%", widestValue: kind.ringFallbackWidest)
    }

    private func snapshot(_ kinds: [StatKind], favourites: [StatKind]? = nil, preset: RingSizePreset = .medium,
                          cap: RingTextCap = .label, reading: ((StatKind) -> RingReading)? = nil) -> RingSnapshot {
        RingSnapshot.make(enabledKinds: kinds, favourites: favourites, preset: preset, cap: cap,
                          reading: reading ?? self.reading)
    }

    private func point(_ s: RingSnapshot, degrees: Double, radius: CGFloat) -> CGPoint {
        RingSector.point(center: s.layout.center, angle: degrees * .pi / 180, radius: radius)
    }

    // MARK: Presets

    func testPresetFootprintsAndRadiiComeFromThePreset() {
        let expected: [(RingSizePreset, CGFloat, CGFloat)] = [(.small, 260, 47), (.medium, 360, 65), (.large, 460, 83)]
        for (preset, diameter, inner) in expected {
            let s = snapshot(sixKinds, preset: preset)
            XCTAssertEqual(s.size, CGSize(width: diameter, height: diameter))
            XCTAssertEqual(s.layout.center, CGPoint(x: diameter / 2, y: diameter / 2))
            XCTAssertEqual(preset.innerRadius, inner)
            for favourite in s.layout.favourites {
                XCTAssertEqual(favourite.sector.innerRadius, inner)
                XCTAssertEqual(favourite.sector.outerRadius, diameter / 2)
            }
        }
    }

    func testTextSizesAreTheSameInEveryPreset() {
        XCTAssertEqual(RingTypography.labelSize, 13)
        XCTAssertEqual(RingTypography.valueSize, 16)
        XCTAssertEqual(RingTypography.secondarySize, 12)
        XCTAssertEqual([RingSizePreset.labelTextSize, RingSizePreset.valueTextSize, RingSizePreset.secondaryTextSize],
                       [13, 16, 12])
    }

    // MARK: Counts and slots

    func testFavouriteCountsZeroOneSixEight() {
        XCTAssertEqual(snapshot([]).layout.favourites.count, 0)
        XCTAssertEqual(snapshot([.cpu]).layout.favourites.count, 1)
        XCTAssertEqual(snapshot(sixKinds).layout.favourites.count, 6)
        XCTAssertEqual(snapshot(eightKinds).layout.favourites.count, 8)
    }

    func testSingleFavouriteIsSixtyDegreesAtTwelveOClock() throws {
        let s = snapshot([.cpu])
        let wedge = try XCTUnwrap(s.layout.favourites.first)
        XCTAssertEqual(wedge.sector.centerAngle, 0, accuracy: 1e-9)
        XCTAssertEqual(wedge.sector.span * 180 / .pi, 60, accuracy: 1e-6)
        XCTAssertEqual(s.target(at: point(s, degrees: 0, radius: 120)), .wedge(.cpu))
        XCTAssertEqual(s.target(at: point(s, degrees: 25, radius: 120)), .wedge(.cpu))
        XCTAssertNil(s.target(at: point(s, degrees: 35, radius: 120)), "remaining annulus is inactive")
        XCTAssertNil(s.target(at: point(s, degrees: 180, radius: 120)))
    }

    func testEqualSectorsClockwiseFromTwelveInOrderWithoutMore() {
        for kinds in [sixKinds, eightKinds] {
            let s = snapshot(kinds)
            XCTAssertNil(s.layout.more)
            let span = 360.0 / Double(kinds.count)
            for (index, kind) in kinds.enumerated() {
                let wedge = s.layout.favourites[index]
                XCTAssertEqual(wedge.kind, kind)
                XCTAssertEqual(wedge.order, index)
                XCTAssertEqual(wedge.sector.centerAngle * 180 / .pi, span * Double(index), accuracy: 1e-6)
                XCTAssertEqual(s.target(at: point(s, degrees: span * Double(index), radius: 120)), .wedge(kind))
            }
        }
    }

    func testMoreWedgeSitsAtSixOClockWithTheRightCountAndReachesEveryRemainingStat() throws {
        for preset in RingSizePreset.allCases {
            for favourites in [0, 1, 6, 8] {
                let favouriteKinds = Array(allKinds.prefix(favourites))
                let s = snapshot(allKinds, favourites: favouriteKinds, preset: preset)
                let label = "\(preset) \(favourites) favourites"
                XCTAssertEqual(s.layout.favourites.map(\.kind), favouriteKinds, label)
                XCTAssertEqual(s.moreKinds, Array(allKinds.dropFirst(favourites)), "\(label): every remaining stat is in More")
                let more = try XCTUnwrap(s.layout.more, label)
                XCTAssertEqual(more.count, allKinds.count - favourites, label)
                XCTAssertEqual(more.sector.centerAngle, .pi, accuracy: 1e-9, "\(label): six o'clock")
                XCTAssertEqual(more.sector.span * 180 / .pi, 24, accuracy: 1e-6, label)
                XCTAssertEqual(s.target(at: point(s, degrees: 180, radius: more.sector.midRadius)), .more, label)
                // No favourite overlaps the More wedge.
                for favourite in s.layout.favourites {
                    XCTAssertGreaterThan(abs(RingSector.wrapped(favourite.sector.centerAngle - .pi)),
                                         favourite.sector.halfSpan + more.sector.halfSpan, label)
                }
            }
        }
    }

    func testMoreWedgeIsAbsentWhenNothingRemainsAndFavouritesUseTheFullCircle() {
        let s = snapshot(eightKinds)
        XCTAssertNil(s.layout.more)
        XCTAssertTrue(s.moreKinds.isEmpty)
        XCTAssertNil(s.emptyMessage)
        XCTAssertEqual(s.layout.favourites.first?.sector.centerAngle ?? 1, 0, accuracy: 1e-9)
    }

    func testExplicitFavouritesKeepTheirOrderDropStrangersAndDuplicatesAndCapAtEight() {
        let s = snapshot(allKinds, favourites: [.gpu, .cpu, .gpu, .uptime])
        XCTAssertEqual(s.favourites.map(\.kind), [.gpu, .cpu, .uptime])
        XCTAssertEqual(s.moreKinds, allKinds.filter { ![.gpu, .cpu, .uptime].contains($0) })
        let outside = snapshot([.cpu, .memory], favourites: [.fan, .memory])
        XCTAssertEqual(outside.favourites.map(\.kind), [.memory], "a stat that is not enabled is not a favourite")
        XCTAssertEqual(snapshot(allKinds, favourites: allKinds).favourites.count, 8)
        XCTAssertEqual(snapshot(allKinds).favourites.map(\.kind), Array(allKinds.prefix(8)))
    }

    func testNoEnabledStatsKeepsTheGearAndExplains() {
        let s = snapshot([])
        XCTAssertEqual(s.emptyMessage, "No stats enabled")
        XCTAssertTrue(s.layout.favourites.isEmpty)
        XCTAssertNil(s.layout.more)
        XCTAssertEqual(s.target(at: s.layout.center), .settings)
    }

    func testNoFavouritesKeepsTheMoreWedgeAndExplainsInTheAnnulus() {
        let s = snapshot([.cpu, .memory, .disk], favourites: [])
        XCTAssertEqual(s.emptyMessage, "No favourites selected")
        XCTAssertEqual(s.layout.more?.count, 3)
        XCTAssertEqual(s.target(at: point(s, degrees: 180, radius: s.layout.more?.sector.midRadius ?? 0)), .more)
    }

    // MARK: Hub

    func testHubOffersTheGearAndDragOnlyAndTheGearIsAtLeast28Square() throws {
        for preset in RingSizePreset.allCases {
            let s = snapshot(allKinds, favourites: Array(allKinds.prefix(6)), preset: preset)
            let hub = s.layout.hub
            XCTAssertEqual(hub.discRadius, preset.innerRadius - 6)
            XCTAssertGreaterThanOrEqual(hub.gearFrame.width, 28)
            XCTAssertGreaterThanOrEqual(hub.gearFrame.height, 28)
            XCTAssertEqual(hub.showsSettingsWord, preset != .small, "the word appears from a 58-point disc")
            XCTAssertEqual(s.target(at: CGPoint(x: hub.gearFrame.midX, y: hub.gearFrame.midY)), .settings)
            XCTAssertEqual(s.target(at: CGPoint(x: hub.center.x, y: hub.center.y + hub.gearFrame.height / 2 + 4)), .drag)
            XCTAssertEqual(s.target(at: CGPoint(x: hub.center.x + hub.discRadius - 1, y: hub.center.y)), .drag)
            XCTAssertNil(s.target(at: point(s, degrees: 0, radius: (hub.discRadius + preset.innerRadius) / 2)),
                         "the band between hub and inner radius selects nothing")
            let frame = try XCTUnwrap(s.frame(of: .drag))
            XCTAssertEqual(frame.width, hub.discRadius * 2)
        }
    }

    func testGapsBetweenWedgesAndOutsideSelectNothing() {
        let s = snapshot(sixKinds)
        // Slot boundary between wedge 0 and wedge 1 sits at 30 degrees.
        XCTAssertNil(s.target(at: point(s, degrees: 30, radius: 120)))
        XCTAssertEqual(s.target(at: point(s, degrees: 27, radius: 120)), .wedge(.cpu))
        XCTAssertEqual(s.target(at: point(s, degrees: 33, radius: 120)), .wedge(.memory))
        XCTAssertNil(s.target(at: point(s, degrees: 0, radius: s.preset.outerRadius + 5)))
        XCTAssertNil(s.target(at: CGPoint(x: -5, y: -5)))
    }

    // MARK: Shared draw / hit geometry

    func testSectorOutlinesAndFramesAgreeWithHitTesting() throws {
        for kinds in [[StatKind.cpu], sixKinds, eightKinds] {
            let s = snapshot(kinds)
            for wedge in s.layout.favourites {
                let frame = try XCTUnwrap(s.frame(of: .wedge(wedge.kind)))
                for vertex in wedge.sector.outline {
                    XCTAssertTrue(frame.insetBy(dx: -0.001, dy: -0.001).contains(vertex))
                    // A vertex nudged toward the wedge's mid-radius anchor is a hit on that wedge.
                    let anchor = RingSector.point(center: s.layout.center, angle: wedge.sector.centerAngle,
                                                  radius: wedge.sector.midRadius)
                    let nudged = CGPoint(x: vertex.x + (anchor.x - vertex.x) * 0.02,
                                         y: vertex.y + (anchor.y - vertex.y) * 0.02)
                    XCTAssertEqual(s.target(at: nudged), .wedge(wedge.kind))
                }
            }
        }
    }

    // MARK: Identity stability

    func testUnavailableEntryKeepsIdentityAndPosition() {
        let available = snapshot(eightKinds)
        let withGap = snapshot(eightKinds) { kind in
            kind == .battery ? RingReading.unavailable(kind) : self.reading(kind)
        }
        XCTAssertEqual(withGap.favourites.map(\.kind), eightKinds)
        XCTAssertFalse(withGap.favourites[4].initialReading.isAvailable)
        for (a, b) in zip(available.layout.favourites, withGap.layout.favourites) {
            XCTAssertEqual(a.kind, b.kind)
            XCTAssertEqual(a.order, b.order)
            XCTAssertEqual(a.sector, b.sector, "sample availability cannot move a slot")
        }
    }

    func testLayoutDoesNotDependOnLiveValuesOnlyWorstCase() {
        let quiet = snapshot(sixKinds) { RingReading(value: "1%", widestValue: $0.ringFallbackWidest) }
        let busy = snapshot(sixKinds) { RingReading(value: "99%", widestValue: $0.ringFallbackWidest) }
        XCTAssertEqual(quiet.layout, busy.layout, "a sample update changes no slot, rung or text frame")
    }

    // MARK: Pointer state

    @MainActor
    func testHoverIsSuppressedUntilTheSummonPointerMovesAndTracksTheFrozenLayout() {
        let s = snapshot(sixKinds)
        let frame = CGRect(x: 100, y: 100, width: 360, height: 360)
        let state = RingPresentationState()
        let local = point(s, degrees: 0, radius: 120)   // twelve o'clock wedge
        let wedgeScreen = CGPoint(x: frame.minX + local.x, y: frame.maxY - local.y)
        state.beginSummon(pointer: wedgeScreen)
        state.updatePointer(screenPoint: wedgeScreen, ringFrame: frame, snapshot: s)
        XCTAssertNil(state.hovered, "stationary pointer after summon never highlights")
        XCTAssertNil(state.pointerInRing)

        state.updatePointer(screenPoint: CGPoint(x: wedgeScreen.x + 5, y: wedgeScreen.y), ringFrame: frame, snapshot: s)
        XCTAssertEqual(state.hovered, .wedge(.cpu))

        // Out in the gap beside the ring the position stays known, with nothing hovered.
        state.updatePointer(screenPoint: CGPoint(x: frame.maxX + 30, y: frame.midY), ringFrame: frame, snapshot: s)
        XCTAssertNil(state.hovered)
        XCTAssertEqual(state.pointerInRing?.x ?? 0, 360 + 30, accuracy: 0.001)

        // The gear highlights; the rest of the hub drag area never does.
        state.updatePointer(screenPoint: CGPoint(x: frame.midX, y: frame.midY), ringFrame: frame, snapshot: s)
        XCTAssertEqual(state.hovered, .settings)
        state.updatePointer(screenPoint: CGPoint(x: frame.midX, y: frame.midY - 25), ringFrame: frame, snapshot: s)
        XCTAssertNil(state.hovered)
    }

    // MARK: Content rungs (D-037)

    private func rungLabel(_ rung: RingContentRung) -> String {
        switch rung {
        case .labelValueSecondary: return "S"
        case .labelValue: return "L"
        case .iconValue: return "I"
        case .icon: return "O"
        }
    }

    /// Every wedge's frozen text frame lies inside its sector with padding, in every preset and
    /// favourite count, including the icon-only rung: nothing is clipped and nothing shrinks.
    func testEveryWedgeFitsAtLeastIconOnlyInEveryPresetAndFavouriteCount() {
        let kinds = allKinds
        let wide: (StatKind) -> RingReading = { kind in
            RingReading(value: kind.ringFallbackWidest, secondary: kind.ringFallbackWidest,
                        widestValue: kind.ringFallbackWidest, widestSecondary: kind.ringFallbackWidest)
        }
        for preset in RingSizePreset.allCases {
            for count in [0, 1, 6, 8] {
                let s = snapshot(kinds, favourites: Array(kinds.prefix(count)), preset: preset, reading: wide)
                XCTAssertTrue(s.layout.unfitFavourites.isEmpty, "\(preset)/\(count): \(s.layout.unfitFavourites.map(\.kind))")
                for favourite in s.layout.favourites {
                    XCTAssertTrue(favourite.sector.contains(rect: favourite.textFrame, padding: RingLayout.textPadding),
                                  "\(preset)/\(count) \(favourite.kind) \(favourite.rung)")
                }
                if let more = s.layout.more {
                    // Unpadded: the 24-degree wedge is narrow at Small, so the 6-point comfort
                    // margin is not required here, but the icon and count must lie inside it.
                    XCTAssertTrue(more.sector.contains(rect: more.contentFrame),
                                  "\(preset)/\(count): More icon and count are contained")
                }
            }
        }
    }

    func testTheTextCapLimitsEveryWedge() {
        for (cap, ceiling) in [(RingTextCap.iconValue, RingContentRung.iconValue), (.icon, .icon)] {
            let s = snapshot(sixKinds, preset: .large, cap: cap)
            XCTAssertTrue(s.layout.favourites.allSatisfy { $0.rung <= ceiling }, "\(cap)")
        }
    }

    #if DEBUG
    /// Lower bound per stat from the 1.1 rung matrix (`docs/evidence/gauge-ring-w1-rung-matrix.md`,
    /// worst rung over every slot a stat can occupy, 8 favourites without More). Each fixture's
    /// own slot can only be as rich or richer. Value is the matrix cell; where a fixture has no
    /// secondary line the cell is capped at label + value.
    private func matrixFloor(preset: RingSizePreset, fixture: String, kind: StatKind) -> RingContentRung {
        switch preset {
        case .small: return .icon
        case .medium:
            switch kind {
            case .cpu: return fixture == "long" ? .labelValueSecondary : .labelValue
            case .battery, .gpu, .power: return .labelValue
            case .temps: return .iconValue
            default: return .icon   // memory, disk, network, fans, uptime
            }
        case .large:
            if fixture == "long" {
                switch kind {
                case .cpu, .disk, .network, .battery: return .labelValueSecondary
                default: return .labelValue
                }
            }
            return .labelValue
        }
    }

    func testRungsOfTheEightAndLongFixturesAgreeWithTheOneOneMatrix() throws {
        var table: [String] = []
        for name in ["eight", "long"] {
            let fixture = try XCTUnwrap(RingFixture.named(name))
            for preset in RingSizePreset.allCases {
                let s = snapshot(fixture.enabledKinds, preset: preset) { fixture.reading(for: $0) }
                XCTAssertTrue(s.layout.unfitFavourites.isEmpty, "\(name)/\(preset)")
                let row = s.layout.favourites.map { "\($0.kind.rawValue)=\(rungLabel($0.rung))" }.joined(separator: " ")
                table.append("RING-RUNG \(name) \(preset.rawValue) \(row)")
                for favourite in s.layout.favourites {
                    let floor = matrixFloor(preset: preset, fixture: name, kind: favourite.kind)
                    XCTAssertGreaterThanOrEqual(favourite.rung, floor, "\(name)/\(preset) \(favourite.kind)")
                }
            }
        }
        print(table.joined(separator: "\n"))
    }

    func testTheOtherFixturesFitInEveryPreset() throws {
        for name in ["none", "one", "six", "twelve", "paired", "unavailable"] {
            let fixture = try XCTUnwrap(RingFixture.named(name))
            for preset in RingSizePreset.allCases {
                let s = snapshot(fixture.enabledKinds, preset: preset) { fixture.reading(for: $0) }
                XCTAssertTrue(s.layout.unfitFavourites.isEmpty, "\(name)/\(preset)")
            }
        }
    }

    // MARK: Gauges on readings

    func testFixtureReadingsCarryTheirGaugeAndUnavailableStatsStayUnavailable() throws {
        let eight = try XCTUnwrap(RingFixture.named("eight"))
        for kind in eight.enabledKinds {
            let gauge = try XCTUnwrap(eight.reading(for: kind).gauge, "\(kind)")
            XCTAssertEqual(gauge.stat, kind)
            XCTAssertTrue(gauge.isAvailable, "\(kind) has a fill in the plain fixtures")
        }
        let unavailable = try XCTUnwrap(RingFixture.named("unavailable"))
        for kind in [StatKind.battery, .gpu, .power] {
            let reading = unavailable.reading(for: kind)
            XCTAssertFalse(reading.isAvailable)
            XCTAssertEqual(reading.gauge?.isAvailable, false, "unavailable draws the empty track, never a zero fill")
        }
        XCTAssertEqual(unavailable.reading(for: .cpu).gauge?.isAvailable, true)
    }

    func testPowerCeilingArgumentChangesTheFixturePowerFill() throws {
        let fixture = try XCTUnwrap(RingFixture.named("eight"))
        let thirty = try XCTUnwrap(fixture.reading(for: .power).gauge)
        let sixty = try XCTUnwrap(fixture.reading(for: .power, powerCeilingWatts: 60).gauge)
        XCTAssertEqual(thirty.totalFraction, 2 * sixty.totalFraction, accuracy: 1e-9)
        XCTAssertEqual(thirty.basisNote, "Fill is measured against a fixed 30 W ceiling.")
        XCTAssertEqual(sixty.basisNote, "Fill is measured against a fixed 60 W ceiling.")
    }
    #endif

    @MainActor
    func testRealDataReadingsBuildTheirGaugeFromLiveSamples() {
        let store = StatsStore()
        // Nothing sampled yet: every stat is unavailable rather than a measured zero.
        for kind in StatKind.allCases where kind != .loadAverage {
            XCTAssertFalse(store.ringGauge(for: kind).isAvailable, "\(kind) before any sample")
        }
        store.cpu = CPUSample(totalUsagePercent: 50, userPercent: 30, systemPercent: 15, idlePercent: 50)
        store.disk = DiskSample(usedBytes: 250, freeBytes: 750, totalBytes: 1_000,
                                readBytesPerSec: 0, writeBytesPerSec: 0)
        store.network = NetworkSample(downBytesPerSec: 1_000_000, upBytesPerSec: 0)
        store.battery = BatterySample(isPresent: true, percent: 80, isCharging: true, isOnAC: true,
                                      minutesRemaining: nil, healthPercent: nil, cycleCount: nil, temperatureC: nil)

        let cpu = store.ringGauge(for: .cpu)
        XCTAssertEqual(cpu.totalFraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(cpu.components.map(\.component), [.user, .system, .nice])
        XCTAssertEqual(store.ringGauge(for: .disk).totalFraction, 0.25, accuracy: 1e-9, "used capacity, whatever the text shows")
        XCTAssertNotNil(store.ringGauge(for: .disk).basisNote)
        XCTAssertEqual(store.ringGauge(for: .network).halves?.left ?? 0, RingRateScale.fraction(bytesPerSecond: 1_000_000), accuracy: 1e-9)
        XCTAssertEqual(store.ringGauge(for: .battery).marks, [.chargingBolt])
        #if DEBUG
        XCTAssertNil(store.ringGauge(for: .cpu).peak, "no peak until a sample has been recorded")
        store.recordRingPeak(.cpu, 0.7)
        store.recordRingPeak(.cpu, 0.4)
        XCTAssertEqual(store.ringGauge(for: .cpu).peak ?? 0, 0.7, accuracy: 1e-9, "60-second maximum, not the latest value")
        #endif
    }

    // MARK: Measurement

    func testMeasurementUsesWorstCaseNotCurrentReading() {
        let narrow = RingTypography.blockSize(name: "CPU", reading: RingReading(value: "1%", widestValue: "1%"))
        let wide = RingTypography.blockSize(name: "CPU", reading: RingReading(value: "1%", widestValue: "888,88 GB"))
        XCTAssertGreaterThan(wide.width, narrow.width)
        let paired = RingTypography.blockSize(name: "CPU", reading: RingReading(
            value: "1%", secondary: "2%", widestValue: "1%", widestSecondary: "2%"))
        XCTAssertGreaterThan(paired.height, narrow.height)
    }

    func testRungSizesDescendAndSkipTheSecondaryWhenThereIsNone() {
        let plain = RingTypography.rungSizes(name: "Memory", reading: RingReading(value: "1 GB", widestValue: "888,88 GB"))
        XCTAssertNil(plain.labelValueSecondary)
        XCTAssertGreaterThan(plain.labelValue.height, plain.icon.height)
        XCTAssertEqual(plain.icon, CGSize(width: RingTypography.iconSide, height: RingTypography.iconSide))
        let paired = RingTypography.rungSizes(name: "Memory", reading: RingReading(
            value: "U 1 GB", secondary: "F 2 GB", widestValue: "U 888,88 GB", widestSecondary: "F 888,88 GB"))
        XCTAssertNotNil(paired.labelValueSecondary)
        XCTAssertGreaterThan(paired.labelValueSecondary?.height ?? 0, paired.labelValue.height)
    }

    func testAccessibilityTextCarriesTheFullReadingWhateverTheRung() {
        XCTAssertEqual(RingReading(value: "42%", secondary: "61\u{00B0}C", widestValue: "100%").accessibilityText,
                       "42%, 61\u{00B0}C")
        XCTAssertEqual(RingReading(value: "42%", widestValue: "100%").accessibilityText, "42%")
        XCTAssertEqual(RingReading.unavailable(.fan).accessibilityText, "Unavailable")
    }
}

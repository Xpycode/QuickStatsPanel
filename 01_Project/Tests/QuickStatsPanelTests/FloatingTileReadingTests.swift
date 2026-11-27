import XCTest

#if DEBUG
/// Floating-tile readings: the explicit usage basis, the spec's colour bands and their boundaries,
/// the reversed battery scale, neutral scales, unavailable states and all eleven stat identities.
@MainActor
final class FloatingTileReadingTests: XCTestCase {

    private func reading(_ kind: StatKind, percent: Double?, value: String = "x") -> FloatingTileReading {
        FloatingTileReading(descriptorKind: kind, value: value, widestValue: value,
                            secondary: nil, widestSecondary: nil, rawPercent: percent)
    }

    // MARK: Bands (FT-7)

    func testBandBoundariesForUtilization() {
        let cases: [(Double, FloatingTileUsageBand)] = [
            (0, .low), (49.9, .low), (50, .elevated), (79.9, .elevated), (80, .high), (100, .high),
        ]
        for kind in [StatKind.cpu, .gpu, .memory, .disk] {
            for (percent, band) in cases {
                XCTAssertEqual(reading(kind, percent: percent).band, band, "\(kind) at \(percent)")
            }
        }
    }

    func testBandsMapToTheExistingThemeBands() {
        XCTAssertEqual(FloatingTileUsageBand.low.themeBand, .calm)
        XCTAssertEqual(FloatingTileUsageBand.elevated.themeBand, .busy)
        XCTAssertEqual(FloatingTileUsageBand.high.themeBand, .hot)
    }

    func testBatteryUsesTheReversedScale() {
        // Band is on 100 minus charge: low charge reads high.
        XCTAssertEqual(reading(.battery, percent: 100).band, .low)
        XCTAssertEqual(reading(.battery, percent: 50.1).band, .low, "drained 49.9")
        XCTAssertEqual(reading(.battery, percent: 50).band, .elevated, "drained 50")
        XCTAssertEqual(reading(.battery, percent: 20.1).band, .elevated, "drained 79.9")
        XCTAssertEqual(reading(.battery, percent: 20).band, .high, "drained 80")
        XCTAssertEqual(reading(.battery, percent: 0).band, .high, "empty battery")
        XCTAssertEqual(reading(.battery, percent: 12).usagePercent, 88)
        XCTAssertEqual(reading(.battery, percent: 12).caption, "88% drained")
    }

    func testNeutralScalesNeverGetABandOrPercentage() {
        for kind in [StatKind.network, .fan, .power, .temps, .loadAverage, .uptime] {
            for percent in [0.0, 49.9, 95, 100] as [Double?] {
                let r = reading(kind, percent: percent)
                XCTAssertNil(r.band, "\(kind) has no meaningful fraction")
                XCTAssertNil(r.usagePercent)
            }
            XCTAssertFalse(FloatingTileUsageBasis.basis(for: kind).isMeaningfulFraction)
            XCTAssertFalse(reading(kind, percent: 99).caption.contains("%"), "\(kind) states a scale, not a percentage")
        }
        for kind in [StatKind.cpu, .gpu, .memory, .disk, .battery] {
            XCTAssertTrue(FloatingTileUsageBasis.basis(for: kind).isMeaningfulFraction)
        }
    }

    func testCaptionStatesThePercentageAndItsBasisWithoutRoundingAcrossABand() {
        XCTAssertEqual(reading(.cpu, percent: 49.9).caption, "49% utilization", "never reads 50% while still low")
        XCTAssertEqual(reading(.memory, percent: 79.9).caption, "79% of total")
        XCTAssertEqual(reading(.disk, percent: 80).caption, "80% of capacity")
        XCTAssertEqual(reading(.gpu, percent: 100).caption, "100% utilization")
        XCTAssertTrue(reading(.memory, percent: 56).explanation.contains("emory used as a share of total"))
        XCTAssertTrue(reading(.network, percent: nil).explanation.contains("no status colour"))
    }

    func testUnmeasurableOrOutOfRangeNumbersNeverBecomeAFalseZero() {
        let none = reading(.memory, percent: nil)
        XCTAssertNil(none.usagePercent)
        XCTAssertNil(none.band)
        XCTAssertEqual(none.caption, "Not measured")
        XCTAssertNil(reading(.cpu, percent: .nan).band)
        XCTAssertNil(reading(.cpu, percent: .infinity).usagePercent)
        XCTAssertEqual(reading(.cpu, percent: 140).usagePercent, 100, "clamped")
        XCTAssertEqual(reading(.cpu, percent: -3).usagePercent, 0)
    }

    func testPairedReadingKeepsItsOwnReservedWidth() {
        let r = FloatingTileReading(descriptorKind: .network, value: "\u{2193} 4,2 MB/s", widestValue: "\u{2193} 888 MB/s",
                                    secondary: "\u{2191} 0,3 MB/s", widestSecondary: "\u{2191} 888 MB/s", rawPercent: nil)
        XCTAssertEqual(r.secondary, "\u{2191} 0,3 MB/s")
        XCTAssertEqual(r.widestSecondary, "\u{2191} 888 MB/s")
        let single = reading(.cpu, percent: 40)
        XCTAssertNil(single.secondary)
        XCTAssertNil(single.widestSecondary)
    }

    // MARK: Fixtures through the store

    private struct Rig {
        let store: StatsStore
        let settings: AppSettings
        let options: FloatingTilePrototypeOptions
    }

    private func rig(_ fixture: FloatingTileFixtureName) throws -> Rig {
        var options = try XCTUnwrap(FloatingTilePrototypeOptions.parse(["--floating-tiles-prototype"]))
        options.fixture = fixture
        let defaults = try XCTUnwrap(FloatingTileFixtures.isolatedDefaults(for: options))
        addTeardownBlock {
            FloatingTileFixtures.removeIsolatedDefaults(for: options)
            try? FileManager.default.removeItem(at: options.historyRoot)
        }
        return Rig(store: FloatingTileFixtures.makeStore(options: options),
                   settings: AppSettings(defaults: defaults), options: options)
    }

    func testAllElevenIdentitiesHaveReadingsWithReservedWidths() throws {
        let rig = try rig(.all)
        XCTAssertEqual(rig.options.fixture.enabledKinds, StatKind.allCases)
        XCTAssertEqual(StatKind.allCases.count, 11)
        for kind in StatKind.allCases {
            let r = rig.store.floatingTileReading(for: kind, settings: rig.settings)
            XCTAssertTrue(r.isAvailable, "\(kind)")
            XCTAssertFalse(r.primary.isEmpty, "\(kind)")
            XCTAssertGreaterThanOrEqual(r.widestPrimary.count, r.primary.count, "\(kind) reserves at least its value")
            if let secondary = r.secondary {
                XCTAssertGreaterThanOrEqual(r.widestSecondary?.count ?? 0, secondary.count, "\(kind)")
            }
            XCTAssertEqual(r.usagePercent != nil, r.basis.isMeaningfulFraction, "\(kind)")
        }
        let network = rig.store.floatingTileReading(for: .network, settings: rig.settings)
        XCTAssertNotNil(network.secondary, "the configured paired Network reading is kept")
    }

    func testTypicalFixtureBandsFollowTheStatedBasis() throws {
        let rig = try rig(.all)
        func band(_ kind: StatKind) -> FloatingTileUsageBand? {
            rig.store.floatingTileReading(for: kind, settings: rig.settings).band
        }
        XCTAssertEqual(band(.cpu), .low, "42%")
        XCTAssertEqual(band(.memory), .elevated, "19.4 of 34.4 GB is 56% used")
        XCTAssertEqual(band(.disk), .elevated, "640 of 1000 GB")
        XCTAssertEqual(band(.battery), .low, "76% charge is 24% drained")
        XCTAssertEqual(band(.gpu), .low)
        XCTAssertNil(band(.network))
    }

    func testHotFixtureCoversHighAndBoundaryBands() throws {
        let rig = try rig(.allHot)
        func r(_ kind: StatKind) -> FloatingTileReading { rig.store.floatingTileReading(for: kind, settings: rig.settings) }
        XCTAssertEqual(r(.cpu).band, .high)
        XCTAssertEqual(r(.memory).band, .high)
        XCTAssertEqual(r(.disk).band, .elevated, "79.9% stays below the high band")
        XCTAssertEqual(r(.disk).caption, "79% of capacity")
        XCTAssertEqual(r(.gpu).band, .elevated, "exactly 50")
        XCTAssertEqual(r(.battery).band, .high, "12% charge")
    }

    func testUnavailableFixtureKeepsIdentityWithNoFalseZero() throws {
        let rig = try rig(.unavailable)
        for kind in [StatKind.battery, .gpu, .fan, .power] {
            let r = rig.store.floatingTileReading(for: kind, settings: rig.settings)
            XCTAssertFalse(r.isAvailable, "\(kind)")
            XCTAssertEqual(r.primary, "Unavailable")
            XCTAssertNil(r.usagePercent)
            XCTAssertNil(r.band)
            XCTAssertEqual(r.caption, "No reading")
            XCTAssertFalse(r.primary.contains("0"), "no false zero")
            XCTAssertTrue(r.accessibilityText.contains("unavailable"))
        }
        for kind in [StatKind.cpu, .memory, .disk, .network, .temps, .loadAverage, .uptime] {
            XCTAssertTrue(rig.store.floatingTileReading(for: kind, settings: rig.settings).isAvailable, "\(kind)")
        }
    }

    func testEmptyTotalsGiveNoPercentageInsteadOfZero() {
        let store = StatsStore()
        XCTAssertNil(store.usageBasisPercent(for: .memory), "total of zero bytes")
        XCTAssertNil(store.usageBasisPercent(for: .disk))
        XCTAssertNil(store.usageBasisPercent(for: .battery), "no battery present")
        XCTAssertNil(store.usageBasisPercent(for: .gpu), "no GPU reading")
    }

    func testFixtureNamesAndSavedOrders() {
        XCTAssertEqual(FloatingTileFixtureName.all.enabledKinds.count, 11)
        XCTAssertEqual(FloatingTileFixtureName.allReversed.enabledKinds, StatKind.allCases.reversed())
        XCTAssertEqual(FloatingTileFixtureName.empty.enabledKinds, [])
        XCTAssertEqual(FloatingTileFixtureName.one.enabledKinds, [.memory])
        XCTAssertEqual(FloatingTileFixtureName.subset.enabledKinds, [.disk, .battery, .uptime, .memory, .temps])
        XCTAssertEqual(FloatingTileFixtureName.unavailable.unavailableKinds, [.battery, .gpu, .fan, .power])
        XCTAssertTrue(FloatingTileFixtureName.allLive.drifts)
        XCTAssertTrue(FloatingTileFixtureName.allHot.isHot)
        XCTAssertTrue(FloatingTileFixtureName.all.unavailableKinds.isEmpty)
    }
}
#endif

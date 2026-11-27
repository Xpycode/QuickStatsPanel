import XCTest

#if DEBUG
/// Hostless checks of the floating-tile Debug launch grammar and its isolation names.
final class FloatingTileOptionsTests: XCTestCase {

    private func parse(_ extra: [String] = [], id: String = "TEST") throws -> FloatingTilePrototypeOptions {
        try XCTUnwrap(FloatingTilePrototypeOptions.parse(["QuickStatsPanel", "--floating-tiles-prototype"] + extra,
                                                         isolationID: id))
    }

    func testWithoutThePrototypeFlagNothingApplies() {
        XCTAssertNil(FloatingTilePrototypeOptions.parse([]))
        XCTAssertNil(FloatingTilePrototypeOptions.parse(["QuickStatsPanel", "--floating-tiles-fixture=network-cpu"]),
                     "a fixture argument alone never switches the prototype on")
    }

    func testFlagAloneSelectsTheCPUNetworkFixture() throws {
        let options = try parse()
        XCTAssertEqual(options.fixture, .cpuNetwork)
        XCTAssertEqual(options.fixture.enabledKinds, [.cpu, .network])
        XCTAssertTrue(options.warnings.isEmpty)
    }

    func testEveryFixtureNameIsParsed() throws {
        for name in FloatingTileFixtureName.allCases {
            XCTAssertEqual(try parse(["--floating-tiles-fixture=\(name.rawValue)"]).fixture, name)
        }
        XCTAssertEqual(try parse(["--floating-tiles-fixture=network-cpu"]).fixture.enabledKinds, [.network, .cpu])
    }

    func testUnknownFixtureWarnsAndUsesTheDefault() throws {
        let options = try parse(["--floating-tiles-fixture=eleven"])
        XCTAssertEqual(options.fixture, .cpuNetwork)
        XCTAssertEqual(options.warnings.count, 1)
        XCTAssertTrue(options.warnings[0].contains("eleven"))
    }

    func testRingPrototypeIsMutuallyExclusive() {
        XCTAssertNil(FloatingTilePrototypeOptions.parse(["QuickStatsPanel", "--floating-tiles-prototype", "--ring-prototype"]),
                     "with both flags the ring keeps its launch and the tiles stay off")
        XCTAssertNotNil(RingPrototypeOptions.parse(["QuickStatsPanel", "--floating-tiles-prototype", "--ring-prototype"]))
        XCTAssertNil(RingPrototypeOptions.parse(["QuickStatsPanel", "--floating-tiles-prototype"]),
                     "the tile flag never switches the ring on")
    }

    func testIsolationNamesAreUniqueAndNeverTheStandardLocations() throws {
        let a = try XCTUnwrap(FloatingTilePrototypeOptions.parse(["--floating-tiles-prototype"]))
        let b = try XCTUnwrap(FloatingTilePrototypeOptions.parse(["--floating-tiles-prototype"]))
        XCTAssertNotEqual(a.defaultsSuiteName, b.defaultsSuiteName, "every launch gets its own suite")
        XCTAssertNotEqual(a.historyRoot, b.historyRoot)
        XCTAssertNotEqual(a.defaultsSuiteName, "com.sim.QuickStatsPanel")
        let temp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        XCTAssertTrue(a.defaultsFile.standardizedFileURL.path.hasPrefix(temp), "defaults file is temporary")
        XCTAssertFalse(a.defaultsFile.path.contains("Library/Preferences"))
        XCTAssertTrue(a.historyRoot.standardizedFileURL.path.hasPrefix(temp), "history root is temporary")
        XCTAssertFalse(a.historyRoot.path.contains("Application Support"))
    }

    func testTheTestProcessIsNotAPrototypeLaunch() {
        XCTAssertNil(FloatingTilePrototypeOptions.current, "normal launches and tests keep default initialization")
    }

    func testFixtureOrderPutsEnabledStatsFirstAndKeepsEveryStat() {
        for name in FloatingTileFixtureName.allCases {
            XCTAssertEqual(Array(name.statOrder.prefix(name.enabledKinds.count)), name.enabledKinds)
            XCTAssertEqual(Set(name.statOrder), Set(StatKind.allCases))
            XCTAssertEqual(name.statOrder.count, StatKind.allCases.count)
        }
    }
}
#endif

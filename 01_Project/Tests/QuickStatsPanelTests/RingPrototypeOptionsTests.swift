import XCTest

#if DEBUG
/// Hostless checks of the Debug launch-argument grammar: defaults, every accepted value, and the
/// log-and-default rule for unknown values.
final class RingPrototypeOptionsTests: XCTestCase {

    private func parse(_ extra: [String] = []) throws -> RingPrototypeOptions {
        try XCTUnwrap(RingPrototypeOptions.parse(["QuickStatsPanel", "--ring-prototype"] + extra))
    }

    func testWithoutThePrototypeFlagNothingApplies() {
        XCTAssertNil(RingPrototypeOptions.parse([]))
        XCTAssertNil(RingPrototypeOptions.parse(["--ring-fixture=eight", "--ring-size=large"]),
                     "options alone never switch the ring on")
    }

    func testPrototypeFlagAloneGivesTheDocumentedDefaults() throws {
        let o = try parse()
        XCTAssertNil(o.fixtureName, "real data")
        XCTAssertEqual(o.size, .medium)
        XCTAssertEqual(o.text, .label)
        XCTAssertEqual(o.fill, .area)
        XCTAssertEqual(o.favourites, 8)
        XCTAssertEqual(o.parts, .typical)
        XCTAssertEqual(o.powerCeilingWatts, 30)
        XCTAssertTrue(o.warnings.isEmpty)
    }

    func testEveryAcceptedValueIsParsed() throws {
        for size in RingSizePreset.allCases {
            XCTAssertEqual(try parse(["--ring-size=\(size.rawValue)"]).size, size)
        }
        XCTAssertEqual(try parse(["--ring-text=label"]).text, .label)
        XCTAssertEqual(try parse(["--ring-text=icon-value"]).text, .iconValue)
        XCTAssertEqual(try parse(["--ring-text=icon"]).text, .icon)
        XCTAssertEqual(try parse(["--ring-fill=area"]).fill, .area)
        XCTAssertEqual(try parse(["--ring-fill=linear"]).fill, .linear)
        for count in 0...8 {
            XCTAssertEqual(try parse(["--ring-favourites=\(count)"]).favourites, count)
        }
        for name in RingPartFixtureName.allCases {
            let o = try parse(["--ring-fixture=eight", "--ring-parts=\(name.rawValue)"])
            XCTAssertEqual(o.parts, name)
            XCTAssertTrue(o.warnings.isEmpty, "--ring-parts is valid in fixture mode")
        }
        XCTAssertEqual(try parse(["--ring-power-ceiling=45"]).powerCeilingWatts, 45)
        XCTAssertEqual(try parse(["--ring-power-ceiling=17.5"]).powerCeilingWatts, 17.5)
        for name in RingFixture.names {
            XCTAssertEqual(try parse(["--ring-fixture=\(name)"]).fixtureName, name)
        }
    }

    func testUnknownValuesLogAndFallBackToTheDefault() throws {
        let bad = try parse(["--ring-size=huge", "--ring-text=words", "--ring-fill=cubic",
                             "--ring-favourites=9", "--ring-parts=lots", "--ring-power-ceiling=-3"])
        XCTAssertEqual(bad.size, .medium)
        XCTAssertEqual(bad.text, .label)
        XCTAssertEqual(bad.fill, .area)
        XCTAssertEqual(bad.favourites, 8)
        XCTAssertEqual(bad.parts, .typical)
        XCTAssertEqual(bad.powerCeilingWatts, 30)
        XCTAssertEqual(bad.warnings.count, 6, "one logged line per rejected argument: \(bad.warnings)")

        XCTAssertEqual(try parse(["--ring-favourites=-1"]).favourites, 8)
        XCTAssertEqual(try parse(["--ring-favourites=abc"]).favourites, 8)
        XCTAssertEqual(try parse(["--ring-power-ceiling=0"]).powerCeilingWatts, 30)
        XCTAssertEqual(try parse(["--ring-power-ceiling=nan"]).powerCeilingWatts, 30)
        XCTAssertEqual(try parse(["--ring-power-ceiling=inf"]).powerCeilingWatts, 30)
    }

    func testUnknownFixtureFallsBackToSix() throws {
        let o = try parse(["--ring-fixture=nope"])
        XCTAssertEqual(o.fixtureName, "six")
        XCTAssertEqual(o.warnings.count, 1)
    }

    func testPartsWithoutAFixtureAreAcceptedButIgnoredWithANote() throws {
        let o = try parse(["--ring-parts=dense"])
        XCTAssertEqual(o.parts, .dense)
        XCTAssertNil(o.fixtureName)
        XCTAssertEqual(o.warnings.count, 1)
    }

    func testTheFirstOccurrenceOfAnArgumentWins() throws {
        XCTAssertEqual(try parse(["--ring-size=small", "--ring-size=large"]).size, .small)
    }
}
#endif

import XCTest

final class RingPartsTests: XCTestCase {

    // MARK: Helpers

    private func cores(_ spec: [(String, Int)], usage: (Int) -> Double = { Double(($0 * 13) % 90) }) -> [RingCoreInput] {
        var out: [RingCoreInput] = []
        var n = 0
        for (group, count) in spec {
            for i in 0..<count {
                out.append(RingCoreInput(id: "c\(n)", name: "\(group.prefix(1))\(i + 1)", group: group, usagePercent: usage(n)))
                n += 1
            }
        }
        return out
    }

    private func sensors(_ spec: [(String, Int)], base: Double = 40) -> [RingSensorInput] {
        var out: [RingSensorInput] = []
        var n = 0
        for (role, count) in spec {
            for i in 0..<count {
                out.append(RingSensorInput(group: role, name: "\(role) \(i + 1)", celsius: base + Double((n * 5) % 40)))
                n += 1
            }
        }
        return out
    }

    // MARK: Fewer than two parts

    func testFewerThanTwoPartsReportsNoSubRing() {
        let none = RingPartBuilder.cpu(cores: [])
        XCTAssertFalse(none.hasSubRing)
        XCTAssertEqual(none.noSubRingReason, .fewerThanTwoParts(count: 0))

        let one = RingPartBuilder.network(interfaces: [RingInterfaceInput(id: "en0", name: "Wi-Fi", downBytesPerSec: 1, upBytesPerSec: 1)])
        XCTAssertFalse(one.hasSubRing)
        XCTAssertEqual(one.noSubRingReason, .fewerThanTwoParts(count: 1))

        let two = RingPartBuilder.cpu(cores: cores([("Performance", 2)]))
        XCTAssertTrue(two.hasSubRing)
        XCTAssertNil(two.noSubRingReason)
    }

    // MARK: Order, grouping, no sorting

    func testGroupOrderIsFixedAndPartsAreNeverSortedByValue() {
        // Input interleaves classes and uses values that would sort differently.
        let input = [
            RingCoreInput(id: "a", name: "P1", group: "Performance", usagePercent: 90),
            RingCoreInput(id: "b", name: "E1", group: "Efficiency", usagePercent: 5),
            RingCoreInput(id: "c", name: "P2", group: "Performance", usagePercent: 10),
            RingCoreInput(id: "d", name: "E2", group: "Efficiency", usagePercent: 70)]
        let list = RingPartBuilder.cpu(cores: input)
        XCTAssertEqual(list.parts.map(\.name), ["E1", "E2", "P1", "P2"])
        XCTAssertEqual(list.parts.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(list.groups, ["Efficiency", "Performance"])
    }

    func testSensorGroupsFollowTheExistingRoleOrderAndUnknownRolesGoLast() {
        let input = [
            RingSensorInput(group: "Battery", name: "B", celsius: 31),
            RingSensorInput(group: "Mystery", name: "M", celsius: 50),
            RingSensorInput(group: "CPU", name: "C", celsius: 60),
            RingSensorInput(group: "SSD", name: "S", celsius: 35)]
        let list = RingPartBuilder.temperature(sensors: input)
        XCTAssertEqual(list.groups, ["CPU", "SSD", "Battery", "Other"])
        XCTAssertEqual(list.parts.map(\.name), ["C", "S", "B", "M"])
    }

    // MARK: Temperature rules

    func testSameNamedSensorsMergeToTheirHottestAndInvalidReadingsDrop() {
        let input = [
            RingSensorInput(group: "CPU", name: "die", celsius: 60),
            RingSensorInput(group: "CPU", name: "die", celsius: 72),
            RingSensorInput(group: "CPU", name: "die", celsius: 66),
            RingSensorInput(group: "GPU", name: "die", celsius: 50),
            RingSensorInput(group: "SoC", name: "hot", celsius: 111),
            RingSensorInput(group: "SoC", name: "cold", celsius: -0.5),
            RingSensorInput(group: "SoC", name: "edge-low", celsius: 0),
            RingSensorInput(group: "SoC", name: "edge-high", celsius: 110),
            RingSensorInput(group: "SSD", name: "nan", celsius: .nan)]
        let list = RingPartBuilder.temperature(sensors: input)
        XCTAssertEqual(list.parts.map(\.id), ["CPU/die", "GPU/die", "SoC/edge-low", "SoC/edge-high"])
        XCTAssertEqual(list.parts.first?.raw, 72)
        XCTAssertEqual(list.parentAggregate?.primary, 110)
    }

    func testHottestSegmentEqualsTheTemperatureGaugeFill() throws {
        let input = sensors([("CPU", 6), ("GPU", 4), ("SoC", 3)])
        let list = RingPartBuilder.temperature(sensors: input)
        let sample = TemperatureSample(thermalState: .nominal,
                                       sensors: input.map { TempReading(label: $0.name, celsius: $0.celsius) })
        let gauge = RingGaugeMapper.temperature(sample)
        let hottest = try XCTUnwrap(RingPartAggregation.hottest(list.parts))
        XCTAssertEqual(gauge.totalFraction, RingGaugeMapper.temperatureFraction(celsius: hottest), accuracy: 1e-9)
    }

    // MARK: Hyperthreads and collapse (AC-35)

    func testAtOrBelow32CoresNothingPairsOrCollapses() {
        let list = RingPartBuilder.cpu(cores: cores([("Efficiency", 8), ("Performance", 24)]))
        XCTAssertEqual(list.parts.count, 32)
        XCTAssertFalse(list.isCollapsed)
        XCTAssertTrue(list.parts.allSatisfy { $0.memberCount == 1 })
    }

    func testAbove32CoresHyperthreadsPairBeforeAnyCollapse() {
        // 40 logical cores = 20 physical with two threads each, one class.
        var input: [RingCoreInput] = []
        for i in 0..<40 {
            input.append(RingCoreInput(id: "t\(i)", name: "T\(i)", group: "Cores", usagePercent: Double(i), physicalIndex: i / 2))
        }
        let list = RingPartBuilder.cpu(cores: input)
        XCTAssertEqual(list.sourceCount, 40)
        XCTAssertEqual(list.parts.count, 20)
        XCTAssertFalse(list.isCollapsed)
        XCTAssertTrue(list.parts.allSatisfy { $0.memberCount == 2 })
        XCTAssertEqual(list.parts[0].raw ?? -1, 0.5, accuracy: 1e-9)
        // Pairing alone keeps the parent mean.
        let aggregate = try? XCTUnwrap(list.aggregate())
        XCTAssertEqual(aggregate?.primary ?? -1, list.parentAggregate?.primary ?? -2, accuracy: 1e-9)
    }

    func testCollapseKeepsTheParentTotalAndEndsAtOrBelow32() throws {
        let input = sensors([("CPU", 20), ("GPU", 12), ("SoC", 8), ("SSD", 4), ("Battery", 3)])  // 47
        let list = RingPartBuilder.temperature(sensors: input)
        XCTAssertEqual(list.sourceCount, 47)
        XCTAssertLessThanOrEqual(list.parts.count, 32)
        XCTAssertTrue(list.isCollapsed)
        // The parent value is the pre-collapse hottest and the displayed hottest still matches it.
        let expected = input.map(\.celsius).max()
        XCTAssertEqual(list.parentAggregate?.primary, expected)
        XCTAssertEqual(list.aggregate()?.primary, expected)
        // No source part is silently dropped.
        XCTAssertEqual(list.parts.reduce(0) { $0 + $1.memberCount }, 47)
        // Indices are contiguous.
        XCTAssertEqual(list.parts.map(\.index), Array(0..<list.parts.count))
    }

    func testCollapseTakesTheLargestGroupFirstAndShowsItsHighestMember() throws {
        let input = sensors([("CPU", 30), ("GPU", 4)])   // 34 -> collapse CPU only
        let list = RingPartBuilder.temperature(sensors: input)
        XCTAssertEqual(list.parts.count, 5)              // CPU collapses to one, GPU stays 4
        let cpu = try XCTUnwrap(list.parts.first { $0.group == "CPU" })
        XCTAssertEqual(cpu.memberCount, 30)
        let cpuMax = input.filter { $0.group == "CPU" }.map(\.celsius).max()
        XCTAssertEqual(cpu.raw, cpuMax)
        XCTAssertEqual(list.parts.filter { $0.group == "GPU" }.count, 4)
    }

    func testCollapseKeepsMeanParentTotalForCores() {
        // Forty cores in three classes, no sibling info: pairing does nothing, collapse applies.
        let list = RingPartBuilder.cpu(cores: cores([("Efficiency", 4), ("Performance", 28), ("Super", 8)]))
        let all = cores([("Efficiency", 4), ("Performance", 28), ("Super", 8)])
        let mean = all.map(\.usagePercent).reduce(0, +) / 40
        XCTAssertLessThanOrEqual(list.parts.count, 32)
        XCTAssertEqual(list.parentAggregate?.primary ?? -1, mean, accuracy: 1e-9)
        XCTAssertEqual(list.parts.reduce(0) { $0 + $1.memberCount }, 40)
        // The collapsed segment shows the highest member of the Performance group.
        let top = all.filter { $0.group == "Performance" }.map(\.usagePercent).max()
        XCTAssertEqual(list.parts.first { $0.group == "Performance" }?.raw, top)
    }

    func testCollapseBackstopWhenEveryGroupIsASingleSegment() {
        // 40 distinct unknown roles merge into "Other" for sensors, so use cores with 40 classes.
        let input = (0..<40).map { RingCoreInput(id: "c\($0)", name: "N\($0)", group: "G\($0)", usagePercent: Double($0)) }
        let list = RingPartBuilder.cpu(cores: input)
        XCTAssertEqual(list.parts.count, 32)
        XCTAssertEqual(list.parts.reduce(0) { $0 + $1.memberCount }, 40)
        XCTAssertEqual(list.parts.last?.raw, 39)
    }

    // MARK: Disk and Network

    func testDiskUsesUsedFractionAndBootContainerMatchesTheReading() throws {
        let list = RingPartBuilder.disk(volumes: [
            RingVolumeInput(id: "boot", name: "Macintosh HD", usedBytes: 600, totalBytes: 1000, isBoot: true),
            RingVolumeInput(id: "ext", name: "Archive", usedBytes: 100, totalBytes: 2000, isBoot: false),
            RingVolumeInput(id: "zero", name: "Broken", usedBytes: 0, totalBytes: 0, isBoot: false)])
        XCTAssertEqual(list.parts.count, 2)
        XCTAssertEqual(list.parts[0].fraction, 0.6)
        XCTAssertEqual(list.aggregate()?.primary, 0.6)
        let disk = DiskSample(usedBytes: 600, freeBytes: 400, totalBytes: 1000, readBytesPerSec: 0, writeBytesPerSec: 0)
        XCTAssertEqual(try XCTUnwrap(list.aggregate()).primary * 100, disk.usedPercent, accuracy: 1e-9)
    }

    func testNetworkInterfacesSumAndUseHalvesOnTheLogScale() throws {
        let list = RingPartBuilder.network(interfaces: [
            RingInterfaceInput(id: "en0", name: "Wi-Fi", downBytesPerSec: 1_000_000, upBytesPerSec: 100_000),
            RingInterfaceInput(id: "en5", name: "Ethernet", downBytesPerSec: 500, upBytesPerSec: 2_000_000)])
        XCTAssertEqual(list.parts[0].fraction ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(list.parts[0].secondFraction ?? -1, 2.0 / 6.0, accuracy: 1e-9)
        XCTAssertEqual(list.parts[1].fraction, 0)
        let sum = try XCTUnwrap(list.aggregate())
        XCTAssertEqual(sum.primary, 1_000_500)
        XCTAssertEqual(sum.secondary, 2_100_000)
        XCTAssertEqual(list.parentAggregate, sum)
    }

    func testAgreementRulesPerStat() {
        XCTAssertEqual(StatKind.cpu.ringPartAgreement, .mean)
        XCTAssertEqual(StatKind.disk.ringPartAgreement, .bootContainer)
        XCTAssertEqual(StatKind.network.ringPartAgreement, .sum)
        XCTAssertEqual(StatKind.temps.ringPartAgreement, .hottest)
        XCTAssertNil(StatKind.memory.ringPartAgreement)
        for a in [RingPartAgreement.mean, .sum, .hottest, .bootContainer] { XCTAssertFalse(a.statement.isEmpty) }
    }

    // MARK: Frozen positions (AC-38, model level)

    func testAMissingPartKeepsItsIndexAndReportsUnavailable() throws {
        let list = RingPartBuilder.network(interfaces: [
            RingInterfaceInput(id: "en0", name: "Wi-Fi", downBytesPerSec: 1_000_000, upBytesPerSec: 1_000),
            RingInterfaceInput(id: "en5", name: "Ethernet", downBytesPerSec: 5_000, upBytesPerSec: 5_000),
            RingInterfaceInput(id: "en7", name: "iPhone USB", downBytesPerSec: 300, upBytesPerSec: 300)])
        // Second reading: the Ethernet interface dropped, an unknown one appeared.
        let later = list.updating(with: [
            RingPartReading(id: "en0", valueText: "fast", fraction: 0.9, secondFraction: 0.1, raw: 9, rawSecondary: 1),
            RingPartReading(id: "en7", valueText: "slow", fraction: 0.2, secondFraction: 0.2, raw: 2, rawSecondary: 2),
            RingPartReading(id: "en9", valueText: "new", fraction: 1, secondFraction: 1, raw: 1, rawSecondary: 1)])
        XCTAssertEqual(later.parts.count, 3)
        XCTAssertEqual(later.parts.map(\.id), ["en0", "en5", "en7"])
        XCTAssertEqual(later.parts.map(\.index), [0, 1, 2])
        let missing = later.parts[1]
        XCTAssertFalse(missing.isAvailable)
        XCTAssertNil(missing.fraction)
        XCTAssertNil(missing.raw)
        XCTAssertEqual(missing.name, "Ethernet")
        XCTAssertEqual(missing.group, list.parts[1].group)
        XCTAssertTrue(later.parts[0].isAvailable)
        XCTAssertEqual(later.parts[2].valueText, "slow")
        // The unavailable part is excluded from sums rather than counted as zero.
        XCTAssertEqual(try XCTUnwrap(later.aggregate()).primary, 11)
        XCTAssertEqual(later.parentAggregate, list.parentAggregate)
    }

    func testAPartReturningAfterAGapTakesItsOldPositionBack() {
        let list = RingPartBuilder.disk(volumes: [
            RingVolumeInput(id: "a", name: "A", usedBytes: 1, totalBytes: 10, isBoot: true),
            RingVolumeInput(id: "b", name: "B", usedBytes: 2, totalBytes: 10, isBoot: false)])
        let gone = list.updating(with: [RingPartReading(id: "a", valueText: "10%", fraction: 0.1, secondFraction: nil, raw: 0.1, rawSecondary: nil)])
        XCTAssertFalse(gone.parts[1].isAvailable)
        let back = gone.updating(with: [
            RingPartReading(id: "a", valueText: "10%", fraction: 0.1, secondFraction: nil, raw: 0.1, rawSecondary: nil),
            RingPartReading(id: "b", valueText: "30%", fraction: 0.3, secondFraction: nil, raw: 0.3, rawSecondary: nil)])
        XCTAssertTrue(back.parts[1].isAvailable)
        XCTAssertEqual(back.parts[1].index, 1)
    }

    // MARK: Fixture sets (AC-34, AC-35)

#if DEBUG
    private func assertAgree(_ set: RingPartFixtureSet, file: StaticString = #filePath, line: UInt = #line) throws {
        // Cores average to the CPU total.
        let coreMean = try XCTUnwrap(set.cpuParts.parentAggregate, file: file, line: line).primary
        XCTAssertEqual(coreMean, set.cpu.totalUsagePercent, accuracy: 1e-6, file: file, line: line)
        // Boot container equals the Disk reading.
        let boot = try XCTUnwrap(set.diskParts.parentAggregate, file: file, line: line).primary
        XCTAssertEqual(boot * 100, set.disk.usedPercent, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(RingGaugeMapper.disk(set.disk).totalFraction, boot, accuracy: 1e-9, file: file, line: line)
        // Interfaces sum to the Network reading.
        let net = try XCTUnwrap(set.networkParts.parentAggregate, file: file, line: line)
        XCTAssertEqual(net.primary, set.network.downBytesPerSec, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(net.secondary ?? -1, set.network.upBytesPerSec, accuracy: 1e-6, file: file, line: line)
        // The hottest segment equals the Temperature fill (when any valid sensor exists).
        let gauge = RingGaugeMapper.temperature(set.temperature)
        if let hottest = set.temperatureParts.parentAggregate?.primary {
            XCTAssertTrue(gauge.isAvailable, file: file, line: line)
            XCTAssertEqual(gauge.totalFraction, RingGaugeMapper.temperatureFraction(celsius: hottest),
                           accuracy: 1e-9, file: file, line: line)
        } else {
            XCTAssertFalse(gauge.isAvailable, file: file, line: line)
        }
        // CPU stack outer reach equals the CPU total.
        XCTAssertEqual(RingGaugeMapper.cpu(set.cpu).totalFraction * 100, set.cpu.totalUsagePercent,
                       accuracy: 1e-6, file: file, line: line)
        // Displayed aggregates agree unless the list collapsed.
        for list in [set.cpuParts, set.diskParts, set.networkParts, set.temperatureParts] where !list.isCollapsed {
            XCTAssertEqual(list.aggregate(), list.parentAggregate, file: file, line: line)
        }
    }

    func testTypicalFixtureAgreesWithItsParents() throws {
        let set = RingPartFixtures.make(.typical)
        XCTAssertEqual(set.cpuParts.parts.count, 10)
        XCTAssertEqual(set.cpuParts.groups.count, 2)
        XCTAssertEqual(set.diskParts.parts.count, 4)
        XCTAssertEqual(set.networkParts.parts.count, 3)
        XCTAssertEqual(set.temperatureParts.parts.count, 29)
        XCTAssertFalse(set.temperatureParts.isCollapsed)
        try assertAgree(set)
    }

    func testDenseFixtureAgreesAndExercisesTheCollapse() throws {
        let set = RingPartFixtures.make(.dense)
        XCTAssertEqual(set.cpuParts.sourceCount, 32)
        XCTAssertEqual(set.cpuParts.parts.count, 32)
        XCTAssertEqual(set.cpuParts.groups.count, 3)
        XCTAssertEqual(set.diskParts.parts.count, 4)
        XCTAssertEqual(set.networkParts.parts.count, 3)
        XCTAssertGreaterThan(set.temperatureParts.sourceCount, 32)
        XCTAssertTrue(set.temperatureParts.isCollapsed)
        XCTAssertLessThanOrEqual(set.temperatureParts.parts.count, 32)
        XCTAssertEqual(set.temperatureParts.parts.reduce(0) { $0 + $1.memberCount }, set.temperatureParts.sourceCount)
        try assertAgree(set)
    }

    func testMinimalFixtureHasNoSubRingForDiskNetworkAndTemperature() throws {
        let set = RingPartFixtures.make(.minimal)
        XCTAssertEqual(set.cpuParts.parts.count, 10)
        XCTAssertTrue(set.cpuParts.hasSubRing)
        XCTAssertFalse(set.diskParts.hasSubRing)
        XCTAssertFalse(set.networkParts.hasSubRing)
        XCTAssertFalse(set.temperatureParts.hasSubRing)
        XCTAssertEqual(set.temperatureParts.noSubRingReason, .fewerThanTwoParts(count: 0))
        XCTAssertTrue(set.temperatureParts.parts.isEmpty)
        try assertAgree(set)
    }

    func testFixturesAreDeterministic() {
        for name in RingPartFixtureName.allCases {
            XCTAssertEqual(RingPartFixtures.make(name).cpuParts, RingPartFixtures.make(name).cpuParts)
            XCTAssertEqual(RingPartFixtures.make(name).temperatureParts, RingPartFixtures.make(name).temperatureParts)
        }
    }
#endif
}

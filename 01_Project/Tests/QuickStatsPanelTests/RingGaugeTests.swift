import XCTest
import SwiftUI

final class RingGaugeTests: XCTestCase {

    private let accuracy = 1e-9

    // MARK: Rate scale

    func testRateScaleIsExactAtTheFixedPoints() {
        XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: 0), 0)
        XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: -5), 0)
        XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: .nan), 0)
        XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: 1), 0)
        XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: 999), 0)
        XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: 1_000), 0, accuracy: accuracy)
        XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: 1_000_000), 0.5, accuracy: accuracy)
        XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: 1_000_000_000), 1, accuracy: accuracy)
        XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: 5_000_000_000), 1)
        XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: 100_000), 2.0 / 6.0, accuracy: accuracy)
        XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: 10_000_000), 4.0 / 6.0, accuracy: accuracy)
    }

    func testRateScaleInverseRoundTrips() {
        for f in stride(from: 0.0, through: 1.0, by: 0.125) {
            XCTAssertEqual(RingRateScale.fraction(bytesPerSecond: RingRateScale.bytesPerSecond(forFraction: f)),
                           f, accuracy: 1e-9)
        }
    }

    // MARK: Stacks (AC-25)

    func testCPUStacksUserSystemNiceAndReachEqualsTotal() throws {
        let s = CPUSample(totalUsagePercent: 50, userPercent: 30, systemPercent: 15, idlePercent: 50)
        let g = RingGaugeMapper.cpu(s)
        XCTAssertTrue(g.isAvailable)
        XCTAssertEqual(g.components.map(\.component), [.user, .system, .nice])
        XCTAssertEqual(g.components.map(\.fraction), [0.30, 0.15, 0.05].map { $0 }, accuracy: accuracy)
        XCTAssertEqual(g.totalFraction, 0.5, accuracy: accuracy)
        XCTAssertEqual(g.cumulativeFractions.last ?? -1, 0.5, accuracy: accuracy)
    }

    func testCPUNiceClampsAtZeroWhenUserPlusSystemExceedsTotal() {
        let s = CPUSample(totalUsagePercent: 40, userPercent: 30, systemPercent: 15, idlePercent: 60)
        let g = RingGaugeMapper.cpu(s)
        XCTAssertEqual(g.components[2].fraction, 0)
    }

    func testCPUPeakIsCarried() {
        let s = CPUSample(totalUsagePercent: 10, userPercent: 6, systemPercent: 4, idlePercent: 90)
        XCTAssertEqual(RingGaugeMapper.cpu(s, peak: 0.7).peak, 0.7)
    }

    func testMemoryStacksAgainstInstalledMemory() {
        let gib: UInt64 = 1_073_741_824
        var s = MemorySample(usedBytes: 12 * gib, totalBytes: 16 * gib, pressurePercent: 75)
        s.appBytes = 6 * gib
        s.wiredBytes = 3 * gib
        s.compressedBytes = 1 * gib
        let g = RingGaugeMapper.memory(s)
        XCTAssertEqual(g.components.map(\.component), [.app, .wired, .compressed, .otherUsed])
        XCTAssertEqual(g.components.map(\.fraction), [6.0 / 16, 3.0 / 16, 1.0 / 16, 2.0 / 16], accuracy: accuracy)
        XCTAssertEqual(g.totalFraction, 0.75, accuracy: accuracy)
        XCTAssertNotNil(g.basisNote)
    }

    func testMemoryOtherUsedNeverGoesNegative() {
        let gib: UInt64 = 1_073_741_824
        var s = MemorySample(usedBytes: 4 * gib, totalBytes: 16 * gib, pressurePercent: 25)
        s.appBytes = 3 * gib
        s.wiredBytes = 2 * gib
        let g = RingGaugeMapper.memory(s)
        XCTAssertEqual(g.components[3].fraction, 0)
        XCTAssertLessThanOrEqual(g.totalFraction, 1 + accuracy)
    }

    func testPowerStacksFiveComponentsAgainstTheCeiling() {
        let s = PowerSample(isAvailable: true, cpuWatts: 6, gpuWatts: 3, aneWatts: 0, dramWatts: 1.5,
                            loadPercent: 0, systemWatts: 15, dcInWatts: nil)
        let g = RingGaugeMapper.power(s)
        XCTAssertEqual(g.components.map(\.component), [.cpu, .gpu, .neuralEngine, .dram, .restOfSystem])
        XCTAssertEqual(g.components.map(\.fraction), [0.2, 0.1, 0, 0.05, 0.15], accuracy: accuracy)
        XCTAssertEqual(g.totalFraction, 0.5, accuracy: accuracy)
    }

    func testPowerCeilingParameterAndFallback() {
        let s = PowerSample(isAvailable: true, cpuWatts: 10, gpuWatts: 0, aneWatts: 0, dramWatts: 0,
                            loadPercent: 0, systemWatts: nil, dcInWatts: nil)
        XCTAssertEqual(RingGaugeMapper.power(s, ceilingWatts: 20).totalFraction, 0.5, accuracy: accuracy)
        XCTAssertEqual(RingGaugeMapper.power(s).totalFraction, 10.0 / 30.0, accuracy: accuracy)
        XCTAssertEqual(RingGaugeMapper.power(s, ceilingWatts: 0).totalFraction, 10.0 / 30.0, accuracy: accuracy)
        // No system watts: the rest-of-system component is empty, not invented.
        XCTAssertEqual(RingGaugeMapper.power(s).components.last?.fraction, 0)
    }

    func testStackBeyondTheCeilingScalesDownToOne() {
        let s = PowerSample(isAvailable: true, cpuWatts: 40, gpuWatts: 20, aneWatts: 0, dramWatts: 0,
                            loadPercent: 0, systemWatts: nil, dcInWatts: nil)
        let g = RingGaugeMapper.power(s)
        XCTAssertEqual(g.totalFraction, 1, accuracy: accuracy)
        XCTAssertEqual(g.components[0].fraction, 2.0 / 3.0, accuracy: accuracy)
    }

    // MARK: Disk (AC-26)

    func testDiskFillFollowsUsedCapacityAndOnlyTheRimFollowsIO() {
        let quiet = DiskSample(usedBytes: 400, freeBytes: 600, totalBytes: 1000, readBytesPerSec: 0, writeBytesPerSec: 0)
        var busy = quiet
        busy.readBytesPerSec = 40_000_000
        busy.writeBytesPerSec = 10_000_000
        let a = RingGaugeMapper.disk(quiet), b = RingGaugeMapper.disk(busy)
        XCTAssertEqual(a.components, b.components)
        XCTAssertEqual(a.totalFraction, 0.4, accuracy: accuracy)
        XCTAssertEqual(a.rim, 0)
        XCTAssertEqual(b.rim ?? -1, RingRateScale.fraction(bytesPerSecond: 50_000_000), accuracy: accuracy)
        XCTAssertGreaterThan(b.rim ?? 0, a.rim ?? 0)

        var fuller = quiet
        fuller.usedBytes = 700
        fuller.freeBytes = 300
        let c = RingGaugeMapper.disk(fuller)
        XCTAssertEqual(c.totalFraction, 0.7, accuracy: accuracy)
        XCTAssertEqual(c.rim, a.rim)
    }

    func testDiskFillAgreesWithTheDiskReading() {
        let s = DiskSample(usedBytes: 250, freeBytes: 750, totalBytes: 1000, readBytesPerSec: 5, writeBytesPerSec: 5)
        XCTAssertEqual(RingGaugeMapper.disk(s).totalFraction * 100, s.usedPercent, accuracy: accuracy)
    }

    // MARK: Network (AC-27)

    func testNetworkSplitsDownloadLeftUploadRightOnTheLogScale() throws {
        let cases: [(down: Double, up: Double, left: Double, right: Double)] = [
            (0, 500, 0, 0),
            (999, 999, 0, 0),
            (1_000, 1_000, 0, 0),
            (1_000_000, 100_000, 0.5, 2.0 / 6.0),
            (10_000_000, 1_000, 4.0 / 6.0, 0),
            (1_000_000_000, 5_000_000_000, 1, 1)
        ]
        for c in cases {
            let sample = NetworkSample(downBytesPerSec: c.down, upBytesPerSec: c.up,
                                       interfaceName: "Wi-Fi (en0)", localIP: nil)
            let g = RingGaugeMapper.network(sample)
            let h = try XCTUnwrap(g.halves)
            XCTAssertEqual(h.left, c.left, accuracy: accuracy, "down \(c.down)")
            XCTAssertEqual(h.right, c.right, accuracy: accuracy, "up \(c.up)")
            XCTAssertTrue(g.components.isEmpty)
        }
    }

    func testNetworkMarksSitAt100KBAnd10MBAndNeverMove() throws {
        let slow = RingGaugeMapper.network(NetworkSample(downBytesPerSec: 10, upBytesPerSec: 10, interfaceName: "en0", localIP: nil))
        let fast = RingGaugeMapper.network(NetworkSample(downBytesPerSec: 9e8, upBytesPerSec: 9e8, interfaceName: "en0", localIP: nil))
        XCTAssertEqual(slow.marks, fast.marks)
        XCTAssertEqual(slow.marks, [.rate(fraction: 2.0 / 6.0, bytesPerSecond: 100_000),
                                    .rate(fraction: 4.0 / 6.0, bytesPerSecond: 10_000_000)])
    }

    func testNetworkPeaksPerHalf() throws {
        let g = RingGaugeMapper.network(NetworkSample(downBytesPerSec: 1, upBytesPerSec: 1, interfaceName: "en0", localIP: nil),
                                        downPeak: 0.6, upPeak: 0.3)
        let h = try XCTUnwrap(g.halves)
        XCTAssertEqual(h.leftPeak, 0.6)
        XCTAssertEqual(h.rightPeak, 0.3)
    }

    // MARK: Battery, GPU, Temperature, Fans, Load, Uptime

    func testBatteryChargeAndPowerMarks() {
        func gauge(percent: Double, charging: Bool, ac: Bool) -> RingGauge {
            RingGaugeMapper.battery(BatterySample(isPresent: true, percent: percent, isCharging: charging,
                                                  isOnAC: ac, minutesRemaining: nil))
        }
        XCTAssertEqual(gauge(percent: 80, charging: false, ac: false).marks, [])
        XCTAssertEqual(gauge(percent: 80, charging: true, ac: true).marks, [.chargingBolt])
        XCTAssertEqual(gauge(percent: 80, charging: false, ac: true).marks, [.pluggedNotCharging])
        XCTAssertEqual(gauge(percent: 100, charging: false, ac: true).marks, [.pluggedFull])
        XCTAssertEqual(gauge(percent: 80, charging: false, ac: false).totalFraction, 0.8, accuracy: accuracy)
    }

    func testGPUUtilisation() {
        let g = RingGaugeMapper.gpu(GPUSample(isAvailable: true, utilizationPercent: 35, deviceName: nil), peak: 0.5)
        XCTAssertEqual(g.totalFraction, 0.35, accuracy: accuracy)
        XCTAssertEqual(g.peak, 0.5)
    }

    func testTemperatureUsesHottestValidSensorOn30To100() throws {
        let sample = TemperatureSample(thermalState: .fair, sensors: [
            TempReading(label: "CPU", celsius: 65),
            TempReading(label: "GPU", celsius: 72.5),
            TempReading(label: "Bad high", celsius: 140),
            TempReading(label: "Bad low", celsius: -3)])
        let g = RingGaugeMapper.temperature(sample)
        XCTAssertTrue(g.isAvailable)
        XCTAssertTrue(g.usesHeatRamp)
        XCTAssertEqual(g.totalFraction, (72.5 - 30) / 70, accuracy: accuracy)
        XCTAssertEqual(g.badge, .thermalState(.fair))
        XCTAssertTrue(try XCTUnwrap({ () -> RingThermalState? in
            if case .thermalState(let s)? = g.badge { return s } else { return nil }
        }()).tintsWedge)
        XCTAssertEqual(RingGaugeMapper.temperatureFraction(celsius: 20), 0)
        XCTAssertEqual(RingGaugeMapper.temperatureFraction(celsius: 105), 1)
    }

    func testThermalTintStartsAtFair() {
        XCTAssertFalse(RingThermalState.nominal.tintsWedge)
        XCTAssertTrue(RingThermalState.fair.tintsWedge)
        XCTAssertTrue(RingThermalState.serious.tintsWedge)
        XCTAssertTrue(RingThermalState.critical.tintsWedge)
    }

    func testFansUseTheFastestFanWithinItsOwnRange() {
        let sample = FanSample(hasFans: true, fans: [
            FanSample.Fan(current: 1500, min: 1200, max: 5000),
            FanSample.Fan(current: 3100, min: 1000, max: 6000)])
        XCTAssertEqual(RingGaugeMapper.fans(sample).totalFraction, (3100.0 - 1000) / 5000, accuracy: accuracy)
        let below = FanSample(hasFans: true, fans: [FanSample.Fan(current: 800, min: 1000, max: 6000)])
        XCTAssertEqual(RingGaugeMapper.fans(below).totalFraction, 0)
        let zeroRange = FanSample(hasFans: true, fans: [FanSample.Fan(current: 800, min: 0, max: 0)])
        XCTAssertFalse(RingGaugeMapper.fans(zeroRange).isAvailable)
    }

    func testLoadIsSelectedAverageOverActiveCoresClamped() {
        let sample = LoadSample(one: 2, five: 5, fifteen: 40)
        XCTAssertEqual(RingGaugeMapper.load(sample, window: .one, activeCores: 10).totalFraction, 0.2, accuracy: accuracy)
        XCTAssertEqual(RingGaugeMapper.load(sample, window: .five, activeCores: 10).totalFraction, 0.5, accuracy: accuracy)
        XCTAssertEqual(RingGaugeMapper.load(sample, window: .fifteen, activeCores: 10).totalFraction, 1, accuracy: accuracy)
        XCTAssertFalse(RingGaugeMapper.load(sample, activeCores: 0).isAvailable)
    }

    func testUptimeHasNoFill() {
        let g = RingGaugeMapper.uptime(UptimeSample(seconds: 90_000))
        XCTAssertTrue(g.isAvailable)
        XCTAssertFalse(g.hasFill)
        XCTAssertTrue(g.components.isEmpty)
        XCTAssertNil(g.halves)
    }

    // MARK: Unavailable (AC-28)

    func testAbsentHardwareAndEmptySamplesAreUnavailableNeverZeroFill() {
        let gauges: [RingGauge] = [
            RingGaugeMapper.cpu(nil), RingGaugeMapper.cpu(.empty),
            RingGaugeMapper.memory(nil), RingGaugeMapper.memory(.empty),
            RingGaugeMapper.disk(nil), RingGaugeMapper.disk(.empty),
            RingGaugeMapper.network(nil), RingGaugeMapper.network(.empty),
            RingGaugeMapper.battery(nil), RingGaugeMapper.battery(.empty),
            RingGaugeMapper.gpu(nil), RingGaugeMapper.gpu(.empty),
            RingGaugeMapper.power(nil), RingGaugeMapper.power(.empty),
            RingGaugeMapper.temperature(nil), RingGaugeMapper.temperature(.empty),
            RingGaugeMapper.fans(nil), RingGaugeMapper.fans(.empty),
            RingGaugeMapper.load(nil, activeCores: 8), RingGaugeMapper.load(.empty, activeCores: 8),
            RingGaugeMapper.uptime(nil), RingGaugeMapper.uptime(.empty)
        ]
        for g in gauges {
            XCTAssertFalse(g.isAvailable, "\(g.stat)")
            XCTAssertTrue(g.components.isEmpty, "\(g.stat)")
            XCTAssertNil(g.halves, "\(g.stat)")
            XCTAssertNil(g.rim, "\(g.stat)")
            XCTAssertNil(g.peak, "\(g.stat)")
            XCTAssertTrue(g.marks.isEmpty, "\(g.stat)")
            XCTAssertFalse(g.usesHeatRamp, "\(g.stat)")
            XCTAssertFalse(g.hasFill, "\(g.stat)")
        }
    }

    func testAMeasuredZeroIsAvailableAndDistinctFromUnavailable() {
        let idle = CPUSample(totalUsagePercent: 0, userPercent: 0, systemPercent: 0, idlePercent: 99.9)
        let g = RingGaugeMapper.cpu(idle)
        XCTAssertTrue(g.isAvailable)
        XCTAssertFalse(g.hasFill)
        XCTAssertNotEqual(g, RingGaugeMapper.cpu(nil))
    }

    func testTemperatureWithNoValidSensorIsUnavailableButKeepsThermalState() {
        let sample = TemperatureSample(thermalState: .serious, sensors: [TempReading(label: "x", celsius: 200)])
        let g = RingGaugeMapper.temperature(sample)
        XCTAssertFalse(g.isAvailable)
        XCTAssertEqual(g.badge, .thermalState(.serious))
        XCTAssertTrue(g.components.isEmpty)
    }

    // MARK: Peak window

    func testPeakWindowKeepsSixtySecondsWithInjectedTimestamps() {
        var w = RingPeakWindow()
        XCTAssertNil(w.peak(at: 0))
        XCTAssertEqual(w.record(0.4, at: 0), 0.4)
        XCTAssertEqual(w.record(0.9, at: 10), 0.9)
        XCTAssertEqual(w.record(0.2, at: 20), 0.9)
        XCTAssertEqual(w.peak(at: 69.9), 0.9)
        // The 0.9 sample is 60 s old at t = 70: it leaves the window.
        XCTAssertEqual(w.peak(at: 70), 0.2)
        XCTAssertNil(w.peak(at: 80))
    }

    func testPeakWindowIgnoresNonFiniteAndResets() {
        var w = RingPeakWindow()
        w.record(.nan, at: 1)
        XCTAssertNil(w.peak(at: 1))
        w.record(0.5, at: 1)
        w.reset()
        XCTAssertNil(w.peak(at: 2))
    }

    // MARK: Palette

    func testContrastRatioKnownValues() {
        let black = RingRGB(hex: 0x000000), white = RingRGB(hex: 0xFFFFFF)
        XCTAssertEqual(RingPalette.contrastRatio(black, white), 21, accuracy: 1e-6)
        XCTAssertEqual(RingPalette.contrastRatio(white, black), 21, accuracy: 1e-6)
        XCTAssertEqual(RingPalette.contrastRatio(white, white), 1, accuracy: 1e-9)
        // #767676 on white is the 4.54:1 reference pair.
        XCTAssertEqual(RingPalette.contrastRatio(RingRGB(hex: 0x767676), white), 4.54, accuracy: 0.01)
    }

    func testEachStatHasItsOwnHueAndStackedStepsAreLighterOrDistinct() {
        let stats = StatKind.allCases.filter { $0 != .uptime }
        let hues = stats.map { RingPalette.hue(for: $0) }
        XCTAssertEqual(Set(hues.map { "\($0.red),\($0.green),\($0.blue)" }).count, hues.count)

        XCTAssertGreaterThan(RingPalette.color(for: .system, stat: .cpu).relativeLuminance,
                             RingPalette.color(for: .user, stat: .cpu).relativeLuminance)
        XCTAssertGreaterThan(RingPalette.color(for: .nice, stat: .cpu).relativeLuminance,
                             RingPalette.color(for: .system, stat: .cpu).relativeLuminance)
        for (stat, comps): (StatKind, [RingComponent]) in [(.cpu, [.user, .system, .nice]),
                                                          (.memory, [.app, .wired, .compressed, .otherUsed]),
                                                          (.power, [.cpu, .gpu, .neuralEngine, .dram, .restOfSystem])] {
            let colors = comps.map { RingPalette.color(for: $0, stat: stat) }
            XCTAssertEqual(Set(colors.map { "\($0.red),\($0.green),\($0.blue)" }).count, colors.count, "\(stat)")
        }
    }

    func testHeatRampLightnessRisesWithHeat() {
        var last = -1.0
        for i in 0...20 {
            let l = RingPalette.heat(fraction: Double(i) / 20).relativeLuminance
            XCTAssertGreaterThan(l, last, "step \(i)")
            last = l
        }
        XCTAssertEqual(RingPalette.heat(fraction: -1), RingPalette.heat(fraction: 0))
        XCTAssertEqual(RingPalette.heat(fraction: 9), RingPalette.heat(fraction: 1))
    }

    /// Fill edge against track must reach 3:1 for every shipped preset. The panel is drawn dark,
    /// so the dark-scheme resolution of each preset's colours is used, with the translucent
    /// panel background composited over black. Any failure is reported by preset and colour.
    func testFillEdgeAgainstTrackIsThreeToOneForEveryShippedPreset() {
        let report = presetContrastReport()
        for line in report.lines { print("PRESET-CONTRAST \(line)") }
        XCTAssertEqual(report.failing, [], "Presets under 3:1: \(report.failing)\n\(report.lines.joined(separator: "\n"))")
    }

    private struct PresetReport { var lines: [String] = []; var failing: [String] = [] }

    private func presetContrastReport() -> PresetReport {
        var report = PresetReport()
        for preset in ThemePreset.allCases {
            let theme = Theme.make(preset, custom: nil, reduceTransparency: false)
            let fg = resolved(theme.colors.primaryText, over: nil)
            let bg = resolved(theme.colors.background, over: RingRGB(hex: 0x000000))
            let fills: [(name: String, color: RingRGB)] = preset == .mono
                ? [("mono", RingPalette.mono)] : RingPalette.allFillColors
            var worstName = "", worst = Double.infinity
            for f in fills {
                let r = RingPalette.edgeContrast(fill: f.color, foreground: fg, background: bg)
                if r < worst { worst = r; worstName = f.name }
            }
            report.lines.append("\(preset.rawValue): worst \(String(format: "%.2f", worst)) at \(worstName)")
            if worst < RingPalette.edgeContrastMinimum { report.failing.append(preset.rawValue) }
        }
        return report
    }

    private func resolved(_ color: Color, over backdrop: RingRGB?) -> RingRGB {
        var env = EnvironmentValues()
        env.colorScheme = .dark
        let r = color.resolve(in: env)
        let base = RingRGB(red: Double(r.red), green: Double(r.green), blue: Double(r.blue))
        guard let backdrop else { return base }
        return base.over(backdrop, alpha: Double(r.opacity))
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}

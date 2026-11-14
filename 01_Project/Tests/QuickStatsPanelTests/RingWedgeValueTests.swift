import XCTest

/// Every value a wedge can draw for a stat must fit inside the worst case the summon measured
/// (D-008): the rung is frozen from `widestValue`/`widestSecondary`, and the wedge never shrinks,
/// truncates or rotates, so a later tick that needs more room would overflow its wedge.
final class RingWedgeValueTests: XCTestCase {
    private func textWidth(_ text: String, secondary: Bool = false) -> CGFloat {
        let reading = secondary
            ? RingReading(value: "", secondary: text, widestValue: "", widestSecondary: text)
            : RingReading(value: text, widestValue: text)
        return RingTypography.blockSize(name: "", reading: reading).width
    }

    @MainActor
    private func withSettings(_ body: (AppSettings) throws -> Void) throws {
        let suite = "com.sim.QuickStatsPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppSettings(defaults: defaults))
    }

    /// Samples spanning charging, on-battery, on-AC, no-sensor, no-SMC-keys and large values.
    @MainActor
    private func fixtures() -> [(String, StatsStore)] {
        func make(_ configure: (StatsStore) -> Void) -> StatsStore {
            let store = StatsStore()
            configure(store)
            return store
        }
        let hot = make { s in
            s.cpu = CPUSample(totalUsagePercent: 100, userPercent: 80, systemPercent: 20, idlePercent: 0)
            s.memory = MemorySample(usedBytes: 120 << 30, totalBytes: 128 << 30, pressurePercent: 95)
            s.disk = DiskSample(usedBytes: 900 << 30, freeBytes: 99 << 30, totalBytes: 999 << 30,
                                readBytesPerSec: 888e6, writeBytesPerSec: 777e6)
            s.network = NetworkSample(downBytesPerSec: 888e6, upBytesPerSec: 123e6)
            s.battery = BatterySample(isPresent: true, percent: 100, isCharging: true, isOnAC: true,
                                      minutesRemaining: 599)
            s.gpu = GPUSample(isAvailable: true, utilizationPercent: 100, deviceName: "GPU")
            s.fan = FanSample(hasFans: true, fans: [.init(current: 8888, min: 1200, max: 8888)])
            s.power = PowerSample(isAvailable: true, cpuWatts: 120.4, gpuWatts: 88.8, aneWatts: 9.9,
                                  dramWatts: 20.2, loadPercent: 100, systemWatts: 888.8, dcInWatts: 140.0)
            s.temps = TemperatureSample(thermalState: .critical, sensors: [
                TempReading(label: "CPU", celsius: 105), TempReading(label: "GPU", celsius: 99)])
            s.loadAverage = LoadSample(one: 88.88, five: 77.77, fifteen: 66.66)
            s.uptime = UptimeSample(seconds: 88 * 86_400 + 8 * 3_600)
        }
        let onBattery = make { s in
            s.cpu = CPUSample(totalUsagePercent: 7, userPercent: 4, systemPercent: 3, idlePercent: 93)
            s.battery = BatterySample(isPresent: true, percent: 36, isCharging: false, isOnAC: false,
                                      minutesRemaining: 4 * 60 + 5)
            s.power = PowerSample(isAvailable: true, cpuWatts: 0.3, gpuWatts: 0.1, aneWatts: 0, dramWatts: 0.2,
                                  loadPercent: 5, systemWatts: 35.1, dcInWatts: 0.0)
            s.temps = TemperatureSample(thermalState: .nominal, sensors: [TempReading(label: "CPU", celsius: 38)])
            s.gpu = GPUSample(isAvailable: true, utilizationPercent: 4, deviceName: nil)
        }
        let noSensors = make { s in
            s.battery = BatterySample(isPresent: true, percent: 50, isCharging: false, isOnAC: true,
                                      minutesRemaining: nil)
            s.power = PowerSample(isAvailable: true, cpuWatts: 1, gpuWatts: 1, aneWatts: 0, dramWatts: 0,
                                  loadPercent: 1, systemWatts: nil, dcInWatts: nil)
            s.temps = TemperatureSample(thermalState: .serious, sensors: [])
        }
        return [("hot", hot), ("onBattery", onBattery), ("noSensors", noSensors), ("empty", StatsStore())]
    }

    /// Calls `body` once per settings combination that changes what a stat emits.
    @MainActor
    private func forEachVariant(_ settings: AppSettings, _ body: () -> Void) {
        func apply(_ mutate: (AppSettings) -> Void) { mutate(settings); body() }
        for power in PowerDisplayMode.allCases { apply { $0.powerDisplayMode = power } }
        for temp in TemperatureDisplayMode.allCases {
            for unit in TemperatureUnit.allCases {
                apply { $0.temperatureDisplayMode = temp; $0.temperatureUnit = unit }
            }
        }
        for load in LoadDisplayMode.allCases { apply { $0.loadDisplayMode = load } }
        for cpu in CPUDisplayMode.allCases { apply { $0.cpuDisplayMode = cpu } }
        for battery in BatteryDisplayMode.allCases { apply { $0.batteryDisplayMode = battery } }
        for disk in DiskDisplayMode.allCases { apply { $0.diskDisplayMode = disk } }
        for mode in TileValueMode.allCases {
            apply { s in StatKind.allCases.forEach { s.setValueMode($0, mode) } }
        }
    }

    @MainActor
    func testEveryEmittedFormFitsItsWidestValue() throws {
        try withSettings { settings in
            var checked = 0
            for (name, store) in fixtures() {
                forEachVariant(settings) {
                    for kind in StatKind.allCases {
                        let reading = store.ringReading(for: kind, settings: settings)
                        guard reading.isAvailable else { continue }
                        let context = "\(name) \(kind) '\(reading.value)' widest '\(reading.widestValue)'"
                        XCTAssertLessThanOrEqual(textWidth(reading.value), textWidth(reading.widestValue), context)
                        if let secondary = reading.secondary {
                            let widest = reading.widestSecondary ?? ""
                            XCTAssertLessThanOrEqual(textWidth(secondary, secondary: true),
                                                     textWidth(widest, secondary: true),
                                                     "\(context) secondary '\(secondary)' widest '\(widest)'")
                        }
                        checked += 1
                    }
                }
            }
            XCTAssertGreaterThan(checked, 100)
        }
    }

    /// A stat with no reading at summon is measured from `ringFallbackWidest`; the value it
    /// draws once a reading arrives must still fit that block.
    @MainActor
    func testReadingThatAppearsAfterSummonFitsTheUnavailableMeasurement() throws {
        try withSettings { settings in
            for (name, store) in fixtures() {
                forEachVariant(settings) {
                    for kind in [StatKind.battery, .gpu, .fan, .power] {
                        let reading = store.ringReading(for: kind, settings: settings)
                        guard reading.isAvailable else { continue }
                        let fallback = RingReading.unavailable(kind)
                        XCTAssertLessThanOrEqual(textWidth(reading.value), textWidth(fallback.widestValue),
                                                 "\(name) \(kind) '\(reading.value)'")
                    }
                }
            }
        }
    }

    /// The paired Power reading from the owner's screenshot no longer reaches the wedge.
    @MainActor
    func testPairedPowerModeShowsOneFigureInTheWedge() throws {
        try withSettings { settings in
            let store = StatsStore()
            store.power = PowerSample(isAvailable: true, cpuWatts: 0.3, gpuWatts: 0.1, aneWatts: 0, dramWatts: 0.2,
                                      loadPercent: 5, systemWatts: 35.1, dcInWatts: 0.0)
            settings.powerDisplayMode = .dcInAndSystem
            XCTAssertEqual(store.ringReading(for: .power, settings: settings).value, "35.1 W")
            XCTAssertEqual(store.resolvedDescriptor(for: .power, settings: settings)?.value,
                           "In 0.0 W \u{00B7} System 35.1 W", "the card keeps the full pair")
            settings.powerDisplayMode = .cpuAndGPU
            XCTAssertEqual(store.ringReading(for: .power, settings: settings).value, "0.4 W")
        }
    }

    /// The wedge draws one compact figure, but accessibility always speaks the configured
    /// reading in full: Power, Temperature and Load pairs are read as the card shows them.
    @MainActor
    func testAccessibilitySpeaksTheFullReadingWhateverTheWedgeDraws() throws {
        try withSettings { settings in
            var compacted = 0
            for (name, store) in fixtures() {
                forEachVariant(settings) {
                    for kind in StatKind.allCases {
                        let reading = store.ringReading(for: kind, settings: settings)
                        guard reading.isAvailable,
                              let descriptor = store.resolvedDescriptor(for: kind, settings: settings) else {
                            XCTAssertEqual(reading.accessibilityText, "Unavailable", "\(name) \(kind)")
                            continue
                        }
                        let full = [descriptor.value, descriptor.secondaryValue].compactMap { $0 }.joined(separator: ", ")
                        XCTAssertEqual(reading.accessibilityText, full, "\(name) \(kind)")
                        if reading.value != descriptor.value { compacted += 1 }
                    }
                }
            }
            XCTAssertGreaterThan(compacted, 0, "some wedge forms are compact, so the field matters")
        }
    }

    @MainActor
    func testPairedPowerIsSpokenAsThePair() throws {
        try withSettings { settings in
            let store = StatsStore()
            store.power = PowerSample(isAvailable: true, cpuWatts: 0.3, gpuWatts: 0.1, aneWatts: 0, dramWatts: 0.2,
                                      loadPercent: 5, systemWatts: 35.1, dcInWatts: 0.0)
            settings.powerDisplayMode = .dcInAndSystem
            let reading = store.ringReading(for: .power, settings: settings)
            XCTAssertEqual(reading.value, "35.1 W")
            XCTAssertEqual(reading.accessibilityText, "In 0.0 W \u{00B7} System 35.1 W")
        }
    }
}

import XCTest

final class CPUBatteryPairTests: XCTestCase {
    // Exercise the panel's settings-to-descriptor path with fixture samples.
    // No AppSettings.shared, app startup, sampler I/O, or hotkey registration.
    @MainActor
    private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
        let suite = "com.sim.QuickStatsPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppSettings(defaults: defaults), defaults)
    }

    @MainActor
    func testPairSettingsPreserveDefaultsPersistAndNotifyPanel() throws {
        try withSettings { settings, defaults in
            XCTAssertEqual(settings.cpuDisplayMode, .usage)
            XCTAssertEqual(settings.batteryDisplayMode, .charge)
            var changes = 0
            settings.onStatsChanged = { changes += 1 }
            settings.cpuDisplayMode = .usageAndTemperature
            XCTAssertEqual(changes, 1)
            settings.batteryDisplayMode = .chargeAndTime
            XCTAssertEqual(changes, 2)
            let restored = AppSettings(defaults: defaults)
            XCTAssertEqual(restored.cpuDisplayMode, .usageAndTemperature)
            XCTAssertEqual(restored.batteryDisplayMode, .chargeAndTime)

            defaults.set("future-mode", forKey: "cpuDisplayMode")
            defaults.set("future-mode", forKey: "batteryDisplayMode")
            let fallback = AppSettings(defaults: defaults)
            XCTAssertEqual(fallback.cpuDisplayMode, .usage)
            XCTAssertEqual(fallback.batteryDisplayMode, .charge)
        }
    }

    @MainActor
    func testCPUSelectionAddsTemperatureInSelectedUnitWithoutChangingUsage() throws {
        try withSettings { settings, _ in
            let store = StatsStore()
            store.cpu = CPUSample(totalUsagePercent: 35, userPercent: 25, systemPercent: 10, idlePercent: 65)
            store.temps = TemperatureSample(thermalState: .fair,
                                           sensors: [TempReading(label: "CPU", celsius: 60)])
            let original = try XCTUnwrap(store.descriptor(for: .cpu, settings: settings))
            XCTAssertEqual(original.value, "35%")
            XCTAssertNil(original.secondaryValue)
            XCTAssertNil(original.widestSecondaryValue)
            settings.cpuDisplayMode = .usageAndTemperature
            for (unit, reading, template) in [(TemperatureUnit.celsius, "60°C", "888°C"),
                                               (.fahrenheit, "140°F", "888°F")] {
                settings.temperatureUnit = unit
                let paired = try XCTUnwrap(store.descriptor(for: .cpu, settings: settings))
                XCTAssertEqual(paired.value, original.value)
                XCTAssertEqual(paired.loadPercent, original.loadPercent)
                XCTAssertEqual(paired.secondaryValue, reading)
                XCTAssertEqual(paired.widestSecondaryValue, template)
            }
            settings.cpuDisplayMode = .usage
            XCTAssertNil(store.descriptor(for: .cpu, settings: settings)?.secondaryValue)
        }
    }

    @MainActor
    func testCPUPairDoesNotSubstituteAnotherTemperatureSensor() throws {
        try withSettings { settings, _ in
            let store = StatsStore()
            store.temps = TemperatureSample(thermalState: .nominal,
                                           sensors: [TempReading(label: "GPU", celsius: 50)])
            settings.cpuDisplayMode = .usageAndTemperature
            for (unit, expected) in [(TemperatureUnit.celsius, "—°C"), (.fahrenheit, "—°F")] {
                settings.temperatureUnit = unit
                XCTAssertEqual(store.descriptor(for: .cpu, settings: settings)?.secondaryValue, expected)
            }
        }
    }

    @MainActor
    func testBatteryPairLabelsChargingAndDischargingEstimatesAndUnknownValues() throws {
        try withSettings { settings, _ in
            let store = StatsStore()
            store.battery = BatterySample(isPresent: true, percent: 72, isCharging: false,
                                          isOnAC: false, minutesRemaining: 120)
            let original = try XCTUnwrap(store.descriptor(for: .battery, settings: settings))
            XCTAssertEqual(original.value, "72%")
            XCTAssertNil(original.secondaryValue)
            XCTAssertNil(original.widestSecondaryValue)
            settings.batteryDisplayMode = .chargeAndTime
            let cases: [(Bool, Int?, String)] = [
                (false, 120, "2:00 left"), (true, 90, "1:30 to full"),
                (false, nil, "— left"), (true, nil, "— to full"),
                (false, 0, "— left"), (true, 0, "— to full"),
                (false, -1, "— left"), (true, -1, "— to full")
            ]
            for (charging, minutes, expected) in cases {
                store.battery.isCharging = charging
                store.battery.isOnAC = charging
                store.battery.minutesRemaining = minutes
                let paired = try XCTUnwrap(store.descriptor(for: .battery, settings: settings))
                XCTAssertEqual(paired.value, original.value)
                XCTAssertEqual(paired.loadPercent, original.loadPercent)
                XCTAssertEqual(paired.secondaryValue, expected)
                XCTAssertEqual(paired.widestSecondaryValue, "888:88 to full")
            }
            settings.batteryDisplayMode = .charge
            XCTAssertNil(store.descriptor(for: .battery, settings: settings)?.secondaryValue)
        }
    }

    @MainActor
    func testBatteryOnACDoesNotPresentStaleTimeOrClaimFullyCharged() throws {
        try withSettings { settings, _ in
            let store = StatsStore()
            settings.batteryDisplayMode = .chargeAndTime
            for percent in [72.0, 100.0] {
                for minutes in [nil, 0, 90] as [Int?] {
                    store.battery = BatterySample(isPresent: true, percent: percent,
                                                  isCharging: false, isOnAC: true,
                                                  minutesRemaining: minutes)
                    let descriptor = try XCTUnwrap(store.descriptor(for: .battery, settings: settings))
                    XCTAssertEqual(descriptor.secondaryValue, "On AC")
                    XCTAssertEqual(descriptor.widestSecondaryValue, "888:88 to full")
                }
            }
        }
    }

    @MainActor
    func testBatteryPairRemainsAbsentWhenThereIsNoBattery() throws {
        try withSettings { settings, _ in
            let store = StatsStore()
            store.battery = .empty
            settings.batteryDisplayMode = .chargeAndTime
            XCTAssertNil(store.descriptor(for: .battery, settings: settings))
        }
    }
}

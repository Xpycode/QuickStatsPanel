import XCTest

final class ExtendedMetricOptionsTests: XCTestCase {
    // All paths use injected preferences and fixture samples: no app startup,
    // standard defaults, live samplers, or hotkey registration.
    @MainActor
    private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
        let suite = "com.sim.QuickStatsPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppSettings(defaults: defaults), defaults)
    }

    @MainActor
    func testExtendedPreferencesPreserveDefaultsAndRoundTrip() throws {
        try withSettings { settings, defaults in
            XCTAssertEqual(settings.temperatureDisplayMode, .status)
            XCTAssertEqual(settings.temperatureUnit, .celsius)
            XCTAssertEqual(settings.diskDisplayMode, .capacity)
            settings.temperatureDisplayMode = .statusAndGPU
            settings.temperatureUnit = .fahrenheit
            settings.diskDisplayMode = .activity
            settings.setValueMode(.disk, .bothReversed)
            let restored = AppSettings(defaults: defaults)
            XCTAssertEqual(restored.temperatureDisplayMode, .statusAndGPU)
            XCTAssertEqual(restored.temperatureUnit, .fahrenheit)
            XCTAssertEqual(restored.diskDisplayMode, .activity)
            XCTAssertEqual(restored.valueMode(.disk), .bothReversed)
            defaults.set("future-mode", forKey: "temperatureDisplayMode")
            defaults.set("future-unit", forKey: "temperatureUnit")
            defaults.set("future-mode", forKey: "diskDisplayMode")
            let fallback = AppSettings(defaults: defaults)
            XCTAssertEqual(fallback.temperatureDisplayMode, .status)
            XCTAssertEqual(fallback.temperatureUnit, .celsius)
            XCTAssertEqual(fallback.diskDisplayMode, .capacity)
        }
    }

    @MainActor
    func testTemperatureChoicesConvertKnownReadingsAndIdentifyCombinedRoles() throws {
        try withSettings { settings, _ in
            let store = populatedStore()
            let expected: [(TemperatureDisplayMode, String, String)] = [
                (.status, "Fair", "Fair"), (.cpu, "60°C", "140°F"),
                (.gpu, "50°C", "122°F"),
                (.statusAndCPU, "Fair · CPU 60°C", "Fair · CPU 140°F"),
                (.statusAndGPU, "Fair · GPU 50°C", "Fair · GPU 122°F")
            ]
            for (mode, celsius, fahrenheit) in expected {
                settings.temperatureDisplayMode = mode
                for (unit, expectedValue) in [(TemperatureUnit.celsius, celsius), (.fahrenheit, fahrenheit)] {
                    settings.temperatureUnit = unit
                    let descriptor = try XCTUnwrap(store.descriptor(for: .temps, settings: settings))
                    XCTAssertEqual(descriptor.value, expectedValue)
                    XCTAssertEqual(descriptor.loadPercent, 40, "Thermal severity must not change with units")
                    XCTAssertEqual(descriptor.detail.first { $0.0 == "CPU" }?.1,
                                   unit == .celsius ? "60°C" : "140°F")
                }
            }
            settings.temperatureUnit = .fahrenheit
            for kind in [StatKind.cpu, .gpu, .battery] {
                let descriptor = try XCTUnwrap(store.descriptor(for: kind, settings: settings))
                let expectedTemp = kind == .cpu ? "140°F" : kind == .gpu ? "122°F" : "86°F"
                XCTAssertEqual(descriptor.detail.first { $0.0 == "Temp" }?.1, expectedTemp)
            }
        }
    }

    @MainActor
    func testMissingTemperatureRoleDoesNotBorrowAnotherSensor() throws {
        try withSettings { settings, _ in
            let store = StatsStore()
            store.temps = TemperatureSample(thermalState: .serious,
                                           sensors: [TempReading(label: "SSD", celsius: 42)])
            for (mode, expectedValue) in [(TemperatureDisplayMode.cpu, "—°C"),
                                          (.gpu, "—°C"),
                                          (.statusAndCPU, "Serious · CPU —°C"),
                                          (.statusAndGPU, "Serious · GPU —°C")] {
                settings.temperatureDisplayMode = mode
                XCTAssertEqual(store.descriptor(for: .temps, settings: settings)?.value, expectedValue)
            }
            store.temps.sensors = []
            settings.temperatureDisplayMode = .status
            let descriptor = try XCTUnwrap(store.descriptor(for: .temps, settings: settings))
            XCTAssertEqual(descriptor.value, "Serious")
            XCTAssertEqual(descriptor.detail.map { $0.0 }, ["Pressure"])
        }
    }

    @MainActor
    func testDiskHeadlineSelectsCapacityOrActivityAndRespectsEveryValueMode() throws {
        try withSettings { settings, _ in
            let store = populatedStore()
            for metric in DiskDisplayMode.allCases {
                settings.diskDisplayMode = metric
                let first = metric == .capacity ? store.disk.freeFormatted : store.disk.readFormatted
                let second = metric == .capacity ? store.disk.usedFormatted : store.disk.writeFormatted
                let firstMarker = metric == .capacity ? "F" : "R"
                let secondMarker = metric == .capacity ? "U" : "W"
                let cases: [(TileValueMode, String, String?)] = [
                    (.first, first, nil), (.second, second, nil),
                    (.both, "\(firstMarker) \(first)", "\(secondMarker) \(second)"),
                    (.bothReversed, "\(secondMarker) \(second)", "\(firstMarker) \(first)")
                ]
                for (mode, primary, secondary) in cases {
                    settings.setValueMode(.disk, mode)
                    let descriptor = try XCTUnwrap(store.descriptor(for: .disk, settings: settings))
                    XCTAssertEqual(descriptor.value, primary, "\(metric.rawValue), \(mode.rawValue)")
                    XCTAssertEqual(descriptor.secondaryValue, secondary)
                    XCTAssertEqual(descriptor.detail.map { $0.0 }, ["Used", "Free", "Total", "Read", "Write"])
                }
            }
        }
    }

    @MainActor
    func testEveryExtendedDetailCardCanHideAllRowsAndRestoreOneWithoutChangingHeadline() throws {
        try withSettings { settings, defaults in
            let store = populatedStore()
            let kinds: [StatKind] = [.cpu, .memory, .disk, .network, .battery, .gpu, .fan, .temps, .uptime]
            for kind in kinds {
                let original = try XCTUnwrap(store.descriptor(for: kind, settings: settings))
                XCTAssertFalse(original.detail.isEmpty, kind.rawValue)
                for row in original.detail { settings.setDetailRowVisible(kind, row.0, false) }
                let restored = AppSettings(defaults: defaults)
                let hidden = try XCTUnwrap(store.descriptor(for: kind, settings: restored))
                XCTAssertTrue(hidden.detail.isEmpty, kind.rawValue)
                XCTAssertEqual(hidden.value, original.value)
                XCTAssertEqual(hidden.secondaryValue, original.secondaryValue)
                let label = try XCTUnwrap(original.detail.first?.0)
                restored.setDetailRowVisible(kind, label, true)
                let revealed = try XCTUnwrap(store.descriptor(for: kind, settings: restored))
                XCTAssertEqual(revealed.detail.map { $0.0 }, [label], kind.rawValue)
            }
        }
    }

    @MainActor
    func testDynamicSensorAndFanRowsKeepPreferencesWhileReadingsDisappear() throws {
        try withSettings { settings, defaults in
            let store = populatedStore()
            store.temps.sensors.append(TempReading(label: "Future sensor", celsius: 40))
            XCTAssertEqual(store.detailRowOptions(for: .fan), ["Fan 1", "Fan 2"])
            XCTAssertTrue(store.detailRowOptions(for: .temps).contains("Future sensor"))
            XCTAssertEqual(Set(store.detailRowOptions(for: .temps)).count,
                           store.detailRowOptions(for: .temps).count)
            settings.setDetailRowVisible(.temps, "Future sensor", false)
            settings.setDetailRowVisible(.fan, "Fan 2", false)
            let restored = AppSettings(defaults: defaults)
            XCTAssertFalse(restored.isDetailRowVisible(.temps, "Future sensor"))
            XCTAssertFalse(restored.isDetailRowVisible(.fan, "Fan 2"))
            XCTAssertFalse(try XCTUnwrap(store.descriptor(for: .temps, settings: restored)).detail.contains { $0.0 == "Future sensor" })
            XCTAssertEqual(store.descriptor(for: .fan, settings: restored)?.detail.map { $0.0 }, ["Fan 1"])
            store.temps.sensors = []
            store.fan = .empty
            XCTAssertNil(store.descriptor(for: .fan, settings: restored))
            XCTAssertEqual(store.detailRowOptions(for: .fan), ["Fan"])
            store.fan = FanSample(hasFans: true, fans: [.init(current: 1500, min: 1000, max: 6000)])
            XCTAssertEqual(store.detailRowOptions(for: .fan), ["Fan"])
            XCTAssertFalse(AppSettings(defaults: defaults).isDetailRowVisible(.fan, "Fan 2"))
            store.temps.sensors = [TempReading(label: "Future sensor", celsius: 40)]
            XCTAssertTrue(try XCTUnwrap(store.descriptor(for: .temps, settings: restored)).detail.isEmpty)
            restored.setDetailRowVisible(.temps, "Future sensor", true)
            XCTAssertEqual(store.descriptor(for: .temps, settings: restored)?.detail.map { $0.0 }, ["Future sensor"])
        }
    }

    @MainActor
    private func populatedStore() -> StatsStore {
        let store = StatsStore()
        store.cpu = CPUSample(totalUsagePercent: 35, userPercent: 25, systemPercent: 10, idlePercent: 65)
        store.memory = MemorySample(usedBytes: 8_000_000_000, totalBytes: 16_000_000_000, pressurePercent: 20)
        store.disk = DiskSample(usedBytes: 250_000_000_000, freeBytes: 750_000_000_000,
                                totalBytes: 1_000_000_000_000, readBytesPerSec: 2_000_000,
                                writeBytesPerSec: 500_000)
        store.network = NetworkSample(downBytesPerSec: 1_000_000, upBytesPerSec: 100_000,
                                      interfaceName: "Wi-Fi (en0)", localIP: "192.0.2.1")
        store.battery = BatterySample(isPresent: true, percent: 60, isCharging: false, isOnAC: false,
                                      minutesRemaining: 120, healthPercent: 95, cycleCount: 100, temperatureC: 30)
        store.gpu = GPUSample(isAvailable: true, utilizationPercent: 40, deviceName: "Fixture GPU")
        store.fan = FanSample(hasFans: true,
                             fans: [.init(current: 1500, min: 1000, max: 6000),
                                    .init(current: 2000, min: 1000, max: 6000)])
        store.temps = TemperatureSample(thermalState: .fair,
                                       sensors: [TempReading(label: "CPU", celsius: 60),
                                                 TempReading(label: "GPU", celsius: 50)])
        store.uptime = UptimeSample(seconds: 90_000)
        return store
    }
}

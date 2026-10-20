import XCTest

final class PanelMetricOptionsTests: XCTestCase {
    /// Exercise the same settings-to-descriptor path used by the panel, with
    /// fixture samples. Sampler I/O, SwiftUI layout, and live tint are not tested.
    /// No AppSettings.shared, app startup, sampler.start(), or hotkey registration.
    @MainActor
    private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
        let suite = "com.sim.QuickStatsPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppSettings(defaults: defaults), defaults)
    }

    @MainActor
    func testNewPreferencesDefaultAndRoundTripWithoutChangingExistingTileOptions() throws {
        try withSettings { settings, defaults in
            XCTAssertEqual(settings.powerDisplayMode, .system)
            XCTAssertEqual(settings.loadDisplayMode, .oneMinute)
            XCTAssertTrue(settings.hiddenDetailRows.isEmpty)

            settings.setValueMode(.network, .second)
            settings.setStyle(.cpu, .textAndGraph)
            settings.powerDisplayMode = .cpuAndGPU
            settings.loadDisplayMode = .relativeToCores
            settings.setDetailRowVisible(.power, "GPU", false)
            settings.setDetailRowVisible(.loadAverage, "5 min", false)

            let restored = AppSettings(defaults: defaults)
            XCTAssertEqual(restored.powerDisplayMode, .cpuAndGPU)
            XCTAssertEqual(restored.loadDisplayMode, .relativeToCores)
            XCTAssertFalse(restored.isDetailRowVisible(.power, "GPU"))
            XCTAssertFalse(restored.isDetailRowVisible(.loadAverage, "5 min"))
            XCTAssertTrue(restored.isDetailRowVisible(.power, "CPU"))
            XCTAssertEqual(restored.valueMode(.network), .second)
            XCTAssertEqual(restored.style(.cpu), .textAndGraph)
        }
    }

    @MainActor
    func testUnknownStoredOptionsFallBackAndUnknownRowsAreDropped() throws {
        try withSettings { _, defaults in
            defaults.set("future-power-mode", forKey: "powerDisplayMode")
            defaults.set("future-load-mode", forKey: "loadDisplayMode")
            defaults.set(["power": ["GPU", "future-row"],
                          "loadAverage": ["5 min"],
                          "cpu": ["User"],
                          "future-stat": ["CPU"]], forKey: "hiddenDetailRows")
            let restored = AppSettings(defaults: defaults)
            XCTAssertEqual(restored.powerDisplayMode, .system)
            XCTAssertEqual(restored.loadDisplayMode, .oneMinute)
            XCTAssertEqual(restored.hiddenDetailRows, [.power: ["GPU"], .loadAverage: ["5 min"], .cpu: ["User"]])
            restored.setDetailRowVisible(.power, "future-row", false)
            XCTAssertEqual(restored.hiddenDetailRows[.power], ["GPU"])
        }
    }

    @MainActor
    func testEachPowerChoiceReachesPanelWithUnambiguousWatts() throws {
        try withSettings { settings, _ in
            let store = StatsStore()
            store.power = powerFixture()
            let expected: [(PowerDisplayMode, String)] = [
                (.system, "30.6 W"), (.chipTotal, "6.0 W"), (.cpu, "0.0 W"),
                (.gpu, "4.4 W"), (.cpuAndGPU, "CPU 0.0 W · GPU 4.4 W"), (.dcIn, "85.1 W")
            ]
            for (mode, value) in expected {
                settings.powerDisplayMode = mode
                let descriptor = try XCTUnwrap(store.descriptor(for: .power, settings: settings))
                XCTAssertEqual(descriptor.value, value, mode.rawValue)
                XCTAssertEqual(descriptor.widestValue, mode.widestValue)
            }
        }
    }

    @MainActor
    func testMissingSystemOrChargerReadingStaysUnavailableInsteadOfSubstitutingChipPower() throws {
        try withSettings { settings, _ in
            let store = StatsStore()
            store.power = powerFixture()
            store.power.systemWatts = nil
            store.power.dcInWatts = nil
            for mode in [PowerDisplayMode.system, .dcIn] {
                settings.powerDisplayMode = mode
                let descriptor = try XCTUnwrap(store.descriptor(for: .power, settings: settings))
                XCTAssertEqual(descriptor.value, "— W")
                XCTAssertFalse(descriptor.detail.contains { $0.0 == "System" || $0.0 == "DC In" })
            }
        }
    }

    @MainActor
    func testDetailRowsCanAllBeHiddenAndIndividuallyRestored() throws {
        try withSettings { settings, defaults in
            let store = StatsStore()
            store.power = powerFixture()
            store.loadAverage = LoadSample(one: 2, five: 4, fifteen: 8)
            for kind in [StatKind.power, .loadAverage] {
                for label in kind.configurableDetailRows {
                    settings.setDetailRowVisible(kind, label, false)
                }
            }
            let restored = AppSettings(defaults: defaults)
            for kind in [StatKind.power, .loadAverage] {
                let hidden = try XCTUnwrap(store.descriptor(for: kind, settings: restored))
                XCTAssertTrue(hidden.detail.isEmpty)
                XCTAssertFalse(hidden.value.isEmpty)
                let label = try XCTUnwrap(kind.configurableDetailRows.first)
                restored.setDetailRowVisible(kind, label, true)
                let revealed = try XCTUnwrap(store.descriptor(for: kind, settings: restored))
                XCTAssertEqual(revealed.detail.map { $0.0 }, [label])
            }
        }
    }

    @MainActor
    func testLoadChoiceUsesSelectedAverageForHeadlineAndSaturation() throws {
        try withSettings { settings, _ in
            let store = StatsStore()
            let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
            store.loadAverage = LoadSample(one: 0.25 * Double(cores),
                                           five: 0.5 * Double(cores),
                                           fifteen: 2 * Double(cores))
            for (mode, percent) in [(LoadDisplayMode.oneMinute, 25.0),
                                    (.fiveMinutes, 50.0), (.fifteenMinutes, 100.0),
                                    (.relativeToCores, 25.0)] {
                settings.loadDisplayMode = mode
                let descriptor = try XCTUnwrap(store.descriptor(for: .loadAverage, settings: settings))
                XCTAssertEqual(descriptor.loadPercent, percent, accuracy: 0.0001)
                switch mode {
                case .oneMinute:
                    XCTAssertEqual(descriptor.value, String(format: "%.2f", 0.25 * Double(cores)))
                case .fiveMinutes:
                    XCTAssertEqual(descriptor.value, String(format: "%.2f", 0.5 * Double(cores)))
                case .fifteenMinutes:
                    XCTAssertEqual(descriptor.value, String(format: "%.2f", 2 * Double(cores)))
                case .relativeToCores:
                    XCTAssertEqual(descriptor.value, String(format: "%.1f / %d cores", 0.25 * Double(cores), cores))
                }
            }
            let fixture = LoadSample(one: 26.93, five: 28.30, fifteen: 25.64)
            XCTAssertEqual(fixture.headline(for: .oneMinute, cores: 10), "26.93")
            XCTAssertEqual(fixture.headline(for: .fiveMinutes, cores: 10), "28.30")
            XCTAssertEqual(fixture.headline(for: .fifteenMinutes, cores: 10), "25.64")
            XCTAssertEqual(fixture.headline(for: .relativeToCores, cores: 10), "26.9 / 10 cores")
            XCTAssertEqual(fixture.saturationPercent(for: .oneMinute, cores: 0), 100)
        }
    }

    private func powerFixture() -> PowerSample {
        PowerSample(isAvailable: true, cpuWatts: 0, gpuWatts: 4.4,
                    aneWatts: 1.1, dramWatts: 0.5, loadPercent: 40,
                    systemWatts: 30.6, dcInWatts: 85.1)
    }
}

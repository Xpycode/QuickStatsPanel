import XCTest

final class RingDetailMeasurementTests: XCTestCase {
    @MainActor
    private func withSettings(_ body: (AppSettings) -> Void) throws {
        let suite = "com.sim.QuickStatsPanelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        body(AppSettings(defaults: defaults))
    }

    @MainActor
    func testRingMeasurementReservesProcessRowsWhenListIsEmpty() throws {
        try withSettings { settings in
            let store = StatsStore()
            XCTAssertTrue(store.topProcesses.cpuRows(10).isEmpty)
            XCTAssertTrue(store.topProcesses.memoryRows(10).isEmpty)
            for kind in [StatKind.cpu, .memory] {
                XCTAssertNil(store.descriptor(for: kind, settings: settings)?.processSection,
                             "Strip stays nil for empty rows: \(kind)")
                let section = store.descriptor(for: kind, settings: settings,
                                               reservingProcessRows: true)?.processSection
                XCTAssertNotNil(section, "\(kind)")
                XCTAssertEqual(section?.rows.count, 0)
                XCTAssertEqual(section?.reservedRows, 10)
            }
        }
    }

    /// Disk has no per-process source, so there is nothing to reserve; its card is unchanged.
    @MainActor
    func testDiskHasNoProcessSectionToReserve() throws {
        try withSettings { settings in
            let store = StatsStore()
            XCTAssertNil(store.descriptor(for: .disk, settings: settings)?.processSection)
            XCTAssertNil(store.descriptor(for: .disk, settings: settings,
                                          reservingProcessRows: true)?.processSection)
        }
    }
}

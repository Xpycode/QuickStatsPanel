import XCTest

#if DEBUG
/// Floating-tile fixture isolation: settings come from a seeded per-launch suite (never the
/// standard domain), the store runs no samplers, period queries settle without automatic
/// scheduling, and the temporary history root is removed after the termination flush.
@MainActor
final class FloatingTileIsolationTests: XCTestCase {

    private func options(_ fixture: FloatingTileFixtureName = .cpuNetwork) throws -> FloatingTilePrototypeOptions {
        var o = try XCTUnwrap(FloatingTilePrototypeOptions.parse(["--floating-tiles-prototype"]))
        o.fixture = fixture
        return o
    }

    func testNormalLaunchKeepsStandardDefaults() {
        XCTAssertTrue(AppSettings.launchDefaults(prototype: nil) === UserDefaults.standard)
        XCTAssertTrue(AppSettings.launchDefaults() === UserDefaults.standard, "tests are not a prototype launch")
    }

    func testPrototypeSettingsComeFromTheSeededIsolatedSuite() throws {
        let o = try options(.networkCPU)
        defer { FloatingTileFixtures.removeIsolatedDefaults(for: o) }
        let standardBefore = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0 == "enabledStats" || $0 == "statOrder" || $0 == "hasSeenHint" }
            .map { "\($0)=\(String(describing: UserDefaults.standard.object(forKey: $0)))" }.sorted()

        let defaults = AppSettings.launchDefaults(prototype: o)
        XCTAssertFalse(defaults === UserDefaults.standard)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.enabledStats, [.network, .cpu])
        XCTAssertEqual(Array(settings.statOrder.prefix(2)), [.network, .cpu])
        XCTAssertTrue(settings.hasSeenHint, "the first-run hint never writes on a fixture launch")
        XCTAssertEqual(settings.anchor, .screenCenter)

        // A fixture Settings write lands in the suite, not in the standard domain.
        settings.setEnabled(.gpu, true)
        XCTAssertEqual(AppSettings(defaults: defaults).enabledStats, [.network, .cpu, .gpu])
        let standardAfter = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0 == "enabledStats" || $0 == "statOrder" || $0 == "hasSeenHint" }
            .map { "\($0)=\(String(describing: UserDefaults.standard.object(forKey: $0)))" }.sorted()
        XCTAssertEqual(standardBefore, standardAfter, "standard defaults untouched")
    }

    func testIsolatedSuiteStartsFreshAndIsRemoved() throws {
        let o = try options()
        let first = try XCTUnwrap(FloatingTileFixtures.isolatedDefaults(for: o))
        first.set("leftover", forKey: "probe")
        let second = try XCTUnwrap(FloatingTileFixtures.isolatedDefaults(for: o))
        XCTAssertNil(second.object(forKey: "probe"), "a suite is reseeded from scratch")
        XCTAssertTrue(FileManager.default.fileExists(atPath: o.defaultsFile.path), "suite is file-backed in temp")
        FloatingTileFixtures.removeIsolatedDefaults(for: o)
        XCTAssertFalse(FileManager.default.fileExists(atPath: o.defaultsFile.path), "suite file removed")
        let preferences = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let leaked = (try? FileManager.default.contentsOfDirectory(atPath: preferences.path))?
            .filter { $0.contains(o.isolationID) } ?? []
        XCTAssertEqual(leaked, [], "nothing written to the user's Preferences folder")
    }

    func testFixtureStoreIsInertAndUsesItsOwnTemporaryRoot() throws {
        let o = try options()
        let store = FloatingTileFixtures.makeStore(options: o)
        XCTAssertFalse(store.isRunning, "no samplers in fixture mode")
        XCTAssertNotNil(store.transferHistoryController)
        XCTAssertEqual(store.disposableTransferHistoryRoot, o.historyRoot)
        XCTAssertGreaterThan(store.cpu.totalUsagePercent, 0, "CPU is seeded")
        XCTAssertGreaterThan(store.network.downBytesPerSec, 0, "Network is seeded")
        try? FileManager.default.removeItem(at: o.historyRoot)
    }

    func testPeriodChangeSettlesWithoutAutomaticScheduling() async throws {
        let o = try options()
        let store = FloatingTileFixtures.makeStore(options: o)
        defer { try? FileManager.default.removeItem(at: o.historyRoot) }
        store.setTransferDetailVisible(.network)
        try await waitFor { store.transferPresentations[.network]?.period == .minute }
        for period in [TransferHistoryPeriod.hour, .day, .minute] {
            store.selectTransferPeriod(period, for: .network)
            try await waitFor { store.transferPresentations[.network]?.period == period }
            XCTAssertEqual(store.transferPresentations[.network]?.period, period, "\(period) settled")
        }
    }

    func testRingFixtureStoreDoesNotOptIn() async throws {
        // Opt-in only: the ring fixture store keeps no disposable root and its existing behaviour.
        let store = StatsStore.makeRingFixtureStore(unavailable: [])
        XCTAssertNil(store.disposableTransferHistoryRoot)
        XCTAssertFalse(store.isRunning)
    }

    func testTemporaryRootIsRemovedAfterTheTerminationFlush() async throws {
        let o = try options()
        let store = FloatingTileFixtures.makeStore(options: o)
        try await waitFor { store.transferPresentations[.network] != nil }
        let done = expectation(description: "termination flush")
        nonisolated(unsafe) var flushError: String??
        store.prepareForTermination { error in flushError = .some(error); done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertNotNil(flushError, "completion ran")
        XCTAssertNil(flushError ?? nil, "the final flush succeeded inside the disposable root")
        XCTAssertFalse(FileManager.default.fileExists(atPath: o.historyRoot.path), "root removed after the flush")
    }

    func testFixtureHistoryIsSeededAndScopedResetCompletesOnDisposableData() async throws {
        let o = try options(.all)
        let store = FloatingTileFixtures.makeStore(options: o)
        defer { try? FileManager.default.removeItem(at: o.historyRoot) }
        store.setTransferDetailVisible(.network)
        try await waitFor { store.transferPresentations[.network] != nil }
        store.selectTransferPeriod(.minute, for: .network)
        try await waitFor { store.transferPresentations[.network]?.cumulativeTotals.first.exactValue != TransferHistoryFormat.exactBytes(0) }
        let before = try XCTUnwrap(store.transferPresentations[.network])
        XCTAssertNotEqual(before.cumulativeTotals.first.exactValue, TransferHistoryFormat.exactBytes(0), "seeded activity")
        XCTAssertNotEqual(before.selectedTotals.first.exactValue, TransferHistoryFormat.exactBytes(0), "the minute has history")

        // Request → confirm → durable completion, all inside the temporary root.
        try await Task.sleep(nanoseconds: 1_100_000_000) // the existing one-second reset spacing
        store.requestTransferReset(for: .network)
        XCTAssertEqual(store.transferDetailStates[.network]?.isConfirmingReset, true)
        store.confirmTransferReset(for: .network)
        try await waitFor { store.transferDetailStates[.network]?.isResetPending == false }
        XCTAssertNil(store.transferDetailStates[.network]?.resetError, "reset confirmed by a durable save")
        store.selectTransferPeriod(.minute, for: .network)
        try await waitFor { store.transferPresentations[.network]?.cumulativeTotals.first.exactValue == TransferHistoryFormat.exactBytes(0) }
        let after = try XCTUnwrap(store.transferPresentations[.network])
        XCTAssertEqual(after.cumulativeTotals.first.exactValue, TransferHistoryFormat.exactBytes(0), "Network totals reset")
        XCTAssertNotEqual(after.selectedTotals.first.exactValue, TransferHistoryFormat.exactBytes(0), "history is kept")
        XCTAssertTrue(o.historyRoot.standardizedFileURL.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path))

        // Scoped: Disk keeps its totals.
        store.setTransferDetailVisible(.disk)
        store.selectTransferPeriod(.minute, for: .disk)
        try await waitFor { store.transferPresentations[.disk]?.cumulativeTotals.first.exactValue != TransferHistoryFormat.exactBytes(0) }
        XCTAssertNotEqual(store.transferPresentations[.disk]?.cumulativeTotals.first.exactValue, TransferHistoryFormat.exactBytes(0))
    }

    private func waitFor(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
    }
}
#endif

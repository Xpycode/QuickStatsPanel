import XCTest

/// Complete headless journeys through the detail-card facade, real sampler accounting,
/// history owner and on-disk checkpoints. All time, counters, metadata and roots are fixtures.
/// Native controls, application termination, sleep and power-loss behavior remain E1.
final class TransferHistoryIntegrationTests: XCTestCase {
    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value
        init(_ value: Value) { self.value = value }
        func read() -> Value { lock.lock(); defer { lock.unlock() }; return value }
        func update(_ action: (inout Value) -> Void) { lock.lock(); defer { lock.unlock() }; action(&value) }
    }

    private final class Clock: TransferClock, @unchecked Sendable {
        let time = Box<Double>(100)
        let bootID = UUID().uuidString
        func now() -> TransferTimestamp {
            let value = time.read()
            return TransferTimestamp(continuousTime: value,
                wallTime: Date(timeIntervalSince1970: 1_800_000_000 + value), bootID: bootID)
        }
        func set(_ value: Double) { time.update { $0 = value } }
    }

    private final class Reader: TransferCounterReader, @unchecked Sendable {
        let stat: TransferStat
        let bytes: Box<TransferBytes>
        init(_ stat: TransferStat) {
            self.stat = stat
            bytes = Box(TransferBytes(first: 8_000_000_000, second: 4_000_000_000))
        }
        func add(_ first: UInt64, _ second: UInt64) {
            bytes.update { $0 = $0.adding(TransferBytes(first: first, second: second))! }
        }
        func read(generation: UUID, sequence: UInt64, timestamp: TransferTimestamp) -> TransferCounterSnapshot {
            let id: TransferSourceID = stat == .network
                ? .network(index: 1, name: "en-fixture", incarnation: 1) : .disk(registryID: 1)
            return TransferCounterSnapshot(stat: stat, generation: generation, sequence: sequence,
                timestamp: timestamp, enumeration: .complete,
                sources: [TransferSourceCounter(id: id, bytes: bytes.read())])
        }
    }

    private final class Samplers: @unchecked Sendable {
        let network: NetworkSampler
        let disk: DiskSampler
        let networkValues = Box<[NetworkSample]>([])
        let diskValues = Box<[DiskSample]>([])
        init(controller: TransferHistoryController, clock: Clock, networkReader: Reader,
             diskReader: Reader, interval: TimeInterval = 1) {
            let networkValues = networkValues, diskValues = diskValues
            network = NetworkSampler(interval: interval, reader: networkReader, clock: clock,
                automaticallySchedules: false, metadataProvider: { (nil, nil) },
                onGeneration: { controller.admitGeneration($0, for: .network) },
                onTransferEvent: { controller.ingest($0) },
                onSample: { sample in networkValues.update { $0.append(sample) } })
            disk = DiskSampler(interval: interval, reader: diskReader, clock: clock,
                automaticallySchedules: false, capacityProvider: { (200, 800, 1_000) },
                onGeneration: { controller.admitGeneration($0, for: .disk) },
                onTransferEvent: { controller.ingest($0) },
                onSample: { sample in diskValues.update { $0.append(sample) } })
        }
        func startAndSeed() { network.start(); disk.start(); sample() }
        func sample() { network.sampleNow(); disk.sampleNow() }
        func stop() { network.stop(); disk.stop() }
        func reset(_ stat: TransferStat, request: UUID) -> Bool {
            stat == .network ? network.requestReset(requestID: request) : disk.requestReset(requestID: request)
        }
        deinit { stop() }
    }

    private func root() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TransferJourney-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func drain(_ controller: TransferHistoryController) async {
        await withCheckedContinuation { continuation in controller.synchronize { continuation.resume() } }
    }

    @discardableResult private func flush(_ controller: TransferHistoryController) async -> String? {
        await withCheckedContinuation { continuation in controller.flush { continuation.resume(returning: $0) } }
    }

    private func expectSaved(_ controller: TransferHistoryController,
                             file: StaticString = #filePath, line: UInt = #line) async {
        let error = await flush(controller)
        XCTAssertNil(error, file: file, line: line)
    }

    private func expectUnsaved(_ controller: TransferHistoryController,
                               file: StaticString = #filePath, line: UInt = #line) async {
        let error = await flush(controller)
        XCTAssertNotNil(error, file: file, line: line)
    }

    @MainActor private func settle(_ store: StatsStore) async throws {
        let controller = try XCTUnwrap(store.transferHistoryController)
        // A reset request may append its ordered observation/marker behind the first barrier.
        await drain(controller); await drain(controller)
        for _ in 0..<20 { await Task.yield() }
    }

    @MainActor private func open(root: URL, clock: Clock, active: Box<Samplers?>) -> StatsStore {
        let store = StatsStore(transferHistoryRoot: root, transferClock: clock,
            transferHistoryAutomaticallySchedules: false,
            transferBoundaryReset: { stat, id in active.read()?.reset(stat, request: id) ?? false })
        // Starting only the retained-history owner avoids AppSettings.shared and real hardware.
        store.startTransferHistory()
        return store
    }

    private func expect(_ totals: TransferPairedTotals, _ first: UInt64, _ second: UInt64,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(totals.first.exactValue, TransferHistoryFormat.exactBytes(first), file: file, line: line)
        XCTAssertEqual(totals.second.exactValue, TransferHistoryFormat.exactBytes(second), file: file, line: line)
    }

    private func expectGraphConserves(_ value: TransferHistoryPresentation, first: Double, second: Double,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let duration = value.period.duration
        let a = value.graph.slots.reduce(0) { $0 + $1.firstRate * ($1.endFraction - $1.startFraction) * duration }
        let b = value.graph.slots.reduce(0) { $0 + $1.secondRate * ($1.endFraction - $1.startFraction) * duration }
        XCTAssertEqual(a, first, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(b, second, accuracy: 0.01, file: file, line: line)
        XCTAssertLessThanOrEqual(value.graph.slots.count, 120, file: file, line: line)
    }

    @MainActor func testDetailJourneySurvivesCadenceReopenScopedResetsAndExpiry() async throws {
        let root = root(), clock = Clock(), active = Box<Samplers?>(nil)
        let network = Reader(.network), disk = Reader(.disk)
        var store = open(root: root, clock: clock, active: active)
        var controller = try XCTUnwrap(store.transferHistoryController)
        var samplers = Samplers(controller: controller, clock: clock, networkReader: network, diskReader: disk)
        active.update { $0 = samplers }; defer { active.read()?.stop(); active.update { $0 = nil } }
        samplers.startAndSeed()
        clock.set(102); network.add(100_000_000, 20_000_000); disk.add(80_000_000, 40_000_000); samplers.sample()
        try await settle(store)
        var net = try XCTUnwrap(store.transferPresentations[.network])
        var diskValue = try XCTUnwrap(store.transferPresentations[.disk])
        expect(net.selectedTotals, 100_000_000, 20_000_000)
        expect(net.cumulativeTotals, 100_000_000, 20_000_000)
        expect(diskValue.selectedTotals, 80_000_000, 40_000_000)
        expect(diskValue.cumulativeTotals, 80_000_000, 40_000_000)
        XCTAssertEqual(samplers.networkValues.read().last?.downBytesPerSec, 50_000_000)
        XCTAssertEqual(samplers.networkValues.read().last?.upBytesPerSec, 10_000_000)
        XCTAssertEqual(samplers.diskValues.read().last?.readBytesPerSec, 40_000_000)
        XCTAssertEqual(samplers.diskValues.read().last?.writeBytesPerSec, 20_000_000)
        XCTAssertEqual(samplers.diskValues.read().last?.totalBytes, 1_000, "Capacity is independent of transfer bytes")
        expectGraphConserves(net, first: 100_000_000, second: 20_000_000)
        expectGraphConserves(diskValue, first: 80_000_000, second: 40_000_000)
        XCTAssertTrue(net.coverageText.contains("Fully measured 2 s"))
        let originalNetworkStart = net.resetStartedText, originalDiskStart = diskValue.resetStartedText

        // Replacing the cadence admits new generations and seeds their lifetime counters.
        samplers.stop(); clock.set(103)
        network.add(9_000_000_000, 7_000_000_000); disk.add(7_000_000_000, 5_000_000_000)
        samplers = Samplers(controller: controller, clock: clock, networkReader: network, diskReader: disk, interval: 0.25)
        active.update { $0 = samplers }; samplers.startAndSeed()
        clock.set(103.25); network.add(10_000_000, 2_000_000); disk.add(8_000_000, 4_000_000); samplers.sample()
        XCTAssertEqual(samplers.networkValues.read().last?.downBytesPerSec, 40_000_000)
        XCTAssertEqual(samplers.diskValues.read().last?.readBytesPerSec, 32_000_000)
        // Superseded period actions reach the same store entry point as native controls.
        for _ in 0..<30 { store.selectTransferPeriod(.minute, for: .network); store.selectTransferPeriod(.hour, for: .network) }
        store.selectTransferPeriod(.day, for: .network); store.selectTransferPeriod(.hour, for: .disk)
        try await settle(store)
        net = try XCTUnwrap(store.transferPresentations[.network]); diskValue = try XCTUnwrap(store.transferPresentations[.disk])
        XCTAssertEqual(net.period, .day); XCTAssertEqual(diskValue.period, .hour)
        expect(net.selectedTotals, 110_000_000, 22_000_000); expect(diskValue.selectedTotals, 88_000_000, 44_000_000)
        XCTAssertEqual(net.resetStartedText, originalNetworkStart); XCTAssertEqual(diskValue.resetStartedText, originalDiskStart)
        expectGraphConserves(net, first: 110_000_000, second: 22_000_000)
        await expectSaved(controller)
        samplers.stop(); active.update { $0 = nil }

        // A new store/controller and fresh samplers simulate process reopening, with downtime
        // represented by absence. Large closed-time counter changes are baseline-only.
        clock.set(110); network.add(5_000_000_000, 4_000_000_000); disk.add(4_000_000_000, 3_000_000_000)
        store = open(root: root, clock: clock, active: active)
        controller = try XCTUnwrap(store.transferHistoryController)
        samplers = Samplers(controller: controller, clock: clock, networkReader: network, diskReader: disk, interval: 5)
        active.update { $0 = samplers }; samplers.startAndSeed()
        clock.set(111); network.add(5_000_000, 1_000_000); disk.add(4_000_000, 2_000_000); samplers.sample()
        try await settle(store)
        net = try XCTUnwrap(store.transferPresentations[.network]); diskValue = try XCTUnwrap(store.transferPresentations[.disk])
        expect(net.selectedTotals, 115_000_000, 23_000_000); expect(diskValue.selectedTotals, 92_000_000, 46_000_000)
        XCTAssertEqual(net.resetStartedText, originalNetworkStart); XCTAssertEqual(diskValue.resetStartedText, originalDiskStart)
        let measured = net.graph.slots.reduce(0) { $0 + (1 - $1.missingFraction - $1.partialFraction) * ($1.endFraction - $1.startFraction) * 60 }
        XCTAssertEqual(measured, 3.25, accuracy: 0.000_001, "Cadence replacement and app-closed intervals remain gaps")

        store.requestTransferReset(for: .network); store.cancelTransferReset(for: .network)
        store.confirmTransferReset(for: .network) // Cancellation cannot reach the sampler.
        try await settle(store); expect(try XCTUnwrap(store.transferPresentations[.network]).cumulativeTotals, 115_000_000, 23_000_000)
        clock.set(112); network.add(10_000_000, 2_000_000)
        store.requestTransferReset(for: .network); store.confirmTransferReset(for: .network)
        try await settle(store)
        XCTAssertFalse(try XCTUnwrap(store.transferDetailStates[.network]).isResetPending)
        XCTAssertNil(store.transferDetailStates[.network]?.resetError)
        net = try XCTUnwrap(store.transferPresentations[.network]); diskValue = try XCTUnwrap(store.transferPresentations[.disk])
        expect(net.cumulativeTotals, 0, 0); expect(net.selectedTotals, 125_000_000, 25_000_000)
        expect(diskValue.cumulativeTotals, 92_000_000, 46_000_000)
        XCTAssertNotEqual(net.resetStartedText, originalNetworkStart); XCTAssertEqual(diskValue.resetStartedText, originalDiskStart)
        XCTAssertTrue(net.saveText.hasPrefix("Saved"))
        let networkResetStart = net.resetStartedText

        clock.set(113); network.add(3_000_000, 600_000); disk.add(2_000_000, 1_000_000); samplers.sample()
        clock.set(114); disk.add(6_000_000, 3_000_000)
        store.requestTransferReset(for: .disk); store.confirmTransferReset(for: .disk)
        try await settle(store)
        net = try XCTUnwrap(store.transferPresentations[.network]); diskValue = try XCTUnwrap(store.transferPresentations[.disk])
        expect(net.cumulativeTotals, 3_000_000, 600_000); expect(net.selectedTotals, 128_000_000, 25_600_000)
        expect(diskValue.cumulativeTotals, 0, 0); expect(diskValue.selectedTotals, 100_000_000, 50_000_000)
        XCTAssertEqual(net.resetStartedText, networkResetStart); XCTAssertNotEqual(diskValue.resetStartedText, originalDiskStart)
        XCTAssertFalse(try XCTUnwrap(store.transferDetailStates[.disk]).isResetPending)
        XCTAssertNil(store.transferDetailStates[.disk]?.resetError)
        let diskResetStart = diskValue.resetStartedText
        clock.set(115); network.add(1_000_000, 200_000); disk.add(1_000_000, 500_000); samplers.sample()
        samplers.stop(); await expectSaved(controller); active.update { $0 = nil }

        clock.set(120); store = open(root: root, clock: clock, active: active)
        controller = try XCTUnwrap(store.transferHistoryController); try await settle(store)
        net = try XCTUnwrap(store.transferPresentations[.network]); diskValue = try XCTUnwrap(store.transferPresentations[.disk])
        expect(net.selectedTotals, 129_000_000, 25_800_000); expect(diskValue.selectedTotals, 101_000_000, 50_500_000)
        expect(net.cumulativeTotals, 4_000_000, 800_000); expect(diskValue.cumulativeTotals, 1_000_000, 500_000)
        XCTAssertEqual(net.resetStartedText, networkResetStart); XCTAssertEqual(diskValue.resetStartedText, diskResetStart)
        clock.set(86_520); store.selectTransferPeriod(.day, for: .network); store.selectTransferPeriod(.day, for: .disk)
        controller.maintenance(); try await settle(store)
        net = try XCTUnwrap(store.transferPresentations[.network]); diskValue = try XCTUnwrap(store.transferPresentations[.disk])
        expect(net.selectedTotals, 0, 0); expect(diskValue.selectedTotals, 0, 0)
        expect(net.cumulativeTotals, 4_000_000, 800_000); expect(diskValue.cumulativeTotals, 1_000_000, 500_000)
        XCTAssertTrue(net.graph.slots.allSatisfy { $0.missingFraction == 1 })
        await expectSaved(controller)
        let saved = try XCTUnwrap(TransferHistoryRepository(root: root).load(now: clock.now()).snapshot)
        for stat in saved.stats { XCTAssertTrue(stat.segments.isEmpty) }
        XCTAssertEqual(saved.stats.first { $0.stat == .network }?.cumulative.startedAt, Date(timeIntervalSince1970: 1_800_000_112))
        XCTAssertEqual(saved.stats.first { $0.stat == .disk }?.cumulative.startedAt, Date(timeIntervalSince1970: 1_800_000_114))
    }

    private final class Storage: TransferHistoryStorage, @unchecked Sendable {
        let repository: TransferHistoryRepository
        let fails = Box(false)
        init(root: URL) { repository = TransferHistoryRepository(root: root) }
        func load(now: TransferTimestamp) -> TransferRepositoryLoadResult { repository.load(now: now) }
        func commit(_ snapshot: TransferTimelineSnapshot) -> TransferPersistenceStatus {
            fails.read() ? TransferPersistenceStatus(message: "Injected checkpoint failure") : repository.commit(snapshot)
        }
    }

    /// These additional journeys bypass StatsStore's native-action facade to inject storage
    /// failures. They still use actual counter accounting, persistence and presentation assembly.
    func testFailedSaveKeepsCollectingAndRecoveryCommitsExactObservedTotals() async throws {
        let root = root(), clock = Clock(), storage = Storage(root: root)
        let values = Box<[TransferStat: TransferHistoryPresentation]>([:])
        let controller = TransferHistoryController(clock: clock, automaticallySchedules: false,
            repositoryFactory: { storage }) { stat, _, _, value in values.update { $0[stat] = value } }
        controller.start()
        let network = Reader(.network), disk = Reader(.disk)
        let samplers = Samplers(controller: controller, clock: clock, networkReader: network, diskReader: disk)
        defer { samplers.stop() }; samplers.startAndSeed()
        clock.set(102); network.add(100_000_000, 20_000_000); disk.add(80_000_000, 40_000_000); samplers.sample()
        await expectSaved(controller)
        storage.fails.update { $0 = true }
        clock.set(104); network.add(25_000_000, 5_000_000); disk.add(10_000_000, 5_000_000); samplers.sample()
        await expectUnsaved(controller)
        var value = try XCTUnwrap(values.read()[.network])
        expect(value.selectedTotals, 125_000_000, 25_000_000); expect(value.cumulativeTotals, 125_000_000, 25_000_000)
        XCTAssertTrue(value.saveText.hasPrefix("Unsaved")); XCTAssertTrue(value.saveText.contains("Last saved"))
        XCTAssertTrue(value.warningText.contains("Injected checkpoint failure"))
        XCTAssertEqual(samplers.networkValues.read().last?.downBytesPerSec, 12_500_000)
        clock.set(106); network.add(5_000_000, 1_000_000); disk.add(2_000_000, 1_000_000); samplers.sample()
        storage.fails.update { $0 = false }; await expectSaved(controller)
        value = try XCTUnwrap(values.read()[.network])
        expect(value.cumulativeTotals, 130_000_000, 26_000_000)
        XCTAssertTrue(value.saveText.hasPrefix("Saved")); XCTAssertTrue(value.warningText.isEmpty)
        samplers.stop(); clock.set(110)
        let recovered = try XCTUnwrap(TransferHistoryRepository(root: root).load(now: clock.now()).snapshot)
        XCTAssertEqual(recovered.stats.first { $0.stat == .network }?.cumulative.bytes, TransferBytes(first: 130_000_000, second: 26_000_000))
        XCTAssertEqual(recovered.stats.first { $0.stat == .disk }?.cumulative.bytes, TransferBytes(first: 92_000_000, second: 46_000_000))
    }

    func testOlderCheckpointRecoveryDisclosesLossWhileNewActivityRemainsUsable() async throws {
        let root = root(), clock = Clock(), values = Box<[TransferStat: TransferHistoryPresentation]>([:])
        let controller = TransferHistoryController(root: root, clock: clock, automaticallySchedules: false) {
            stat, _, _, value in values.update { $0[stat] = value }
        }
        controller.start()
        let network = Reader(.network), disk = Reader(.disk)
        let samplers = Samplers(controller: controller, clock: clock, networkReader: network, diskReader: disk)
        defer { samplers.stop() }; samplers.startAndSeed()
        clock.set(102); network.add(100_000_000, 20_000_000); disk.add(80_000_000, 40_000_000); samplers.sample()
        await expectSaved(controller)
        clock.set(104); network.add(25_000_000, 5_000_000); disk.add(10_000_000, 5_000_000); samplers.sample()
        samplers.stop(); await expectSaved(controller)
        try Data(repeating: 0, count: 32).write(to: root.appendingPathComponent("checkpoint"))
        clock.set(110)
        let reopened = TransferHistoryController(root: root, clock: clock, automaticallySchedules: false) {
            stat, _, _, value in values.update { $0[stat] = value }
        }
        reopened.start(); await drain(reopened)
        var value = try XCTUnwrap(values.read()[.network])
        expect(value.selectedTotals, 100_000_000, 20_000_000); expect(value.cumulativeTotals, 100_000_000, 20_000_000)
        XCTAssertTrue(value.saveText.hasPrefix("Recovered")); XCTAssertTrue(value.warningText.contains("older checkpoint"))
        XCTAssertTrue(value.accessibilitySummary.contains("may be lost"))
        network.add(8_000_000_000, 6_000_000_000); disk.add(6_000_000_000, 4_000_000_000)
        let fresh = Samplers(controller: reopened, clock: clock, networkReader: network, diskReader: disk)
        defer { fresh.stop() }; fresh.startAndSeed()
        clock.set(112); network.add(5_000_000, 1_000_000); disk.add(4_000_000, 2_000_000); fresh.sample()
        await drain(reopened)
        value = try XCTUnwrap(values.read()[.network])
        expect(value.cumulativeTotals, 105_000_000, 21_000_000)
        XCTAssertTrue(value.saveText.hasPrefix("Unsaved")); XCTAssertTrue(value.warningText.contains("older checkpoint"))
        await expectSaved(reopened)
        value = try XCTUnwrap(values.read()[.network])
        XCTAssertTrue(value.saveText.hasPrefix("Saved")); XCTAssertTrue(value.warningText.contains("older checkpoint"))
    }
}

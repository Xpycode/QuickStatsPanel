import XCTest

/// Headless, manual-clock tests enter the same selection/reset/flush facade as the detail UI.
/// Every repository layer is injected with a disposable root; no hardware or timer is started.
final class TransferLifecycleTests: XCTestCase {
    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T
        init(_ value: T) { self.value = value }
        func read() -> T { lock.lock(); defer { lock.unlock() }; return value }
        func update(_ action: (inout T) -> Void) { lock.lock(); defer { lock.unlock() }; action(&value) }
    }
    private final class Clock: TransferClock, @unchecked Sendable {
        let time = Box<Double>(0)
        func now() -> TransferTimestamp {
            let value = time.read()
            return TransferTimestamp(continuousTime: value, wallTime: Date(timeIntervalSince1970: 1_800_000_000 + value), bootID: "lifecycle-fixture")
        }
    }
    private final class Reader: TransferCounterReader, @unchecked Sendable {
        let stat: TransferStat
        let bytes = Box<UInt64>(0)
        init(_ stat: TransferStat = .network) { self.stat = stat }
        func read(generation: UUID, sequence: UInt64, timestamp: TransferTimestamp) -> TransferCounterSnapshot {
            let value = bytes.read()
            return TransferCounterSnapshot(stat: stat, generation: generation, sequence: sequence,
                timestamp: timestamp, enumeration: .complete,
                sources: [TransferSourceCounter(id: .disk(registryID: 1), bytes: TransferBytes(first: value, second: value / 2))])
        }
    }
    private final class Storage: TransferHistoryStorage, @unchecked Sendable {
        let repository: TransferHistoryRepository
        let enteredLoad = DispatchSemaphore(value: 0), releaseLoad = DispatchSemaphore(value: 0)
        let enteredCommit = DispatchSemaphore(value: 0), releaseCommit = DispatchSemaphore(value: 0)
        let blocksLoad = Box(false), blocksCommit = Box(false), fails = Box(false), commits = Box(0)
        init(root: URL) { repository = TransferHistoryRepository(root: root) }
        func load(now: TransferTimestamp) -> TransferRepositoryLoadResult {
            if blocksLoad.read() { enteredLoad.signal(); _ = releaseLoad.wait(timeout: .now() + 5) }
            return repository.load(now: now)
        }
        func commit(_ snapshot: TransferTimelineSnapshot) -> TransferPersistenceStatus {
            commits.update { $0 += 1 }
            if blocksCommit.read() { enteredCommit.signal(); _ = releaseCommit.wait(timeout: .now() + 5) }
            if fails.read() { return TransferPersistenceStatus(message: "Fixture storage failure") }
            return repository.commit(snapshot)
        }
    }
    private final class Fixture {
        let root: URL
        let clock = Clock()
        let storage: Storage
        let values = Box<[TransferStat: TransferHistoryPresentation]>([:])
        let publications = Box(0)
        let controller: TransferHistoryController
        init() {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("TransferLifecycle-\(UUID())")
            storage = Storage(root: root)
            let clock = clock, storage = storage, values = values, publications = publications
            controller = TransferHistoryController(clock: clock, automaticallySchedules: false,
                repositoryFactory: { storage }) { stat, _, _, value in
                    values.update { $0[stat] = value }; publications.update { $0 += 1 }
                }
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        func sampler(_ reader: Reader) -> NetworkSampler {
            let controller = controller
            return NetworkSampler(reader: reader, clock: clock, automaticallySchedules: false,
                metadataProvider: { (nil, nil) },
                onGeneration: { controller.admitGeneration($0, for: .network) },
                onTransferEvent: { controller.ingest($0) }, onSample: { _ in })
        }
    }
    private func barrier(_ controller: TransferHistoryController, file: StaticString = #filePath, line: UInt = #line) {
        let done = expectation(description: "History queue and presentations drained")
        controller.synchronize { done.fulfill() }; wait(for: [done], timeout: 4)
    }
    @discardableResult private func flush(_ controller: TransferHistoryController) -> String? {
        let done = expectation(description: "Checkpoint completed"), result = Box<String?>(nil)
        controller.flush { error in result.update { $0 = error }; done.fulfill() }
        wait(for: [done], timeout: 4); return result.read()
    }
    private func observation(_ fixture: Fixture, stat: TransferStat = .network, generation: UUID,
                             sequence: UInt64, start: Double, end: Double, bytes: UInt64) -> TransferEvent {
        fixture.clock.time.update { $0 = end }
        return .observation(TransferObservation(generation: generation, sequence: sequence, timestamp: fixture.clock.now(),
            interval: TransferInterval(start: start, end: end, bytes: TransferBytes(first: bytes, second: bytes / 2), stat: stat, coverage: .complete), accountingOverflow: false))
    }
    private func total(_ fixture: Fixture, stat: TransferStat = .network) -> String? { fixture.values.read()[stat]?.cumulativeTotals.first.exactValue }
    private func expectTotal(_ fixture: Fixture, _ bytes: UInt64, stat: TransferStat = .network, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(total(fixture, stat: stat), TransferHistoryFormat.exactBytes(bytes), file: file, line: line)
    }

    func testTicksDuringBlockedLoadWaitForRecoveryAndNeverDoubleCount() throws {
        let f = Fixture(), generation = UUID()
        var saved = TransferTimeline(now: f.clock.now())
        saved.admitGeneration(generation, for: .network, admission: 1)
        saved.ingest(observation(f, generation: generation, sequence: 1, start: 0, end: 1, bytes: 100))
        _ = f.storage.repository.load(now: f.clock.now())
        XCTAssertTrue(f.storage.repository.commit(saved.snapshot(now: f.clock.now())).isDurable)
        f.storage.blocksLoad.update { $0 = true }; f.controller.start()
        XCTAssertEqual(f.storage.enteredLoad.wait(timeout: .now() + 2), .success)
        let next = UUID(); f.controller.admitGeneration(next, for: .network)
        let event = observation(f, generation: next, sequence: 1, start: 1, end: 2, bytes: 50)
        f.controller.ingest(event); f.controller.ingest(event)
        f.controller.start() // Idempotent, never restores a second time over buffered activity.
        f.storage.releaseLoad.signal(); barrier(f.controller); expectTotal(f, 150)
        XCTAssertNil(flush(f.controller))
        let reopened = TransferHistoryRepository(root: f.root).load(now: f.clock.now())
        XCTAssertEqual(reopened.snapshot?.stats.first(where: { $0.stat == .network })?.cumulative.bytes.first, 150)
        XCTAssertEqual(reopened.snapshot?.stats.first(where: { $0.stat == .network })?.watermark.admission, 2)
    }

    func testIntervalRestartPreservesHistoryAndRejectsLateGeneration() {
        let f = Fixture(), old = UUID(), next = UUID(); f.controller.start()
        f.controller.admitGeneration(old, for: .network)
        f.controller.ingest(observation(f, generation: old, sequence: 1, start: 0, end: 1, bytes: 100))
        f.controller.admitGeneration(next, for: .network)
        f.controller.ingest(observation(f, generation: old, sequence: 2, start: 1, end: 2, bytes: 999))
        f.controller.ingest(observation(f, generation: next, sequence: 1, start: 2, end: 3, bytes: 50))
        barrier(f.controller); expectTotal(f, 150)
        XCTAssertEqual(f.values.read()[.network]?.selectedTotals.first.exactValue, TransferHistoryFormat.exactBytes(150))
    }

    func testResetImmediatelyAfterStartUsesSamplerBoundaryAndDurableCompletion() {
        let f = Fixture(), reader = Reader(), sampler = f.sampler(reader)
        f.controller.start(); sampler.start()
        let done = expectation(description: "Reset saved")
        f.controller.requestReset(stat: .network, requestID: UUID(), performBoundaryReset: { sampler.requestReset(requestID: $0) }) { error in
            XCTAssertNil(error); done.fulfill()
        }
        wait(for: [done], timeout: 4); barrier(f.controller); expectTotal(f, 0)
        XCTAssertTrue(f.values.read()[.network]?.saveText.hasPrefix("Saved") == true)
        sampler.stop()
    }

    func testResetAccountsQueuedTickThenPreservesHistoryAndOtherStat() {
        let f = Fixture(), reader = Reader(), sampler = f.sampler(reader), disk = UUID()
        f.controller.start(); sampler.start(); sampler.sampleNow()
        f.controller.admitGeneration(disk, for: .disk)
        f.controller.ingest(observation(f, stat: .disk, generation: disk, sequence: 1, start: 0, end: 1, bytes: 80))
        reader.bytes.update { $0 = 100 }; sampler.sampleNow()
        f.clock.time.update { $0 = 2 }; reader.bytes.update { $0 = 150 }
        let done = expectation(description: "Reset boundary committed")
        f.controller.requestReset(stat: .network, requestID: UUID(), performBoundaryReset: { sampler.requestReset(requestID: $0) }) { error in
            XCTAssertNil(error); done.fulfill()
        }
        wait(for: [done], timeout: 4)
        f.clock.time.update { $0 = 3 }; reader.bytes.update { $0 = 175 }; sampler.sampleNow()
        barrier(f.controller); expectTotal(f, 25); expectTotal(f, 80, stat: .disk)
        XCTAssertEqual(f.values.read()[.network]?.selectedTotals.first.exactValue, TransferHistoryFormat.exactBytes(175))
        sampler.stop()
    }

    func testPendingResetDuplicateAndThrottleSurviveSamplerReplacement() {
        let f = Fixture(), reader = Reader(), sampler = f.sampler(reader), id = UUID()
        f.controller.start(); sampler.start()
        let boundary = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let first = expectation(description: "First reset")
        f.controller.requestReset(stat: .network, requestID: id, performBoundaryReset: { request in
            boundary.signal(); _ = release.wait(timeout: .now() + 3); return sampler.requestReset(requestID: request)
        }) { error in XCTAssertNil(error); first.fulfill() }
        XCTAssertEqual(boundary.wait(timeout: .now() + 2), .success)
        let pending = expectation(description: "Pending rejected")
        f.controller.requestReset(stat: .network, requestID: UUID(), performBoundaryReset: { _ in XCTFail("Pending reset must not reach sampler"); return false }) { error in
            XCTAssertNotNil(error); pending.fulfill()
        }
        release.signal(); wait(for: [first, pending], timeout: 4)
        sampler.stop(); let replacement = f.sampler(reader); replacement.start()
        let duplicate = expectation(description: "Duplicate rejected"), throttle = expectation(description: "Cross-instance throttle")
        f.controller.requestReset(stat: .network, requestID: id, performBoundaryReset: { _ in XCTFail("Duplicate action"); return true }) { error in XCTAssertNotNil(error); duplicate.fulfill() }
        f.clock.time.update { $0 = 0.5 }
        f.controller.requestReset(stat: .network, requestID: UUID(), performBoundaryReset: { _ in XCTFail("Throttled action"); return true }) { error in XCTAssertNotNil(error); throttle.fulfill() }
        wait(for: [duplicate, throttle], timeout: 4); replacement.stop()
    }

    func testShortSleepWakeFreshBaselinesLeaveGapAndNoLifetimeCounterSpike() {
        let f = Fixture(), reader = Reader(), sampler = f.sampler(reader)
        f.controller.start(); sampler.start(); sampler.sampleNow()
        f.clock.time.update { $0 = 1 }; reader.bytes.update { $0 = 100 }; sampler.sampleNow()
        sampler.stop(); XCTAssertNil(flush(f.controller))
        // Three seconds is below the ten-second automatic gap threshold. Only the explicit
        // lifecycle stop/start prevents the sleeping interval from becoming a counter spike.
        f.clock.time.update { $0 = 4 }; reader.bytes.update { $0 = 9_000 }; sampler.start(); sampler.sampleNow()
        f.clock.time.update { $0 = 5 }; reader.bytes.update { $0 = 9_050 }; sampler.sampleNow()
        f.controller.selectPeriod(.minute, for: .network); barrier(f.controller); expectTotal(f, 150)
        XCTAssertTrue(f.values.read()[.network]?.coverageText.contains("Missing 58 s") == true)
        sampler.stop()
    }

    func testDirtyCheckpointAtThirtySecondsAndFailureDoesNotStopCollection() {
        let f = Fixture(), generation = UUID(); f.controller.start(); f.controller.admitGeneration(generation, for: .network)
        barrier(f.controller) // Establish initial dirty timestamp at zero.
        f.controller.ingest(observation(f, generation: generation, sequence: 1, start: 0, end: 1, bytes: 100))
        barrier(f.controller)
        f.clock.time.update { $0 = 29.99 }; f.controller.maintenance(); barrier(f.controller)
        XCTAssertEqual(f.storage.commits.read(), 0)
        f.clock.time.update { $0 = 30 }; f.storage.fails.update { $0 = true }
        f.controller.maintenance(); barrier(f.controller)
        XCTAssertEqual(f.storage.commits.read(), 1)
        XCTAssertTrue(f.values.read()[.network]?.warningText.contains("Fixture storage failure") == true)
        f.controller.ingest(observation(f, generation: generation, sequence: 2, start: 30, end: 31, bytes: 50))
        barrier(f.controller); expectTotal(f, 150)
        f.clock.time.update { $0 = 59.99 }; f.controller.maintenance(); barrier(f.controller)
        XCTAssertEqual(f.storage.commits.read(), 1)
        f.storage.fails.update { $0 = false }; f.clock.time.update { $0 = 60 }
        f.controller.maintenance(); barrier(f.controller)
        XCTAssertEqual(f.storage.commits.read(), 2)
        XCTAssertTrue(f.values.read()[.network]?.saveText.hasPrefix("Saved") == true)
    }

    func testFailedResetRemainsZeroInMemoryAndReportsUnsaved() {
        let f = Fixture(), reader = Reader(), sampler = f.sampler(reader)
        f.controller.start(); sampler.start(); sampler.sampleNow()
        f.clock.time.update { $0 = 1 }; reader.bytes.update { $0 = 100 }; sampler.sampleNow()
        barrier(f.controller); expectTotal(f, 100)
        f.clock.time.update { $0 = 2 }; f.storage.fails.update { $0 = true }
        let done = expectation(description: "Reset unsaved")
        f.controller.requestReset(stat: .network, requestID: UUID(), performBoundaryReset: { sampler.requestReset(requestID: $0) }) { error in
            XCTAssertTrue(error?.contains("unsaved") == true); done.fulfill()
        }
        wait(for: [done], timeout: 4); barrier(f.controller); expectTotal(f, 0)
        XCTAssertEqual(f.values.read()[.network]?.selectedTotals.first.exactValue, TransferHistoryFormat.exactBytes(100))
        XCTAssertNotNil(flush(f.controller)); sampler.stop()
    }

    func testSlowQuitFlushIsAsynchronousAndCompletesOnlyAfterCommit() {
        let f = Fixture(), generation = UUID(); f.controller.start(); f.controller.admitGeneration(generation, for: .network)
        barrier(f.controller); f.storage.blocksCommit.update { $0 = true }
        let completed = Box(false), done = expectation(description: "Slow flush completes")
        f.controller.flush { error in XCTAssertNil(error); completed.update { $0 = true }; done.fulfill() }
        XCTAssertEqual(f.storage.enteredCommit.wait(timeout: .now() + 2), .success)
        XCTAssertFalse(completed.read()) // Returning from flush is not a durability acknowledgement.
        // NSApplication's two-second termination deadline is owned by AppDelegate and reviewed separately.
        f.storage.releaseCommit.signal(); wait(for: [done], timeout: 4)
        XCTAssertTrue(completed.read())
    }

    func testDirtyCollectionKeepsRecoveryWarningVisible() throws {
        let f = Fixture(), generation = UUID()
        try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
        try Data([0, 1, 2]).write(to: f.root.appendingPathComponent("checkpoint"))
        f.controller.start(); barrier(f.controller)
        f.controller.admitGeneration(generation, for: .network)
        f.controller.ingest(observation(f, generation: generation, sequence: 1, start: 0, end: 1, bytes: 100))
        barrier(f.controller); expectTotal(f, 100)
        XCTAssertTrue(f.values.read()[.network]?.saveText.hasPrefix("Unsaved") == true)
        XCTAssertTrue(f.values.read()[.network]?.warningText.contains("could not be recovered") == true)
    }

    func testSelectedRangeCoalescesAndUsesLatestSelectionWithoutBodyQueries() {
        let f = Fixture(), generation = UUID(); f.controller.start(); f.controller.admitGeneration(generation, for: .network)
        barrier(f.controller); let count = f.publications.read()
        for _ in 0..<50 { f.controller.selectPeriod(.day, for: .network); f.controller.selectPeriod(.hour, for: .network) }
        f.controller.selectPeriod(.minute, for: .network); barrier(f.controller)
        XCTAssertEqual(f.publications.read() - count, 1)
        XCTAssertEqual(f.values.read()[.network]?.period, .minute)
    }
}

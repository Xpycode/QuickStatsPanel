import XCTest

/// All sampler tests inject readers, clocks, metadata/capacity and manual scheduling. No timer,
/// hardware enumeration, NSApplication, production profile or persistent store is started.
final class TransferSamplerTests: XCTestCase {
    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value
        init(_ value: Value) { self.value = value }
        func read() -> Value { lock.lock(); defer { lock.unlock() }; return value }
        func update(_ body: (inout Value) -> Void) { lock.lock(); defer { lock.unlock() }; body(&value) }
    }
    private final class Clock: TransferClock, @unchecked Sendable {
        let time = Box<TimeInterval>(0)
        func now() -> TransferTimestamp {
            TransferTimestamp(continuousTime: time.read(), wallTime: Date(timeIntervalSince1970: time.read()), bootID: "fixture-boot")
        }
    }
    private final class Reader: TransferCounterReader, @unchecked Sendable {
        let stat: TransferStat
        let sources = Box<[TransferSourceCounter]>([])
        let enumeration = Box<TransferEnumeration>(.complete)
        let reads = Box(0)
        var beforeRead: (@Sendable () -> Void)?
        init(_ stat: TransferStat = .network) { self.stat = stat }
        func read(generation: UUID, sequence: UInt64, timestamp: TransferTimestamp) -> TransferCounterSnapshot {
            beforeRead?()
            reads.update { $0 += 1 }
            return TransferCounterSnapshot(stat: stat, generation: generation, sequence: sequence,
                timestamp: timestamp, enumeration: enumeration.read(), sources: sources.read())
        }
    }
    private func source(_ value: UInt64?, id: UInt64 = 1) -> TransferSourceCounter {
        TransferSourceCounter(id: .disk(registryID: id), bytes: value.map { TransferBytes(first: $0, second: $0 / 2) })
    }
    private func observations(_ events: [TransferEvent]) -> [TransferObservation] {
        events.compactMap { if case .observation(let value) = $0 { return value }; return nil }
    }
    private func sampler(reader: Reader, clock: Clock, events: Box<[TransferEvent]>, samples: Box<[NetworkSample]>) -> NetworkSampler {
        NetworkSampler(reader: reader, clock: clock, automaticallySchedules: false,
            metadataProvider: { ("Fixture", "192.0.2.1") }, onTransferEvent: { event in events.update { $0.append(event) } },
            onSample: { sample in samples.update { $0.append(sample) } })
    }

    func testFirstReadingSeedsAndDelayedTickUsesExactElapsedBeyondFourGiB() throws {
        let reader = Reader(); let clock = Clock(); let events = Box<[TransferEvent]>([]); let samples = Box<[NetworkSample]>([])
        let sampler = sampler(reader: reader, clock: clock, events: events, samples: samples)
        reader.sources.update { $0 = [source(5_000_000_000)] }
        sampler.start(); sampler.sampleNow()
        XCTAssertTrue(events.read().isEmpty)
        XCTAssertEqual(samples.read().last?.downBytesPerSec, 0)
        clock.time.update { $0 = 2 }; reader.sources.update { $0 = [source(5_020_000_000)] }; sampler.sampleNow()
        let observation = try XCTUnwrap(observations(events.read()).last)
        XCTAssertEqual(observation.interval.bytes, TransferBytes(first: 20_000_000, second: 10_000_000))
        XCTAssertEqual(observation.interval.coverage, .complete)
        XCTAssertEqual(samples.read().last?.downBytesPerSec, 10_000_000)
        XCTAssertEqual(samples.read().last?.interfaceName, "Fixture")
        sampler.stop()
    }

    func testMembershipCounterDecreaseDuplicatesAndFailurePreserveHealthyPeer() throws {
        let reader = Reader(); let clock = Clock(); let events = Box<[TransferEvent]>([]); let samples = Box<[NetworkSample]>([])
        let sampler = sampler(reader: reader, clock: clock, events: events, samples: samples)
        func tick(_ time: Double, _ sources: [TransferSourceCounter]) {
            clock.time.update { $0 = time }; reader.sources.update { $0 = sources }; sampler.sampleNow()
        }
        sampler.start(); tick(0, [source(100), source(100, id: 2)])
        tick(1, [source(200), source(10, id: 2)]) // Counter decrease only discards that source.
        XCTAssertEqual(observations(events.read()).last?.interval.bytes.first, 100)
        XCTAssertEqual(observations(events.read()).last?.interval.coverage, .partial)
        tick(2, [source(300), source(20, id: 2), source(999, id: 2)])
        XCTAssertEqual(observations(events.read()).last?.interval.bytes.first, 100)
        tick(3, [source(400), source(nil, id: 2)])
        XCTAssertEqual(observations(events.read()).last?.interval.bytes.first, 100)
        tick(4, [source(500), source(10_000, id: 2)]) // Unreadable peer must seed, no catch-up.
        XCTAssertEqual(observations(events.read()).last?.interval.bytes.first, 100)
        tick(5, [source(600)]) // Removal retains healthy delta and partial coverage.
        XCTAssertEqual(observations(events.read()).last?.interval.bytes.first, 100)
        XCTAssertEqual(observations(events.read()).last?.interval.coverage, .partial)
        reader.enumeration.update { $0 = .failed }; tick(6, [source(700)])
        XCTAssertEqual(observations(events.read()).last?.interval.coverage, .missing)
        reader.enumeration.update { $0 = .complete }; tick(7, [source(10_000)])
        XCTAssertEqual(observations(events.read()).last?.interval.coverage, .missing)
        tick(8, [source(10_100)])
        XCTAssertEqual(observations(events.read()).last?.interval.bytes.first, 100)
        sampler.stop()
    }

    func testDiscontinuityAndLongDelayRebaselineWithoutCatchup() throws {
        let reader = Reader(); let clock = Clock(); let events = Box<[TransferEvent]>([]); let samples = Box<[NetworkSample]>([])
        let sampler = sampler(reader: reader, clock: clock, events: events, samples: samples)
        sampler.start(); reader.sources.update { $0 = [source(100)] }; sampler.sampleNow()
        clock.time.update { $0 = 11 }; reader.sources.update { $0 = [source(10_000)] }; sampler.sampleNow()
        XCTAssertEqual(observations(events.read()).last?.interval.coverage, .missing)
        sampler.invalidate()
        clock.time.update { $0 = 12 }; reader.sources.update { $0 = [source(20_000)] }; sampler.sampleNow()
        XCTAssertEqual(observations(events.read()).last?.interval.coverage, .missing)
        clock.time.update { $0 = 13 }; reader.sources.update { $0 = [source(20_100)] }; sampler.sampleNow()
        XCTAssertEqual(observations(events.read()).last?.interval.bytes.first, 100)
        sampler.stop()
    }

    func testResetEmitsBoundaryBeforeMarkerAndRejectsDuplicateAdmissionAcrossRestarts() throws {
        let reader = Reader(); let clock = Clock(); let events = Box<[TransferEvent]>([]); let samples = Box<[NetworkSample]>([])
        let sampler = sampler(reader: reader, clock: clock, events: events, samples: samples)
        reader.sources.update { $0 = [source(100)] }; sampler.start(); sampler.sampleNow()
        clock.time.update { $0 = 2 }; reader.sources.update { $0 = [source(300)] }
        let requestID = UUID()
        XCTAssertTrue(sampler.requestReset(requestID: requestID))
        let values = events.read()
        XCTAssertEqual(values.count, 2)
        guard case .observation(let boundary) = values[0], case .reset(let marker) = values[1] else { return XCTFail("Reset must follow boundary") }
        XCTAssertEqual(boundary.interval.bytes.first, 200)
        XCTAssertEqual(marker.sequence, boundary.sequence + 1)
        XCTAssertEqual(marker.timestamp, boundary.timestamp)
        XCTAssertEqual(marker.requestID, requestID)
        let readCount = reader.reads.read()
        XCTAssertFalse(sampler.requestReset(requestID: UUID()))
        XCTAssertEqual(reader.reads.read(), readCount)
        sampler.stop(); sampler.start()
        XCTAssertFalse(sampler.requestReset(requestID: UUID()), "Restart must not bypass resource admission")
        clock.time.update { $0 = 3 }
        XCTAssertFalse(sampler.requestReset(requestID: requestID), "Retrying same accepted request must not reset again")
        XCTAssertTrue(sampler.requestReset(requestID: UUID()))
        sampler.stop(); XCTAssertFalse(sampler.requestReset())
    }

    func testFailedResetBoundaryAndSameTimestampBoundaryCannotBackfillNewEpoch() throws {
        let reader = Reader(); let clock = Clock(); let events = Box<[TransferEvent]>([]); let samples = Box<[NetworkSample]>([])
        let sampler = sampler(reader: reader, clock: clock, events: events, samples: samples)
        sampler.start(); reader.sources.update { $0 = [source(100)] }; sampler.sampleNow()
        clock.time.update { $0 = 1 }; reader.sources.update { $0 = [source(200)] }; sampler.sampleNow()
        reader.sources.update { $0 = [source(300)] }
        let readCount = reader.reads.read()
        XCTAssertFalse(sampler.requestReset()) // Identical capture time has no valid elapsed interval.
        clock.time.update { $0 = 0.5 }
        XCTAssertFalse(sampler.requestReset()) // Reversed time must not move the cumulative boundary.
        XCTAssertEqual(reader.reads.read(), readCount)
        clock.time.update { $0 = 2 }; reader.sources.update { $0 = [source(400)] }; sampler.sampleNow()
        XCTAssertEqual(observations(events.read()).last?.interval.bytes.first, 200)
        reader.enumeration.update { $0 = .failed }; clock.time.update { $0 = 3 }
        XCTAssertTrue(sampler.requestReset())
        guard case .reset = events.read().last else { return XCTFail("Failed boundary still orders reset") }
        XCTAssertEqual(observations(events.read()).last?.interval.coverage, .missing)
        reader.enumeration.update { $0 = .complete }; clock.time.update { $0 = 4 }
        reader.sources.update { $0 = [source(10_000)] }; sampler.sampleNow()
        XCTAssertEqual(observations(events.read()).last?.interval.bytes, .zero)
        sampler.stop()
    }

    func testGenerationRegisteredBeforeCallbacksAndOldQueuedTickRejected() {
        let reader = Reader(); let clock = Clock(); let admitted = Box<[UUID]>([]); let callbacks = Box<[UUID]>([])
        let sampler = NetworkSampler(reader: reader, clock: clock, automaticallySchedules: false,
            metadataProvider: { (nil, nil) }, onGeneration: { run in admitted.update { $0.append(run) } },
            onSampleWithIdentity: { _, run, _ in
                XCTAssertTrue(admitted.read().contains(run)); callbacks.update { $0.append(run) }
            }, onSample: { _ in })
        let old = sampler.start(); sampler.sampleNow(); sampler.stop()
        let new = sampler.start()
        XCTAssertNotEqual(old, new)
        sampler.sampleNow(expectedGeneration: old)
        XCTAssertEqual(reader.reads.read(), 1)
        sampler.sampleNow(expectedGeneration: new)
        XCTAssertEqual(callbacks.read(), [old, new])
        XCTAssertEqual(sampler.sequence, 1)
        sampler.stop(); sampler.sampleNow(); XCTAssertEqual(reader.reads.read(), 2)
    }

    func testStopDrainsInFlightReadAndCallbackBeforeReturning() {
        let reader = Reader(); let clock = Clock()
        let entered = DispatchSemaphore(value: 0); let release = DispatchSemaphore(value: 0)
        let stopEntered = DispatchSemaphore(value: 0); let stopped = DispatchSemaphore(value: 0)
        let sampleCompleted = Box(false)
        reader.beforeRead = { entered.signal(); release.wait() }
        let sampler = NetworkSampler(reader: reader, clock: clock, automaticallySchedules: false,
            metadataProvider: { (nil, nil) }, onSample: { _ in sampleCompleted.update { $0 = true } })
        sampler.start()
        DispatchQueue.global().async { sampler.sampleNow() }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async { stopEntered.signal(); sampler.stop(); stopped.signal() }
        XCTAssertEqual(stopEntered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(stopped.wait(timeout: .now()), .timedOut)
        release.signal()
        XCTAssertEqual(stopped.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(sampleCompleted.read())
        sampler.sampleNow(); XCTAssertEqual(reader.reads.read(), 1)
    }

    func testDiskCapacityStaysIndependentOfMissingIOAndCadenceIsClamped() {
        let reader = Reader(.disk); let clock = Clock(); let samples = Box<[DiskSample]>([])
        let sampler = DiskSampler(interval: 0, reader: reader, clock: clock, automaticallySchedules: false,
            capacityProvider: { (used: 60, free: 40, total: 100) }, onSample: { sample in samples.update { $0.append(sample) } })
        XCTAssertEqual(sampler.interval, 0.25)
        sampler.start(); sampler.sampleNow(); clock.time.update { $0 = 1 }; sampler.sampleNow()
        XCTAssertEqual(samples.read().last?.usedBytes, 60)
        XCTAssertEqual(samples.read().last?.readBytesPerSec, 0)
        sampler.stop()
        let network = NetworkSampler(interval: .infinity, reader: Reader(), clock: clock,
            automaticallySchedules: false, metadataProvider: { (nil, nil) }, onSample: { _ in })
        XCTAssertEqual(network.interval, 1)
        XCTAssertEqual(TransferCadence.effective(10), 5)
    }

    func testDiskReaderRejectsUnpairedInvalidAndFloatingCounters() {
        let valid: [String: Any] = ["Bytes (Read)": NSNumber(value: UInt64(5_000_000_000)), "Bytes (Write)": NSNumber(value: UInt64(6_000_000_000))]
        XCTAssertEqual(DiskTransferCounterReader.pairedCounters(valid)?.first, 5_000_000_000)
        XCTAssertNil(DiskTransferCounterReader.pairedCounters(["Bytes (Read)": NSNumber(value: UInt64(5_000_000_000))]))
        XCTAssertNil(DiskTransferCounterReader.pairedCounters(["Bytes (Read)": true, "Bytes (Write)": NSNumber(value: UInt64(6_000_000_000))]))
        XCTAssertNil(DiskTransferCounterReader.pairedCounters(["Bytes (Read)": NSNumber(value: -5_000_000_000 as Int64), "Bytes (Write)": NSNumber(value: UInt64(6_000_000_000))]))
        XCTAssertNil(DiskTransferCounterReader.pairedCounters(["Bytes (Read)": NSNumber(value: 5_000_000_000.5), "Bytes (Write)": NSNumber(value: UInt64(6_000_000_000))]))
    }

    func testDiskReaderExcludesVirtualAndInvalidatesUnknownDuplicateAndStackedSources() {
        func record(_ id: UInt64, _ layer: TransferStorageLayer = .physical, ancestors: Set<UInt64>? = []) -> DiskTransferRecord {
            DiskTransferRecord(registryID: id, layer: layer, bytes: TransferBytes(first: 10, second: 20), blockDriverAncestors: ancestors)
        }
        let values = DiskTransferCounterReader.sources(from: [record(1), record(2, .excludedVirtual), record(3, .unknown),
            record(4), record(4), record(5, ancestors: [6]), record(6), record(7, ancestors: nil)])
        XCTAssertEqual(values.count, 7)
        XCTAssertEqual(values.filter { $0.bytes != nil }.map(\.id), [.disk(registryID: 1)])
        XCTAssertFalse(values.contains { $0.id == .disk(registryID: 2) })
    }
}

import XCTest
import Darwin

/// Real filesystem integration, with disposable injected roots only. No app startup, preferences,
/// counters, timers or production Application Support. Controller ordering is tested separately.
final class TransferPersistenceTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDownWithError() throws {
        for root in roots { if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) } }
        roots.removeAll()
    }
    private func directory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qsp-persistence-\(UUID().uuidString)")
        roots.append(root); return root
    }
    private func time(_ value: Double) -> TransferTimestamp {
        TransferTimestamp(continuousTime: value, wallTime: Date(timeIntervalSince1970: 1_000_000 + value), bootID: "boot")
    }
    private func fixture(_ value: UInt64 = 100, end: Double = 600) -> TransferTimelineSnapshot {
        var timeline = TransferTimeline(now: time(0))
        for stat in TransferStat.allCases {
            let id = UUID(); _ = timeline.admitGeneration(id, for: stat, admission: 1)
            for (sequence, interval) in [(UInt64(1), (0.0, 1.0)), (2, (end - 1, end))] {
                _ = timeline.ingest(.observation(TransferObservation(generation: id, sequence: sequence,
                    timestamp: time(interval.1), interval: TransferInterval(start: interval.0, end: interval.1,
                        bytes: TransferBytes(first: value, second: value / 2), stat: stat, coverage: .complete), accountingOverflow: false)))
            }
        }
        return timeline.snapshot(now: time(end))
    }
    private func files(_ root: URL) throws -> [URL] { try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }
    private func segment(_ root: URL) throws -> URL { try XCTUnwrap(files(root).first { $0.lastPathComponent.hasPrefix("segment-") }) }

    func testRoundTripRetainsPairedTotalsWatermarksAndEpochs() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root), snapshot = fixture()
        XCTAssertNil(repository.load(now: time(600)).snapshot)
        let saved = repository.commit(snapshot)
        XCTAssertTrue(saved.isDurable, saved.message ?? "")
        XCTAssertEqual(saved.savedAt, time(600).wallTime)
        let loaded = TransferHistoryRepository(root: root).load(now: time(601))
        let restored = try XCTUnwrap(loaded.snapshot)
        XCTAssertEqual(restored.stats.map(\.cumulative), snapshot.stats.map(\.cumulative))
        XCTAssertEqual(restored.stats.map(\.watermark), snapshot.stats.map(\.watermark))
        XCTAssertEqual(restored.stats.map { $0.segments.reduce(0) { $0 + $1.records.count } }, [2, 2])
        XCTAssertEqual(saved.savedWatermarks[.network]?.sequence, 2)
        XCTAssertEqual(restored.stats[0].segments[0].records.first?.bytes, TransferBytes(first: 100, second: 50))
    }
    func testCorruptSealedSegmentBecomesGapWithoutLosingCumulative() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root)
        _ = repository.load(now: time(0)); XCTAssertTrue(repository.commit(fixture()).isDurable)
        try Data([0, 1, 2]).write(to: segment(root))
        let loaded = TransferHistoryRepository(root: root).load(now: time(601))
        XCTAssertTrue(loaded.status.diagnostics.contains(.corruptSegment))
        XCTAssertEqual(loaded.snapshot?.stats.map { $0.cumulative.bytes.first }, [200, 200])
        XCTAssertEqual(loaded.snapshot?.stats.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.records.count } }, 3)
    }
    func testTruncatedCheckpointFallsBackWithSavedTimeAndPossibleLoss() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root)
        _ = repository.load(now: time(0)); XCTAssertTrue(repository.commit(fixture(100)).isDurable)
        XCTAssertTrue(repository.commit(fixture(200, end: 601)).isDurable)
        try Data([1, 2]).write(to: root.appendingPathComponent("checkpoint"))
        let loaded = TransferHistoryRepository(root: root).load(now: time(602))
        XCTAssertTrue(loaded.status.diagnostics.contains(.staleCheckpoint))
        XCTAssertEqual(loaded.status.savedAt, time(600).wallTime)
        XCTAssertEqual(loaded.snapshot?.stats[0].cumulative.bytes.first, 200)
        XCTAssertTrue(loaded.status.message?.contains("lost") == true)
    }
    func testUnsupportedCheckpointAndSegmentVersionsRemainUntouched() throws {
        for alterSegment in [false, true] {
            let root = directory(), repository = TransferHistoryRepository(root: root)
            _ = repository.load(now: time(0)); XCTAssertTrue(repository.commit(fixture()).isDurable)
            let target = try alterSegment ? segment(root) : root.appendingPathComponent("checkpoint")
            var bytes = try Data(contentsOf: target); bytes[8] = 2; try bytes.write(to: target)
            let names = try files(root).map(\.lastPathComponent).sorted()
            let reopened = TransferHistoryRepository(root: root), loaded = reopened.load(now: time(601))
            XCTAssertTrue(loaded.status.writeBlocked)
            XCTAssertTrue(loaded.status.diagnostics.contains(.unsupportedVersion))
            XCTAssertFalse(reopened.commit(fixture()).isDurable)
            _ = reopened.prune()
            XCTAssertEqual(try Data(contentsOf: target), bytes)
            XCTAssertEqual(try files(root).map(\.lastPathComponent).sorted(), names)
        }
    }
    func testMissingCumulativeExplicitlyRequiresNewEpochAndQuarantineIsBounded() throws {
        let root = directory(); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let corrupt = Data(repeating: 42, count: 200)
        try corrupt.write(to: root.appendingPathComponent("checkpoint"))
        for _ in 0..<3 {
            let loaded = TransferHistoryRepository(root: root).load(now: time(600))
            XCTAssertNil(loaded.snapshot)
            XCTAssertTrue(loaded.status.diagnostics.contains(.missingCumulative))
            XCTAssertTrue(loaded.status.message?.contains("new cumulative epoch") == true)
        }
        XCTAssertEqual(try files(root).filter { $0.lastPathComponent == "quarantine" }.count, 1)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("quarantine")), corrupt)
    }
    func testCrashAtEveryCommitStageRecoversOneWholeCheckpoint() throws {
        struct Crash: Error {}
        for stage in TransferCommitStage.allCases {
            let root = directory(), first = TransferHistoryRepository(root: root)
            _ = first.load(now: time(0)); XCTAssertTrue(first.commit(fixture(100)).isDurable)
            let crashing = TransferHistoryRepository(root: root, faultInjector: { if $0 == stage { throw Crash() } })
            _ = crashing.load(now: time(600))
            XCTAssertEqual(crashing.commit(fixture(200, end: 601)).isDurable, [.currentReplaced, .garbageCollected].contains(stage))
            let loaded = TransferHistoryRepository(root: root).load(now: time(602))
            let expected: UInt64 = [.currentReplaced, .garbageCollected].contains(stage) ? 400 : 200
            XCTAssertEqual(loaded.snapshot?.stats.map { $0.cumulative.bytes.first }, [expected, expected], "\(stage)")
            XCTAssertEqual(loaded.snapshot?.stats.map { $0.segments.reduce(0) { $0 + $1.records.count } }, [2, 2], "\(stage)")
        }
    }
    func testPriorReferencesAreKeptUntilBothCheckpointsReleaseThem() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root)
        _ = repository.load(now: time(0)); XCTAssertTrue(repository.commit(fixture()).isDurable)
        let old = try segment(root)
        var empty = fixture(200, end: 700)
        for i in empty.stats.indices { empty.stats[i].segments = [] }
        XCTAssertTrue(repository.commit(empty).isDurable); XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(repository.commit(empty).isDurable); XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }
    func testPrunedSliceWithStableIDGetsDistinctImmutableFile() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root)
        _ = repository.load(now: time(0))
        var snapshot = fixture()
        var first = snapshot.stats[0].segments[0]
        first.records.append(TransferInterval(start: 1, end: 2, bytes: TransferBytes(first: 5, second: 2), stat: .network, coverage: .complete))
        snapshot.stats[0].segments[0] = first
        XCTAssertTrue(repository.commit(snapshot).isDurable)
        let before = Set(try files(root).filter { $0.lastPathComponent.hasPrefix("segment-") }.map(\.lastPathComponent))
        snapshot.stats[0].segments[0].records.removeFirst()
        XCTAssertTrue(repository.commit(snapshot).isDurable)
        let after = Set(try files(root).filter { $0.lastPathComponent.hasPrefix("segment-") }.map(\.lastPathComponent))
        XCTAssertEqual(after.subtracting(before).count, 1)
        XCTAssertTrue(before.isSubset(of: after))
        let loaded = TransferHistoryRepository(root: root).load(now: time(601))
        XCTAssertEqual(loaded.snapshot?.stats[0].segments[0].records.first?.bytes.first, 5)
    }
    func testResetAndDuplicateWatermarksSurviveRestartWithoutReplay() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root)
        _ = repository.load(now: time(0))
        var snapshot = fixture()
        let originalDisk = snapshot.stats[1].cumulative
        snapshot.stats[0].cumulative = TransferCumulativeEpoch(bytes: .zero, startedAt: time(600).wallTime, accountingOverflow: false)
        snapshot.stats[0].watermark.sequence = 3
        XCTAssertTrue(repository.commit(snapshot).isDurable)
        let loaded = try XCTUnwrap(TransferHistoryRepository(root: root).load(now: time(601)).snapshot)
        XCTAssertEqual(loaded.stats[0].cumulative.bytes, .zero); XCTAssertEqual(loaded.stats[1].cumulative, originalDisk)
        var timeline = TransferTimeline(restoring: loaded, now: time(601))
        let generation = try XCTUnwrap(loaded.stats[0].watermark.generation)
        let replay = TransferEvent.reset(TransferResetMarker(stat: .network, generation: generation, sequence: 3, timestamp: time(600), requestID: UUID()))
        XCTAssertFalse(timeline.ingest(replay))
        XCTAssertEqual(timeline.retainedIntervalCount(for: .network), 2)
    }
    func testStorageFailureDoesNotClaimUnsavedStateDurable() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root)
        _ = repository.load(now: time(0)); XCTAssertTrue(repository.commit(fixture()).isDurable)
        let saved = repository.commit(fixture()).savedAt
        try FileManager.default.removeItem(at: root)
        try Data([1]).write(to: root)
        let failed = repository.commit(fixture(300, end: 601))
        XCTAssertFalse(failed.isDurable); XCTAssertEqual(failed.savedAt, saved)
        XCTAssertTrue(failed.diagnostics.contains(.storageFailure))
    }
    func testOversizedCountsLengthsAndFileFloodAreRejectedBeforePayloadAllocation() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root)
        _ = repository.load(now: time(0)); XCTAssertTrue(repository.commit(fixture()).isDurable)
        let checkpoint = root.appendingPathComponent("checkpoint")
        try Data(repeating: 0, count: TransferHistoryRepository.maximumCheckpointBytes + 1).write(to: checkpoint)
        XCTAssertNil(TransferHistoryRepository(root: root).load(now: time(601)).snapshot)
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0...TransferHistoryRepository.maximumFiles { _ = FileManager.default.createFile(atPath: root.appendingPathComponent("extra\(index)").path, contents: Data()) }
        let loaded = TransferHistoryRepository(root: root).load(now: time(600))
        XCTAssertTrue(loaded.status.diagnostics.contains(.resourceLimit))
    }
    private func rewriteChecksum(_ data: inout Data) {
        var checksum: UInt64 = 14_695_981_039_346_656_037
        for byte in data.prefix(data.count - 8) { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
        for index in 0..<8 { data[data.count - 8 + index] = UInt8(truncatingIfNeeded: checksum >> (8 * index)) }
    }
    func testChecksummedDeclaredCountsAreBoundedBeforeReserve() throws {
        for changeCheckpoint in [false, true] {
            let root = directory(), repository = TransferHistoryRepository(root: root)
            _ = repository.load(now: time(0)); XCTAssertTrue(repository.commit(fixture()).isDurable)
            let target = try changeCheckpoint ? root.appendingPathComponent("checkpoint") : segment(root)
            var bytes = try Data(contentsOf: target)
            // Fixture boot ID is four UTF-8 bytes, both watermarks contain generation/sequence/time.
            // This is the network reference-count field, or the segment record-count field.
            let offset = changeCheckpoint ? 128 : 16
            for index in offset..<(offset + 4) { bytes[index] = 255 }
            rewriteChecksum(&bytes); try bytes.write(to: target)
            let loaded = TransferHistoryRepository(root: root).load(now: time(601))
            if changeCheckpoint {
                XCTAssertNil(loaded.snapshot); XCTAssertTrue(loaded.status.diagnostics.contains(.missingCumulative))
            } else {
                XCTAssertEqual(loaded.snapshot?.stats[0].cumulative.bytes.first, 200)
                XCTAssertTrue(loaded.status.diagnostics.contains(.corruptSegment))
            }
        }
    }
    func testOversizedFutureFormatIsPreservedWithoutOverwrite() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root)
        _ = repository.load(now: time(0)); XCTAssertTrue(repository.commit(fixture()).isDurable)
        let checkpoint = root.appendingPathComponent("checkpoint")
        var bytes = try Data(contentsOf: checkpoint); bytes[8] = 2
        bytes.append(Data(repeating: 0, count: TransferHistoryRepository.maximumCheckpointBytes))
        try bytes.write(to: checkpoint)
        let reopened = TransferHistoryRepository(root: root)
        XCTAssertTrue(reopened.load(now: time(601)).status.writeBlocked)
        XCTAssertFalse(reopened.commit(fixture()).isDurable)
        _ = reopened.prune()
        XCTAssertEqual(try Data(contentsOf: checkpoint), bytes)
    }
    func testUnreadableCurrentRecoversPriorAndBlocksOverwrite() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root)
        _ = repository.load(now: time(0)); XCTAssertTrue(repository.commit(fixture(100)).isDurable)
        XCTAssertTrue(repository.commit(fixture(200, end: 601)).isDurable)
        let checkpoint = root.appendingPathComponent("checkpoint")
        let bytes = try Data(contentsOf: checkpoint)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: checkpoint.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: checkpoint.path) }
        let reopened = TransferHistoryRepository(root: root), loaded = reopened.load(now: time(602))
        XCTAssertEqual(loaded.snapshot?.stats[0].cumulative.bytes.first, 200)
        XCTAssertTrue(loaded.status.diagnostics.contains(.staleCheckpoint)); XCTAssertTrue(loaded.status.writeBlocked)
        XCTAssertFalse(reopened.commit(fixture()).isDurable)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: checkpoint.path)
        XCTAssertEqual(try Data(contentsOf: checkpoint), bytes)
    }
    func testExcessInventoryStillRecoversAuthoritativeCumulative() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root)
        _ = repository.load(now: time(0)); XCTAssertTrue(repository.commit(fixture()).isDurable)
        for index in 0...TransferHistoryRepository.maximumFiles {
            _ = FileManager.default.createFile(atPath: root.appendingPathComponent("extra-\(index)").path, contents: Data())
        }
        let loaded = TransferHistoryRepository(root: root).load(now: time(601))
        XCTAssertTrue(loaded.status.diagnostics.contains(.resourceLimit))
        XCTAssertFalse(loaded.status.diagnostics.contains(.missingCumulative))
        XCTAssertEqual(loaded.snapshot?.stats.map { $0.cumulative.bytes.first }, [200, 200])
        // Active records are small and recoverable; sealed records remain on disk, unallocated.
        XCTAssertEqual(loaded.snapshot?.stats.map { $0.segments.reduce(0) { $0 + $1.records.count } }, [1, 1])
    }
    func testValidChecksumWithOutOfRangeSegmentBecomesOnlyAGap() throws {
        let root = directory(), repository = TransferHistoryRepository(root: root)
        _ = repository.load(now: time(0)); XCTAssertTrue(repository.commit(fixture()).isDurable)
        let target = try segment(root)
        var bytes = try Data(contentsOf: target)
        let invalidEnd = Double(900).bitPattern
        for index in 0..<8 { bytes[32 + index] = UInt8(truncatingIfNeeded: invalidEnd >> (8 * index)) }
        rewriteChecksum(&bytes); try bytes.write(to: target)
        let loaded = TransferHistoryRepository(root: root).load(now: time(601))
        XCTAssertTrue(loaded.status.diagnostics.contains(.corruptSegment))
        XCTAssertEqual(loaded.snapshot?.stats.map { $0.cumulative.bytes.first }, [200, 200])
        XCTAssertEqual(loaded.snapshot?.stats.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.records.count } }, 3)
    }
    private func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        XCTAssertEqual(result, KERN_SUCCESS, "Memory measurement must succeed.")
        XCTAssertGreaterThan(info.resident_size, 0)
        return info.resident_size
    }
    func testActualWorstDayDiskMemoryAndIncrementalCheckpointSize() throws {
        let root = directory()
        var peakAllocated = 0
        var peakResident: UInt64 = 0
        let repository = TransferHistoryRepository(root: root, faultInjector: { _ in
            let allocation = try self.files(root).reduce(0) { try $0 + $1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize! }
            peakAllocated = max(peakAllocated, allocation)
            peakResident = max(peakResident, self.residentBytes())
        })
        _ = repository.load(now: time(0))
        let baseline = residentBytes()
        var snapshot: TransferTimelineSnapshot? = {
            var states: [TransferTimelineStatSnapshot] = []
            for stat in TransferStat.allCases {
                var segments: [TransferTimelineSegment] = []
                for chunk in 0..<288 {
                    var records: [TransferInterval] = []; records.reserveCapacity(1_502)
                    for second in 0..<300 {
                        let base = Double(chunk * 300 + second)
                        let edges = [0.0, 0.125, 0.25, 0.5, 0.75, 1.0]
                        for index in 0..<5 { records.append(TransferInterval(start: base + edges[index], end: base + edges[index + 1], bytes: TransferBytes(first: 1, second: 2), stat: stat, coverage: .complete)) }
                    }
                    segments.append(TransferTimelineSegment(id: UUID(), stat: stat, records: records[...], isSealed: chunk < 287))
                }
                states.append(TransferTimelineStatSnapshot(stat: stat, cumulative: TransferCumulativeEpoch(bytes: TransferBytes(first: 432_000, second: 864_000), startedAt: time(0).wallTime, accountingOverflow: false), watermark: TransferTimelineWatermark(generation: UUID(), admission: 1, sequence: 518_400, lastEventTime: 86_400), segments: segments))
            }
            return TransferTimelineSnapshot(anchor: TransferTimelineAnchor(continuousTime: 86_400, timelineTime: 86_400, wallTime: time(86_400).wallTime, bootID: "boot"), stats: states, warnings: [])
        }()
        let initial = repository.commit(snapshot!)
        XCTAssertTrue(initial.isDurable, initial.message ?? "")
        XCTAssertLessThan(initial.checkpointBytes, TransferHistoryRepository.maximumCheckpointBytes)
        let sealedFile = try segment(root)
        let modified = try sealedFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        // Same full set of immutable day segments, with a normal 30 seconds of active records.
        // This is an encoding-size fixture; it deliberately omits older active records only.
        var normal = snapshot!
        for i in normal.stats.indices {
            let last = normal.stats[i].segments.count - 1
            normal.stats[i].segments[last].records = normal.stats[i].segments[last].records.suffix(150)
        }
        let normalStatus = repository.commit(normal)
        XCTAssertTrue(normalStatus.isDurable)
        XCTAssertLessThan(normalStatus.checkpointBytes, 100 * 1024)
        // Release the extra snapshot before the independent load/memory measurement.
        normal.stats.removeAll()
        let second = repository.commit(snapshot!)
        XCTAssertTrue(second.isDurable)
        XCTAssertEqual(try sealedFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified)
        let entries = try files(root)
        let logical = try entries.reduce(0) { try $0 + $1.resourceValues(forKeys: [.fileSizeKey]).fileSize! }
        let allocated = try entries.reduce(0) { try $0 + $1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize! }
        peakResident = max(peakResident, residentBytes())
        let savingMemory = peakResident > baseline ? peakResident - baseline : 0
        XCTAssertLessThan(logical, TransferResourceBudget.maximumBytes)
        XCTAssertLessThan(allocated, TransferResourceBudget.maximumBytes)
        XCTAssertLessThan(peakAllocated, TransferResourceBudget.maximumBytes)
        XCTAssertLessThan(savingMemory, UInt64(TransferResourceBudget.maximumBytes))
        // Release the producer snapshot before loading; production never keeps two independent days.
        snapshot = nil
        let loadBaseline = residentBytes()
        let loaded = TransferHistoryRepository(root: root).load(now: time(86_400))
        XCTAssertEqual(loaded.snapshot?.stats.map { $0.segments.reduce(0) { $0 + $1.records.count } }, [432_000, 432_000])
        let loadingResident = residentBytes()
        let loadingMemory = loadingResident > loadBaseline ? loadingResident - loadBaseline : 0
        let totalHistoryResident = loadingResident > baseline ? loadingResident - baseline : 0
        XCTAssertLessThan(totalHistoryResident, UInt64(TransferResourceBudget.maximumBytes))
        XCTAssertLessThan(loadingMemory, UInt64(TransferResourceBudget.maximumBytes))
        print("TransferPersistence worst-day records=864000 packed=34560000 logical=\(logical) allocated=\(allocated) checkpoint=\(initial.checkpointBytes) normal30sCheckpoint=\(normalStatus.checkpointBytes) peakAllocated=\(peakAllocated) savingResidentDelta=\(savingMemory) loadingResidentDelta=\(loadingMemory) totalHistoryResidentDelta=\(totalHistoryResident) files=\(entries.count)")
    }
}

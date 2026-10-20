import XCTest

final class TransferTimelineTests: XCTestCase {
    private let generation = UUID()
    private func time(_ value: Double, wall: Double? = nil, boot: String = "boot") -> TransferTimestamp {
        TransferTimestamp(continuousTime: value, wallTime: Date(timeIntervalSince1970: wall ?? value + 1_000_000), bootID: boot)
    }
    private func observation(_ sequence: UInt64, _ start: Double, _ end: Double, _ first: UInt64,
                             _ second: UInt64 = 0, stat: TransferStat = .network,
                             coverage: TransferCoverage = .complete, overflow: Bool = false,
                             run: UUID? = nil, wall: Double? = nil) -> TransferEvent {
        .observation(TransferObservation(generation: run ?? generation, sequence: sequence,
            timestamp: time(end, wall: wall), interval: TransferInterval(start: start, end: end,
                bytes: TransferBytes(first: first, second: second), stat: stat, coverage: coverage), accountingOverflow: overflow))
    }
    private func fresh() -> TransferTimeline {
        var result = TransferTimeline(now: time(0))
        XCTAssertTrue(result.admitGeneration(generation, for: .network, admission: 1))
        XCTAssertTrue(result.admitGeneration(generation, for: .disk, admission: 1))
        return result
    }
    func testPairedBytesCoverageAndBoundedResolutionShareOneRange() {
        var timeline = fresh()
        XCTAssertTrue(timeline.ingest(observation(1, 0, 2, 20_000_000, 4_000_000)))
        XCTAssertTrue(timeline.ingest(observation(2, 3, 4, 3, 6, coverage: .partial)))
        let result = timeline.query(stat: .network, now: time(5), duration: 5, slotCount: 200)
        XCTAssertEqual(result.bytes, TransferBytes(first: 20_000_003, second: 4_000_006))
        XCTAssertEqual(result.fullyMeasuredDuration, 2)
        XCTAssertEqual(result.partialDuration, 1)
        XCTAssertEqual(result.slots.count, 120)
        XCTAssertEqual(result.slots.reduce(UInt64(0)) { $0 + $1.bytes.first }, result.bytes.first)
        XCTAssertFalse(result.hasBoundaryEstimate)
        XCTAssertEqual(timeline.query(stat: .network, now: time(5), duration: 5, slotCount: 3).bytes, result.bytes)
    }
    func testAdjacentEdgesConserveIntegerRemaindersIncludingUInt64Maximum() {
        var timeline = fresh()
        _ = timeline.ingest(observation(1, 0, 3, 3, .max))
        var first: UInt64 = 0; var second: UInt64 = 0
        for end in 1...3 {
            let piece = timeline.query(stat: .network, now: time(Double(end)), duration: 1, slotCount: 7)
            first += piece.bytes.first; second += piece.bytes.second
            XCTAssertEqual(piece.bytes.first, 1)
            XCTAssertTrue(piece.hasBoundaryEstimate)
            XCTAssertEqual(piece.slots.reduce(UInt64(0)) { $0 + $1.bytes.second }, piece.bytes.second)
        }
        XCTAssertEqual(first, 3); XCTAssertEqual(second, .max)
        XCTAssertEqual(timeline.query(stat: .network, now: time(3), duration: 3).bytes.second, .max)
        XCTAssertEqual(timeline.query(stat: .network, now: time(4), duration: 1).bytes, .zero)
    }
    func testMissingAndIdleDifferAndOverlapsCannotDoubleCountDuration() {
        var timeline = fresh()
        _ = timeline.ingest(observation(1, 0, 1, 0))
        _ = timeline.ingest(observation(2, 1, 2, 0, coverage: .missing))
        XCTAssertFalse(timeline.ingest(observation(3, 0.5, 2.5, 100)))
        XCTAssertTrue(timeline.ingest(observation(3, 2, 3, 7, coverage: .partial)))
        let result = timeline.query(stat: .network, now: time(4), duration: 4, slotCount: 4)
        XCTAssertEqual(result.slots[0].fullyMeasuredDuration, 1)
        XCTAssertEqual(result.slots[1].fullyMeasuredDuration, 0)
        XCTAssertEqual(result.fullyMeasuredDuration + result.partialDuration, 2)
        XCTAssertEqual(result.bytes.first, 7)
    }
    func testGenerationSequenceBootAndResetOrderingAreIndependent() {
        var timeline = fresh()
        _ = timeline.ingest(observation(1, 0, 1, 11))
        _ = timeline.ingest(observation(1, 0, 1, 22, stat: .disk))
        XCTAssertFalse(timeline.ingest(observation(1, 1, 2, 999)))
        let newer = UUID()
        XCTAssertTrue(timeline.admitGeneration(newer, for: .network, admission: 2))
        XCTAssertFalse(timeline.admitGeneration(generation, for: .network, admission: 1))
        XCTAssertFalse(timeline.ingest(observation(2, 1, 2, 999)))
        XCTAssertTrue(timeline.ingest(observation(1, 1, 2, 5, run: newer)))
        XCTAssertTrue(timeline.ingest(.reset(TransferResetMarker(stat: .network, generation: newer,
            sequence: 2, timestamp: time(2), requestID: UUID()))))
        XCTAssertEqual(timeline.cumulative(for: .network).bytes, .zero)
        XCTAssertEqual(timeline.cumulative(for: .network).startedAt, time(2).wallTime)
        XCTAssertEqual(timeline.cumulative(for: .disk).bytes.first, 22)
        XCTAssertEqual(timeline.query(stat: .network, now: time(2), duration: 2).bytes.first, 16)
        XCTAssertFalse(timeline.ingest(.reset(TransferResetMarker(stat: .network, generation: newer,
            sequence: 3, timestamp: time(1), requestID: UUID()))))
    }
    func testCumulativeOverflowIsVisibleAndResetRecoversOnlyChosenEpoch() {
        var timeline = fresh()
        _ = timeline.ingest(observation(1, 0, 1, .max))
        _ = timeline.ingest(observation(2, 1, 2, 1))
        XCTAssertTrue(timeline.cumulative(for: .network).accountingOverflow)
        XCTAssertTrue(timeline.query(stat: .network, now: time(2), duration: 2).accountingOverflow)
        _ = timeline.ingest(.reset(TransferResetMarker(stat: .network, generation: generation,
            sequence: 3, timestamp: time(2), requestID: UUID())))
        XCTAssertFalse(timeline.cumulative(for: .network).accountingOverflow)
        _ = timeline.ingest(observation(4, 2, 3, 0, coverage: .missing, overflow: true))
        XCTAssertTrue(timeline.cumulative(for: .network).accountingOverflow)
    }
    func testMixedCadenceExpiryKeepsOneIntersectingEdgeAndIndependentCumulative() {
        var timeline = fresh()
        _ = timeline.ingest(observation(1, 0, 3, 30))
        _ = timeline.ingest(observation(2, 3, 3.25, 4))
        _ = timeline.ingest(observation(3, 3.25, 8.25, 50))
        timeline.maintenance(now: time(86_402))
        XCTAssertEqual(timeline.query(stat: .network, now: time(86_402), duration: 86_400).bytes.first, 64)
        timeline.maintenance(now: time(86_409))
        XCTAssertEqual(timeline.retainedIntervalCount(for: .network), 0)
        XCTAssertEqual(timeline.cumulative(for: .network).bytes.first, 84)
    }
    func testWallClockChangesDoNotMoveSameBootHistoryAndRestorePrunes() {
        var timeline = fresh()
        _ = timeline.ingest(observation(1, 0, 1, 10, wall: 9_000_000))
        _ = timeline.ingest(observation(2, 1, 2, 20, wall: 1))
        let snapshot = timeline.snapshot(now: time(2, wall: 1))
        let restored = TransferTimeline(restoring: snapshot, now: time(3, wall: 999))
        XCTAssertEqual(restored.query(stat: .network, now: time(3), duration: 3).bytes.first, 30)
        let expired = TransferTimeline(restoring: snapshot, now: time(90_000, wall: 999))
        XCTAssertEqual(expired.retainedIntervalCount(for: .network), 0)
        XCTAssertEqual(expired.cumulative(for: .network).bytes.first, 30)
    }
    func testRebootReanchorsOnceAndAmbiguousClockDropsOnlyHistory() {
        var timeline = fresh()
        _ = timeline.ingest(observation(1, 100, 102, 20))
        let snapshot = timeline.snapshot(now: time(102))
        let reboot = TransferTimeline(restoring: snapshot, now: time(1, wall: 1_000_104, boot: "new"))
        XCTAssertEqual(reboot.query(stat: .network, now: time(1, wall: 1_000_104, boot: "new"), duration: 5).bytes.first, 20)
        let ambiguous = TransferTimeline(restoring: snapshot, now: time(1, wall: 1, boot: "new"))
        XCTAssertEqual(ambiguous.retainedIntervalCount(for: .network), 0)
        XCTAssertEqual(ambiguous.cumulative(for: .network).bytes.first, 20)
        XCTAssertTrue(ambiguous.warnings.contains(.historyClockAmbiguous))
        let impossible = TransferTimeline(restoring: snapshot, now: time(1_000, wall: 1_000_103, boot: "new"))
        XCTAssertEqual(impossible.retainedIntervalCount(for: .network), 0)
        XCTAssertEqual(impossible.cumulative(for: .network).bytes.first, 20)
        XCTAssertTrue(impossible.warnings.contains(.historyClockAmbiguous))
    }
    func testInvalidRestoredIntervalsAreExcludedAndCumulativePreserved() {
        var timeline = fresh()
        _ = timeline.ingest(observation(1, 0, 1, 10))
        var snapshot = timeline.snapshot(now: time(1))
        let malformed = TransferInterval(start: 0.5, end: 1, bytes: .zero, stat: .network, coverage: .complete)
        snapshot.stats[0].segments.append(TransferTimelineSegment(id: UUID(), stat: .network, records: [malformed][...], isSealed: true))
        let restored = TransferTimeline(restoring: snapshot, now: time(2))
        XCTAssertTrue(restored.warnings.contains(.invalidHistory))
        XCTAssertEqual(restored.retainedIntervalCount(for: .network), 0)
        XCTAssertEqual(restored.cumulative(for: .network).bytes.first, 10)
    }
    func testFullDayFastestCadenceIsBoundedWithoutFullDaySnapshotCopies() {
        var timeline = fresh()
        for index in 0..<345_600 {
            let start = Double(index) * 0.25
            _ = timeline.ingest(observation(UInt64(index + 1), start, start + 0.25, 1, 2))
        }
        XCTAssertEqual(timeline.retainedIntervalCount(for: .network), 345_600)
        let snapshot = timeline.snapshot(now: time(86_400))
        XCTAssertLessThanOrEqual(snapshot.stats[0].segments.count, 290)
        XCTAssertTrue(snapshot.stats[0].segments.allSatisfy { $0.records.count <= TransferResourceBudget.maximumRecordsPerSegmentPerStat })
        XCTAssertEqual(timeline.query(stat: .network, now: time(86_400), duration: 86_400).bytes.first, 345_600)
        _ = timeline.ingest(observation(345_601, 86_400, 86_400.25, 1, 2))
        XCTAssertEqual(snapshot.stats[0].segments.reduce(0) { $0 + $1.records.count }, 345_600)
        XCTAssertEqual(timeline.retainedIntervalCount(for: .network), 345_600)
    }
    func testRepeatedRestoreResumesActiveSegmentAndResetBeforeFirstNewObservation() {
        var timeline = fresh()
        _ = timeline.ingest(observation(1, 0, 0.25, 1))
        for index in 1...400 {
            let current = Double(index) * 0.25
            let saved = timeline.snapshot(now: time(current))
            timeline = TransferTimeline(restoring: saved, now: time(current))
            let run = UUID()
            XCTAssertTrue(timeline.admitGeneration(run, for: .network, admission: UInt64(index + 1)))
            XCTAssertTrue(timeline.ingest(observation(1, current, current + 0.25, 1, run: run)))
        }
        XCTAssertEqual(timeline.retainedIntervalCount(for: .network), 401)
        XCTAssertEqual(timeline.cumulative(for: .network).bytes.first, 401)
        XCTAssertFalse(timeline.warnings.contains(.resourceLimit))
        let run = UUID()
        XCTAssertTrue(timeline.admitGeneration(run, for: .network, admission: 402))
        XCTAssertTrue(timeline.ingest(.reset(TransferResetMarker(stat: .network, generation: run,
            sequence: 1, timestamp: time(102), requestID: UUID()))))
        XCTAssertEqual(timeline.cumulative(for: .network).bytes, .zero)
        XCTAssertEqual(timeline.retainedIntervalCount(for: .network), 401)
    }

    func testUnsupportedCadenceBoundsHistoryButNeverDropsCumulativeAccounting() {
        var timeline = fresh()
        let count = TransferResourceBudget.maximumRecordsPerSegmentPerStat + 5
        for index in 0..<count {
            _ = timeline.ingest(observation(UInt64(index + 1), Double(index) / 100, Double(index + 1) / 100, 1))
        }
        XCTAssertTrue(timeline.warnings.contains(.resourceLimit))
        XCTAssertEqual(timeline.retainedIntervalCount(for: .network), TransferResourceBudget.maximumRecordsPerSegmentPerStat)
        XCTAssertEqual(timeline.cumulative(for: .network).bytes.first, UInt64(count))
        XCTAssertEqual(timeline.watermark(for: .network).sequence, UInt64(count))
    }

    func testBothStatsWorstCaseResetBoundaryAllowanceFitsMemoryAndPrunesAtLoad() {
        var timeline = fresh()
        for index in 0..<432_000 {
            let start = Double(index) / 5, end = Double(index + 1) / 5
            for stat in TransferStat.allCases {
                XCTAssertTrue(timeline.ingest(observation(UInt64(index + 1), start, end, 1, 2, stat: stat)))
            }
        }
        var snapshot = timeline.snapshot(now: time(86_400))
        let allocated = snapshot.stats.reduce(0) { total, state in
            total + state.segments.reduce(0) { $0 + $1.records.capacity * MemoryLayout<TransferInterval>.stride }
        }
        XCTAssertLessThan(allocated + 4 * 1024 * 1024, TransferResourceBudget.maximumBytes)
        XCTAssertFalse(timeline.warnings.contains(.resourceLimit))
        let reboot = TransferTimeline(restoring: snapshot, now: time(1, wall: 1_086_401, boot: "new"))
        for stat in TransferStat.allCases {
            XCTAssertEqual(timeline.retainedIntervalCount(for: stat), 432_000)
            XCTAssertEqual(reboot.cumulative(for: stat).bytes.first, 432_000)
        }
        snapshot.anchor.continuousTime = 86_400
        let expired = TransferTimeline(restoring: snapshot, now: time(172_801))
        XCTAssertEqual(expired.retainedIntervalCount(for: .network), 0)
        XCTAssertEqual(expired.cumulative(for: .disk).bytes.second, 864_000)
    }

    func testNextDownSlotBoundaryConservesMaximumIntegerBytes() {
        var timeline = fresh()
        let start = 61.08052334077484, end = 104.79942737218536
        _ = timeline.ingest(observation(1, start, end, .max, .max))
        let result = timeline.query(stat: .network, now: time(end), duration: 74.94669262527518, slotCount: 24)
        XCTAssertEqual(result.bytes.first, .max)
        XCTAssertEqual(result.slots.reduce(UInt64(0)) { $0 + $1.bytes.first }, .max)
        XCTAssertEqual(result.slots.reduce(UInt64(0)) { $0 + $1.bytes.second }, .max)
    }

    func testExtremePersistedAnchorCannotPoisonFreshCollection() {
        var timeline = fresh()
        _ = timeline.ingest(observation(1, 0, 1, 10))
        var snapshot = timeline.snapshot(now: time(1))
        snapshot.anchor.timelineTime = 1e308
        var restored = TransferTimeline(restoring: snapshot, now: time(1e308))
        XCTAssertTrue(restored.warnings.contains(.historyClockAmbiguous))
        XCTAssertEqual(restored.cumulative(for: .network).bytes.first, 10)
        XCTAssertEqual(restored.retainedIntervalCount(for: .network), 0)
        XCTAssertTrue(restored.query(stat: .network, now: time(1e308), duration: 60).end.isFinite)
        let run = UUID()
        XCTAssertTrue(restored.admitGeneration(run, for: .network, admission: 2))
        XCTAssertTrue(restored.ingest(observation(1, 1, 2, 1, run: run)))
        XCTAssertEqual(restored.cumulative(for: .network).bytes.first, 11)
    }

}

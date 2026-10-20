import XCTest

final class TransferAccountingTests: XCTestCase {
    private let run = UUID()
    private let a = TransferSourceID.disk(registryID: 1)
    private let b = TransferSourceID.disk(registryID: 2)
    private func source(_ id: TransferSourceID, _ first: UInt64?, _ second: UInt64 = 0) -> TransferSourceCounter {
        TransferSourceCounter(id: id, bytes: first.map { TransferBytes(first: $0, second: second) })
    }
    private func snapshot(_ sequence: UInt64, _ time: Double, _ sources: [TransferSourceCounter],
                          stat: TransferStat = .disk, enumeration: TransferEnumeration = .complete,
                          generation: UUID? = nil, wall: Double? = nil) -> TransferCounterSnapshot {
        TransferCounterSnapshot(stat: stat, generation: generation ?? run, sequence: sequence,
            timestamp: TransferTimestamp(continuousTime: time, wallTime: Date(timeIntervalSince1970: wall ?? time), bootID: "fixture-boot"),
            enumeration: enumeration, sources: sources)
    }

    func testTwoSecondDelayUsesActualElapsedAndPairedIntegerBytesBeyondFourGiB() throws {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        let baseline: UInt64 = 1 << 34
        XCTAssertNil(accounting.consume(snapshot(1, 10, [source(a, baseline, baseline)])))
        let measured = try XCTUnwrap(accounting.consume(snapshot(2, 12, [source(a, baseline + 20_000_000, baseline + 4_000_000)])))
        XCTAssertEqual(measured.interval.bytes, TransferBytes(first: 20_000_000, second: 4_000_000))
        XCTAssertEqual(measured.interval.firstBytesPerSecond, 10_000_000)
        XCTAssertEqual(measured.interval.secondBytesPerSecond, 2_000_000)
        XCTAssertEqual(measured.interval.coverage, .complete)
    }

    func testRemovalAndReappearanceDiscardOnlyUncertainSource() throws {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = accounting.consume(snapshot(1, 1, [source(a, 100), source(b, 1_000)]))
        let removed = try XCTUnwrap(accounting.consume(snapshot(2, 2, [source(a, 110)])))
        XCTAssertEqual(removed.interval.bytes.first, 10)
        XCTAssertEqual(removed.interval.coverage, .partial)
        let returned = try XCTUnwrap(accounting.consume(snapshot(3, 3, [source(a, 120), source(b, 9_000)])))
        XCTAssertEqual(returned.interval.bytes.first, 10)
        XCTAssertEqual(returned.interval.coverage, .partial)
        let next = try XCTUnwrap(accounting.consume(snapshot(4, 4, [source(a, 130), source(b, 9_100)])))
        XCTAssertEqual(next.interval.bytes.first, 110)
        XCTAssertEqual(next.interval.coverage, .complete)
    }

    func testCounterResetDiscardsBothDirectionsButKeepsHealthyPeer() throws {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = accounting.consume(snapshot(1, 1, [source(a, 100, 100), source(b, 100, 100)]))
        let reset = try XCTUnwrap(accounting.consume(snapshot(2, 2, [source(a, 1, 1_000), source(b, 110, 120)])))
        XCTAssertEqual(reset.interval.bytes, TransferBytes(first: 10, second: 20))
        XCTAssertEqual(reset.interval.coverage, .partial)
    }

    func testFailedPairInvalidatesItsBaselineWithoutBackfillingRecovery() throws {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = accounting.consume(snapshot(1, 1, [source(a, 100), source(b, 100)]))
        let failed = try XCTUnwrap(accounting.consume(snapshot(2, 2, [source(a, nil), source(b, 110)])))
        XCTAssertEqual(failed.interval.bytes.first, 10)
        XCTAssertEqual(failed.interval.coverage, .partial)
        let recovery = try XCTUnwrap(accounting.consume(snapshot(3, 3, [source(a, 10_000), source(b, 120)])))
        XCTAssertEqual(recovery.interval.bytes.first, 10)
        XCTAssertEqual(recovery.interval.coverage, .partial)
        XCTAssertEqual(accounting.consume(snapshot(4, 4, [source(a, 10_005), source(b, 125)]))?.interval.bytes.first, 10)
    }

    func testEnumerationFailureAndLongGapNeverBackfill() throws {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = accounting.consume(snapshot(1, 1, [source(a, 100)]))
        XCTAssertEqual(accounting.consume(snapshot(2, 2, [], enumeration: .failed))?.interval.coverage, .missing)
        XCTAssertEqual(accounting.consume(snapshot(3, 3, [source(a, 10_000)]))?.interval.bytes, .zero)
        XCTAssertEqual(accounting.consume(snapshot(4, 14, [source(a, 100_000)]))?.interval.coverage, .missing)
        XCTAssertEqual(accounting.consume(snapshot(5, 15, [source(a, 100_010)]))?.interval.bytes.first, 10)
    }

    func testDuplicateLateAndForeignEventsDoNotAdvanceBaseline() throws {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = accounting.consume(snapshot(1, 1, [source(a, 100)]))
        XCTAssertNil(accounting.consume(snapshot(1, 2, [source(a, 1_000)])))
        XCTAssertNil(accounting.consume(snapshot(2, 2, [source(a, 1_000)], generation: UUID())))
        XCTAssertEqual(accounting.consume(snapshot(2, 2, [source(a, 110)]))?.interval.bytes.first, 10)
        XCTAssertNil(accounting.consume(snapshot(1, 3, [source(a, 10_000)])))
        XCTAssertEqual(accounting.consume(snapshot(3, 3, [source(a, 120)]))?.interval.bytes.first, 10)
    }

    func testDuplicateSourceInvalidatesOnlyThatIdentity() throws {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = accounting.consume(snapshot(1, 1, [source(a, 100), source(b, 100)]))
        let result = try XCTUnwrap(accounting.consume(snapshot(2, 2, [source(a, 110), source(a, 900), source(b, 110)])))
        XCTAssertEqual(result.interval.bytes.first, 10)
        XCTAssertEqual(result.interval.coverage, .partial)
    }

    func testCheckedSumOverflowIsMissingAndVisible() throws {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = accounting.consume(snapshot(1, 1, [source(a, 0), source(b, 0)]))
        let result = try XCTUnwrap(accounting.consume(snapshot(2, 2, [source(a, .max), source(b, 1)])))
        XCTAssertTrue(result.accountingOverflow)
        XCTAssertEqual(result.interval.coverage, .missing)
        XCTAssertEqual(result.interval.bytes, .zero)
    }

    func testKnownOfflineNetworkDiffersFromUnavailableDisk() {
        var network = TransferAccounting(stat: .network, generation: run, interval: 1)
        var disk = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = network.consume(snapshot(1, 1, [], stat: .network))
        _ = disk.consume(snapshot(1, 1, []))
        XCTAssertEqual(network.consume(snapshot(2, 2, [], stat: .network))?.interval.coverage, .complete)
        XCTAssertEqual(disk.consume(snapshot(2, 2, []))?.interval.coverage, .missing)
    }

    func testClockJumpDoesNotAffectRateAndInvalidElapsedCannotPoisonBaseline() {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = accounting.consume(snapshot(1, 10, [source(a, 100)], wall: 1_000))
        XCTAssertNil(accounting.consume(snapshot(2, .nan, [source(a, 999)])))
        XCTAssertNil(accounting.consume(snapshot(2, 9, [source(a, 999)])))
        let result = accounting.consume(snapshot(2, 12, [source(a, 120)], wall: 1))
        XCTAssertEqual(result?.interval.firstBytesPerSecond, 10)
    }

    func testExplicitDiscontinuityReseedsAndCadenceIsBounded() {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = accounting.consume(snapshot(1, 1, [source(a, 100)]))
        accounting.invalidateBaselines()
        XCTAssertEqual(accounting.consume(snapshot(2, 2, [source(a, 999)]))?.interval.coverage, .missing)
        XCTAssertEqual(accounting.consume(snapshot(3, 3, [source(a, 1_009)]))?.interval.bytes.first, 10)
        XCTAssertEqual(TransferCadence.effective(0), 0.25)
        XCTAssertEqual(TransferCadence.effective(100), 5)
        XCTAssertEqual(TransferCadence.effective(.nan), 1)
    }

    func testProviderClassificationExcludesImagesAndPreservesUnknownCoverage() {
        XCTAssertEqual(TransferStorageLayer.classify(interconnect: "Apple Fabric", location: "Internal"), .physical)
        XCTAssertEqual(TransferStorageLayer.classify(interconnect: "USB", location: "External"), .physical)
        XCTAssertEqual(TransferStorageLayer.classify(interconnect: "Virtual Interface", location: nil), .excludedVirtual)
        XCTAssertEqual(TransferStorageLayer.classify(interconnect: "Virtual Interface", location: "File"), .excludedVirtual)
        XCTAssertEqual(TransferStorageLayer.classify(interconnect: nil, location: "File"), .excludedVirtual)
        XCTAssertEqual(TransferStorageLayer.classify(interconnect: nil, location: "Internal"), .unknown)
        XCTAssertEqual(TransferStorageLayer.classify(interconnect: "Unknown", location: "Internal"), .unknown)
        XCTAssertEqual(TransferStorageLayer.classify(interconnect: "USB", location: nil), .unknown)
    }


    func testBootIdentityInvalidWallAndExactGapBoundary() {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = accounting.consume(snapshot(1, 1, [source(a, 100)]))
        let foreignBoot = TransferCounterSnapshot(stat: .disk, generation: run, sequence: 2,
            timestamp: TransferTimestamp(continuousTime: 2, wallTime: Date(), bootID: "other-boot"),
            enumeration: .complete, sources: [source(a, 999)])
        XCTAssertNil(accounting.consume(foreignBoot))
        XCTAssertNil(accounting.consume(snapshot(2, 2, [source(a, 999)], wall: .nan)))
        XCTAssertEqual(accounting.consume(snapshot(2, 11, [source(a, 120)]))?.interval.coverage, .complete)
        XCTAssertEqual(accounting.consume(snapshot(3, 21.001, [source(a, 140)]))?.interval.coverage, .missing)
    }

    func testSecondDirectionOverflowAndDuplicateSourceRecovery() throws {
        var accounting = TransferAccounting(stat: .disk, generation: run, interval: 1)
        _ = accounting.consume(snapshot(1, 1, [source(a, 0), source(b, 0)]))
        XCTAssertTrue(try XCTUnwrap(accounting.consume(snapshot(2, 2, [source(a, 0, .max), source(b, 0, 1)]))).accountingOverflow)
        _ = accounting.consume(snapshot(3, 3, [source(a, 1, .max), source(a, 2, .max), source(b, 1, 2)]))
        XCTAssertEqual(accounting.consume(snapshot(4, 4, [source(a, 100, .max), source(b, 2, 3)]))?.interval.bytes, TransferBytes(first: 1, second: 1))
        XCTAssertEqual(accounting.consume(snapshot(5, 5, [source(a, 101, .max), source(b, 3, 4)]))?.interval.bytes, TransferBytes(first: 2, second: 1))
    }

    func testPackedFullDayIncludingCadenceLimitedResetBoundariesFitsBudget() {
        // Exercise actual retained array stride, rather than just an on-paper record estimate.
        XCTAssertLessThanOrEqual(MemoryLayout<TransferInterval>.stride, TransferInterval.packedSize)
        let count = 2 * TransferResourceBudget.maximumIntervalsPerStat
        var day: [TransferInterval] = []
        day.reserveCapacity(count)
        for index in 0..<count {
            let start = Double(index / 2) * 0.2
            day.append(TransferInterval(start: start, end: start + 0.2,
                bytes: TransferBytes(first: 1, second: 2), stat: index.isMultiple(of: 2) ? .network : .disk, coverage: .complete))
        }
        XCTAssertEqual(day.count, 864_002)
        XCTAssertEqual(TransferResourceBudget.packedDayBytes, 34_560_080)
        // One retained array + bounded active/checkpoint/query metadata, no full-day copies.
        XCTAssertLessThan(day.count * MemoryLayout<TransferInterval>.stride + 4 * 1024 * 1024, TransferResourceBudget.maximumBytes)
        XCTAssertLessThan(TransferResourceBudget.proposedDiskCeiling, TransferResourceBudget.maximumBytes)
        XCTAssertLessThan(2 * TransferResourceBudget.maximumRecordsPerSegmentPerStat * TransferInterval.packedSize + 2 * TransferResourceBudget.segmentHeaderAllowance, 128 * 1024)
        XCTAssertEqual(day.last?.bytes.second, 2)
    }
}

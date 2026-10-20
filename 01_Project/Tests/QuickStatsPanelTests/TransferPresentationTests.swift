import XCTest

final class TransferPresentationTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let zone = TimeZone(secondsFromGMT: 0)!
    private func result(stat: TransferStat = .network, estimated: Bool = false, overflow: Bool = false) -> TransferPeriodResult {
        TransferPeriodResult(stat: stat, start: 0, end: 60, bytes: TransferBytes(first: 100_000_000, second: 20_000_000),
            fullyMeasuredDuration: 30, partialDuration: 10, hasBoundaryEstimate: estimated, accountingOverflow: overflow,
            slots: [TransferPeriodSlot(start: 0, end: 20, bytes: .zero, fullyMeasuredDuration: 20, partialDuration: 0, accountingOverflow: false),
                    TransferPeriodSlot(start: 20, end: 40, bytes: TransferBytes(first: 100_000_000, second: 20_000_000), fullyMeasuredDuration: 10, partialDuration: 10, accountingOverflow: false),
                    TransferPeriodSlot(start: 40, end: 60, bytes: .zero, fullyMeasuredDuration: 0, partialDuration: 0, accountingOverflow: false)])
    }
    private func presentation(_ result: TransferPeriodResult? = nil, state: TransferHistorySaveState = .loading) -> TransferHistoryPresentation {
        TransferHistoryPresentation(result: result ?? self.result(), period: .minute,
            cumulative: TransferCumulativeEpoch(bytes: TransferBytes(first: 80_000_000, second: 40_000_000),
                startedAt: Date(timeIntervalSince1970: 0), accountingOverflow: false), durability: state, locale: locale, timeZone: zone)
    }

    func testUnsignedMaximumFormattingKeepsExactBytesAndDistinctRateUnits() {
        XCTAssertEqual(TransferHistoryFormat.bytes(0, locale: locale), "0 B")
        XCTAssertEqual(TransferHistoryFormat.bytes(100_000_000, locale: locale), "100 MB")
        XCTAssertEqual(TransferHistoryFormat.bytes(.max, locale: locale), "18.4 EB")
        XCTAssertEqual(TransferHistoryFormat.exactBytes(.max, locale: locale), "18,446,744,073,709,551,615 B")
        XCTAssertEqual(TransferHistoryFormat.rate(100_000_000, locale: locale), "100 MB/s")
        XCTAssertEqual(TransferHistoryFormat.rate(0, locale: locale), "0 B/s")
        for value in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertEqual(TransferHistoryFormat.rate(value, locale: locale), "Unavailable")
        }
        XCTAssertFalse(TransferHistoryFormat.rate(.greatestFiniteMagnitude, locale: locale).isEmpty)
    }

    func testDirectionLabelsAndMonochromeMarkersDoNotDependOnColor() {
        let network = presentation()
        XCTAssertEqual(network.selectedTotals.first.label, "Downloaded")
        XCTAssertEqual(network.selectedTotals.second.label, "Uploaded")
        XCTAssertEqual(network.selectedTotals.first.marker, "↓")
        XCTAssertEqual(network.selectedTotals.second.marker, "↑")
        XCTAssertEqual(network.selectedTotals.first.value, "100 MB")
        let disk = presentation(result(stat: .disk))
        XCTAssertEqual(disk.selectedTotals.first.label, "Read")
        XCTAssertEqual(disk.selectedTotals.second.label, "Written")
        XCTAssertEqual(disk.graph.firstMarker, "R")
        XCTAssertEqual(disk.graph.secondMarker, "W")
        XCTAssertEqual(disk.cumulativeTotals.first.value, "80 MB")
    }

    func testCoverageReportsFullPartialAndMissingTimeSeparately() {
        let model = presentation()
        XCTAssertEqual(model.coverageText, "Fully measured 30 s of 1 min · Partial 10 s · Missing 20 s")
        XCTAssertEqual(model.graph.slots[0].missingFraction, 0)
        XCTAssertEqual(model.graph.slots[0].firstRate, 0)
        XCTAssertEqual(model.graph.slots[1].partialFraction, 0.5)
        XCTAssertEqual(model.graph.slots[2].missingFraction, 1)
        XCTAssertTrue(model.accessibilitySummary.contains("missing time is unobserved"))
    }

    func testBoundaryEstimateDisclosesApproximationAndExactObservedCount() {
        let model = presentation(result(estimated: true))
        XCTAssertEqual(model.selectedTotals.first.value, "≈100 MB")
        XCTAssertEqual(model.selectedTotals.first.exactValue, "100,000,000 B")
        XCTAssertTrue(model.boundaryEstimateHelp?.contains("uniform") == true)
        XCTAssertFalse(model.cumulativeTotals.first.value.contains("≈"))
        XCTAssertTrue(model.accessibilitySummary.contains("sampling boundary estimate"))
    }

    func testOverflowNeverPresentsRetainedSubtotalAsExactAccounting() {
        let model = presentation(result(overflow: true))
        XCTAssertEqual(model.selectedTotals.first.value, "Unavailable")
        XCTAssertTrue(model.warningText.contains("Accounting unavailable"))
        XCTAssertEqual(model.graph.slots.count, 3)
    }

    func testSaveFailureRecoveryAndLocalizedResetStartAreTruthful() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(presentation(state: .saved(date)).saveText.hasPrefix("Saved "))
        XCTAssertTrue(presentation(state: .unsaved(lastSaved: date)).saveText.contains("Unsaved"))
        XCTAssertTrue(presentation(state: .unsaved(lastSaved: nil)).saveText.contains("Not saved yet"))
        XCTAssertTrue(presentation(state: .saving(lastSaved: date)).saveText.contains("Saving"))
        let failed = presentation(state: .failed(lastSaved: date, message: "Disk full"))
        XCTAssertTrue(failed.saveText.contains("Unsaved"))
        XCTAssertTrue(failed.warningText.contains("Disk full"))
        let recovered = presentation(state: .recovered(lastSaved: date, message: "Some recent data may be missing"))
        XCTAssertTrue(recovered.warningText.contains("Some recent data may be missing"))
        XCTAssertTrue(recovered.saveText.contains("Recovered"))
        XCTAssertTrue(recovered.resetStartedText.contains("1970"))
        XCTAssertTrue(recovered.resetStartedText.contains("Started"))
        let french = TransferHistoryPresentation(result: result(), period: .minute,
            cumulative: TransferCumulativeEpoch(bytes: .zero, startedAt: date, accountingOverflow: false), durability: .loading,
            locale: Locale(identifier: "fr_FR"), timeZone: zone)
        XCTAssertNotEqual(french.resetStartedText, recovered.resetStartedText)
    }

    func testResetStartChangesVisiblyForResetsWithinOneMinute() {
        let first = TransferHistoryFormat.date(Date(timeIntervalSince1970: 100), locale: locale, timeZone: zone)
        let second = TransferHistoryFormat.date(Date(timeIntervalSince1970: 101), locale: locale, timeZone: zone)
        XCTAssertNotEqual(first, second, "A confirmed reset must show a visibly new start time even within the same minute")
    }

    func testRelativeAxisAndPeakCacheAdvanceOnlyOnNewRevisionAndStayPerStatPeriod() {
        XCTAssertEqual(TransferHistoryPeriod.minute.axisLabels, ["−1 min", "−30 s", "Now"])
        XCTAssertEqual(TransferHistoryPeriod.hour.axisLabels, ["−1 h", "−30 min", "Now"])
        XCTAssertEqual(TransferHistoryPeriod.day.axisLabels, ["−24 h", "−12 h", "Now"])
        var cache = TransferGraphPeakCache()
        let first = cache.graph(result: result(), period: .minute, revision: 1, locale: locale)
        let idle = TransferPeriodResult(stat: .network, start: 0, end: 60, bytes: .zero,
            fullyMeasuredDuration: 60, partialDuration: 0, hasBoundaryEstimate: false, accountingOverflow: false, slots: [])
        let repeated = cache.graph(result: idle, period: .minute, revision: 1, locale: locale)
        XCTAssertEqual(first.firstPeak, repeated.firstPeak)
        let next = cache.graph(result: idle, period: .minute, revision: 2, locale: locale)
        XCTAssertLessThan(next.firstPeak, first.firstPeak)
        let empty = cache.graph(result: idle, period: .hour, revision: 2, locale: locale)
        XCTAssertEqual(empty.firstPeak, 0)
        XCTAssertEqual(empty.firstPeakText, "0 B/s")
        var disk = result(stat: .disk)
        disk = TransferPeriodResult(stat: .disk, start: disk.start, end: disk.end, bytes: .zero,
            fullyMeasuredDuration: 0, partialDuration: 0, hasBoundaryEstimate: false, accountingOverflow: false, slots: [])
        XCTAssertEqual(cache.graph(result: disk, period: .minute, revision: 2, locale: locale).firstPeak, 0)
        // A later query cannot mutate an already-published packet.
        XCTAssertEqual(first.firstPeak, 5_000_000)
    }

    func testResetStateRequiresConfirmationAndSuppressesDuplicatePendingActions() {
        var state = TransferDetailState(stat: .network)
        XCTAssertEqual(state.period, .minute)
        XCTAssertFalse(state.beginReset())
        XCTAssertTrue(state.requestReset())
        XCTAssertEqual(state.confirmationTitle, "Reset Network totals?")
        state.cancelReset()
        XCTAssertFalse(state.isConfirmingReset)
        XCTAssertTrue(state.requestReset())
        XCTAssertTrue(state.beginReset())
        XCTAssertFalse(state.requestReset())
        XCTAssertFalse(state.beginReset())
        state.dismiss()
        XCTAssertTrue(state.isResetPending)
        state.completeReset(error: "Reset is unsaved")
        XCTAssertFalse(state.isResetPending)
        XCTAssertEqual(state.resetError, "Reset is unsaved")
        state.select(.day)
        XCTAssertEqual(state.period, .day)
        var other = TransferDetailState(stat: .disk)
        XCTAssertEqual(other.period, .minute)
        XCTAssertTrue(other.requestReset())
        other.dismiss()
        XCTAssertFalse(other.isConfirmingReset)
    }
}

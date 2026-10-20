import XCTest

/// These enter the pure state methods used by StatsStore's native-control
/// actions. Native target/action delivery, panel focus and layout remain E1.
final class TransferDetailStateTests: XCTestCase {
    func testPeriodsRemainIndependentAcrossDismissalAndResetOutcomes() {
        var network = TransferDetailState(stat: .network)
        var disk = TransferDetailState(stat: .disk)
        network.select(.day)
        disk.select(.hour)

        XCTAssertTrue(network.requestReset())
        XCTAssertTrue(network.beginReset())
        network.completeReset(error: "Reset is unsaved")
        XCTAssertTrue(disk.requestReset())
        network.dismiss()
        disk.dismiss()

        XCTAssertEqual(network.period, .day)
        XCTAssertEqual(disk.period, .hour)
        XCTAssertEqual(network.resetError, "Reset is unsaved")
        XCTAssertNil(disk.resetError)
        XCTAssertFalse(disk.isConfirmingReset)
        XCTAssertFalse(disk.beginReset(), "Dismissed confirmation cannot reach a reset")
    }

    func testDismissCancelsOnlyUnconfirmedWorkWhilePendingResetCanFinish() {
        var network = TransferDetailState(stat: .network)
        var disk = TransferDetailState(stat: .disk)
        XCTAssertTrue(network.requestReset())
        XCTAssertTrue(network.beginReset())
        XCTAssertTrue(disk.requestReset())

        network.dismiss()
        disk.dismiss()
        network.cancelReset()
        network.select(.hour)

        XCTAssertTrue(network.isResetPending)
        XCTAssertFalse(network.requestReset())
        XCTAssertFalse(network.beginReset())
        XCTAssertFalse(disk.isConfirmingReset)
        XCTAssertFalse(disk.isResetPending)
        network.completeReset()
        XCTAssertFalse(network.isResetPending)
        XCTAssertEqual(network.period, .hour)
        XCTAssertNil(network.resetError)
    }

    func testEveryResetRequiresAReachableFreshConfirmation() {
        var state = TransferDetailState(stat: .disk)
        XCTAssertFalse(state.beginReset())
        XCTAssertTrue(state.requestReset())
        state.cancelReset()
        XCTAssertFalse(state.beginReset())

        XCTAssertTrue(state.requestReset())
        XCTAssertTrue(state.beginReset())
        state.completeReset()
        XCTAssertFalse(state.beginReset(), "A completed reset does not authorize another reset")
        XCTAssertTrue(state.requestReset())
        XCTAssertTrue(state.beginReset())
        XCTAssertEqual(state.confirmationTitle, "Reset Disk totals?")
        XCTAssertTrue(state.confirmationHelp.contains("History is kept"))
    }

    func testUnexpectedCompletionCannotCancelConfirmationOrIntroduceAnError() {
        var state = TransferDetailState(stat: .network)
        state.completeReset(error: "Unexpected failure")
        XCTAssertNil(state.resetError)
        XCTAssertTrue(state.requestReset())
        state.completeReset(error: "Stale completion")
        XCTAssertTrue(state.isConfirmingReset)
        XCTAssertNil(state.resetError)
        XCTAssertTrue(state.beginReset())
    }

    func testFailedResetRemainsVisibleAfterDismissAndRetryClearsOnlyItsError() {
        var state = TransferDetailState(stat: .network)
        state.select(.day)
        XCTAssertTrue(state.requestReset())
        XCTAssertTrue(state.beginReset())
        state.completeReset(error: "Unsaved reset\n" + String(repeating: "x", count: 240))
        let error = state.resetError
        XCTAssertEqual(error?.count, 180)
        XCTAssertFalse(error?.contains("\n") ?? true)
        state.dismiss()
        XCTAssertEqual(state.resetError, error)
        XCTAssertEqual(state.period, .day)

        XCTAssertTrue(state.requestReset())
        XCTAssertNil(state.resetError)
        XCTAssertTrue(state.isConfirmingReset)
        XCTAssertEqual(state.period, .day)
        XCTAssertTrue(state.beginReset())
        state.completeReset()
        XCTAssertNil(state.resetError)
        XCTAssertFalse(state.isResetPending)
    }
}

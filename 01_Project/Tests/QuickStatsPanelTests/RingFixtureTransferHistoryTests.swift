import XCTest

#if DEBUG
/// Ring fixture mode builds a disposable store that never starts samplers. Its transfer
/// cards must still resolve out of "Loading..." by loading the empty temporary root once.
@MainActor
final class RingFixtureTransferHistoryTests: XCTestCase {

    func testFixtureStorePublishesTransferPresentationsFromItsDisposableRoot() async throws {
        let store = StatsStore.makeRingFixtureStore(unavailable: [])
        XCTAssertFalse(store.isRunning, "fixture mode starts no samplers")
        XCTAssertNotNil(store.transferHistoryController, "the history controller loaded once")

        let deadline = Date().addingTimeInterval(5)
        while (store.transferPresentations[.disk] == nil || store.transferPresentations[.network] == nil),
              Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(store.transferPresentations[.disk], "Disk card has a state to render")
        XCTAssertNotNil(store.transferPresentations[.network], "Network card has a state to render")
    }
}
#endif

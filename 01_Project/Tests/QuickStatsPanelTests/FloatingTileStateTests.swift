import XCTest

#if DEBUG
/// The floating-tile interaction loop: summon, select, switch, return, staged Escape, dismiss.
final class FloatingTileStateTests: XCTestCase {

    private let plan = FloatingTilePlan.make(kinds: [.cpu, .network],
                                             detailSizes: [.cpu: CGSize(width: 244, height: 330),
                                                           .network: CGSize(width: 284, height: 560)],
                                             available: CGSize(width: 1400, height: 860))

    func testSummonShowsOverviewWithoutTakingKeyboardFocus() {
        var s = FloatingTileState()
        XCTAssertEqual(s.summon(), .showOverview(focus: nil))
        XCTAssertEqual(s.mode, .overview)
        XCTAssertNil(s.focus)
        XCTAssertEqual(s.entryTarget(kinds: plan.kinds), .tile(.cpu), "keyboard entry starts at the first tile")
    }

    func testOpenSwitchReturnAndDismissJourney() {
        var s = FloatingTileState()
        _ = s.summon()
        XCTAssertEqual(s.select(.cpu, plan: plan), .showDetail(.cpu, focus: .switcher(.cpu)))
        XCTAssertEqual(s.mode, .detail(.cpu))
        XCTAssertEqual(s.select(.cpu, plan: plan), .none, "selecting the current stat is inert")
        XCTAssertEqual(s.select(.network, plan: plan), .showDetail(.network, focus: .switcher(.network)))
        XCTAssertEqual(s.returnToOverview(), .showOverview(focus: .tile(.network)), "focus returns to the selected tile")
        XCTAssertEqual(s.mode, .overview)
        XCTAssertEqual(s.dismiss(), .dismiss)
        XCTAssertEqual(s.mode, .hidden)
        XCTAssertEqual(s.dismiss(), .none, "redundant dismissal is a no-op")
    }

    func testEscapeIsStaged() {
        var s = FloatingTileState()
        _ = s.summon()
        _ = s.select(.network, plan: plan)
        XCTAssertEqual(s.escape(), .showOverview(focus: .tile(.network)))
        XCTAssertEqual(s.escape(), .dismiss)
        XCTAssertEqual(s.escape(), .none)
    }

    func testReopeningStartsInOverview() {
        var s = FloatingTileState()
        _ = s.summon()
        _ = s.select(.cpu, plan: plan)
        _ = s.dismiss()
        XCTAssertEqual(s.summon(), .showOverview(focus: nil))
        XCTAssertEqual(s.mode, .overview)
        XCTAssertNil(s.lastSelected)
    }

    func testUnknownOrHiddenSelectionIsIgnored() {
        var s = FloatingTileState()
        XCTAssertEqual(s.select(.cpu, plan: plan), .none, "nothing selects while hidden")
        _ = s.summon()
        XCTAssertEqual(s.select(.gpu, plan: plan), .none, "only planned identities open")
        XCTAssertEqual(s.returnToOverview(), .none)
    }

    func testArrowFocusMovesByNeighbour() {
        var s = FloatingTileState()
        _ = s.summon()
        s.focus(.tile(.cpu))
        XCTAssertEqual(s.moveFocus(.right, plan: plan), .tile(.network))
        XCTAssertEqual(s.focus, .tile(.network))
        XCTAssertEqual(s.moveFocus(.left, plan: plan), .tile(.cpu))
        XCTAssertNil(s.moveFocus(.left, plan: plan), "edge keeps focus")
        XCTAssertEqual(s.focus, .tile(.cpu))
        _ = s.select(.cpu, plan: plan)
        XCTAssertEqual(s.moveFocus(.down, plan: plan), .allStatistics)
    }

    func testFocusIsIgnoredWhileHidden() {
        var s = FloatingTileState()
        s.focus(.tile(.cpu))
        XCTAssertNil(s.focus)
        XCTAssertNil(s.entryTarget(kinds: plan.kinds))
    }
}
#endif

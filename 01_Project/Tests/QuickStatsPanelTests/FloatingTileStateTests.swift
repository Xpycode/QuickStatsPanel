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
        XCTAssertEqual(s.select(.cpu, from: .tile(.cpu), plan: plan), .showDetail(.cpu, focus: .tile(.cpu)),
                       "focus stays on the tile; the overview stays")
        XCTAssertEqual(s.mode, .detail(.cpu))
        XCTAssertEqual(s.entryTarget(kinds: plan.kinds), .tile(.cpu))
        XCTAssertEqual(s.select(.cpu, from: .switcher(.cpu), plan: plan), .none, "the current switcher item is inert")
        XCTAssertEqual(s.select(.network, from: .switcher(.network), plan: plan), .showDetail(.network, focus: .switcher(.network)))
        XCTAssertEqual(s.returnToOverview(), .showOverview(focus: .tile(.network)), "focus returns to the selected tile")
        XCTAssertEqual(s.mode, .overview)
        XCTAssertEqual(s.dismiss(), .dismiss)
        XCTAssertEqual(s.mode, .hidden)
        XCTAssertEqual(s.dismiss(), .none, "redundant dismissal is a no-op")
    }

    func testEscapeIsStaged() {
        var s = FloatingTileState()
        _ = s.summon()
        _ = s.select(.network, from: .tile(.network), plan: plan)
        XCTAssertEqual(s.escape(), .showOverview(focus: .tile(.network)))
        XCTAssertEqual(s.escape(), .dismiss)
        XCTAssertEqual(s.escape(), .none)
    }

    func testReopeningStartsInOverview() {
        var s = FloatingTileState()
        _ = s.summon()
        _ = s.select(.cpu, from: .tile(.cpu), plan: plan)
        _ = s.dismiss()
        XCTAssertEqual(s.summon(), .showOverview(focus: nil))
        XCTAssertEqual(s.mode, .overview)
        XCTAssertNil(s.lastSelected)
    }

    func testUnknownOrHiddenSelectionIsIgnored() {
        var s = FloatingTileState()
        XCTAssertEqual(s.select(.cpu, from: .tile(.cpu), plan: plan), .none, "nothing selects while hidden")
        _ = s.summon()
        XCTAssertEqual(s.select(.gpu, from: .tile(.gpu), plan: plan), .none, "only planned identities open")
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
        _ = s.select(.cpu, from: .tile(.cpu), plan: plan)
        XCTAssertEqual(s.moveFocus(.right, plan: plan), .tile(.network), "tiles stay navigable with a card open")
    }

    func testSelectingTheOpenTileAgainClosesItsCard() {
        var s = FloatingTileState()
        _ = s.summon()
        _ = s.select(.network, from: .tile(.network), plan: plan)
        XCTAssertEqual(s.select(.network, from: .tile(.network), plan: plan), .showOverview(focus: .tile(.network)))
        XCTAssertEqual(s.mode, .overview)
    }

    func testFocusIsIgnoredWhileHidden() {
        var s = FloatingTileState()
        s.focus(.tile(.cpu))
        XCTAssertNil(s.focus)
        XCTAssertNil(s.entryTarget(kinds: plan.kinds))
    }

    func testEmptyOverviewKeyboardEntryLandsOnSettings() {
        var s = FloatingTileState()
        _ = s.summon()
        XCTAssertEqual(s.entryTarget(kinds: []), .settings, "nothing enabled: Settings and Quit stay reachable")
        let empty = FloatingTilePlan.make(kinds: [], detailSizes: [:], available: CGSize(width: 1400, height: 860))
        XCTAssertNil(s.moveFocus(.left, plan: empty), "no focus yet, no movement")
        s.focus(.settings)
        XCTAssertEqual(s.moveFocus(.right, plan: empty), .quit)
        XCTAssertEqual(s.escape(), .dismiss, "Escape in the empty overview dismisses")
    }

    func testSelectingAnUnknownStatIsInert() {
        var s = FloatingTileState()
        _ = s.summon()
        XCTAssertEqual(s.select(.gpu, from: .tile(.gpu), plan: plan), .none, "only enabled identities can be selected")
        XCTAssertEqual(s.mode, .overview)
    }
}
#endif

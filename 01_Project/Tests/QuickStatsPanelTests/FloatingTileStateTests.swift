import XCTest

#if DEBUG
/// The floating-tile interaction loop (D-044): summon, open a primary's detail (others hide),
/// return via the same primary or Escape, a second Escape dismisses. There is no switcher.
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

    func testOpenReturnAndDismissJourney() {
        var s = FloatingTileState()
        _ = s.summon()
        XCTAssertEqual(s.visiblePrimaries(in: plan.kinds), [.cpu, .network])
        XCTAssertEqual(s.select(.cpu, from: .tile(.cpu), plan: plan),
                       .showDetail(.cpu, hiding: [.network], focus: .tile(.cpu)),
                       "the other primaries hide; focus stays on the clicked primary")
        XCTAssertEqual(s.mode, .detail(.cpu))
        XCTAssertEqual(s.visiblePrimaries(in: plan.kinds), [.cpu], "only the clicked primary remains")
        XCTAssertEqual(s.entryTarget(kinds: plan.kinds), .tile(.cpu))
        XCTAssertEqual(s.returnToOverview(), .showOverview(focus: .tile(.cpu)), "focus returns to the primary")
        XCTAssertEqual(s.mode, .overview)
        XCTAssertEqual(s.visiblePrimaries(in: plan.kinds), [.cpu, .network], "all primaries return")
        XCTAssertEqual(s.dismiss(), .dismiss)
        XCTAssertEqual(s.mode, .hidden)
        XCTAssertEqual(s.visiblePrimaries(in: plan.kinds), [])
        XCTAssertEqual(s.dismiss(), .none, "redundant dismissal is a no-op")
    }

    func testHidingListsEveryOtherPrimaryInSavedOrder() {
        let wide = FloatingTilePlan.make(kinds: [.disk, .cpu, .gpu, .memory], detailSizes: [:],
                                         available: CGSize(width: 1400, height: 860))
        var s = FloatingTileState()
        _ = s.summon()
        XCTAssertEqual(s.select(.gpu, from: .tile(.gpu), plan: wide),
                       .showDetail(.gpu, hiding: [.disk, .cpu, .memory], focus: .tile(.gpu)))
    }

    func testChangingStatRequiresReturningFirst() {
        var s = FloatingTileState()
        _ = s.summon()
        _ = s.select(.cpu, from: .tile(.cpu), plan: plan)
        XCTAssertEqual(s.select(.network, from: .tile(.network), plan: plan), .none,
                       "a hidden primary cannot switch the detail (no switcher)")
        XCTAssertEqual(s.mode, .detail(.cpu))
        XCTAssertEqual(s.escape(), .showOverview(focus: .tile(.cpu)))
        XCTAssertEqual(s.select(.network, from: .tile(.network), plan: plan),
                       .showDetail(.network, hiding: [.cpu], focus: .tile(.network)))
    }

    func testEscapeIsStaged() {
        var s = FloatingTileState()
        _ = s.summon()
        _ = s.select(.network, from: .tile(.network), plan: plan)
        XCTAssertEqual(s.escape(), .showOverview(focus: .tile(.network)), "first Escape: all primaries return")
        XCTAssertEqual(s.visiblePrimaries(in: plan.kinds), [.cpu, .network])
        XCTAssertEqual(s.escape(), .dismiss, "second Escape dismisses")
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
        XCTAssertNotEqual(s.moveFocus(.right, plan: plan), .tile(.network), "hidden primaries are not focus targets")
        s.focus(.tile(.cpu))
        XCTAssertNil(s.moveFocus(.left, plan: plan))
        XCTAssertNil(s.moveFocus(.down, plan: plan))
    }

    func testSelectingTheOpenPrimaryAgainReturnsThenEscapeDismisses() {
        var s = FloatingTileState()
        _ = s.summon()
        _ = s.select(.network, from: .tile(.network), plan: plan)
        XCTAssertEqual(s.select(.network, from: .tile(.network), plan: plan), .showOverview(focus: .tile(.network)))
        XCTAssertEqual(s.mode, .overview)
        XCTAssertEqual(s.visiblePrimaries(in: plan.kinds), [.cpu, .network])
        XCTAssertEqual(s.escape(), .dismiss)
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

import XCTest

/// Hostless checks of the ring interaction state machine: injected clock, generation
/// tokens, held-vs-preview precedence and the spec's input table. No AppKit, no timers.
final class RingInteractionTests: XCTestCase {

    private final class FakeClock: RingClock {
        var time: TimeInterval = 0
        func now() -> TimeInterval { time }
    }

    private let clock = FakeClock()
    private let far = CGPoint(x: 5_000, y: 5_000)
    private let summonPoint = CGPoint(x: -1_000, y: -1_000)

    // Frames (screen points): two sibling wedges, the More wedge, two More entries.
    private let cpuFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
    private let memoryFrame = CGRect(x: 0, y: 110, width: 100, height: 100)
    private let moreFrame = CGRect(x: 0, y: 220, width: 100, height: 40)

    private var plan: RingPlan { plan() }

    // Sub-ring arc frames for `bandPlan`: CPU's above-left of its wedge, Memory's to its left.
    private let cpuArcFrame = CGRect(x: -60, y: 120, width: 50, height: 100)
    private let memoryArcFrame = CGRect(x: -60, y: 230, width: 50, height: 100)
    private let moreArcFrame = CGRect(x: 0, y: 280, width: 400, height: 60)

    /// A plan whose band gives CPU and Memory a sub-ring arc each (as an `.outerBand`
    /// summon reserves them); every other stat has none.
    private var bandPlan: RingPlan {
        plan(arcs: [.stat(.cpu): cpuArcFrame, .stat(.memory): memoryArcFrame])
    }

    private func plan(arcs: [RingArcOwner: CGRect] = [:]) -> RingPlan {
        var nodes: [RingNode: CGRect] = [
            .wedge(.cpu): cpuFrame, .wedge(.memory): memoryFrame, .more: moreFrame,
            .moreItem(.gpu): CGRect(x: 500, y: 0, width: 100, height: 50),
            .moreItem(.temps): CGRect(x: 500, y: 60, width: 100, height: 50),
        ]
        var details: [StatKind: CGRect] = [
            .cpu: CGRect(x: 300, y: 0, width: 150, height: 200),
            .memory: CGRect(x: 300, y: 0, width: 150, height: 200),
            .gpu: CGRect(x: 700, y: 0, width: 150, height: 200),
            .temps: CGRect(x: 700, y: 0, width: 150, height: 200),
        ]
        for kind in StatKind.allCases.dropFirst(8) {
            nodes[.moreItem(kind)] = CGRect(x: 500, y: 120, width: 100, height: 50)
            details[kind] = CGRect(x: 700, y: 0, width: 150, height: 200)
        }
        return RingPlan(mode: arcs.isEmpty ? .sideList : .outerBand,
                        baseFrame: CGRect(x: 0, y: 0, width: 520, height: 520),
                        moreSurface: CGRect(x: 480, y: 0, width: 140, height: 300), nodeFrames: nodes,
                        detailFrames: details, scrollingDetails: [], side: .right, isClamped: false,
                        arcFrames: arcs)
    }

    private func makeState() -> RingBranchState { makeState(plan) }

    private func makeState(_ plan: RingPlan) -> RingBranchState {
        let state = RingBranchState(plan: plan, clock: clock)
        state.summon(plan: plan, pointer: summonPoint)
        return state
    }

    private let cpuArc = RingBranchHit.arc(.stat(.cpu))
    private let cpuArcPoint = CGPoint(x: -35, y: 170)
    private let cpuOwner = RingArcOwner.stat(.cpu)
    private var cpuBranchOpened: [RingBranchCommand] { [.showArc(.stat(.cpu)), .showDetail(.cpu, owner: .stat(.cpu))] }
    private var cpuBranchClosed: [RingBranchCommand] { [.hideDetail, .hideArc(.stat(.cpu))] }

    private func cpuBranch(_ hold: RingHold) -> RingExpansion {
        RingExpansion(arc: .init(owner: cpuOwner, hold: hold), detail: .init(kind: .cpu, owner: cpuOwner, hold: hold))
    }

    /// At most one arc and one card, and both belong to the same owner.
    private func assertSingleBranch(_ state: RingBranchState, _ message: String = "",
                                    file: StaticString = #filePath, line: UInt = #line) {
        let e = state.expansion
        if let arc = e.arc, let detail = e.detail {
            XCTAssertEqual(arc.owner, detail.owner, message, file: file, line: line)
            if arc.owner != .more { XCTAssertEqual(arc.hold, detail.hold, "sub-ring and card share a hold \(message)", file: file, line: line) }
        }
    }

    /// Moves the pointer to a node's frame centre (armed after the first call).
    private func move(_ state: RingBranchState, to hit: RingBranchHit, at point: CGPoint) {
        state.pointerMoved(to: point, hit: hit)
    }

    private func onCPU(_ state: RingBranchState, dx: CGFloat = 0) {
        move(state, to: .node(.wedge(.cpu)), at: CGPoint(x: 50 + dx, y: 50))
    }

    private func advance(_ state: RingBranchState, by seconds: TimeInterval) -> [RingBranchCommand] {
        clock.time += seconds
        return state.fire(token: state.timerToken)
    }

    /// Absolute time, written with the same sums the state uses so boundaries are exact.
    private func at(_ time: TimeInterval, _ state: RingBranchState) -> [RingBranchCommand] {
        clock.time = time
        return state.fire(token: state.timerToken)
    }

    private let cpuDetail = RingExpansion.Detail(kind: .cpu, owner: .stat(.cpu), hold: .preview)

    // MARK: Summon and arming

    func testSummonIsCollapsedAndHoverWaitsForRealMovement() {
        let state = makeState()
        XCTAssertEqual(state.expansion, .collapsed)
        state.pointerMoved(to: CGPoint(x: summonPoint.x + 1, y: summonPoint.y),
                           hit: .node(.wedge(.cpu)))
        XCTAssertFalse(state.isArmed)
        XCTAssertNil(state.nextDeadline, "a stationary pointer under a clamped summon never starts a dwell")
        onCPU(state)
        XCTAssertTrue(state.isArmed)
        XCTAssertEqual(state.nextDeadline ?? -1, clock.time + RingBranchState.dwell, accuracy: 1e-9)
    }

    func testSummonForgetsEarlierExpansion() {
        let state = makeState()
        state.click(.wedge(.cpu))
        XCTAssertNotNil(state.expansion.detail)
        state.summon(plan: plan, pointer: summonPoint)
        XCTAssertEqual(state.expansion, .collapsed)
    }

    // MARK: Dwell boundaries

    func testDwellBelowAtAndAboveTheBoundary() {
        let state = makeState()
        onCPU(state)
        XCTAssertEqual(at(0.349, state), [])
        XCTAssertEqual(state.expansion, .collapsed, "349 ms is below the 350 ms dwell")
        let opened = at(0.35, state)
        XCTAssertEqual(opened, [.showDetail(.cpu, owner: .stat(.cpu))], "exactly 350 ms completes the dwell")
        XCTAssertEqual(state.expansion.detail, cpuDetail)
    }

    func testDwellAboveTheBoundaryStillOpensOnce() {
        let state = makeState()
        onCPU(state)
        XCTAssertEqual(advance(state, by: 0.9), [.showDetail(.cpu, owner: .stat(.cpu))])
        XCTAssertEqual(advance(state, by: 0.9), [], "nothing reopens or repeats")
    }

    func testJitterInsideATargetDoesNotRestartTheDwell() {
        let state = makeState()
        onCPU(state)
        let token = state.timerToken
        clock.time += 0.2
        onCPU(state, dx: 3)
        onCPU(state, dx: -4)
        XCTAssertEqual(state.timerToken, token, "pointer jitter keeps the pending dwell")
        XCTAssertEqual(at(0.35, state), [.showDetail(.cpu, owner: .stat(.cpu))])
    }

    func testMovingToAnotherStatRestartsTheDwell() {
        let state = makeState()
        onCPU(state)
        clock.time += 0.3
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 160))
        XCTAssertEqual(at(0.36, state), [], "cpu's original 350 ms has passed; memory's has not")
        XCTAssertEqual(state.expansion, .collapsed)
        XCTAssertEqual(at(0.3 + 0.35, state), [.showDetail(.memory, owner: .stat(.memory))])
    }

    func testLeavingBeforeTheDwellCancelsIt() {
        let state = makeState()
        onCPU(state)
        move(state, to: .none, at: far)
        XCTAssertNil(state.nextDeadline)
        XCTAssertEqual(advance(state, by: 1), [])
    }

    // MARK: Click and hold

    func testClickOpensHeldImmediatelyAndPreviewBecomesHeld() {
        let state = makeState()
        XCTAssertEqual(state.click(.wedge(.cpu)), [.showDetail(.cpu, owner: .stat(.cpu))])
        XCTAssertEqual(state.expansion.detail?.hold, .held)

        let preview = makeState()
        onCPU(preview)
        _ = advance(preview, by: 0.35)
        XCTAssertEqual(preview.expansion.detail?.hold, .preview)
        XCTAssertEqual(preview.click(.wedge(.cpu)), [], "same stat: no reopen, just held")
        XCTAssertEqual(preview.expansion.detail?.hold, .held)
    }

    func testClickingTheHeldOwnerAgainClosesItAndBlocksReopenUntilReentry() {
        let state = makeState()
        onCPU(state)
        state.click(.wedge(.cpu))
        XCTAssertEqual(state.click(.wedge(.cpu)), [.hideDetail])
        XCTAssertEqual(state.expansion, .collapsed)

        // Stationary pointer and ordinary jitter over the same wedge: still suppressed.
        onCPU(state, dx: 2)
        XCTAssertEqual(advance(state, by: 2), [])
        XCTAssertEqual(state.expansion, .collapsed)

        // Exit, then re-enter: dwell resumes.
        move(state, to: .none, at: far)
        onCPU(state)
        XCTAssertEqual(advance(state, by: 0.35), [.showDetail(.cpu, owner: .stat(.cpu))])
    }

    func testClickingAnotherStatReplacesWithAHeldDetail() {
        let state = makeState()
        state.click(.wedge(.cpu))
        XCTAssertEqual(state.click(.wedge(.memory)), [.showDetail(.memory, owner: .stat(.memory))])
        XCTAssertEqual(state.expansion.detail, .init(kind: .memory, owner: .stat(.memory), hold: .held))
    }

    func testExplicitClickWinsOverPendingDwellAndTransit() {
        let state = makeState()
        onCPU(state)
        _ = advance(state, by: 0.35)                       // cpu preview
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 125)) // crossing sibling, in transit
        XCTAssertEqual(state.click(.wedge(.memory)), [.showDetail(.memory, owner: .stat(.memory))])
        XCTAssertEqual(state.expansion.detail?.hold, .held)
        XCTAssertNil(state.nextDeadline)
    }

    // MARK: Held precedence

    func testHeldDetailIgnoresHoverReplacementAndMore() {
        let state = makeState()
        state.click(.wedge(.cpu))
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 160))
        XCTAssertEqual(advance(state, by: 5), [])
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        XCTAssertEqual(advance(state, by: 5), [])
        XCTAssertEqual(state.expansion.detail, .init(kind: .cpu, owner: .stat(.cpu), hold: .held))
        XCTAssertNil(state.expansion.arc)
    }

    func testHeldDetailSurvivesLeavingWhileUnheldOnesDoNot() {
        let held = makeState()
        held.click(.wedge(.cpu))
        move(held, to: .none, at: far)
        XCTAssertEqual(advance(held, by: 5), [])
        XCTAssertNotNil(held.expansion.detail)

        let preview = makeState()
        onCPU(preview)
        _ = advance(preview, by: 0.35)
        move(preview, to: .none, at: far)
        XCTAssertEqual(advance(preview, by: 0.45), [.hideDetail])
    }

    func testExplicitMoreClickClosesAFavouriteDetailAndHoldsMore() {
        let state = makeState()
        state.click(.wedge(.cpu))
        XCTAssertEqual(state.click(.more), [.hideDetail, .showArc(.more)])
        XCTAssertEqual(state.expansion, RingExpansion(arc: .init(owner: .more, hold: .held), detail: nil))
    }

    // MARK: Leave delay

    func testLeaveDelayBelowAtAndAboveTheBoundary() {
        for (wait, closes) in [(0.449, false), (0.45, true), (0.6, true)] {
            clock.time = 0
            let state = makeState()
            onCPU(state)
            _ = advance(state, by: 0.35)
            move(state, to: .none, at: far)
            let commands = at(0.35 + wait, state)
            XCTAssertEqual(commands, closes ? [.hideDetail] : [], "wait \(wait)")
            XCTAssertEqual(state.expansion.detail == nil, closes, "wait \(wait)")
        }
    }

    func testReentryCancelsTheLeave() {
        let state = makeState()
        onCPU(state)
        _ = advance(state, by: 0.35)
        move(state, to: .none, at: far)
        clock.time += 0.3
        onCPU(state)
        XCTAssertNil(state.nextDeadline)
        XCTAssertEqual(advance(state, by: 5), [])
        XCTAssertNotNil(state.expansion.detail)
    }

    func testPointerOnTheDetailKeepsThePreviewOpen() {
        let state = makeState()
        onCPU(state)
        _ = advance(state, by: 0.35)
        move(state, to: .inert, at: CGPoint(x: 200, y: 50))     // gap between wedge and card
        move(state, to: .detail, at: CGPoint(x: 350, y: 50))
        XCTAssertEqual(advance(state, by: 5), [])
        XCTAssertNotNil(state.expansion.detail)
    }

    // MARK: Transit and sibling switching

    func testTransitSuppressesCrossedSiblingForAtMost700Ms() {
        let state = makeState()
        onCPU(state)
        _ = advance(state, by: 0.35)                        // cpu preview open
        move(state, to: .inert, at: CGPoint(x: 120, y: 60)) // leaves the wedge: transit begins
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 125))   // crossing a sibling
        XCTAssertEqual(at(0.35 + 0.40, state), [], "a 350 ms dwell on the sibling cannot complete in transit")
        XCTAssertEqual(state.expansion.detail?.kind, .cpu)
        XCTAssertEqual(at(0.35 + 0.69, state), [], "690 ms: still inside the grace")
        XCTAssertEqual(state.expansion.detail?.kind, .cpu)
        XCTAssertEqual(at(0.35 + 0.7, state), [.showDetail(.memory, owner: .stat(.memory))],
                       "at 700 ms a pointer that stopped on the sibling resumes normal selection")
    }

    func testTransitIntoTheDetailNeverSelectsTheCrossedSibling() {
        let state = makeState()
        onCPU(state)
        _ = advance(state, by: 0.35)
        move(state, to: .inert, at: CGPoint(x: 120, y: 60))
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 125))
        clock.time += 0.2
        move(state, to: .detail, at: CGPoint(x: 350, y: 60))
        XCTAssertEqual(advance(state, by: 5), [])
        XCTAssertEqual(state.expansion.detail?.kind, .cpu)
    }

    func testDeliberateMoveToASiblingOutsideTheRouteReplacesBeforeTheLeave() {
        let state = makeState()
        onCPU(state)
        _ = advance(state, by: 0.35)
        // Straight down onto memory is inside this hull only while in transit; arriving
        // after the grace shows normal 350 ms dwell replacing the preview.
        clock.time += 0.8
        move(state, to: .none, at: CGPoint(x: -300, y: 400))   // leaves everything: leave starts
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 160))
        XCTAssertEqual(advance(state, by: 0.35), [.showDetail(.memory, owner: .stat(.memory))],
                       "dwell (350 ms) completes before the 450 ms leave")
        XCTAssertEqual(state.expansion.detail?.kind, .memory)
        XCTAssertEqual(advance(state, by: 5), [])
    }

    func testPointerStrandedInTheRouteClosesAfterGraceAndLeave() {
        let state = makeState()
        onCPU(state)
        _ = advance(state, by: 0.35)
        move(state, to: .inert, at: CGPoint(x: 200, y: 60))   // in the route, over nothing
        XCTAssertEqual(at(0.35 + 0.7, state), [], "route protects the branch for the grace")
        XCTAssertEqual(at(0.35 + 0.7 + 0.45, state), [.hideDetail], "then the normal 450 ms leave applies")
    }

    func testTravelRegionToleranceIsTwelvePoints() {
        let region = RingTravelRegion(from: CGRect(x: 0, y: 0, width: 100, height: 100),
                                      to: CGRect(x: 300, y: 0, width: 150, height: 200))
        XCTAssertTrue(region.contains(CGPoint(x: 50, y: -11.9)))
        XCTAssertTrue(region.contains(CGPoint(x: 50, y: -12)))
        XCTAssertFalse(region.contains(CGPoint(x: 50, y: -12.1)))
        XCTAssertTrue(region.contains(CGPoint(x: 200, y: 60)))
        XCTAssertFalse(region.contains(CGPoint(x: 200, y: 400)))
    }

    // MARK: More branch

    func testDwellOnMoreOpensPreviewAndClickHoldsThenClosesWithItsChild() {
        let state = makeState()
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        XCTAssertEqual(advance(state, by: 0.35), [.showArc(.more)])
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .preview))
        XCTAssertEqual(state.click(.more), [], "first click on a hover-open More holds it")
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .held))
        state.click(.moreItem(.gpu))
        XCTAssertEqual(state.click(.more), [.hideDetail, .hideArc(.more)], "closing a held More closes its child")
        XCTAssertEqual(state.expansion, .collapsed)
    }

    func testMoreSupportsEveryNonFavouriteNotOnlyFour() {
        let state = makeState()
        let nonFavourites = Array(StatKind.allCases.dropFirst(8))
        XCTAssertGreaterThanOrEqual(nonFavourites.count, 1)
        var kinds: [StatKind] = []
        for kind in [StatKind.gpu, .temps] + nonFavourites where !kinds.contains(kind) { kinds.append(kind) }
        state.click(.more)
        for kind in kinds {
            XCTAssertEqual(state.click(.moreItem(kind)), [.showDetail(kind, owner: .more)], "\(kind)")
            XCTAssertEqual(state.expansion.detail, .init(kind: kind, owner: .more, hold: .held))
            XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .held))
        }
    }

    func testMoreItemClickWithoutOpenMoreIsIgnored() {
        let state = makeState()
        XCTAssertEqual(state.click(.moreItem(.gpu)), [])
        XCTAssertEqual(state.expansion, .collapsed)
    }

    func testMoreChildKeepsMoreVisibleAndPreviewSwapsBetweenEntries() {
        let state = makeState()
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        _ = advance(state, by: 0.35)
        move(state, to: .arc(.more), at: CGPoint(x: 490, y: 200))
        move(state, to: .node(.moreItem(.gpu)), at: CGPoint(x: 550, y: 20))
        XCTAssertEqual(advance(state, by: 0.35), [.showDetail(.gpu, owner: .more)])
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .preview))
        move(state, to: .node(.moreItem(.temps)), at: CGPoint(x: 550, y: 80))
        XCTAssertEqual(advance(state, by: 0.35), [.showDetail(.temps, owner: .more)])
        XCTAssertEqual(state.expansion.detail?.kind, .temps)
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .preview))
    }

    func testHeldChildHoldsMoreAndResistsHover() {
        let state = makeState()
        state.click(.more)
        state.click(.moreItem(.gpu))
        move(state, to: .node(.moreItem(.temps)), at: CGPoint(x: 550, y: 80))
        XCTAssertEqual(advance(state, by: 5), [])
        move(state, to: .none, at: far)
        XCTAssertEqual(advance(state, by: 5), [])
        XCTAssertEqual(state.expansion, RingExpansion(arc: .init(owner: .more, hold: .held), detail: .init(kind: .gpu, owner: .more, hold: .held)))
    }

    func testHeldMoreStillSwapsItsPreviewChildOnHover() {
        let state = makeState()
        state.click(.more)
        move(state, to: .node(.moreItem(.gpu)), at: CGPoint(x: 550, y: 20))
        XCTAssertEqual(advance(state, by: 0.35), [.showDetail(.gpu, owner: .more)])
        XCTAssertEqual(state.expansion.detail?.hold, .preview)
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .held))
        move(state, to: .none, at: far)
        XCTAssertEqual(advance(state, by: 0.45), [.hideDetail], "only the preview child leaves; held More stays")
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .held))
    }

    func testSelectingAFavouriteFromAPreviewMoreClosesMoreAtomically() {
        let state = makeState()
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        _ = advance(state, by: 0.35)
        move(state, to: .node(.wedge(.cpu)), at: CGPoint(x: 50, y: 50))
        let commands = advance(state, by: 5)
        XCTAssertEqual(commands, [.hideArc(.more), .showDetail(.cpu, owner: .stat(.cpu))])
        XCTAssertNil(state.expansion.arc)
    }

    func testExplicitFavouriteClickWhileMoreIsHeldClosesMoreAndOpensItHeld() {
        let state = makeState()
        state.click(.more)
        XCTAssertEqual(state.click(.wedge(.cpu)), [.hideArc(.more), .showDetail(.cpu, owner: .stat(.cpu))])
        XCTAssertEqual(state.expansion, RingExpansion(arc: nil, detail: .init(kind: .cpu, owner: .stat(.cpu), hold: .held)))
    }

    func testHoverCannotReplaceAHeldMore() {
        let state = makeState()
        state.click(.more)
        onCPU(state)
        XCTAssertEqual(advance(state, by: 5), [])
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .held))
    }

    func testReturningToTheMoreWedgeKeepsAPreviewChildAndTheArc() {
        let state = makeState()
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        _ = advance(state, by: 0.35)
        move(state, to: .node(.moreItem(.gpu)), at: CGPoint(x: 550, y: 20))
        XCTAssertEqual(advance(state, by: 0.35), [.showDetail(.gpu, owner: .more)])
        move(state, to: .arc(.more), at: CGPoint(x: 490, y: 200))
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        XCTAssertEqual(advance(state, by: 0.449), [])
        XCTAssertEqual(advance(state, by: 5), [], "resting on the arc's parent wedge closes nothing and reopens nothing")
        XCTAssertEqual(state.expansion, RingExpansion(arc: .init(owner: .more, hold: .preview),
                                                      detail: .init(kind: .gpu, owner: .more, hold: .preview)))
    }

    func testReturningToAHeldMoreWedgeKeepsItsPreviewChild() {
        let state = makeState()
        state.click(.more)
        move(state, to: .node(.moreItem(.gpu)), at: CGPoint(x: 550, y: 20))
        XCTAssertEqual(advance(state, by: 0.35), [.showDetail(.gpu, owner: .more)])
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        XCTAssertEqual(advance(state, by: 5), [])
        XCTAssertEqual(state.expansion.detail, .init(kind: .gpu, owner: .more, hold: .preview))
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .held))
    }

    func testLeavingTheMoreArcPaddingTowardsTheChildCardGetsTheTransitGrace() {
        let state = makeState()
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        _ = advance(state, by: 0.35)
        move(state, to: .node(.moreItem(.gpu)), at: CGPoint(x: 550, y: 20))
        XCTAssertEqual(advance(state, by: 0.35), [.showDetail(.gpu, owner: .more)])
        move(state, to: .arc(.more), at: CGPoint(x: 590, y: 45))      // arc padding beside the entry
        move(state, to: .none, at: CGPoint(x: 650, y: 40))             // on the entry-to-card route
        XCTAssertEqual(at(0.35 + 0.35 + 0.69, state), [], "690 ms: still inside the grace")
        XCTAssertEqual(state.expansion.detail?.kind, .gpu)
        XCTAssertEqual(at(0.35 + 0.35 + 0.7, state), [], "grace ends; the 450 ms leave begins")
        XCTAssertEqual(at(0.35 + 0.35 + 0.7 + 0.449, state), [])
        XCTAssertEqual(at(0.35 + 0.35 + 0.7 + 0.45, state), [.hideDetail, .hideArc(.more)])
    }

    func testLeavingAPreviewMoreClosesItAndItsChild() {
        let state = makeState()
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        _ = advance(state, by: 0.35)
        move(state, to: .node(.moreItem(.gpu)), at: CGPoint(x: 550, y: 20))
        _ = advance(state, by: 0.35)
        move(state, to: .none, at: far)
        XCTAssertEqual(advance(state, by: 0.45), [.hideDetail, .hideArc(.more)])
        XCTAssertEqual(state.expansion, .collapsed)
    }

    // MARK: Detail interaction

    func testMouseDownInAPreviewDetailPromotesItBeforeControlsAct() {
        let state = makeState()
        onCPU(state)
        _ = advance(state, by: 0.35)
        XCTAssertEqual(state.detailInteracted(), [])
        XCTAssertEqual(state.expansion.detail?.hold, .held)
        move(state, to: .none, at: far)
        XCTAssertEqual(advance(state, by: 5), [], "promoted detail no longer closes on leave")
    }

    func testMouseDownInAMoreChildDetailHoldsTheMoreBranchToo() {
        let state = makeState()
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        _ = advance(state, by: 0.35)
        move(state, to: .node(.moreItem(.gpu)), at: CGPoint(x: 550, y: 20))
        _ = advance(state, by: 0.35)
        state.detailInteracted()
        XCTAssertEqual(state.expansion, RingExpansion(arc: .init(owner: .more, hold: .held), detail: .init(kind: .gpu, owner: .more, hold: .held)))
    }

    // MARK: Escape

    func testEscapeClosesDetailThenMoreThenTheHUD() {
        let state = makeState()
        state.click(.more)
        state.click(.moreItem(.gpu))
        XCTAssertEqual(state.escape(), [.hideDetail])
        XCTAssertEqual(state.expansion, RingExpansion(arc: .init(owner: .more, hold: .held), detail: nil), "More stays while it owned the detail")
        XCTAssertEqual(state.escape(), [.hideArc(.more)])
        XCTAssertEqual(state.expansion, .collapsed)
        XCTAssertEqual(state.escape(), [.hideHUD])
    }

    func testEscapeOnAFavouriteDetailThenHUDAndNeverNeedsPinState() {
        // The state has no pin input at all: the hierarchy is identical while pinned.
        let state = makeState()
        state.click(.wedge(.cpu))
        XCTAssertEqual(state.escape(), [.hideDetail])
        XCTAssertEqual(state.escape(), [.hideHUD])
    }

    func testEscapeAndCloseBlockReopeningUnderTheStationaryPointer() {
        let state = makeState()
        onCPU(state)
        _ = advance(state, by: 0.35)
        state.escape()
        onCPU(state, dx: 1)
        XCTAssertEqual(advance(state, by: 2), [])
        XCTAssertEqual(state.expansion, .collapsed)

        let closed = makeState()
        onCPU(closed)
        closed.click(.wedge(.cpu))
        XCTAssertEqual(closed.closeDetail(), [.hideDetail])
        onCPU(closed, dx: 1)
        XCTAssertEqual(advance(closed, by: 2), [])
        XCTAssertEqual(closed.expansion, .collapsed)
    }

    func testEscapeFromPreviewCancelsAPendingLeaveAndDwell() {
        let state = makeState()
        onCPU(state)
        _ = advance(state, by: 0.35)
        state.escape()
        XCTAssertNil(state.nextDeadline)
    }

    // MARK: Stale generations

    func testStaleTimerTokenAfterHideDoesNothing() {
        let state = makeState()
        onCPU(state)
        let stale = state.timerToken
        state.hide()
        clock.time += 5
        XCTAssertEqual(state.fire(token: stale), [])
        XCTAssertEqual(state.expansion, .collapsed)
    }

    func testStaleTimerTokenAfterANewerSelectionDoesNothing() {
        let state = makeState()
        onCPU(state)
        let stale = state.timerToken
        clock.time += 0.1
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 160))
        clock.time += 0.3
        XCTAssertEqual(state.fire(token: stale), [], "the old cpu callback is stale")
        XCTAssertEqual(state.expansion, .collapsed)
    }

    func testStaleLeaveCallbackCannotCloseAfterReentry() {
        let state = makeState()
        onCPU(state)
        _ = advance(state, by: 0.35)
        move(state, to: .none, at: far)
        let stale = state.timerToken
        clock.time += 0.2
        onCPU(state)
        clock.time += 1
        XCTAssertEqual(state.fire(token: stale), [])
        XCTAssertNotNil(state.expansion.detail)
    }

    func testEarlyFireWithTheCurrentTokenChangesNothing() {
        let state = makeState()
        onCPU(state)
        let token = state.timerToken
        clock.time += 0.1
        XCTAssertEqual(state.fire(token: token), [])
        XCTAssertEqual(state.timerToken, token)
        XCTAssertNotNil(state.nextDeadline)
    }

    func testStaleCallbackAfterSummonDragAndSettings() {
        let state = makeState()
        onCPU(state)
        var stale = state.timerToken
        state.summon(plan: plan, pointer: summonPoint)
        clock.time += 5
        XCTAssertEqual(state.fire(token: stale), [])

        onCPU(state)
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 160))
        stale = state.timerToken
        state.dragBegan()
        clock.time += 5
        XCTAssertEqual(state.fire(token: stale), [])
        XCTAssertEqual(state.expansion, .collapsed)

        state.dragEnded(plan: plan, pointer: CGPoint(x: 50, y: 50))
        onCPU(state)
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 160))
        stale = state.timerToken
        state.settingsRequested()
        clock.time += 5
        XCTAssertEqual(state.fire(token: stale), [])
        XCTAssertEqual(state.expansion, .collapsed)
    }

    func testGenerationsAdvanceOnDismissalAndBranchChange() {
        let state = makeState()
        let g0 = state.generation, b0 = state.branchGeneration
        state.click(.wedge(.cpu))
        XCTAssertEqual(state.generation, g0)
        XCTAssertGreaterThan(state.branchGeneration, b0)
        state.hide()
        XCTAssertGreaterThan(state.generation, g0)
    }

    // MARK: Drag, Settings, display

    func testDragCancelsPendingHoverClosesExpansionsAndResumesOnlyAfterMovement() {
        let state = makeState()
        state.click(.more)
        state.click(.moreItem(.gpu))
        XCTAssertEqual(state.dragBegan(), [.hideDetail, .hideArc(.more)])
        XCTAssertEqual(state.expansion, .collapsed)
        XCTAssertNil(state.nextDeadline)

        let after = CGPoint(x: 50, y: 50)
        state.dragEnded(plan: plan, pointer: after)
        state.pointerMoved(to: CGPoint(x: after.x + 1, y: after.y), hit: .node(.wedge(.cpu)))
        XCTAssertNil(state.nextDeadline, "no hover on the wedge that landed under the pointer")
        onCPU(state, dx: 3)
        XCTAssertNotNil(state.nextDeadline)
    }

    func testSettingsAndDisplayLossCloseDescendants() {
        let state = makeState()
        state.click(.more)
        state.click(.moreItem(.gpu))
        XCTAssertEqual(state.settingsClicked(), [.hideDetail, .hideArc(.more), .openSettings])
        XCTAssertEqual(state.expansion, .collapsed)

        state.click(.wedge(.cpu))
        XCTAssertEqual(state.displayChanged(), [.hideDetail, .hideHUD])
        XCTAssertEqual(state.expansion, .collapsed)
        XCTAssertNil(state.nextDeadline)
    }

    // MARK: Accessibility

    func testExpandedStateAndPressFollowTheClickRows() {
        let state = makeState()
        XCTAssertFalse(state.isExpanded(.wedge(.cpu)))
        state.click(.wedge(.cpu))                     // Press == click
        XCTAssertTrue(state.isExpanded(.wedge(.cpu)))
        XCTAssertFalse(state.isExpanded(.wedge(.memory)))
        state.click(.more)
        XCTAssertTrue(state.isExpanded(.more))
        XCTAssertFalse(state.isExpanded(.wedge(.cpu)))
        state.click(.moreItem(.gpu))
        XCTAssertTrue(state.isExpanded(.moreItem(.gpu)))
        XCTAssertFalse(state.isExpanded(.moreItem(.temps)))
        state.click(.moreItem(.gpu))                  // second Press on the held owner closes
        XCTAssertFalse(state.isExpanded(.moreItem(.gpu)))
        XCTAssertTrue(state.isExpanded(.more))
    }

    func testCrossingTheCentreAloneOpensNothing() {
        let state = makeState()
        move(state, to: .inert, at: CGPoint(x: 260, y: 260))
        move(state, to: .inert, at: CGPoint(x: 280, y: 260))
        XCTAssertNil(state.nextDeadline)
        XCTAssertEqual(state.expansion, .collapsed)
    }

    // MARK: Favourite sub-ring branch (outer band)

    func testFavouriteSubRingAndCardPreviewTogetherAtTheDwellBoundary() {
        for (wait, opens) in [(0.349, false), (0.35, true), (0.351, true)] {
            clock.time = 0
            let state = makeState(bandPlan)
            onCPU(state)
            XCTAssertEqual(at(wait, state), opens ? cpuBranchOpened : [], "dwell \(wait)")
            XCTAssertEqual(state.expansion, opens ? cpuBranch(.preview) : .collapsed, "dwell \(wait)")
        }
    }

    func testClickHoldsSubRingAndCardAndOwnerClickClosesBoth() {
        let state = makeState(bandPlan)
        onCPU(state)
        XCTAssertEqual(state.click(.wedge(.cpu)), cpuBranchOpened)
        XCTAssertEqual(state.expansion, cpuBranch(.held))
        XCTAssertTrue(state.isExpanded(.wedge(.cpu)))
        XCTAssertEqual(state.click(.wedge(.cpu)), cpuBranchClosed)
        XCTAssertEqual(state.expansion, .collapsed)
        XCTAssertFalse(state.isExpanded(.wedge(.cpu)))

        onCPU(state, dx: 2)
        XCTAssertEqual(advance(state, by: 2), [], "the stationary pointer cannot reopen the closed branch")
        move(state, to: .none, at: far)
        onCPU(state)
        XCTAssertEqual(advance(state, by: 0.35), cpuBranchOpened, "exit and re-entry resume dwell")
    }

    func testClickingAPreviewedFavouriteHoldsSubRingAndCardWithoutReopening() {
        let state = makeState(bandPlan)
        onCPU(state)
        XCTAssertEqual(advance(state, by: 0.35), cpuBranchOpened)
        XCTAssertEqual(state.click(.wedge(.cpu)), [])
        XCTAssertEqual(state.expansion, cpuBranch(.held))
        move(state, to: .none, at: far)
        XCTAssertEqual(advance(state, by: 5), [], "a held branch survives leaving")
    }

    func testCloseOrOneEscapeClosesTheSubRingWithItsCardThenEscapeHidesTheHUD() {
        let closed = makeState(bandPlan)
        closed.click(.wedge(.cpu))
        XCTAssertEqual(closed.closeDetail(), cpuBranchClosed)
        XCTAssertEqual(closed.expansion, .collapsed)

        let escaped = makeState(bandPlan)
        onCPU(escaped)
        _ = advance(escaped, by: 0.35)
        XCTAssertEqual(escaped.escape(), cpuBranchClosed, "one Escape closes a favourite's sub-ring and card")
        onCPU(escaped, dx: 1)
        XCTAssertEqual(advance(escaped, by: 2), [], "no stationary reopen after Escape")
        XCTAssertEqual(escaped.escape(), [.hideHUD])
    }

    func testMouseDownInAPreviewSubRingHoldsTheBranch() {
        let state = makeState(bandPlan)
        onCPU(state)
        _ = advance(state, by: 0.35)
        move(state, to: cpuArc, at: cpuArcPoint)
        XCTAssertEqual(state.arcInteracted(), [])
        XCTAssertEqual(state.expansion, cpuBranch(.held))
        move(state, to: .none, at: far)
        XCTAssertEqual(advance(state, by: 5), [], "promoted branch no longer closes on leave")
        XCTAssertEqual(state.arcInteracted(), [], "already held: nothing changes")
    }

    func testArcMouseDownPromotesNeitherMoreNorAnEmptyBranch() {
        let state = makeState(bandPlan)
        XCTAssertEqual(state.arcInteracted(), [])
        XCTAssertEqual(state.expansion, .collapsed)
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        XCTAssertEqual(advance(state, by: 0.35), [.showArc(.more)])
        XCTAssertEqual(state.arcInteracted(), [], "More's arc padding is not preview content")
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .preview))
    }

    func testMouseDownInThePreviewCardAlsoHoldsItsSubRing() {
        let state = makeState(bandPlan)
        onCPU(state)
        _ = advance(state, by: 0.35)
        XCTAssertEqual(state.detailInteracted(), [])
        XCTAssertEqual(state.expansion, cpuBranch(.held))
    }

    func testSegmentHoverShowsACaptionOnlyAndKeepsThePreview() {
        let state = makeState(bandPlan)
        onCPU(state)
        _ = advance(state, by: 0.35)
        let segment = RingSegmentRef(stat: .cpu, index: 3)
        move(state, to: .segment(segment), at: cpuArcPoint)
        XCTAssertEqual(state.hoveredSegment, segment)
        XCTAssertNil(state.hovered, "a segment is not a node")
        XCTAssertNil(state.nextDeadline, "no dwell target and no leave inside the sub-ring")
        XCTAssertEqual(advance(state, by: 5), [])
        XCTAssertEqual(state.expansion, cpuBranch(.preview), "no further level opens")
        move(state, to: cpuArc, at: cpuArcPoint)
        XCTAssertNil(state.hoveredSegment)
        move(state, to: .segment(segment), at: cpuArcPoint)
        state.escape()
        XCTAssertNil(state.hoveredSegment, "the caption goes with its sub-ring")
    }

    func testASegmentOfAClosedSubRingIsOutsideAndShowsNoCaption() {
        let state = makeState(bandPlan)
        onCPU(state)
        _ = advance(state, by: 0.35)
        move(state, to: .segment(.init(stat: .memory, index: 0)), at: CGPoint(x: -35, y: 280))
        XCTAssertNil(state.hoveredSegment)
        XCTAssertEqual(advance(state, by: 0.45), cpuBranchClosed)
    }

    func testSubRingIsInsideTheBranchAndTheLeaveBoundaryStillHolds() {
        for (wait, closes) in [(0.449, false), (0.45, true), (0.6, true)] {
            clock.time = 0
            let state = makeState(bandPlan)
            onCPU(state)
            _ = advance(state, by: 0.35)
            move(state, to: cpuArc, at: cpuArcPoint)
            XCTAssertNil(state.nextDeadline, "on the sub-ring: inside")
            move(state, to: .none, at: far)
            XCTAssertEqual(at(0.35 + wait, state), closes ? cpuBranchClosed : [], "wait \(wait)")
            XCTAssertEqual(state.expansion == .collapsed, closes, "wait \(wait)")
        }
    }

    func testTravelFromTheSubRingTowardsTheCardIsProtectedForTheGraceOnly() {
        let state = makeState(bandPlan)
        onCPU(state)
        _ = advance(state, by: 0.35)
        move(state, to: cpuArc, at: cpuArcPoint)
        // Between the sub-ring and the card, outside the wedge-to-card route.
        move(state, to: .none, at: CGPoint(x: 150, y: 215))
        XCTAssertEqual(at(0.35 + 0.69, state), [])
        XCTAssertEqual(state.expansion, cpuBranch(.preview))
        XCTAssertEqual(at(0.35 + 0.7, state), [], "grace ends; the 450 ms leave begins")
        XCTAssertEqual(at(0.35 + 0.7 + 0.449, state), [])
        XCTAssertEqual(at(0.35 + 0.7 + 0.45, state), cpuBranchClosed)
    }

    func testAFavouriteWithoutASubRingOpensItsCardAlone() {
        let state = makeState(plan(arcs: [.stat(.cpu): cpuArcFrame]))
        XCTAssertEqual(state.click(.wedge(.memory)), [.showDetail(.memory, owner: .stat(.memory))])
        XCTAssertEqual(state.expansion, RingExpansion(arc: nil, detail: .init(kind: .memory, owner: .stat(.memory), hold: .held)))
        XCTAssertEqual(state.escape(), [.hideDetail])

        let hover = makeState(plan(arcs: [.stat(.cpu): cpuArcFrame]))
        move(hover, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 160))
        XCTAssertEqual(advance(hover, by: 0.35), [.showDetail(.memory, owner: .stat(.memory))])
        XCTAssertNil(hover.expansion.arc)
    }

    func testClickingAnotherFavouriteReplacesTheWholeBranchAtomically() {
        let state = makeState(bandPlan)
        state.click(.wedge(.cpu))
        XCTAssertEqual(state.click(.wedge(.memory)),
                       [.hideArc(.stat(.cpu)), .showArc(.stat(.memory)), .showDetail(.memory, owner: .stat(.memory))])
        XCTAssertEqual(state.expansion, RingExpansion(arc: .init(owner: .stat(.memory), hold: .held),
                                                      detail: .init(kind: .memory, owner: .stat(.memory), hold: .held)))
    }

    func testPreviewReplacementBetweenFavouritesKeepsOneArcAndOneCard() {
        let state = makeState(bandPlan)
        onCPU(state)
        _ = advance(state, by: 0.35)
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 160))   // crossing inside the route
        XCTAssertEqual(at(0.35 + 0.69, state), [])
        XCTAssertEqual(state.expansion, cpuBranch(.preview))
        XCTAssertEqual(at(0.35 + 0.7, state),
                       [.hideArc(.stat(.cpu)), .showArc(.stat(.memory)), .showDetail(.memory, owner: .stat(.memory))])
        assertSingleBranch(state)
    }

    func testMoreClickReplacesAFavouriteBranchAndAFavouriteClickReplacesMore() {
        let state = makeState(bandPlan)
        state.click(.wedge(.cpu))
        XCTAssertEqual(state.click(.more), [.hideDetail, .hideArc(.stat(.cpu)), .showArc(.more)])
        XCTAssertEqual(state.expansion, RingExpansion(arc: .init(owner: .more, hold: .held), detail: nil))
        state.click(.moreItem(.gpu))
        XCTAssertEqual(state.click(.wedge(.cpu)),
                       [.hideArc(.more), .showArc(.stat(.cpu)), .showDetail(.cpu, owner: .stat(.cpu))])
        XCTAssertEqual(state.expansion, cpuBranch(.held))
    }

    func testPreviewMoreGivesWayToAFavouriteBranchAtomically() {
        let state = makeState(bandPlan)
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        _ = advance(state, by: 0.35)
        onCPU(state)
        XCTAssertEqual(advance(state, by: 5), [.hideArc(.more), .showArc(.stat(.cpu)), .showDetail(.cpu, owner: .stat(.cpu))])
        XCTAssertEqual(state.expansion, cpuBranch(.preview))
    }

    func testHeldFavouriteBranchResistsHoverOnSiblingsMoreAndSegments() {
        let state = makeState(bandPlan)
        state.click(.wedge(.cpu))
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 160))
        XCTAssertEqual(advance(state, by: 5), [])
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        XCTAssertEqual(advance(state, by: 5), [])
        move(state, to: .segment(.init(stat: .cpu, index: 0)), at: cpuArcPoint)
        XCTAssertEqual(advance(state, by: 5), [])
        XCTAssertEqual(state.expansion, cpuBranch(.held))
    }

    func testAStatInTheMoreArcOpensItsCardOnlyAndKeepsTheMoreArc() {
        // GPU is given an arc frame on purpose: reached through More it still opens no sub-ring.
        let state = makeState(plan(arcs: [.more: moreArcFrame, .stat(.gpu): cpuArcFrame]))
        XCTAssertEqual(state.click(.more), [.showArc(.more)])
        XCTAssertEqual(state.click(.moreItem(.gpu)), [.showDetail(.gpu, owner: .more)])
        XCTAssertEqual(state.expansion, RingExpansion(arc: .init(owner: .more, hold: .held),
                                                      detail: .init(kind: .gpu, owner: .more, hold: .held)))
        XCTAssertFalse(state.isExpanded(.wedge(.gpu)))
        XCTAssertTrue(state.isExpanded(.moreItem(.gpu)))
        XCTAssertEqual(state.escape(), [.hideDetail], "card first; the More arc stays")
        XCTAssertEqual(state.escape(), [.hideArc(.more)])
        XCTAssertEqual(state.escape(), [.hideHUD])
    }

    func testTravelFromTheMoreWedgeIntoItsArcUsesTheArcFrame() {
        let state = makeState(plan(arcs: [.more: moreArcFrame]))
        move(state, to: .node(.more), at: CGPoint(x: 50, y: 240))
        XCTAssertEqual(advance(state, by: 0.35), [.showArc(.more)])
        move(state, to: .none, at: CGPoint(x: 50, y: 270))      // between wedge and arc
        XCTAssertEqual(at(0.35 + 0.69, state), [])
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .preview))
        move(state, to: .arc(.more), at: CGPoint(x: 200, y: 300))
        XCTAssertNil(state.nextDeadline)
        XCTAssertEqual(advance(state, by: 5), [])
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .preview))
    }

    func testRapidMovementBetweenParentsKeepsAtMostOneArcAndOneCard() {
        let state = makeState(bandPlan)
        let route: [(RingBranchHit, CGPoint)] = [
            (.node(.wedge(.cpu)), CGPoint(x: 50, y: 50)), (.node(.wedge(.memory)), CGPoint(x: 50, y: 160)),
            (.node(.more), CGPoint(x: 50, y: 240)), (cpuArc, cpuArcPoint), (.none, far),
        ]
        var stale: [UInt64] = []
        for step in 0..<25 {
            let (hit, point) = route[step % route.count]
            stale.append(state.timerToken)
            move(state, to: hit, at: point)
            clock.time += step.isMultiple(of: 2) ? 0.4 : 0.2
            _ = state.fire(token: state.timerToken)
            assertSingleBranch(state, "step \(step)")
        }
        let settled = state.expansion
        for token in stale where token != state.timerToken {
            XCTAssertEqual(state.fire(token: token), [])
        }
        XCTAssertEqual(state.expansion, settled, "stale callbacks change nothing")
    }

    func testStaleCallbacksCannotReopenASubRingAfterHideDragSettingsOrDisplayChange() {
        let closers: [(String, (RingBranchState) -> Void)] = [
            ("hide", { _ = $0.hide() }), ("drag", { _ = $0.dragBegan() }),
            ("settings", { _ = $0.settingsRequested() }), ("display", { _ = $0.displayChanged() }),
        ]
        for (name, close) in closers {
            clock.time = 0
            let pending = makeState(bandPlan)
            onCPU(pending)
            let staleDwell = pending.timerToken
            close(pending)
            clock.time = 5
            XCTAssertEqual(pending.fire(token: staleDwell), [], name)
            XCTAssertEqual(pending.expansion, .collapsed, name)

            clock.time = 0
            let open = makeState(bandPlan)
            onCPU(open)
            _ = at(0.35, open)
            move(open, to: .none, at: far)
            let staleLeave = open.timerToken
            XCTAssertEqual(open.expansion, cpuBranch(.preview), name)
            close(open)
            XCTAssertEqual(open.expansion, .collapsed, name)
            clock.time = 5
            XCTAssertEqual(open.fire(token: staleLeave), [], name)
            XCTAssertNil(open.nextDeadline, name)
        }
    }

    func testStaleDwellCannotOpenASubRingAfterANewerSelection() {
        let state = makeState(bandPlan)
        onCPU(state)
        let stale = state.timerToken
        clock.time = 0.1
        move(state, to: .node(.wedge(.memory)), at: CGPoint(x: 50, y: 160))
        clock.time = 0.36
        XCTAssertEqual(state.fire(token: stale), [], "cpu's earlier dwell is stale")
        XCTAssertEqual(state.expansion, .collapsed)
        XCTAssertEqual(at(0.1 + 0.35, state), [.showArc(.stat(.memory)), .showDetail(.memory, owner: .stat(.memory))])
    }

    func testDragAndSettingsCloseAnOpenSubRingWithItsCard() {
        let state = makeState(bandPlan)
        state.click(.wedge(.cpu))
        XCTAssertEqual(state.dragBegan(), cpuBranchClosed)
        state.dragEnded(plan: bandPlan, pointer: CGPoint(x: 50, y: 50))
        state.click(.wedge(.cpu))
        XCTAssertEqual(state.settingsRequested(), cpuBranchClosed + [.openSettings])
        state.click(.wedge(.cpu))
        XCTAssertEqual(state.displayChanged(), cpuBranchClosed + [.hideHUD])
        XCTAssertEqual(state.expansion, .collapsed)
    }

    // MARK: Branch commands the panel controller carries out

    /// The controller drives the state directly: every arc surface it shows or hides is named
    /// by its owner, so sub-ring and More arcs need no translation layer.
    func testBranchCommandsNameEveryArcSurfaceByItsOwner() {
        let state = makeState(plan(arcs: [.stat(.cpu): cpuArcFrame, .more: moreArcFrame]))
        XCTAssertEqual(state.click(.wedge(.cpu)), cpuBranchOpened, "the sub-ring opens with its card")
        XCTAssertEqual(state.click(.more), [.hideDetail, .hideArc(.stat(.cpu)), .showArc(.more)])
        XCTAssertEqual(state.expansion.arc, .init(owner: .more, hold: .held))
        XCTAssertEqual(state.click(.moreItem(.gpu)), [.showDetail(.gpu, owner: .more)])
        XCTAssertEqual(state.escape(), [.hideDetail])
        XCTAssertEqual(state.escape(), [.hideArc(.more)])
        XCTAssertEqual(state.pointerMoved(to: CGPoint(x: 50, y: 160), hit: .node(.wedge(.memory))), [])
        XCTAssertNotNil(state.nextDeadline, "branch hits drive the dwell directly")
        XCTAssertEqual(state.escape(), [.hideHUD])
    }
}

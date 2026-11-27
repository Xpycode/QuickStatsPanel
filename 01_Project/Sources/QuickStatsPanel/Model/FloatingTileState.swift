import Foundation

#if DEBUG

/// What the floating-tile HUD shows.
enum FloatingTileMode: Equatable, Sendable {
    case hidden
    case overview
    case detail(StatKind)
}

/// What the controller must do after a state change.
enum FloatingTileEffect: Equatable, Sendable {
    case none
    /// Show every primary again (closing any detail); restore keyboard focus to `focus` when
    /// keyboard focus is in the HUD.
    case showOverview(focus: FloatingTileTarget?)
    /// Open this stat's detail beside its primary, which stays where it is, and hide the other
    /// primaries (`hiding`, in saved order).
    case showDetail(StatKind, hiding: [StatKind], focus: FloatingTileTarget)
    case dismiss
}

/// Pure interaction state of the prototype: overview, detail, hidden, and the focused target.
/// Geometry comes from the frozen `FloatingTilePlan`; this never moves anything.
struct FloatingTileState: Equatable, Sendable {
    private(set) var mode: FloatingTileMode = .hidden
    /// The keyboard-focused target, or nil when keyboard focus is not in the HUD.
    private(set) var focus: FloatingTileTarget?
    /// The stat whose detail was last opened; its tile gets focus back on return.
    private(set) var lastSelected: StatKind?

    var isVisible: Bool { mode != .hidden }
    var detailKind: StatKind? { if case .detail(let kind) = mode { return kind }; return nil }

    /// Reopening always starts in the overview, without keyboard focus (no focus theft).
    mutating func summon() -> FloatingTileEffect {
        mode = .overview
        focus = nil
        lastSelected = nil
        return .showOverview(focus: nil)
    }

    /// The primaries currently shown: all of them in the overview, only the clicked one while its
    /// detail is open, none while hidden.
    func visiblePrimaries(in kinds: [StatKind]) -> [StatKind] {
        switch mode {
        case .hidden: return []
        case .overview: return kinds
        case .detail(let kind): return kinds.filter { $0 == kind }
        }
    }

    /// Click/Return on a primary (`source`). From the overview it opens that stat's detail and
    /// hides the other primaries; focus stays on the primary used. The open primary again returns
    /// to all primaries. Any other primary is hidden while a detail is open, so selecting it is
    /// inert: changing stat means returning first (D-044, no switcher).
    mutating func select(_ kind: StatKind, from source: FloatingTileTarget, plan: FloatingTilePlan) -> FloatingTileEffect {
        guard mode != .hidden, plan.kinds.contains(kind) else { return .none }
        if let open = detailKind { return open == kind ? returnToOverview() : .none }
        mode = .detail(kind)
        lastSelected = kind
        focus = source
        return .showDetail(kind, hiding: plan.kinds.filter { $0 != kind }, focus: source)
    }

    /// Escape or the open primary again: close the detail, show every primary, focus on the
    /// primary that was open.
    mutating func returnToOverview() -> FloatingTileEffect {
        guard case .detail(let kind) = mode else { return .none }
        mode = .overview
        focus = .tile(kind)
        return .showOverview(focus: .tile(kind))
    }

    /// Escape is staged: a detail returns to all primaries; a second Escape dismisses.
    mutating func escape() -> FloatingTileEffect {
        switch mode {
        case .hidden: return .none
        case .detail: return returnToOverview()
        case .overview: return dismiss()
        }
    }

    mutating func dismiss() -> FloatingTileEffect {
        guard mode != .hidden else { return .none }
        mode = .hidden
        focus = nil
        lastSelected = nil
        return .dismiss
    }

    /// Keyboard focus moved to `target` (Tab, click, or the first key entry).
    mutating func focus(_ target: FloatingTileTarget?) {
        guard mode != .hidden else { return }
        focus = target
    }

    /// Arrow keys follow actual visual neighbours of the frozen plan. Returns the new target, or
    /// nil (focus unchanged) at an edge.
    mutating func moveFocus(_ direction: FloatingTileDirection, plan: FloatingTilePlan) -> FloatingTileTarget? {
        guard mode != .hidden, let focus,
              let next = plan.neighbour(of: focus, direction, open: detailKind) else { return nil }
        self.focus = next
        return next
    }

    /// Where keyboard entry lands when focus first enters the HUD.
    func entryTarget(kinds: [StatKind]) -> FloatingTileTarget? {
        if let focus { return focus }
        switch mode {
        case .hidden: return nil
        case .overview:
            // With nothing enabled the only controls are Settings and Quit.
            return (lastSelected ?? kinds.first).map { .tile($0) } ?? .settings
        case .detail(let kind): return .tile(kind)
        }
    }
}

#endif

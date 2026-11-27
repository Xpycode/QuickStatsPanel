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
    /// Show the overview; restore keyboard focus to `focus` when keyboard focus is in the HUD.
    case showOverview(focus: FloatingTileTarget?)
    /// Replace the overview (or the current detail) with this stat's detail.
    case showDetail(StatKind, focus: FloatingTileTarget)
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

    /// Click/Return on a tile or switcher item. Selecting the stat already open is inert.
    mutating func select(_ kind: StatKind, plan: FloatingTilePlan) -> FloatingTileEffect {
        guard mode != .hidden, plan.kinds.contains(kind), detailKind != kind else { return .none }
        mode = .detail(kind)
        lastSelected = kind
        focus = .switcher(kind)
        return .showDetail(kind, focus: .switcher(kind))
    }

    /// "All statistics": back to the same overview geometry, focus on the selected tile.
    mutating func returnToOverview() -> FloatingTileEffect {
        guard case .detail(let kind) = mode else { return .none }
        mode = .overview
        focus = .tile(kind)
        return .showOverview(focus: .tile(kind))
    }

    /// Escape is staged: detail returns to the overview; the overview dismisses.
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
              let next = plan.neighbour(of: focus, direction, detail: detailKind != nil) else { return nil }
        self.focus = next
        return next
    }

    /// Where keyboard entry lands when focus first enters the HUD.
    func entryTarget(kinds: [StatKind]) -> FloatingTileTarget? {
        if let focus { return focus }
        switch mode {
        case .hidden: return nil
        case .overview: return (lastSelected ?? kinds.first).map { .tile($0) }
        case .detail(let kind): return .switcher(kind)
        }
    }
}

#endif

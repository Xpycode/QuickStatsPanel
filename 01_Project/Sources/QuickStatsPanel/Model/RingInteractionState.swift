import CoreGraphics
import Foundation

// MARK: - Clock

/// Source of time for the interaction state. Production reads the system uptime;
/// tests advance a fake, so every dwell, leave and transit boundary is deterministic.
protocol RingClock: AnyObject {
    func now() -> TimeInterval
}

final class SystemRingClock: RingClock {
    func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

// MARK: - Vocabulary

/// Something that can own a branch: a favourite wedge, the More wedge, or an
/// entry of the More arc or list. Settings and the hub drag area are not nodes; they
/// never expand anything. Sub-ring segments are not nodes either: they are caption-only.
enum RingNode: Hashable, Sendable {
    case wedge(StatKind)
    case more
    case moreItem(StatKind)
}

/// A parent target that can own the single outer arc: the More wedge (its arc of
/// non-favourites, or the side More list standing in for it when no arc fits) or a
/// favourite stat wedge (its sub-ring of parts).
enum RingArcOwner: Hashable, Sendable {
    case more
    case stat(StatKind)

    /// The parent target in the ring.
    var node: RingNode {
        switch self {
        case .more: return .more
        case .stat(let kind): return .wedge(kind)
        }
    }
}

/// One part segment of a stat's sub-ring, by its frozen index.
struct RingSegmentRef: Hashable, Sendable {
    let stat: StatKind
    let index: Int
}

/// What the pointer is over, resolved by the owner against the frozen geometry.
enum RingBranchHit: Equatable, Sendable {
    case node(RingNode)
    /// The open detail card.
    case detail
    /// The open child surface of `owner` away from any entry or segment: its outer arc,
    /// including the gap between the ring and the band, or the side More list's padding.
    case arc(RingArcOwner)
    /// A part segment of an open sub-ring. Caption only: no dwell target, no further level.
    case segment(RingSegmentRef)
    /// Base-ring space that selects nothing: hub, Settings, drag area, gaps.
    case inert
    case none

    var node: RingNode? {
        if case .node(let node) = self { return node }
        return nil
    }
}

enum RingHold: Equatable, Sendable {
    /// Opened by hover; closes after the leave delay.
    case preview
    /// Opened or promoted by an explicit click; only click, Close or Escape closes it.
    case held
}

/// The open branch, independent of `isPinned`: at most one outer arc and at most one detail
/// card. When both are open they belong to the same owner. A favourite's sub-ring and card
/// share one hold; a More child card that is held also holds the More arc.
struct RingExpansion: Equatable, Sendable {
    struct Arc: Equatable, Sendable {
        var owner: RingArcOwner
        var hold: RingHold
    }

    struct Detail: Equatable, Sendable {
        var kind: StatKind
        /// `.stat(kind)` for a favourite's card, `.more` for a card opened from the More arc or list.
        var owner: RingArcOwner
        var hold: RingHold

        /// The target the card hangs from: the favourite wedge or the More entry.
        var parent: RingNode {
            owner == .more ? .moreItem(kind) : .wedge(kind)
        }
    }

    var arc: Arc?
    var detail: Detail?

    static let collapsed = RingExpansion(arc: nil, detail: nil)

    var detailOwner: RingNode? { detail?.parent }

    /// Owner of the open branch, if any.
    var owner: RingArcOwner? { detail?.owner ?? arc?.owner }
}

/// Effects the owner performs. Hold-only changes emit nothing; read `expansion`.
enum RingBranchCommand: Equatable, Sendable {
    /// Show the child surface of `owner`: a sub-ring, the More arc, or the side More list.
    case showArc(RingArcOwner)
    case hideArc(RingArcOwner)
    case showDetail(StatKind, owner: RingArcOwner)
    case hideDetail
    case hideHUD
    case openSettings
}

// MARK: - Travel region

/// Convex route between a parent target and its child surface, built from the actual
/// frames and widened by the route tolerance. It only preserves state: it is never a
/// clickable surface.
struct RingTravelRegion: Equatable, Sendable {
    let polygon: [CGPoint]

    init(from parent: CGRect, to child: CGRect, tolerance: CGFloat = RingBranchState.routeTolerance) {
        let a = parent.insetBy(dx: -tolerance, dy: -tolerance)
        let b = child.insetBy(dx: -tolerance, dy: -tolerance)
        let corners = [a, b].flatMap { r in
            [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
             CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        }
        polygon = Self.convexHull(corners)
    }

    func contains(_ p: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if cross < -1e-9 { return false }   // hull is counter-clockwise
        }
        return true
    }

    /// Andrew's monotone chain, counter-clockwise, collinear points dropped.
    private static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [CGPoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }
}

// MARK: - State machine

/// Collapsed / preview / held branches for the ring, following the spec's interaction
/// table. Any parent target (the More wedge or a favourite) can own the one outer arc, plus
/// at most one detail card. Pure: time comes from an injected clock, geometry from the
/// summon's `RingPlan` and pointer position from the owner, so nothing here touches AppKit.
///
/// A favourite opens its card together with its sub-ring when the plan reserved an arc
/// frame for it; otherwise (fewer than two parts, or no outer band this summon) the card
/// opens alone. A stat reached through More opens its card only and keeps the More arc.
///
/// Timers are values, not callbacks. After every call the owner schedules one wake-up at
/// `nextDeadline` and hands back `timerToken` when it fires; any change to the pending
/// timers (or a hide, drag, settings or summon) changes the token, so a callback scheduled
/// earlier is ignored. `generation` identifies the summon-level epoch and
/// `branchGeneration` the current branch, for owners with their own async work.
final class RingBranchState {

    /// Starting values from the spec; to be validated natively, not exposed as settings.
    static let dwell: TimeInterval = 0.35
    static let leaveDelay: TimeInterval = 0.45
    static let maxTransit: TimeInterval = 0.7
    static let routeTolerance: CGFloat = 12
    /// Pointer travel after summon or drag that arms hover.
    static let armingDistance: CGFloat = 2

    private let clock: any RingClock
    private(set) var plan: RingPlan
    private(set) var expansion = RingExpansion.collapsed
    /// Node under the pointer, for highlight.
    private(set) var hovered: RingNode?
    /// Segment of the open sub-ring under the pointer, for its caption.
    private(set) var hoveredSegment: RingSegmentRef?
    private(set) var generation: UInt64 = 0
    private(set) var branchGeneration: UInt64 = 0
    private(set) var timerToken: UInt64 = 0

    private var armed = false
    private var suppressPoint: CGPoint?
    private var lastHit: RingBranchHit?
    private var lastPoint: CGPoint?
    /// Closed by click, Close or Escape: not reopened until the pointer exits and re-enters.
    private var closedParent: RingNode?
    private var dwell: (node: RingNode, deadline: TimeInterval)?
    private var leaveDeadline: TimeInterval?
    private var transitUntil: TimeInterval?

    init(plan: RingPlan, clock: any RingClock = SystemRingClock()) {
        self.plan = plan
        self.clock = clock
    }

    // MARK: Queries

    var isArmed: Bool { armed }

    /// Earliest pending wake-up, or `nil` when nothing is scheduled.
    var nextDeadline: TimeInterval? {
        [dwell?.deadline, leaveDeadline, transitUntil].compactMap { $0 }.min()
    }

    /// Accessibility expanded state of a node.
    func isExpanded(_ node: RingNode) -> Bool {
        switch node {
        case .wedge(let kind): return expansion.owner == .stat(kind)
        case .more: return expansion.arc?.owner == .more
        case .moreItem(let kind): return expansion.detail.map { $0.owner == .more && $0.kind == kind } ?? false
        }
    }

    // MARK: Lifecycle inputs

    /// New summon: collapsed, no remembered expansion, hover suppressed until the pointer
    /// actually moves so clamping cannot open a stat under a stationary pointer.
    func summon(plan: RingPlan, pointer: CGPoint) {
        self.plan = plan
        resetAll()
        suppressPoint = pointer
    }

    /// Hotkey, click-away, Escape's last step or any other whole-HUD hide.
    @discardableResult
    func hide() -> [RingBranchCommand] { closeEverything() }

    /// Mouse-down on the hub drag area: cancel pending hover and close expansions first.
    @discardableResult
    func dragBegan() -> [RingBranchCommand] { closeEverything() }

    /// Mouse-up after a drag. Hover resumes only after movement; the owner supplies the
    /// re-resolved plan for the new position.
    func dragEnded(plan: RingPlan, pointer: CGPoint) {
        self.plan = plan
        armed = false
        suppressPoint = pointer
        lastHit = nil
        lastPoint = nil
        hovered = nil
        hoveredSegment = nil
    }

    /// Settings opens in an activating window: close descendants, cancel everything.
    @discardableResult
    func settingsRequested() -> [RingBranchCommand] {
        closeEverything() + [.openSettings]
    }

    /// Host display removed or reconfigured: dismiss; the next summon recomputes geometry.
    @discardableResult
    func displayChanged() -> [RingBranchCommand] {
        closeEverything() + [.hideHUD]
    }

    // MARK: Pointer

    @discardableResult
    func pointerMoved(to point: CGPoint, hit: RingBranchHit) -> [RingBranchCommand] {
        tracked {
            if !armed {
                guard let start = suppressPoint,
                      hypot(point.x - start.x, point.y - start.y) >= Self.armingDistance else { return [] }
                armed = true
            }
            let owner = currentOwner
            let wasOnSource = owner != nil && isRouteSource(lastHit)
            lastHit = hit
            lastPoint = point
            hovered = hit.node
            hoveredSegment = nil
            if case .segment(let segment) = hit, expansion.arc?.owner == .stat(segment.stat) {
                hoveredSegment = segment
            }
            if let owner {
                if hit.node == owner || isChildHit(hit) {
                    transitUntil = nil
                } else if wasOnSource, transitUntil == nil {
                    // Left the owner (or its sub-ring) towards (possibly) its card: bounded grace begins.
                    transitUntil = clock.now() + Self.maxTransit
                }
            }
            return evaluate()
        }
    }

    // MARK: Click, Press, Escape, Close

    /// Explicit click (or accessibility Press) on a node. Always wins over hover, travel
    /// grace and pending timers.
    @discardableResult
    func click(_ node: RingNode) -> [RingBranchCommand] {
        tracked {
            var next = expansion
            switch node {
            case .wedge(let kind):
                if expansion.owner == .stat(kind) {
                    if branchHold == .held {
                        next = .collapsed
                        closedParent = node
                    } else {
                        next = statBranch(kind, hold: .held)
                    }
                } else {
                    next = statBranch(kind, hold: .held)
                }
            case .more:
                switch expansion.arc?.owner == .more ? expansion.arc?.hold : nil {
                case .held:
                    next = .collapsed
                    closedParent = node
                case .preview:
                    next.arc?.hold = .held
                case nil:
                    // An explicit More click replaces a favourite's branch.
                    next = RingExpansion(arc: .init(owner: .more, hold: .held), detail: nil)
                }
            case .moreItem(let kind):
                guard next.arc?.owner == .more else { return [] }
                if let d = next.detail, d.owner == .more, d.kind == kind {
                    if d.hold == .held {
                        next.detail = nil
                        closedParent = node
                    } else {
                        next.detail?.hold = .held
                        next.arc?.hold = .held
                    }
                } else {
                    next.detail = .init(kind: kind, owner: .more, hold: .held)
                    next.arc?.hold = .held   // a held child holds its More branch
                }
            }
            cancelTimers()
            let commands = set(next)
            return commands + evaluate()
        }
    }

    /// Settings was clicked or pressed.
    @discardableResult
    func settingsClicked() -> [RingBranchCommand] { settingsRequested() }

    /// Mouse-down inside the detail card: a preview becomes held before any control acts.
    /// A favourite's sub-ring and a More child's arc are held with it.
    @discardableResult
    func detailInteracted() -> [RingBranchCommand] {
        tracked {
            guard expansion.detail?.hold == .preview else { return [] }
            var next = expansion
            next.detail?.hold = .held
            next.arc?.hold = .held
            cancelTimers()
            return set(next)
        }
    }

    /// Mouse-down inside an open sub-ring: a preview branch becomes held, card included,
    /// as when interacting with the card. The More arc is not promoted by its padding;
    /// its entries are clicked instead.
    @discardableResult
    func arcInteracted() -> [RingBranchCommand] {
        tracked {
            guard let arc = expansion.arc, arc.owner != .more, arc.hold == .preview else { return [] }
            var next = expansion
            next.arc?.hold = .held
            next.detail?.hold = .held
            cancelTimers()
            return set(next)
        }
    }

    /// Close button on the detail card: the first step of Escape. A favourite's sub-ring
    /// closes with its card; the More arc stays when it owned the card.
    @discardableResult
    func closeDetail() -> [RingBranchCommand] {
        tracked {
            guard let detail = expansion.detail else { return [] }
            closedParent = detail.parent
            cancelTimers()
            return set(closingDetail(detail)) + evaluate()
        }
    }

    /// Escape in Ring, including while pinned: detail (with its sub-ring), then More, then the HUD.
    @discardableResult
    func escape() -> [RingBranchCommand] {
        tracked {
            var next = expansion
            if let detail = expansion.detail {
                closedParent = detail.parent
                next = closingDetail(detail)
            } else if let arc = expansion.arc {
                closedParent = arc.owner.node
                next.arc = nil
            } else {
                return [.hideHUD]
            }
            cancelTimers()
            return set(next) + evaluate()
        }
    }

    // MARK: Timer callback

    /// Called when the wake-up scheduled for `token` fires. A token from before the latest
    /// change to the pending timers, hide, drag, settings or summon is stale and ignored.
    @discardableResult
    func fire(token: UInt64) -> [RingBranchCommand] {
        guard token == timerToken else { return [] }
        return tracked {
            let now = clock.now()
            var commands: [RingBranchCommand] = []
            if let pending = dwell, pending.deadline <= now {
                dwell = nil
                commands += openAfterDwell(pending.node)
            }
            if let transit = transitUntil, transit <= now { transitUntil = nil }
            commands += evaluate()
            if let leave = leaveDeadline, leave <= now {
                leaveDeadline = nil
                commands += closeUnheld()
                commands += evaluate()
            }
            return commands
        }
    }

    // MARK: - Evaluation

    /// Recomputes the pending timers from the pointer's last known position. Idempotent:
    /// a timer that still applies keeps its original deadline, so pointer jitter inside a
    /// target never restarts a dwell or a leave.
    private func evaluate() -> [RingBranchCommand] {
        guard armed, let hit = lastHit, let point = lastPoint else { return [] }
        let node = hit.node
        if let closed = closedParent, closed != node { closedParent = nil }
        let suppressed = closedParent != nil && closedParent == node
        let now = clock.now()

        let transitActive = isTransitActive(at: point, now: now)

        // Leave delay applies only to unheld branches the pointer has left.
        if hasUnheld, !isInside(hit, point: point, transitActive: transitActive) {
            if leaveDeadline == nil { leaveDeadline = now + Self.leaveDelay }
        } else {
            leaveDeadline = nil
        }

        // Dwell: restarts per stat; crossed siblings cannot complete during transit.
        if let node, !suppressed, allowsHover(node), !isOpen(node) {
            if dwell?.node != node {
                // Deliberate, provisional choice for E1: during transit grace a dwell on a crossed
                // sibling completes no earlier than the grace end, so a pointer that stops on a
                // sibling previews it up to 700 ms after arriving rather than 350 ms.
                let earliest = now + Self.dwell
                let deadline = transitActive ? max(earliest, transitUntil ?? earliest) : earliest
                dwell = (node, deadline)
            }
        } else {
            dwell = nil
        }
        return []
    }

    private func openAfterDwell(_ node: RingNode) -> [RingBranchCommand] {
        guard lastHit?.node == node, allowsHover(node), closedParent != node else { return [] }
        var next = expansion
        switch node {
        case .wedge(let kind):
            next = statBranch(kind, hold: .preview)
        case .more:
            next = RingExpansion(arc: .init(owner: .more, hold: .preview), detail: nil)
        case .moreItem(let kind):
            guard next.arc?.owner == .more else { return [] }
            next.detail = .init(kind: kind, owner: .more, hold: .preview)
        }
        transitUntil = nil
        return set(next)
    }

    private func closeUnheld() -> [RingBranchCommand] {
        var next = expansion
        if next.detail?.hold == .preview { next.detail = nil }
        if next.arc?.hold == .preview {
            next.arc = nil
            next.detail = nil   // a held child would have held its arc, so only a preview child remains
        }
        transitUntil = nil
        return set(next)
    }

    // MARK: Rules

    /// A favourite's branch: its card, plus its sub-ring when the plan reserved one.
    private func statBranch(_ kind: StatKind, hold: RingHold) -> RingExpansion {
        let owner = RingArcOwner.stat(kind)
        let arc = plan.arcFrames[owner] != nil ? RingExpansion.Arc(owner: owner, hold: hold) : nil
        return RingExpansion(arc: arc, detail: .init(kind: kind, owner: owner, hold: hold))
    }

    /// What Close or Escape on `detail` leaves open.
    private func closingDetail(_ detail: RingExpansion.Detail) -> RingExpansion {
        var next = expansion
        next.detail = nil
        if detail.owner != .more { next.arc = nil }
        return next
    }

    /// Hold of the open branch: the card's, or the arc's when no card is open.
    private var branchHold: RingHold? { expansion.detail?.hold ?? expansion.arc?.hold }

    /// A held card resists every hover replacement; a held arc resists everything but
    /// moving between the More arc's own entries.
    private func allowsHover(_ node: RingNode) -> Bool {
        if expansion.detail?.hold == .held { return false }
        if let arc = expansion.arc, arc.hold == .held {
            if arc.owner == .more, case .moreItem = node { return true }
            return false
        }
        if case .moreItem = node { return expansion.arc?.owner == .more }
        return true
    }

    private func isOpen(_ node: RingNode) -> Bool { isExpanded(node) }

    private var hasUnheld: Bool {
        expansion.detail?.hold == .preview || expansion.arc?.hold == .preview
    }

    /// The node whose child surface is the pointer's destination.
    private var currentOwner: RingNode? {
        expansion.detailOwner ?? expansion.arc?.owner.node
    }

    /// Where leaving starts the transit grace: the owner, or a favourite's open sub-ring on
    /// the way to its card.
    private func isRouteSource(_ hit: RingBranchHit?) -> Bool {
        guard let hit else { return false }
        if hit.node != nil { return hit.node == currentOwner }
        guard let detail = expansion.detail, detail.owner != .more, expansion.arc?.owner == detail.owner else {
            return false
        }
        switch hit {
        case .arc(let owner): return owner == detail.owner
        case .segment(let segment): return RingArcOwner.stat(segment.stat) == detail.owner
        default: return false
        }
    }

    private func isChildHit(_ hit: RingBranchHit) -> Bool {
        switch hit {
        case .detail: return expansion.detail != nil
        case .arc(let owner): return expansion.arc?.owner == owner
        case .segment(let segment): return expansion.arc?.owner == .stat(segment.stat)
        case .node(.moreItem): return expansion.arc?.owner == .more
        default: return false
        }
    }

    private func isInside(_ hit: RingBranchHit, point: CGPoint, transitActive: Bool) -> Bool {
        if isChildHit(hit) { return true }
        if let owner = currentOwner, hit.node == owner { return true }
        return transitActive
    }

    private func isTransitActive(at point: CGPoint, now: TimeInterval) -> Bool {
        guard let until = transitUntil, now < until else { return false }
        return travelRegions().contains { $0.contains(point) }
    }

    /// Routes from the actual frames: parent target to card, and a favourite's sub-ring to
    /// its card; without a card, parent target to its arc or list.
    private func travelRegions() -> [RingTravelRegion] {
        var regions: [RingTravelRegion] = []
        if let detail = expansion.detail, let card = plan.detailFrames[detail.kind] {
            if let parent = plan.nodeFrames[detail.parent] {
                regions.append(RingTravelRegion(from: parent, to: card))
            }
            if detail.owner != .more, expansion.arc?.owner == detail.owner,
               let arc = plan.arcFrames[detail.owner] {
                regions.append(RingTravelRegion(from: arc, to: card))
            }
        }
        if regions.isEmpty, let arc = expansion.arc, let parent = plan.nodeFrames[arc.owner.node],
           let surface = plan.surfaceFrame(of: arc.owner) {
            regions.append(RingTravelRegion(from: parent, to: surface))
        }
        return regions
    }

    // MARK: Mutation plumbing

    /// Runs a mutating input and bumps the timer token when the pending timers changed.
    private func tracked(_ body: () -> [RingBranchCommand]) -> [RingBranchCommand] {
        let before = timerSignature()
        let commands = body()
        if timerSignature() != before { timerToken &+= 1 }
        return commands
    }

    private func timerSignature() -> [TimeInterval?] {
        [dwell.map { $0.deadline }, leaveDeadline, transitUntil]
    }

    private func cancelTimers() {
        dwell = nil
        leaveDeadline = nil
        transitUntil = nil
    }

    /// Applies a new expansion and emits only the open/close/replace effects, closing the
    /// old surfaces before opening the new ones.
    private func set(_ next: RingExpansion) -> [RingBranchCommand] {
        let old = expansion
        guard next != old else { return [] }
        expansion = next
        branchGeneration &+= 1
        if let segment = hoveredSegment, next.arc?.owner != .stat(segment.stat) { hoveredSegment = nil }
        var commands: [RingBranchCommand] = []
        if old.detail != nil, next.detail == nil { commands.append(.hideDetail) }
        if let arc = old.arc, next.arc?.owner != arc.owner { commands.append(.hideArc(arc.owner)) }
        if let arc = next.arc, old.arc?.owner != arc.owner { commands.append(.showArc(arc.owner)) }
        if let detail = next.detail,
           old.detail?.kind != detail.kind || old.detail?.owner != detail.owner {
            commands.append(.showDetail(detail.kind, owner: detail.owner))
        }
        return commands
    }

    private func closeEverything() -> [RingBranchCommand] {
        let old = expansion
        resetAll()
        var commands: [RingBranchCommand] = []
        if old.detail != nil { commands.append(.hideDetail) }
        if let arc = old.arc { commands.append(.hideArc(arc.owner)) }
        return commands
    }

    private func resetAll() {
        expansion = .collapsed
        hovered = nil
        hoveredSegment = nil
        armed = false
        suppressPoint = nil
        lastHit = nil
        lastPoint = nil
        closedParent = nil
        cancelTimers()
        generation &+= 1
        branchGeneration &+= 1
        timerToken &+= 1
    }
}

// MARK: - Compatibility for RingPanelController (removed by 4.1)

/// Hit vocabulary of the 2.1 controller. `.moreSurface` is the More child surface; sub-ring
/// hits have no equivalent and read as inert.
enum RingHit: Equatable, Sendable {
    case node(RingNode)
    case detail
    case moreSurface
    case inert
    case none

    var node: RingNode? {
        if case .node(let node) = self { return node }
        return nil
    }

    init(_ hit: RingBranchHit) {
        switch hit {
        case .node(let node): self = .node(node)
        case .detail: self = .detail
        case .arc(.more): self = .moreSurface
        case .arc(.stat), .segment: self = .inert
        case .inert: self = .inert
        case .none: self = .none
        }
    }

    var branchHit: RingBranchHit {
        switch self {
        case .node(let node): return .node(node)
        case .detail: return .detail
        case .moreSurface: return .arc(.more)
        case .inert: return .inert
        case .none: return .none
        }
    }
}

/// Command vocabulary of the 2.1 controller. Sub-ring arcs have no native surface before
/// 4.1, so their show/hide commands are dropped.
enum RingCommand: Equatable, Sendable {
    case showMore
    case hideMore
    case showDetail(StatKind, viaMore: Bool)
    case hideDetail
    case hideHUD
    case openSettings

    static func legacy(_ commands: [RingBranchCommand]) -> [RingCommand] {
        commands.compactMap { command in
            switch command {
            case .showArc(.more): return .showMore
            case .hideArc(.more): return .hideMore
            case .showArc(.stat), .hideArc(.stat): return nil
            case .showDetail(let kind, let owner): return .showDetail(kind, viaMore: owner == .more)
            case .hideDetail: return .hideDetail
            case .hideHUD: return .hideHUD
            case .openSettings: return .openSettings
            }
        }
    }
}

extension RingExpansion {
    /// Hold of the More branch, as the 2.1 controller reads it.
    var more: RingHold? { arc?.owner == .more ? arc?.hold : nil }
}

/// The 2.1 controller's interface over `RingBranchState`: same inputs, legacy hits and
/// commands.
final class RingInteractionState {
    let branch: RingBranchState

    init(plan: RingPlan, clock: any RingClock = SystemRingClock()) {
        branch = RingBranchState(plan: plan, clock: clock)
    }

    var plan: RingPlan { branch.plan }
    var expansion: RingExpansion { branch.expansion }
    var hovered: RingNode? { branch.hovered }
    var generation: UInt64 { branch.generation }
    var branchGeneration: UInt64 { branch.branchGeneration }
    var timerToken: UInt64 { branch.timerToken }
    var isArmed: Bool { branch.isArmed }
    var nextDeadline: TimeInterval? { branch.nextDeadline }

    func isExpanded(_ node: RingNode) -> Bool { branch.isExpanded(node) }
    func summon(plan: RingPlan, pointer: CGPoint) { branch.summon(plan: plan, pointer: pointer) }
    func dragEnded(plan: RingPlan, pointer: CGPoint) { branch.dragEnded(plan: plan, pointer: pointer) }

    @discardableResult func hide() -> [RingCommand] { RingCommand.legacy(branch.hide()) }
    @discardableResult func dragBegan() -> [RingCommand] { RingCommand.legacy(branch.dragBegan()) }
    @discardableResult func settingsRequested() -> [RingCommand] { RingCommand.legacy(branch.settingsRequested()) }
    @discardableResult func displayChanged() -> [RingCommand] { RingCommand.legacy(branch.displayChanged()) }
    @discardableResult func pointerMoved(to point: CGPoint, hit: RingHit) -> [RingCommand] {
        RingCommand.legacy(branch.pointerMoved(to: point, hit: hit.branchHit))
    }
    @discardableResult func click(_ node: RingNode) -> [RingCommand] { RingCommand.legacy(branch.click(node)) }
    @discardableResult func settingsClicked() -> [RingCommand] { RingCommand.legacy(branch.settingsClicked()) }
    @discardableResult func detailInteracted() -> [RingCommand] { RingCommand.legacy(branch.detailInteracted()) }
    @discardableResult func closeDetail() -> [RingCommand] { RingCommand.legacy(branch.closeDetail()) }
    @discardableResult func escape() -> [RingCommand] { RingCommand.legacy(branch.escape()) }
    @discardableResult func fire(token: UInt64) -> [RingCommand] { RingCommand.legacy(branch.fire(token: token)) }
}

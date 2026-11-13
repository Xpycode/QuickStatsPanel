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

/// Something that can own a branch: a favourite wedge, the hub's More control, or an
/// entry of the More ring/list. Settings and the hub drag area are not nodes; they
/// never expand anything.
enum RingNode: Hashable, Sendable {
    case wedge(StatKind)
    case more
    case moreItem(StatKind)
}

/// What the pointer is over, resolved by the owner against the frozen geometry.
enum RingHit: Equatable, Sendable {
    case node(RingNode)
    /// The open detail card.
    case detail
    /// The open More ring/list, but no entry.
    case moreSurface
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

/// The open branches, independent of `isPinned`.
struct RingExpansion: Equatable, Sendable {
    struct Detail: Equatable, Sendable {
        var kind: StatKind
        /// True when the detail belongs to a More entry rather than a favourite wedge.
        var viaMore: Bool
        var hold: RingHold
    }

    var more: RingHold?
    var detail: Detail?

    static let collapsed = RingExpansion(more: nil, detail: nil)

    var detailOwner: RingNode? {
        detail.map { $0.viaMore ? .moreItem($0.kind) : .wedge($0.kind) }
    }
}

/// Effects the owner performs. Hold-only changes emit nothing; read `expansion`.
enum RingCommand: Equatable, Sendable {
    case showMore
    case hideMore
    case showDetail(StatKind, viaMore: Bool)
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

    init(from parent: CGRect, to child: CGRect, tolerance: CGFloat = RingInteractionState.routeTolerance) {
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
/// table. Pure: time comes from an injected clock, geometry from the summon's `RingPlan`
/// and pointer position from the owner, so nothing here touches AppKit.
///
/// Timers are values, not callbacks. After every call the owner schedules one wake-up at
/// `nextDeadline` and hands back `timerToken` when it fires; any change to the pending
/// timers (or a hide, drag, settings or summon) changes the token, so a callback scheduled
/// earlier is ignored. `generation` identifies the summon-level epoch and
/// `branchGeneration` the current branch, for owners with their own async work.
final class RingInteractionState {

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
    private(set) var generation: UInt64 = 0
    private(set) var branchGeneration: UInt64 = 0
    private(set) var timerToken: UInt64 = 0

    private var armed = false
    private var suppressPoint: CGPoint?
    private var lastHit: RingHit?
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
        case .wedge(let kind): return expansion.detail.map { !$0.viaMore && $0.kind == kind } ?? false
        case .more: return expansion.more != nil
        case .moreItem(let kind): return expansion.detail.map { $0.viaMore && $0.kind == kind } ?? false
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
    func hide() -> [RingCommand] { closeEverything() }

    /// Mouse-down on the hub drag area: cancel pending hover and close expansions first.
    @discardableResult
    func dragBegan() -> [RingCommand] { closeEverything() }

    /// Mouse-up after a drag. Hover resumes only after movement; the owner supplies the
    /// re-resolved plan for the new position.
    func dragEnded(plan: RingPlan, pointer: CGPoint) {
        self.plan = plan
        armed = false
        suppressPoint = pointer
        lastHit = nil
        lastPoint = nil
        hovered = nil
    }

    /// Settings opens in an activating window: close descendants, cancel everything.
    @discardableResult
    func settingsRequested() -> [RingCommand] {
        closeEverything() + [.openSettings]
    }

    /// Host display removed or reconfigured: dismiss; the next summon recomputes geometry.
    @discardableResult
    func displayChanged() -> [RingCommand] {
        closeEverything() + [.hideHUD]
    }

    // MARK: Pointer

    @discardableResult
    func pointerMoved(to point: CGPoint, hit: RingHit) -> [RingCommand] {
        tracked {
            if !armed {
                guard let start = suppressPoint,
                      hypot(point.x - start.x, point.y - start.y) >= Self.armingDistance else { return [] }
                armed = true
            }
            let owner = currentOwner
            let wasOnOwner = owner != nil && lastHit?.node == owner
            lastHit = hit
            lastPoint = point
            hovered = hit.node
            if let owner {
                if hit.node == owner || isChildHit(hit) {
                    transitUntil = nil
                } else if wasOnOwner, transitUntil == nil {
                    // Left the owner towards (possibly) its child: bounded grace begins.
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
    func click(_ node: RingNode) -> [RingCommand] {
        tracked {
            var next = expansion
            switch node {
            case .wedge(let kind):
                if let d = next.detail, !d.viaMore, d.kind == kind {
                    if d.hold == .held {
                        next.detail = nil
                        closedParent = node
                    } else {
                        next.detail?.hold = .held
                    }
                } else {
                    next.more = nil
                    next.detail = .init(kind: kind, viaMore: false, hold: .held)
                }
            case .more:
                switch next.more {
                case .held:
                    next.more = nil
                    next.detail = nil
                    closedParent = node
                case .preview:
                    next.more = .held
                case nil:
                    next.detail = nil   // an explicit More click replaces a favourite detail
                    next.more = .held
                }
            case .moreItem(let kind):
                guard next.more != nil else { return [] }
                if let d = next.detail, d.viaMore, d.kind == kind {
                    if d.hold == .held {
                        next.detail = nil
                        closedParent = node
                    } else {
                        next.detail?.hold = .held
                        next.more = .held
                    }
                } else {
                    next.detail = .init(kind: kind, viaMore: true, hold: .held)
                    next.more = .held   // a held child holds its More branch
                }
            }
            cancelTimers()
            let commands = set(next)
            return commands + evaluate()
        }
    }

    /// Settings was clicked or pressed.
    @discardableResult
    func settingsClicked() -> [RingCommand] { settingsRequested() }

    /// Mouse-down inside the detail card: a preview becomes held before any control acts.
    @discardableResult
    func detailInteracted() -> [RingCommand] {
        tracked {
            guard var detail = expansion.detail, detail.hold == .preview else { return [] }
            var next = expansion
            detail.hold = .held
            next.detail = detail
            if detail.viaMore, next.more != nil { next.more = .held }
            cancelTimers()
            return set(next)
        }
    }

    /// Close button on the detail card: the first step of Escape.
    @discardableResult
    func closeDetail() -> [RingCommand] {
        tracked {
            guard let owner = expansion.detailOwner else { return [] }
            closedParent = owner
            var next = expansion
            next.detail = nil
            cancelTimers()
            return set(next) + evaluate()
        }
    }

    /// Escape in Ring, including while pinned: detail, then More, then the HUD.
    @discardableResult
    func escape() -> [RingCommand] {
        tracked {
            var next = expansion
            if let owner = expansion.detailOwner {
                closedParent = owner
                next.detail = nil
            } else if expansion.more != nil {
                closedParent = .more
                next.more = nil
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
    func fire(token: UInt64) -> [RingCommand] {
        guard token == timerToken else { return [] }
        return tracked {
            let now = clock.now()
            var commands: [RingCommand] = []
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
    private func evaluate() -> [RingCommand] {
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

    private func openAfterDwell(_ node: RingNode) -> [RingCommand] {
        guard lastHit?.node == node, allowsHover(node), closedParent != node else { return [] }
        var next = expansion
        switch node {
        case .wedge(let kind):
            next.more = nil
            next.detail = .init(kind: kind, viaMore: false, hold: .preview)
        case .more:
            next.detail = nil
            next.more = .preview
        case .moreItem(let kind):
            guard next.more != nil else { return [] }
            next.detail = .init(kind: kind, viaMore: true, hold: .preview)
        }
        transitUntil = nil
        return set(next)
    }

    private func closeUnheld() -> [RingCommand] {
        var next = expansion
        if next.detail?.hold == .preview { next.detail = nil }
        if next.more == .preview {
            next.more = nil
            next.detail = nil   // a held child would have held More, so only a preview child remains
        }
        transitUntil = nil
        return set(next)
    }

    // MARK: Rules

    /// A held detail resists every hover replacement; a held More resists everything but
    /// moving between its own entries.
    private func allowsHover(_ node: RingNode) -> Bool {
        if expansion.detail?.hold == .held { return false }
        if expansion.more == .held {
            if case .moreItem = node { return true }
            return false
        }
        if case .moreItem = node { return expansion.more != nil }
        return true
    }

    private func isOpen(_ node: RingNode) -> Bool { isExpanded(node) }

    private var hasUnheld: Bool {
        expansion.detail?.hold == .preview || expansion.more == .preview
    }

    /// The node whose child surface is the pointer's destination.
    private var currentOwner: RingNode? {
        expansion.detailOwner ?? (expansion.more != nil ? .more : nil)
    }

    private func isChildHit(_ hit: RingHit) -> Bool {
        switch hit {
        case .detail: return expansion.detail != nil
        case .moreSurface: return expansion.more != nil
        case .node(.moreItem): return expansion.more != nil
        default: return false
        }
    }

    private func isInside(_ hit: RingHit, point: CGPoint, transitActive: Bool) -> Bool {
        if isChildHit(hit) { return true }
        if let owner = currentOwner, hit.node == owner { return true }
        return transitActive
    }

    private func isTransitActive(at point: CGPoint, now: TimeInterval) -> Bool {
        guard let until = transitUntil, now < until, let region = travelRegion() else { return false }
        return region.contains(point)
    }

    private func travelRegion() -> RingTravelRegion? {
        if let owner = expansion.detailOwner, let detail = expansion.detail,
           let parent = plan.nodeFrames[owner], let child = plan.detailFrames[detail.kind] {
            return RingTravelRegion(from: parent, to: child)
        }
        if expansion.more != nil, let hub = plan.nodeFrames[.more], let surface = plan.moreSurface {
            return RingTravelRegion(from: hub, to: surface)
        }
        return nil
    }

    // MARK: Mutation plumbing

    /// Runs a mutating input and bumps the timer token when the pending timers changed.
    private func tracked(_ body: () -> [RingCommand]) -> [RingCommand] {
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

    /// Applies a new expansion and emits only the open/close/replace effects.
    private func set(_ next: RingExpansion) -> [RingCommand] {
        let old = expansion
        guard next != old else { return [] }
        expansion = next
        branchGeneration &+= 1
        var commands: [RingCommand] = []
        if old.detail != nil, next.detail == nil { commands.append(.hideDetail) }
        if old.more != nil, next.more == nil { commands.append(.hideMore) }
        if old.more == nil, next.more != nil { commands.append(.showMore) }
        if let detail = next.detail,
           old.detail?.kind != detail.kind || old.detail?.viaMore != detail.viaMore {
            commands.append(.showDetail(detail.kind, viaMore: detail.viaMore))
        }
        return commands
    }

    private func closeEverything() -> [RingCommand] {
        let old = expansion
        resetAll()
        var commands: [RingCommand] = []
        if old.detail != nil { commands.append(.hideDetail) }
        if old.more != nil { commands.append(.hideMore) }
        return commands
    }

    private func resetAll() {
        expansion = .collapsed
        hovered = nil
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

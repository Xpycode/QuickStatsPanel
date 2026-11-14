#if DEBUG
import AppKit
import OSLog
import SwiftUI

/// Debug-only launch configuration for the ring prototype. `RingPrototypeOptions` owns the
/// argument grammar (`--ring-prototype` is required; `--ring-fixture`, `--ring-size`,
/// `--ring-text`, `--ring-fill`, `--ring-favourites`, `--ring-parts` and
/// `--ring-power-ceiling` are optional); this adds the fixture lookup and the launch log.
///
/// Without `--ring-fixture` the ring shows real data: ordinary store, samplers and transfer-history
/// lifecycle. With it, fixture mode: a disposable store, no samplers, retained transfer history,
/// updater or first-run hint, and no production defaults written. An unknown value logs and falls
/// back to the argument's default (an unknown fixture falls back to `six`).
struct RingPrototypeLaunch: Sendable {
    let options: RingPrototypeOptions
    let fixture: RingFixture?

    static let current: RingPrototypeLaunch? = parse(CommandLine.arguments)

    static func parse(_ arguments: [String]) -> RingPrototypeLaunch? {
        guard let options = RingPrototypeOptions.parse(arguments) else { return nil }
        for warning in options.warnings { NSLog("%@", warning) }
        return RingPrototypeLaunch(options: options, fixture: options.fixtureName.flatMap(RingFixture.named))
    }
}

/// Shows the ring, its side More list and (through callbacks) the detail card as separate
/// borderless, non-activating `NSPanel`s sized to visible content, never one large
/// transparent window. Everything about where surfaces go comes from the summon's frozen
/// `RingPlan`; everything about when they open comes from `RingInteractionState`. This
/// controller only resolves pointer and clicks against the plan and carries out commands.
/// Visibility is reported through `onVisibilityChanged`, the same signal
/// `PanelWindowController` emits, so the owner drives identical effects.
@MainActor
final class RingPanelController {

    /// Fired with `true` when the ring appears and `false` when it hides, by any route.
    var onVisibilityChanged: ((Bool) -> Void)?
    /// Open the detail for a stat at its reserved frame; `true` when it must scroll.
    var onShowDetail: ((StatKind, CGRect, Bool) -> Void)?
    var onHideDetail: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOutsideClick: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu)?

    let state = RingPresentationState()
    private(set) var snapshot: RingSnapshot?
    private(set) var plan: RingPlan?
    private(set) var interaction: RingInteractionState?

    private var basePanel: NSPanel?
    private var morePanel: NSPanel?
    private var sideListLayout: RingListLayout?
    private var wholeListLayout: RingListLayout?
    private var placementInput: RingPlacement.Input?
    private var readingProvider: ((StatKind) -> RingReading)?
    private let edgeMargin: CGFloat = 24
    private let clock = SystemRingClock()
    private var timerItem: DispatchWorkItem?

    private enum Press: Equatable { case node(RingNode), settings }
    private var pressed: Press?

    var isVisible: Bool { basePanel?.isVisible ?? false }
    var frame: NSRect? { basePanel?.frame }
    var isDetailOpen: Bool { interaction?.expansion.detail != nil }

    // MARK: Hover observation

    // Hover is a visibility-scoped, permission-free mouse-moved observation, evaluated
    // against the frozen plan: a global monitor (other apps frontmost), a local monitor
    // (events delivered to this app's windows) and a 20 Hz poll of NSEvent.mouseLocation
    // that only acts when neither monitor has delivered recently. None intercepts an
    // event; all are removed on hide. Which mechanism delivered is logged (category
    // "RingPrototype") so the owner can confirm natively.
    private enum Mechanism: String { case global, local, poll }
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var detailDownMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var lastMonitorEvent = Date.distantPast
    private var lastPolledPoint: NSPoint?
    private var deliveries: [Mechanism: Int] = [:]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sim.QuickStatsPanel",
                                category: "RingPrototype")

    // MARK: Show / hide

    func toggle(snapshot: RingSnapshot, anchor: PanelAnchor, reading: @escaping (StatKind) -> RingReading,
                describe: @escaping (RingTarget) -> RingInputView.Description,
                detailSizes: [StatKind: CGSize]) {
        if isVisible { hide() } else {
            show(snapshot: snapshot, anchor: anchor, reading: reading, describe: describe, detailSizes: detailSizes)
        }
    }

    /// - Parameter detailSizes: measured detail card per stat, taken once now so the whole
    ///   branch geometry is selected before any input.
    func show(snapshot: RingSnapshot, anchor: PanelAnchor, reading: @escaping (StatKind) -> RingReading,
              describe: @escaping (RingTarget) -> RingInputView.Description,
              detailSizes: [StatKind: CGSize]) {
        guard basePanel == nil else { return }
        let cursor = NSEvent.mouseLocation
        let host = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let visible = host?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = snapshot.size
        let input = RingPlacement.Input(
            snapshot: snapshot, visible: visible,
            preferredBase: NSRect(origin: preferredOrigin(forSize: size, anchor: anchor, cursor: cursor, visible: visible), size: size),
            detailSizes: detailSizes, scale: host?.backingScaleFactor ?? 1)
        let plan = RingPlacement.resolve(input)

        self.snapshot = snapshot
        self.plan = plan
        self.placementInput = input
        self.readingProvider = reading
        sideListLayout = nil
        wholeListLayout = nil

        let panel: NSPanel
        if plan.mode == .wholeList {
            panel = makeWholeListPanel(plan: plan, snapshot: snapshot, reading: reading)
        } else {
            let inputView = RingInputView(snapshot: snapshot)
            inputView.describe = { [weak self] target in
                var description = describe(target)
                description.isExpanded = self?.isExpanded(target) ?? false
                return description
            }
            inputView.onPress = { [weak self] target in self?.press(target) }
            wire(inputView)
            let hosting = PassthroughHostingView(rootView: RingView(snapshot: snapshot, state: state, reading: reading))
            hosting.frame = NSRect(origin: .zero, size: size)
            inputView.addSubview(hosting)
            panel = makePanel(size: size)
            panel.contentView = inputView
        }
        panel.setFrame(plan.baseFrame, display: true)
        basePanel = panel

        let interaction = RingInteractionState(plan: plan, clock: clock)
        interaction.summon(plan: plan, pointer: cursor)
        self.interaction = interaction
        state.beginSummon(pointer: cursor)
        pressed = nil

        panel.orderFrontRegardless()
        installObservation()
        onVisibilityChanged?(true)
    }

    func hide() {
        // Redundant hides (click-away after Escape) must not emit a second `false`.
        guard basePanel != nil else { return }
        timerItem?.cancel()
        timerItem = nil
        removeObservation()
        interaction?.hide()
        hideMoreSurface()
        basePanel?.orderOut(nil)
        basePanel = nil
        snapshot = nil
        plan = nil
        interaction = nil
        placementInput = nil
        readingProvider = nil
        sideListLayout = nil
        wholeListLayout = nil
        pressed = nil
        state.reset()
        onVisibilityChanged?(false)
    }

    // MARK: Inputs from the owner

    /// Escape in Ring, including while pinned: detail, then More, then the HUD.
    func handleEscape() {
        guard let interaction else { return }
        apply(interaction.escape())
    }

    /// The detail card's Close button.
    func closeDetail() {
        guard let interaction else { return }
        apply(interaction.closeDetail())
    }

    private func isExpanded(_ target: RingTarget) -> Bool {
        guard let interaction else { return false }
        switch target {
        case .wedge(let kind): return interaction.isExpanded(.wedge(kind))
        case .more: return interaction.isExpanded(.more)
        case .settings, .drag: return false
        }
    }

    /// Accessibility Press: the click rows of the spec table.
    private func press(_ target: RingTarget) {
        guard let interaction else { return }
        switch target {
        case .wedge(let kind): apply(interaction.click(.wedge(kind)))
        case .more: apply(interaction.click(.more))
        case .settings: apply(interaction.settingsClicked())
        case .drag: break
        }
    }

    // MARK: Command application

    private func apply(_ commands: [RingCommand]) {
        for command in commands {
            switch command {
            case .showMore: showMoreSurface()
            case .hideMore: hideMoreSurface()
            case .showDetail(let kind, _):
                if let plan, let frame = plan.detailFrames[kind] {
                    onShowDetail?(kind, frame, plan.scrollingDetails.contains(kind))
                }
            case .hideDetail: onHideDetail?()
            case .hideHUD: hide()
            case .openSettings: onOpenSettings?()
            }
        }
        if let interaction {
            state.syncExpansion(interaction.expansion, hovered: interaction.hovered)
        }
        reschedule()
    }

    private func reschedule() {
        timerItem?.cancel()
        timerItem = nil
        guard let interaction, let deadline = interaction.nextDeadline else { return }
        let token = interaction.timerToken
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.timerFired(token) }
        }
        timerItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - clock.now()), execute: item)
    }

    /// A callback from before the latest change carries a stale token and does nothing.
    private func timerFired(_ token: UInt64) {
        guard let interaction else { return }
        apply(interaction.fire(token: token))
    }

    // MARK: Resolving points against the plan

    private func resolve(_ p: CGPoint) -> (hit: RingHit, special: RingSpecial?) {
        guard let plan, let snapshot, let interaction, let basePanel else { return (.none, nil) }
        return RingHitResolver(plan: plan, baseFrame: basePanel.frame, snapshot: snapshot,
                               openDetailKind: interaction.expansion.detail?.kind,
                               moreOpen: interaction.expansion.more != nil,
                               sideList: sideListLayout, wholeList: wholeListLayout).resolve(p)
    }

    // MARK: Mouse

    private func wire(_ view: RingForwardingView) {
        view.onMouseDown = { [weak self] point, event in self?.mouseDown(at: point, event: event) }
        view.onMouseUp = { [weak self] point in self?.mouseUp(at: point) }
        view.onScroll = { [weak self] point, delta in self?.scroll(at: point, by: delta) }
        view.contextMenuProvider = { [weak self] in self?.contextMenuProvider?() ?? NSMenu() }
    }

    private func mouseDown(at point: CGPoint, event: NSEvent) {
        pressed = nil
        let resolved = resolve(point)
        if resolved.special == .drag {
            beginDrag(event)
            return
        }
        if resolved.special == .settings { pressed = .settings; return }
        switch resolved.hit {
        case .node(let node): pressed = .node(node)
        case .none: onOutsideClick?()
        case .detail, .moreSurface, .inert: break
        }
    }

    private func mouseUp(at point: CGPoint) {
        defer { pressed = nil }
        guard let pressed, let interaction else { return }
        let resolved = resolve(point)
        switch pressed {
        case .settings:
            guard resolved.special == .settings else { return }
            apply(interaction.settingsClicked())
        case .node(let node):
            guard resolved.hit == .node(node) else { return }
            apply(interaction.click(node))
        }
    }

    private func scroll(at point: CGPoint, by delta: CGFloat) {
        guard let plan, let basePanel else { return }
        if plan.mode == .wholeList, var layout = wholeListLayout, basePanel.frame.contains(point) {
            layout.scroll(by: delta)
            wholeListLayout = layout
            state.listOffset = layout.offset
        } else if plan.mode == .sideList, var layout = sideListLayout, plan.moreSurface?.contains(point) == true {
            layout.scroll(by: delta)
            sideListLayout = layout
            state.listOffset = layout.offset
        }
    }

    /// Hub drag: close descendants first, then the native window drag. Nothing persists.
    private func beginDrag(_ event: NSEvent) {
        guard let interaction, let basePanel else { return }
        apply(interaction.dragBegan())
        basePanel.performDrag(with: event)
        guard self.basePanel != nil, var next = placementInput else { return }
        // Re-resolve around the base where the user left it: it stays put, only the child
        // surfaces are chosen again, so the next expansion is still fitted without clipping.
        next.preferredBase = basePanel.frame
        // The drop may be on another display: children are fitted to the display the base
        // landed on, not the summon's.
        let mid = NSPoint(x: basePanel.frame.midX, y: basePanel.frame.midY)
        let host = NSScreen.screens.first { $0.frame.contains(mid) }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let host {
            next.visible = host.visibleFrame
            next.scale = host.backingScaleFactor
        }
        next.canShift = false
        if plan?.mode == .wholeList {
            next.forceWholeList = true
        } else {
            next.allowWholeList = false
        }
        let replanned = RingPlacement.resolve(next)
        plan = replanned
        placementInput = next
        interaction.dragEnded(plan: replanned, pointer: NSEvent.mouseLocation)
        state.beginSummon(pointer: NSEvent.mouseLocation)
        reschedule()
    }

    // MARK: More surface

    /// The More wedge opens the side list above the detail card (the declared fallback until
    /// the outer band exists); the whole-list plan has no separate More surface.
    private func showMoreSurface() {
        guard morePanel == nil, let plan, let snapshot, let surface = plan.moreSurface,
              plan.mode == .sideList, let reading = readingProvider else { return }
        let layout = RingListLayout(size: surface.size, rows: snapshot.moreKinds.map { .moreItem($0) }, hasChrome: false)
        sideListLayout = layout
        state.listOffset = 0
        let panel = makeListPanel(layout: layout, label: "More stats", reading: reading)
        panel.setFrame(surface, display: true)
        morePanel = panel
        panel.orderFrontRegardless()
    }

    private func hideMoreSurface() {
        morePanel?.orderOut(nil)
        morePanel = nil
        sideListLayout = nil
        state.listOffset = 0
    }

    private func makeElement(kind: StatKind, node: RingNode, frame: CGRect,
                             reading: (StatKind) -> RingReading) -> RingAccessibilityElement {
        let live = reading(kind)
        let element = RingAccessibilityElement()
        element.setAccessibilityRole(.button)
        element.setAccessibilityLabel(kind.displayName)
        element.setAccessibilityValue(live.accessibilityText)
        element.setAccessibilityEnabled(true)
        element.setAccessibilityExpanded(interaction?.isExpanded(node) ?? false)
        if !live.isAvailable { element.setAccessibilityHelp("No reading is available for this stat right now.") }
        element.setAccessibilityFrameInParentSpace(frame)
        element.onPress = { [weak self] in
            guard let self, let interaction = self.interaction else { return }
            self.apply(interaction.click(node))
        }
        return element
    }

    // MARK: Panels

    private func makeListPanel(layout: RingListLayout, label: String,
                               reading: @escaping (StatKind) -> RingReading) -> NSPanel {
        let input = RingSurfaceInputView(size: layout.size, label: label)
        input.accessibilityElementsProvider = { [weak self] in self?.listAccessibility() ?? [] }
        wire(input)
        let hosting = PassthroughHostingView(rootView: RingListView(layout: layout, state: state, reading: reading))
        hosting.frame = NSRect(origin: .zero, size: layout.size)
        input.addSubview(hosting)
        let panel = makePanel(size: layout.size)
        panel.contentView = input
        panel.isMovable = false
        return panel
    }

    private func makeWholeListPanel(plan: RingPlan, snapshot: RingSnapshot,
                                    reading: @escaping (StatKind) -> RingReading) -> NSPanel {
        let layout = RingListLayout(size: plan.baseFrame.size, rows: snapshot.enabledKinds.map { .wedge($0) }, hasChrome: true)
        wholeListLayout = layout
        let panel = makeListPanel(layout: layout, label: "Quick stats", reading: reading)
        panel.isMovable = true   // header drag uses performDrag; nothing persists
        return panel
    }

    private func listAccessibility() -> [RingAccessibilityElement] {
        guard let plan, let reading = readingProvider else { return [] }
        let layout = plan.mode == .wholeList ? wholeListLayout : sideListLayout
        guard let layout else { return [] }
        let scrolled = layout.scrolled(by: state.listOffset)
        var elements: [RingAccessibilityElement] = []
        for (index, node) in layout.rows.enumerated() {
            let kind: StatKind
            switch node {
            case .wedge(let k), .moreItem(let k): kind = k
            case .more: continue
            }
            let frame = scrolled.rowFrame(at: index)
            guard layout.viewport.intersects(frame) else { continue }
            elements.append(makeElement(kind: kind, node: node, frame: frame, reading: reading))
        }
        if layout.hasChrome {
            let element = RingAccessibilityElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel("Settings")
            element.setAccessibilityEnabled(true)
            element.setAccessibilityFrameInParentSpace(layout.footerFrame)
            element.onPress = { [weak self] in
                guard let self, let interaction = self.interaction else { return }
                self.apply(interaction.settingsClicked())
            }
            elements.append(element)
        }
        return elements
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear      // SwiftUI draws the wedges
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = true              // hub drag uses performDrag; nothing persists
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        return panel
    }

    // MARK: Observation

    private func installObservation() {
        deliveries = [:]
        lastMonitorEvent = .distantPast
        lastPolledPoint = NSEvent.mouseLocation
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in self?.pointerMoved(via: .global) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved(via: .local) }
            return event
        }
        // A mouse-down inside the detail card promotes a preview to held before the card's
        // controls handle the click; the monitor observes and never consumes the event.
        detailDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.detailMouseDown() }
            return event
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        // Display removal or reconfiguration: dismiss; the next summon recomputes geometry.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let interaction = self.interaction else { return }
                self.apply(interaction.displayChanged())
            }
        }
    }

    private func removeObservation() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let detailDownMonitor { NSEvent.removeMonitor(detailDownMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        globalMonitor = nil
        localMonitor = nil
        detailDownMonitor = nil
        screenObserver = nil
        pollTimer?.invalidate()
        pollTimer = nil
        logger.info("hover deliveries this summon: global=\(self.deliveries[.global, default: 0]) local=\(self.deliveries[.local, default: 0]) poll=\(self.deliveries[.poll, default: 0])")
    }

    private func detailMouseDown() {
        guard let plan, let interaction, let detail = interaction.expansion.detail,
              let frame = plan.detailFrames[detail.kind], frame.contains(NSEvent.mouseLocation) else { return }
        apply(interaction.detailInteracted())
    }

    private func poll() {
        let location = NSEvent.mouseLocation
        guard location != lastPolledPoint else { return }
        lastPolledPoint = location
        // A monitor delivered moments ago: the poll is only the fallback.
        guard Date().timeIntervalSince(lastMonitorEvent) > 0.15 else { return }
        pointerMoved(via: .poll)
    }

    private func pointerMoved(via mechanism: Mechanism) {
        guard let basePanel, let snapshot, let plan, let interaction else { return }
        if mechanism != .poll { lastMonitorEvent = Date() }
        let point = NSEvent.mouseLocation
        lastPolledPoint = point
        let count = deliveries[mechanism, default: 0] + 1
        deliveries[mechanism] = count
        if count == 1 {
            logger.info("first hover event delivered by \(mechanism.rawValue, privacy: .public)")
        }
        if plan.mode != .wholeList {
            state.updatePointer(screenPoint: point, ringFrame: basePanel.frame, snapshot: snapshot)
        }
        apply(interaction.pointerMoved(to: point, hit: resolve(point).hit))
    }

    // MARK: Placement

    /// Anchor-derived position for the footprint before edge fitting (read only; a ring
    /// drag saves nothing). `RingPlacement` then moves it inward as far as needed.
    private func preferredOrigin(forSize size: NSSize, anchor: PanelAnchor, cursor: NSPoint,
                                 visible: NSRect) -> NSPoint {
        switch anchor {
        case .cursor:
            return NSPoint(x: cursor.x - size.width / 2, y: cursor.y - size.height / 2)
        case .screenCenter:
            return NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        case .topCenter:
            return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - edgeMargin)
        case .bottomCenter:
            return NSPoint(x: visible.midX - size.width / 2, y: visible.minY + edgeMargin)
        }
    }
}
#endif

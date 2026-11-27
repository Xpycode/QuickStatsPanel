#if DEBUG
import AppKit
import OSLog
import SwiftUI

/// Shows the floating-tile prototype (Debug only, `--floating-tiles-prototype`).
///
/// **Panel arrangement:** one borderless, non-activating, fully transparent host panel sized to
/// the summon's frozen footprint. Primaries (tiles), the detail card and the group bar are
/// separate surfaces inside it with transparent gaps between them. The panel covers the core
/// (group bar, overview) plus every stat's frozen detail frame, so opening a detail never moves or
/// resizes anything: the clicked primary stays put, the others fade out and its detail fades in
/// beside it, toward where the others were (D-044). Unused space is transparent and passes
/// clicks through. One window keeps keyboard
/// focus, dismissal and group dragging trivially coordinated (there is nothing to keep in sync),
/// while the window server passes clicks on fully transparent pixels through to the window below,
/// where the existing global monitor treats them as click-away. Separate detail panels
/// would only be needed if transparent-gap delivery or focus failed natively.
///
/// Geometry comes only from the frozen `FloatingTilePlan`; interaction only from
/// `FloatingTileState`. Visibility is reported through `onVisibilityChanged`, the same signal the
/// Strip and Ring emit, so the owner drives identical hotkey/pin/sampling effects.
@MainActor
final class FloatingTilePanelController {

    var onVisibilityChanged: ((Bool) -> Void)?
    /// The stat whose detail is open, or nil; lets the owner manage transfer-history presentation.
    var onDetailChanged: ((StatKind?) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu)?

    private(set) var state = FloatingTileState()
    private(set) var plan: FloatingTilePlan?

    private var panel: FloatingTileHUDPanel?
    private var host: FloatingTileHostView?
    private var buttons: [FloatingTileTarget: FloatingTileButton] = [:]
    private var tileValue: ((StatKind) -> String)?
    private var detailHost: NSView?
    private var detailContent: ((StatKind, CGSize, Bool) -> AnyView)?
    /// Focus rings show only while the HUD is driven from the keyboard (D-044: no outline after a
    /// click). Mouse input turns them off again.
    private var keyboardCues = false
    /// Bumped on every open/return so a stale fade completion never hides a returned primary.
    private var transitionGeneration = 0
    /// Fade length for primaries and the detail; instant with Reduce Motion.
    static let fadeDuration: TimeInterval = 0.15
    private var keyObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sim.QuickStatsPanel",
                                category: "FloatingTiles")

    var isVisible: Bool { panel?.isVisible ?? false }
    var frame: NSRect? { panel?.frame }
    /// Observers this controller owns while visible (0 once hidden); logged on hide.
    private var ownedObserverCount: Int {
        [keyObserver, activationObserver, screenObserver].compactMap { $0 }.count
    }

    // MARK: Show / hide

    /// - Parameters:
    ///   - detailSizes: every enabled stat's measured detail card, taken once now so the whole
    ///     footprint (and every detail frame) is chosen before any input.
    ///   - tile: overview tile content for a stat (`true` for the large first tile).
    ///   - tileValue: the tile's live accessibility value (its readings and usage basis).
    ///   - detail: detail card content for a stat at its frozen frame size; `true` when it scrolls.
    func show(kinds: [StatKind], detailSizes: [StatKind: CGSize], anchor: PanelAnchor,
              tile: (StatKind, Bool) -> AnyView,
              tileValue: @escaping (StatKind) -> String,
              detail: @escaping (StatKind, CGSize, Bool) -> AnyView) {
        guard panel == nil else { return }
        let options = FloatingTilePrototypeOptions.current
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let real = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // A simulated constrained display (`--floating-tiles-frame=`) is a model check only.
        let visible = FloatingTilePlacement.region(visible: real, simulated: options?.simulatedFrame)
        let available = FloatingTilePlacement.available(in: visible)
        // "Always show scroll bars": scrolling content gets the legacy scroller's width beside it.
        let reserve = NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        // Two steps: place the core (bar, overview), then give each stat's detail a frozen frame
        // beside its primary, on the side toward the overview's larger part that fits this display.
        let core = FloatingTilePlan.make(kinds: kinds, detailSizes: detailSizes, available: available,
                                         scrollerReserve: reserve)
        let coreOrigin = FloatingTilePlacement.origin(size: core.coreFrame.size, anchor: anchor, cursor: cursor,
                                                      visible: visible, edge: options?.edge)
        let bounds = FloatingTilePlacement.bounds(coreOrigin: coreOrigin, coreSize: core.coreFrame.size,
                                                  visible: visible)
        let plan = FloatingTilePlan.make(kinds: kinds, detailSizes: detailSizes, available: available,
                                         bounds: bounds, scrollerReserve: reserve)
        logger.info("summon region \(Int(visible.width))x\(Int(visible.height)) simulated=\(options?.simulatedFrame != nil) plan \(Int(plan.size.width))x\(Int(plan.size.height)) columns=\(plan.columns) fits=\(plan.fits) scrollingDetails=\(plan.scrollingDetails.map(\.displayName).sorted().joined(separator: ","), privacy: .public) overviewScrolls=\(plan.overviewViewport != nil) reserve=\(Int(reserve))")
        if !plan.fits {
            NSLog("Floating tiles: footprint %.0fx%.0f exceeds the available %.0fx%.0f; navigation may clip",
                  plan.size.width, plan.size.height, available.width, available.height)
        }
        self.plan = plan
        detailContent = detail
        self.tileValue = tileValue

        let host = FloatingTileHostView(frame: NSRect(origin: .zero, size: plan.size))
        host.contextMenuProvider = contextMenuProvider
        host.setAccessibilityElement(true)
        host.setAccessibilityRole(.group)
        host.setAccessibilityLabel("Statistics overview")
        build(in: host, plan: plan, tile: tile)

        let panel = makePanel(size: plan.size)
        panel.contentView = host
        panel.autorecalculatesKeyViewLoop = true
        panel.setFrame(FloatingTilePlacement.hostFrame(coreOrigin: coreOrigin, plan: plan), display: true)
        logger.info("detail sides \(plan.kinds.map { "\($0.displayName)=\(plan.detailSides[$0].map { "\($0)" } ?? "-")/\(plan.detailAlignments[$0].map { "\($0)" } ?? "-")" }.joined(separator: ","), privacy: .public)")
        self.panel = panel
        self.host = host
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyboardEntered() }
        }
        // Explicit activation of this agent app (never caused by summoning) also admits keyboard
        // entry, since the HUD is then the app's only window that can take keys.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.allowKeyboardEntry() }
        }
        // Display removal or reconfiguration: the group re-clamps as one unit (one window).
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayChanged() }
        }

        apply(state.summon())
        // Ordered front without becoming key: summoning never activates the app or takes
        // keyboard focus from another app.
        panel.orderFrontRegardless()
        // When this app is already the active one (another app holds no keyboard focus to take),
        // keyboard entry starts at once instead of after a first click.
        if NSApp.isActive { panel.allowKeyboardEntry() }
        logger.info("summoned key=\(panel.isKeyWindow) appActive=\(NSApp.isActive)")
        onVisibilityChanged?(true)
    }

    func hide() {
        guard panel != nil else { return }
        _ = state.dismiss()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        logger.info("hidden; owned observers remaining=\(self.ownedObserverCount)")
        panel?.orderOut(nil)
        panel = nil
        host = nil
        buttons = [:]
        detailHost = nil
        detailContent = nil
        tileValue = nil
        plan = nil
        keyboardCues = false
        transitionGeneration += 1
        onDetailChanged?(nil)
        onVisibilityChanged?(false)
    }

    /// Escape (scoped Carbon hotkey, also while pinned): detail → all primaries → dismiss.
    func handleEscape() { apply(state.escape()) }

    // MARK: Construction

    private func build(in host: FloatingTileHostView, plan: FloatingTilePlan, tile: (StatKind, Bool) -> AnyView) {
        buttons = [:]
        let radius = AppSettings.shared.theme.metrics.cornerRadius

        // Limited space only: the overview scrolls inside its viewport; tile frames shift into the
        // document's coordinates. The group bar stays outside it.
        let overviewParent: NSView
        let offset: CGPoint
        if let viewport = plan.overviewViewport {
            let documentHeight = (plan.tileFrames.values.map(\.maxY).max() ?? viewport.minY) - viewport.minY
            let document = FloatingTileOverviewDocumentView(frame: NSRect(
                x: 0, y: 0, width: viewport.width - plan.scrollerReserve, height: documentHeight))
            let scroll = NSScrollView(frame: viewport)
            scroll.drawsBackground = false
            scroll.contentView.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.documentView = document
            scroll.setAccessibilityLabel("Statistics, scrollable")
            host.addSubview(scroll)
            overviewParent = document
            offset = viewport.origin
        } else {
            overviewParent = host
            offset = .zero
        }

        for (index, kind) in plan.kinds.enumerated() {
            guard let frame = plan.tileFrames[kind] else { continue }
            // No "open" outline (D-044): the primary looks the same with its detail open.
            let button = makeButton(.tile(kind), label: kind.displayName, content: tile(kind, index == 0),
                                    frame: frame.offsetBy(dx: -offset.x, dy: -offset.y), in: overviewParent)
            button.cornerRadius = radius
            button.toolTip = "Show or hide \(kind.displayName) detail"
            button.setAccessibilityHelp("Shows the \(kind.displayName) detail and hides the other statistics; again, or Escape, shows them all.")
            button.accessibilitySelectedProvider = { [weak self] in self?.state.detailKind == kind }
            button.accessibilityValueProvider = { [weak self] in self?.tileValue?(kind) }
        }

        if let emptyFrame = plan.emptyStateFrame {
            let empty = FloatingTileDrawingView(rootView: FloatingTileEmptyStateView())
            empty.frame = emptyFrame
            empty.setAccessibilityElement(true)
            empty.setAccessibilityRole(.staticText)
            empty.setAccessibilityLabel("No statistics enabled. Choose statistics in Settings.")
            host.addSubview(empty)
        }

        let bar = FloatingTileDrawingView(rootView: FloatingTileSurface())
        bar.frame = plan.barFrame
        host.addSubview(bar)
        let barItems: [(FloatingTileTarget, String, String)] = [
            (.handle, "arrow.up.and.down.and.arrow.left.and.right", "Move statistics"),
            (.settings, "gearshape", "Settings"),
            (.quit, "power", "Quit QuickStatsPanel"),
        ]
        for (target, symbol, label) in barItems {
            guard let frame = plan.barItemFrames[target] else { continue }
            let button = makeButton(target, label: label, content: FloatingTileBarItemView(symbol: symbol),
                                    frame: frame, in: host)
            button.toolTip = label
            switch target {
            case .handle: button.setAccessibilityHelp("Drag to move all statistics together.")
            case .settings: button.setAccessibilityHelp("Opens Settings and closes the statistics.")
            case .quit: button.setAccessibilityHelp("Quits QuickStatsPanel.")
            default: break
            }
            if target == .handle {
                button.onDragStart = { [weak self] _ in
                    guard let panel = self?.panel else { return }
                    PanelDragTracker.track(panel)   // moves every surface together; saves nothing
                }
            }
        }
    }

    private func makeButton<Content: View>(_ target: FloatingTileTarget, label: String, content: Content,
                                           frame: CGRect, in host: NSView) -> FloatingTileButton {
        let button = FloatingTileButton(target: target, label: label, content: content)
        button.frame = frame
        button.focusRingType = keyboardCues ? .exterior : .none
        button.onActivate = { [weak self] in self?.activate($0) }
        button.onArrow = { [weak self] target, direction in self?.arrow(from: target, direction) }
        button.onFocus = { [weak self] in
            self?.noteInput()
            self?.state.focus($0)
        }
        host.addSubview(button)
        buttons[target] = button
        return button
    }

    // MARK: Actions

    private func activate(_ target: FloatingTileTarget) {
        guard let plan else { return }
        noteInput()
        switch target {
        case .tile(let kind): apply(state.select(kind, from: target, plan: plan))
        case .settings: onOpenSettings?()
        case .quit:
            // Every surface and owned observer goes before the termination flush starts.
            hide()
            onQuit?()
        case .handle: break
        }
    }

    private func arrow(from target: FloatingTileTarget, _ direction: FloatingTileDirection) {
        guard let plan else { return }
        setKeyboardCues(true)
        state.focus(target)
        if let next = state.moveFocus(direction, plan: plan) { focusButton(next) }
    }

    /// First key entry (a click inside the HUD made it key): put keyboard focus on a real control.
    private func keyboardEntered() {
        guard let panel, let plan else { return }
        logger.info("keyboard entry: panel became key, appActive=\(NSApp.isActive)")
        if let responder = panel.firstResponder as? FloatingTileButton, !responder.isHiddenOrHasHiddenAncestor { return }
        if let target = state.entryTarget(kinds: plan.kinds) { focusButton(target) }
    }

    /// Keyboard input shows focus rings; mouse input hides them (focus itself stays put).
    private func noteInput() {
        switch NSApp.currentEvent?.type {
        case .keyDown?: setKeyboardCues(true)
        case .leftMouseDown?, .leftMouseUp?, .rightMouseDown?, .rightMouseUp?, .otherMouseDown?, .otherMouseUp?:
            setKeyboardCues(false)
        default: break
        }
    }

    private func setKeyboardCues(_ on: Bool) {
        guard on != keyboardCues else { return }
        keyboardCues = on
        for button in buttons.values {
            button.focusRingType = on ? .exterior : .none
            button.noteFocusRingMaskChanged()
            button.setKeyboardFocusRingNeedsDisplay(button.bounds)
        }
    }

    private func focusButton(_ target: FloatingTileTarget) {
        guard let panel, let button = buttons[target], !button.isHiddenOrHasHiddenAncestor else { return }
        panel.makeFirstResponder(button)
    }

    private func apply(_ effect: FloatingTileEffect) {
        switch effect {
        case .none:
            return
        case .showOverview(let focus):
            transitionGeneration += 1
            // Every primary fades back in at its frozen frame; the detail fades out and goes.
            let primaries = plan?.kinds.compactMap { buttons[.tile($0)] } ?? []
            let returning = primaries.filter { $0.isHidden || $0.alphaValue < 1 }
            for view in returning where view.isHidden {
                view.alphaValue = 0
                view.isHidden = false
            }
            let card = detailHost
            detailHost = nil
            fade(in: returning, out: card.map { [$0] } ?? []) { card?.removeFromSuperview() }
            host?.setAccessibilityLabel("Statistics overview")
            if let host { NSAccessibility.post(element: host, notification: .layoutChanged) }
            onDetailChanged?(nil)
            if let focus, panel?.isKeyWindow == true { focusButton(focus) }
        case .showDetail(let kind, let hiding, let focus):
            guard let plan, let host, let frame = plan.detailFrames[kind], let detailContent else { return }
            transitionGeneration += 1
            let generation = transitionGeneration
            detailHost?.removeFromSuperview()
            let card = FloatingTileInteractiveHostingView(
                rootView: detailContent(kind, frame.size, plan.scrollingDetails.contains(kind)))
            // The frozen frame is authoritative; content changes never resize or move the card.
            card.sizingOptions = []
            card.frame = frame
            card.alphaValue = 0
            host.addSubview(card)
            detailHost = card
            card.setAccessibilityLabel("\(kind.displayName) detail")
            // The clicked primary stays exactly where it is; only the others fade out.
            let others = hiding.compactMap { buttons[.tile($0)] }
            fade(in: [card], out: others) { [weak self] in
                guard let self, self.transitionGeneration == generation else { return }
                others.forEach { $0.isHidden = true }
            }
            host.setAccessibilityLabel("\(kind.displayName) with detail")
            NSAccessibility.post(element: host, notification: .layoutChanged)
            if let item = buttons[.tile(kind)] { NSAccessibility.post(element: item, notification: .valueChanged) }
            onDetailChanged?(kind)
            if panel?.isKeyWindow == true { focusButton(focus) }
        case .dismiss:
            hide()
        }
    }

    /// Opacity-only cross-fade (no frame changes, so nothing slides or moves); instant with
    /// Reduce Motion. `completion` runs once the fade has finished.
    private func fade(in shown: [NSView], out gone: [NSView], completion: @escaping @MainActor () -> Void) {
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.fadeDuration
        guard duration > 0, !(shown.isEmpty && gone.isEmpty) else {
            shown.forEach { $0.alphaValue = 1 }
            gone.forEach { $0.alphaValue = 0 }
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shown.forEach { $0.animator().alphaValue = 1 }
            gone.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated { completion() }
        })
    }

    // MARK: Panel and placement

    private func makePanel(size: NSSize) -> FloatingTileHUDPanel {
        let panel = FloatingTileHUDPanel(contentRect: NSRect(origin: .zero, size: size),
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // No window shadow: a shadow computed for one surface arrangement would go stale when
        // a card opens or closes inside the same window.
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // A click on any control may make the panel key (without activating the app), so keyboard
        // navigation starts from the first click. Summon itself never makes it key.
        panel.becomesKeyOnlyIfNeeded = false
        return panel
    }

    /// Re-clamps the whole group after a display change; dismisses when the frozen footprint no
    /// longer fits any display, so navigation can never be stranded off screen.
    private func displayChanged() {
        guard let panel else { return }
        let frames = NSScreen.screens.map(\.visibleFrame)
        if let origin = FloatingTilePlacement.reclamp(frame: panel.frame, visibleFrames: frames) {
            if origin != panel.frame.origin { panel.setFrameOrigin(origin) }
            logger.info("display change: group re-clamped to \(Int(origin.x)),\(Int(origin.y))")
        } else {
            logger.info("display change: footprint no longer fits; dismissing")
            hide()
        }
    }
}
#endif

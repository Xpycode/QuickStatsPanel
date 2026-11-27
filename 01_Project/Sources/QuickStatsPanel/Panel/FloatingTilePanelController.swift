#if DEBUG
import AppKit
import OSLog
import SwiftUI

/// Shows the floating-tile prototype (Debug only, `--floating-tiles-prototype`).
///
/// **Panel arrangement:** one borderless, non-activating, fully transparent host panel sized to
/// the summon's frozen footprint. Tiles, the detail card, the switcher and the group bar are
/// separate surfaces inside it with transparent gaps between them. One window keeps keyboard
/// focus, dismissal and group dragging trivially coordinated (there is nothing to keep in sync),
/// while the window server passes clicks on fully transparent pixels through to the window below,
/// where the existing global monitor treats them as click-away. Separate detail/switcher panels
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
    private var tileViews: [NSView] = []
    private var switcherViews: [NSView] = []
    private var detailHost: NSView?
    private var detailContent: ((StatKind, CGSize, Bool) -> AnyView)?
    private let selection = FloatingTileSelectionModel()
    private var keyObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private let edgeMargin: CGFloat = 24
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sim.QuickStatsPanel",
                                category: "FloatingTiles")

    var isVisible: Bool { panel?.isVisible ?? false }
    var frame: NSRect? { panel?.frame }

    // MARK: Show / hide

    /// - Parameters:
    ///   - detailSizes: every enabled stat's measured detail card, taken once now so the whole
    ///     footprint (and the switcher position) is chosen before any input.
    ///   - tile: overview tile content for a stat (`true` for the large first tile).
    ///   - detail: detail card content for a stat at its frozen frame size; `true` when it scrolls.
    func show(kinds: [StatKind], detailSizes: [StatKind: CGSize], anchor: PanelAnchor,
              tile: (StatKind, Bool) -> AnyView,
              detail: @escaping (StatKind, CGSize, Bool) -> AnyView) {
        guard panel == nil else { return }
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let available = CGSize(width: visible.width - 16, height: visible.height - 16)
        let plan = FloatingTilePlan.make(kinds: kinds, detailSizes: detailSizes, available: available)
        logger.info("summon plan \(Int(plan.size.width))x\(Int(plan.size.height)) columns=\(plan.columns) fits=\(plan.fits) scrolling=\(plan.scrollingDetails.count)")
        if !plan.fits {
            NSLog("Floating tiles: footprint %.0fx%.0f exceeds the available %.0fx%.0f; navigation may clip",
                  plan.size.width, plan.size.height, available.width, available.height)
        }
        self.plan = plan
        detailContent = detail

        let host = FloatingTileHostView(frame: NSRect(origin: .zero, size: plan.size))
        host.contextMenuProvider = contextMenuProvider
        build(in: host, plan: plan, tile: tile)

        let panel = makePanel(size: plan.size)
        panel.contentView = host
        panel.autorecalculatesKeyViewLoop = true
        let origin = origin(for: plan.size, anchor: anchor, cursor: cursor, visible: visible)
        panel.setFrame(NSRect(origin: origin, size: plan.size), display: true)
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

        apply(state.summon())
        // Ordered front without becoming key: summoning never takes keyboard focus or activates.
        panel.orderFrontRegardless()
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
        panel?.orderOut(nil)
        panel = nil
        host = nil
        buttons = [:]
        tileViews = []
        switcherViews = []
        detailHost = nil
        detailContent = nil
        plan = nil
        selection.current = nil
        onDetailChanged?(nil)
        onVisibilityChanged?(false)
    }

    /// Escape (scoped Carbon hotkey, also while pinned): detail → overview → dismiss.
    func handleEscape() { apply(state.escape()) }

    // MARK: Construction

    private func build(in host: FloatingTileHostView, plan: FloatingTilePlan, tile: (StatKind, Bool) -> AnyView) {
        buttons = [:]
        tileViews = []
        switcherViews = []
        let radius = AppSettings.shared.theme.metrics.cornerRadius

        for (index, kind) in plan.kinds.enumerated() {
            guard let frame = plan.tileFrames[kind] else { continue }
            let button = makeButton(.tile(kind), label: "\(kind.displayName) tile",
                                    content: tile(kind, index == 0), frame: frame, in: host)
            button.cornerRadius = radius
            button.toolTip = "Open \(kind.displayName) detail"
            tileViews.append(button)
        }

        let switcherBackground = FloatingTileDrawingView(rootView: FloatingTileSwitcherBackground())
        switcherBackground.frame = plan.switcherFrame
        host.addSubview(switcherBackground)
        switcherViews.append(switcherBackground)
        for kind in plan.kinds {
            guard let frame = plan.switcherItemFrames[.switcher(kind)] else { continue }
            let button = makeButton(.switcher(kind), label: "Show \(kind.displayName) detail",
                                    content: FloatingTileSwitcherItem(kind: kind, selection: selection),
                                    frame: frame, in: host)
            switcherViews.append(button)
        }
        if let frame = plan.switcherItemFrames[.allStatistics] {
            let button = makeButton(.allStatistics, label: "All statistics",
                                    content: FloatingTileAllStatisticsView(), frame: frame, in: host)
            button.toolTip = "Return to all statistics (Escape)"
            switcherViews.append(button)
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
        button.onActivate = { [weak self] in self?.activate($0) }
        button.onArrow = { [weak self] target, direction in self?.arrow(from: target, direction) }
        button.onFocus = { [weak self] in self?.state.focus($0) }
        host.addSubview(button)
        buttons[target] = button
        return button
    }

    // MARK: Actions

    private func activate(_ target: FloatingTileTarget) {
        guard let plan else { return }
        switch target {
        case .tile(let kind), .switcher(let kind): apply(state.select(kind, plan: plan))
        case .allStatistics: apply(state.returnToOverview())
        case .settings: onOpenSettings?()
        case .quit: onQuit?()
        case .handle: break
        }
    }

    private func arrow(from target: FloatingTileTarget, _ direction: FloatingTileDirection) {
        guard let plan else { return }
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

    private func focusButton(_ target: FloatingTileTarget) {
        guard let panel, let button = buttons[target], !button.isHiddenOrHasHiddenAncestor else { return }
        panel.makeFirstResponder(button)
    }

    private func apply(_ effect: FloatingTileEffect) {
        switch effect {
        case .none:
            return
        case .showOverview(let focus):
            detailHost?.removeFromSuperview()
            detailHost = nil
            selection.current = nil
            tileViews.forEach { $0.isHidden = false }
            switcherViews.forEach { $0.isHidden = true }
            onDetailChanged?(nil)
            if let focus, panel?.isKeyWindow == true { focusButton(focus) }
        case .showDetail(let kind, let focus):
            guard let plan, let host, let frame = plan.detailFrames[kind], let detailContent else { return }
            detailHost?.removeFromSuperview()
            let card = FloatingTileInteractiveHostingView(
                rootView: detailContent(kind, frame.size, plan.scrollingDetails.contains(kind)))
            // The frozen frame is authoritative; content changes never resize or move the card.
            card.sizingOptions = []
            card.frame = frame
            host.addSubview(card)
            detailHost = card
            selection.current = kind
            for k in plan.kinds {
                buttons[.switcher(k)]?.setAccessibilityLabel(k == kind ? "\(k.displayName), current" : "Show \(k.displayName) detail")
            }
            tileViews.forEach { $0.isHidden = true }
            switcherViews.forEach { $0.isHidden = false }
            onDetailChanged?(kind)
            if panel?.isKeyWindow == true { focusButton(focus) }
        case .dismiss:
            hide()
        }
    }

    // MARK: Panel and placement

    private func makePanel(size: NSSize) -> FloatingTileHUDPanel {
        let panel = FloatingTileHUDPanel(contentRect: NSRect(origin: .zero, size: size),
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // No window shadow: a shadow computed for one surface arrangement would go stale when
        // the detail replaces the overview inside the same window.
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

    private func origin(for size: CGSize, anchor: PanelAnchor, cursor: NSPoint, visible: NSRect) -> NSPoint {
        var origin: NSPoint
        switch anchor {
        case .cursor: origin = NSPoint(x: cursor.x - size.width / 2, y: cursor.y - size.height - 18)
        case .screenCenter: origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        case .topCenter: origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - edgeMargin)
        case .bottomCenter: origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + edgeMargin)
        }
        origin.x = size.width <= visible.width ? min(max(origin.x, visible.minX), visible.maxX - size.width) : visible.minX
        origin.y = size.height <= visible.height ? min(max(origin.y, visible.minY), visible.maxY - size.height)
                                                 : visible.maxY - size.height
        return origin
    }
}
#endif

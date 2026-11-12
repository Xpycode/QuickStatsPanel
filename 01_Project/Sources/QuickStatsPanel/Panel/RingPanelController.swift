#if DEBUG
import AppKit
import OSLog
import SwiftUI

/// Debug-only launch configuration for the ring prototype.
///
/// Arguments (both are needed; `--ring-fixture` alone is ignored and launches Strip):
///   --ring-prototype              Show Ring instead of Strip. Real data: ordinary store,
///                                 samplers and transfer-history lifecycle.
///   --ring-fixture=<name>         With `--ring-prototype`: deterministic fixture mode on a
///                                 disposable store; no samplers, retained transfer history,
///                                 updater or first-run hint, and no production defaults written.
///                                 Names: none, one, six, eight, twelve, long, paired,
///                                 unavailable. (`twelve` enables all eleven stat kinds.)
///                                 An unknown name logs an error and falls back to `six`.
struct RingPrototypeLaunch: Sendable {
    let fixture: RingFixture?

    static let current: RingPrototypeLaunch? = parse(CommandLine.arguments)

    static func parse(_ arguments: [String]) -> RingPrototypeLaunch? {
        guard arguments.contains("--ring-prototype") else { return nil }
        let prefix = "--ring-fixture="
        guard let raw = arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return RingPrototypeLaunch(fixture: nil)
        }
        let name = String(raw.dropFirst(prefix.count))
        if let fixture = RingFixture.named(name) { return RingPrototypeLaunch(fixture: fixture) }
        NSLog("Unknown --ring-fixture '%@'; using 'six'. Valid: %@", name, RingFixture.names.joined(separator: ", "))
        return RingPrototypeLaunch(fixture: RingFixture.named("six"))
    }
}

/// Shows the favourite ring in its own borderless, non-activating `NSPanel` sized to
/// the 520 x 520 footprint. Separate panels per surface (this one, the detail card)
/// keep every window the size of visible content; there is never one large
/// transparent window. Visibility is reported through `onVisibilityChanged`, the same
/// signal `PanelWindowController` emits, so the owner drives identical effects.
@MainActor
final class RingPanelController {

    /// Fired with `true` when the ring appears and `false` when it hides, by any route.
    var onVisibilityChanged: ((Bool) -> Void)?
    var onActivate: ((RingTarget) -> Void)?
    var onOutsideClick: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu)?

    let state = RingPresentationState()
    private(set) var snapshot: RingSnapshot?

    private var panel: NSPanel?
    private let edgeMargin: CGFloat = 24

    var isVisible: Bool { panel?.isVisible ?? false }
    var frame: NSRect? { panel?.frame }

    // MARK: Hover observation

    // Hover is a visibility-scoped, permission-free mouse-moved observation, evaluated
    // against the frozen geometry: a global monitor (other apps frontmost), a local
    // monitor (events delivered to this app's windows) and a 20 Hz poll of
    // NSEvent.mouseLocation that only acts when neither monitor has delivered recently.
    // None intercepts an event; all are removed on hide. Which mechanism delivered is
    // logged (category "RingPrototype") so the owner can confirm natively.
    private enum Mechanism: String { case global, local, poll }
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTimer: Timer?
    private var lastMonitorEvent = Date.distantPast
    private var lastPolledPoint: NSPoint?
    private var deliveries: [Mechanism: Int] = [:]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.sim.QuickStatsPanel",
                                category: "RingPrototype")

    func toggle(snapshot: RingSnapshot, anchor: PanelAnchor, reading: @escaping (StatKind) -> RingReading,
                describe: @escaping (RingTarget) -> RingInputView.Description) {
        if isVisible { hide() } else { show(snapshot: snapshot, anchor: anchor, reading: reading, describe: describe) }
    }

    func show(snapshot: RingSnapshot, anchor: PanelAnchor, reading: @escaping (StatKind) -> RingReading,
              describe: @escaping (RingTarget) -> RingInputView.Description) {
        guard panel == nil else { return }
        self.snapshot = snapshot
        let size = snapshot.geometry.size

        let input = RingInputView(geometry: snapshot.geometry)
        input.describe = describe
        input.onActivate = { [weak self] in self?.onActivate?($0) }
        input.onOutsideClick = { [weak self] in self?.onOutsideClick?() }
        input.contextMenuProvider = { [weak self] in self?.contextMenuProvider?() ?? NSMenu() }

        let hosting = PassthroughHostingView(rootView: RingView(snapshot: snapshot, state: state, reading: reading))
        hosting.frame = NSRect(origin: .zero, size: size)
        input.addSubview(hosting)

        let panel = makePanel(size: size)
        panel.contentView = input
        panel.setFrame(NSRect(origin: origin(forSize: size, anchor: anchor), size: size), display: true)
        self.panel = panel

        state.beginSummon(pointer: NSEvent.mouseLocation)
        panel.orderFrontRegardless()
        installHoverObservation()
        onVisibilityChanged?(true)
    }

    func hide() {
        // Redundant hides (click-away after Escape) must not emit a second `false`.
        guard panel != nil else { return }
        removeHoverObservation()
        panel?.orderOut(nil)
        panel = nil
        snapshot = nil
        state.reset()
        onVisibilityChanged?(false)
    }

    /// Screen frame of a wedge (the parent target for its detail card).
    func screenFrame(of target: RingTarget) -> NSRect? {
        guard let panel, let snapshot, let local = snapshot.geometry.frame(of: target) else { return nil }
        let frame = panel.frame
        return NSRect(x: frame.minX + local.minX, y: frame.maxY - local.maxY,
                      width: local.width, height: local.height)
    }

    // MARK: Hover observation implementation

    private func installHoverObservation() {
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
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func removeHoverObservation() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
        logger.info("hover deliveries this summon: global=\(self.deliveries[.global, default: 0]) local=\(self.deliveries[.local, default: 0]) poll=\(self.deliveries[.poll, default: 0])")
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
        guard let panel, let snapshot else { return }
        if mechanism != .poll { lastMonitorEvent = Date() }
        lastPolledPoint = NSEvent.mouseLocation
        let count = deliveries[mechanism, default: 0] + 1
        deliveries[mechanism] = count
        if count == 1 {
            logger.info("first hover event delivered by \(mechanism.rawValue, privacy: .public)")
        }
        state.updatePointer(screenPoint: NSEvent.mouseLocation, ringFrame: panel.frame, geometry: snapshot.geometry)
    }

    // MARK: Placement

    /// Centre the footprint per the saved anchor (read only; a ring drag saves nothing),
    /// clamped inside the visible frame of the pointer's screen.
    private func origin(forSize size: NSSize, anchor: PanelAnchor) -> NSPoint {
        let cursor = NSEvent.mouseLocation
        let host = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let visible = host?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var origin: NSPoint
        switch anchor {
        case .cursor:
            origin = NSPoint(x: cursor.x - size.width / 2, y: cursor.y - size.height / 2)
        case .screenCenter:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        case .topCenter:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - edgeMargin)
        case .bottomCenter:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + edgeMargin)
        }
        origin.x = visible.width >= size.width ? min(max(origin.x, visible.minX), visible.maxX - size.width) : visible.minX
        origin.y = visible.height >= size.height ? min(max(origin.y, visible.minY), visible.maxY - size.height) : visible.minY
        return origin
    }

    // MARK: Panel

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
}
#endif

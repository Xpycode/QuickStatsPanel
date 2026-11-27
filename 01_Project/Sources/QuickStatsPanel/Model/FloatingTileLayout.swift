import CoreGraphics
import Foundation

#if DEBUG

/// Floating-tile prototype dimensions (spec "Proposed prototype defaults"). Frozen for the
/// prototype as of task 2.1 (a test pins them); they are starting values for native review, not
/// accepted sizing, and there is no production settings UI to change them.
struct FloatingTileMetrics: Equatable, Sendable {
    /// Width of the four-column overview, as in the reviewed HTML mockup.
    var baseWidth: CGFloat = 480
    var columns = 4
    /// Column reduction floor on narrow displays: the 2×2 first tile still fits.
    var minimumColumns = 2
    var rowHeight: CGFloat = 100
    /// Between primaries (and below the group bar).
    var gap: CGFloat = 12
    /// Between an open primary and its detail (D-045).
    var detailGap: CGFloat = 6
    /// The widest detail the host reserves room for on each side of the core (the envelope sized
    /// at summon, so details measured at open never resize the host).
    var detailEnvelopeWidth: CGFloat = 480
    /// The group bar (move handle, Settings, Quit) above the overview's right edge.
    var barWidth: CGFloat = 106
    var barHeight: CGFloat = 28

    var columnWidth: CGFloat { (baseWidth - gap * CGFloat(columns - 1)) / CGFloat(columns) }
}

/// Every focusable surface control of the prototype, by identity. There is no switcher (D-044):
/// a stat is changed by closing its detail and picking another primary.
enum FloatingTileTarget: Hashable, Sendable {
    case tile(StatKind)
    case handle, settings, quit
}

enum FloatingTileDirection: Sendable, CaseIterable {
    case left, right, up, down
}

/// The side of its primary (overview tile) a stat's detail opens on. Always sideways (D-044).
enum FloatingTileSide: Sendable, CaseIterable {
    case left, right

    var opposite: FloatingTileSide { self == .left ? .right : .left }
}

/// One opened detail's frame, computed when its primary is opened from the size measured then
/// (D-045), and frozen while that detail stays open.
struct FloatingTileDetailPlacement: Equatable, Sendable {
    /// In the host's top-left coordinates.
    let frame: CGRect
    let side: FloatingTileSide
    /// The measured content is taller than `frame`; the card scrolls.
    let scrolls: Bool
}

/// The frozen geometry of one summon, in a top-left-origin space of size `size` (the host
/// window). The core — group bar and overview — never moves. Clicking a primary hides the other
/// primaries; the clicked one stays exactly where it is and its detail opens sideways beside it,
/// toward the larger part of the old overview footprint (D-044). The host is sized once at summon
/// to a generous envelope (the core, plus up to `detailEnvelopeWidth` on each side and down to the
/// display's bottom, clamped to the display), so a detail measured at open (D-045) always fits
/// inside it and the host never resizes or moves. Sample updates never rebuild the plan.
struct FloatingTilePlan: Equatable, Sendable {
    let kinds: [StatKind]
    let metrics: FloatingTileMetrics
    /// Overview columns actually used (reduced on narrow displays).
    let columns: Int
    /// The host window's size: the core plus the detail envelope.
    let size: CGSize
    /// Group bar and overview, inside `size`.
    let coreFrame: CGRect
    /// The overview footprint (all primaries, or their scrolling viewport) below the bar.
    let overviewFrame: CGRect
    let barFrame: CGRect
    let barItemFrames: [FloatingTileTarget: CGRect]
    let tileFrames: [StatKind: CGRect]
    /// The display region (as planned at summon) inside the host, where details may go.
    let detailRegion: CGRect
    /// The visible overview region when the overview is taller than the available space (it then
    /// scrolls inside this frame; tile frames stay in unscrolled footprint coordinates). Nil when
    /// the whole overview fits, which is the normal case.
    let overviewViewport: CGRect?
    /// Width added beside scrolling content for a legacy ("Always show") scroll bar; 0 for overlay
    /// scrollers. Applied only to content that actually scrolls.
    let scrollerReserve: CGFloat
    /// The compact empty state shown instead of tiles when no stat is enabled; nil otherwise.
    let emptyStateFrame: CGRect?
    /// False when even the reduced core exceeds the available space (the prototype's stop
    /// condition: navigation would not stay reachable without clipping).
    let fits: Bool

    /// Top-left of the overview, below the group bar.
    var contentOrigin: CGPoint { CGPoint(x: coreFrame.minX, y: coreFrame.minY + metrics.barHeight + metrics.gap) }

    /// Builds the plan once per summon. Columns reduce 4 → 2 only when the core is wider than
    /// `available`.
    /// - Parameter bounds: the display region details must stay inside, in the core's own
    ///   top-left coordinates (core origin at 0,0). Nil centres the core in `available`.
    static func make(kinds: [StatKind], available: CGSize, bounds: CGRect? = nil, scrollerReserve: CGFloat = 0,
                     metrics: FloatingTileMetrics = FloatingTileMetrics()) -> FloatingTilePlan {
        var columns = metrics.columns
        var plan = layout(kinds: kinds, available: available, bounds: bounds,
                          scrollerReserve: scrollerReserve, metrics: metrics, columns: columns)
        // Reduce columns at summon (never on selection) while the core is too wide.
        while plan.coreFrame.width > available.width, columns > metrics.minimumColumns {
            columns = max(metrics.minimumColumns, columns - 2)
            plan = layout(kinds: kinds, available: available, bounds: bounds,
                          scrollerReserve: scrollerReserve, metrics: metrics, columns: columns)
        }
        return plan
    }

    private static func layout(kinds: [StatKind], available: CGSize, bounds requestedBounds: CGRect?,
                               scrollerReserve reserve: CGFloat, metrics m: FloatingTileMetrics,
                               columns: Int) -> FloatingTilePlan {
        let top = m.barHeight + m.gap
        let maxContentHeight = max(0, available.height - top)
        let tiles = packTiles(kinds: kinds, columns: columns, metrics: m)
        let overviewWidth = CGFloat(columns) * m.columnWidth + CGFloat(columns - 1) * m.gap
        let emptyState: CGRect? = kinds.isEmpty
            ? CGRect(x: 0, y: top, width: overviewWidth, height: m.rowHeight) : nil
        // Height of the overview content below the bar.
        let overviewHeight = (emptyState?.maxY ?? tiles.values.map(\.maxY).max() ?? top) - top
        // Limited space: an overview taller than the display scrolls inside a viewport, with the
        // group bar outside it (navigation always reachable); type never shrinks.
        let overviewViewport: CGRect? = overviewHeight > maxContentHeight + 0.5
            ? CGRect(x: 0, y: top, width: overviewWidth + reserve, height: maxContentHeight) : nil
        let overviewFootprintWidth = overviewViewport?.width ?? overviewWidth
        let overviewRect = CGRect(x: 0, y: top, width: overviewFootprintWidth,
                                  height: overviewViewport?.height ?? overviewHeight)

        // Group bar above the overview's right edge: move handle, Settings, Quit.
        let barX = max(0, overviewFootprintWidth - m.barWidth)
        let bar = CGRect(x: barX, y: 0, width: m.barWidth, height: m.barHeight)
        let barItem = (m.barWidth - 4 * 2) / 3
        var barItems: [FloatingTileTarget: CGRect] = [:]
        for (index, target) in [FloatingTileTarget.handle, .settings, .quit].enumerated() {
            barItems[target] = CGRect(x: barX + 2 + CGFloat(index) * (barItem + 2), y: 2,
                                      width: barItem, height: m.barHeight - 4)
        }

        let core = CGRect(x: 0, y: 0, width: max(overviewFootprintWidth, bar.maxX), height: top + overviewRect.height)
        let bounds = requestedBounds ?? CGRect(x: (core.width - available.width) / 2,
                                               y: (core.height - available.height) / 2,
                                               width: available.width, height: available.height)

        // The detail envelope: beside the core on both sides and from the core's top down to the
        // display's bottom (every detail's top is the overview's top, D-045), clamped to the
        // display but never smaller than the core itself.
        let reach = m.detailGap + m.detailEnvelopeWidth + reserve
        let hostMinX = min(core.minX, max(bounds.minX, core.minX - reach))
        let hostMaxX = max(core.maxX, min(bounds.maxX, core.maxX + reach))
        let hostMaxY = max(core.maxY, bounds.maxY)
        let host = CGRect(x: hostMinX, y: core.minY, width: hostMaxX - hostMinX, height: hostMaxY - core.minY)
        let region = bounds.intersection(host)

        // Shift everything so the host starts at 0,0.
        let dx = -host.minX, dy = -host.minY
        func shift(_ r: CGRect) -> CGRect { r.offsetBy(dx: dx, dy: dy) }

        let fits = core.width <= available.width + 0.5
            && top + min(overviewHeight, m.rowHeight) <= available.height + 0.5
        return FloatingTilePlan(kinds: kinds, metrics: m, columns: columns, size: host.size,
                                coreFrame: shift(core), overviewFrame: shift(overviewRect), barFrame: shift(bar),
                                barItemFrames: barItems.mapValues(shift), tileFrames: tiles.mapValues(shift),
                                detailRegion: region.isNull ? shift(core) : shift(region),
                                overviewViewport: overviewViewport.map(shift), scrollerReserve: reserve,
                                emptyStateFrame: emptyState.map(shift), fits: fits)
    }

    /// Toward the larger part of the overview footprint: a primary in the left half opens its
    /// detail to the right, one in the right half to the left. A centred (full-width) primary
    /// opens to the right.
    static func preferredSide(tile: CGRect, overview: CGRect) -> FloatingTileSide {
        tile.midX <= overview.midX + 0.5 ? .right : .left
    }

    /// The frame for `kind`'s detail, from the size measured now (when it is opened, D-045).
    /// - Parameter display: the current display region in host coordinates (the group may have
    ///   been dragged since summon); nil uses the region planned at summon. Always limited to the
    ///   host, which never resizes.
    func detailPlacement(for kind: StatKind, measured: CGSize, display: CGRect? = nil) -> FloatingTileDetailPlacement {
        let host = CGRect(origin: .zero, size: size)
        var region = (display ?? detailRegion).intersection(host)
        if region.isNull || region.isEmpty { region = host }
        let tile = tileFrames[kind] ?? overviewFrame
        var placed = Self.placeDetail(size: measured, tile: tile, overview: overviewFrame, bounds: region,
                                      gap: metrics.detailGap)
        // A scrolling detail gets a legacy scroll bar's width beside its measured content.
        if placed.scrolls, scrollerReserve > 0 {
            placed = Self.placeDetail(size: CGSize(width: measured.width + scrollerReserve, height: measured.height),
                                      tile: tile, overview: overviewFrame, bounds: region, gap: metrics.detailGap)
        }
        return placed
    }

    /// Places one detail beside its primary, which never moves:
    /// - side: the preferred side (`preferredSide`) if the detail fits the region there, else the
    ///   opposite side; if neither fits, the side with more room, clamped into `bounds` (only on
    ///   displays too narrow for the detail — the measured width never shrinks, so text does not);
    /// - vertical: the top edge is the overview's top (one line for every detail, D-045); the
    ///   height is limited to the region's bottom, and a limited detail scrolls.
    static func placeDetail(size: CGSize, tile: CGRect, overview: CGRect, bounds: CGRect,
                            gap: CGFloat) -> FloatingTileDetailPlacement {
        let width = min(size.width, bounds.width)
        func x(_ side: FloatingTileSide) -> CGFloat { side == .right ? tile.maxX + gap : tile.minX - gap - width }
        func room(_ side: FloatingTileSide) -> CGFloat {
            side == .right ? bounds.maxX - (tile.maxX + gap) : (tile.minX - gap) - bounds.minX
        }
        let preferred = preferredSide(tile: tile, overview: overview)
        let side: FloatingTileSide
        var fx: CGFloat
        if let fitting = [preferred, preferred.opposite].first(where: { room($0) >= width - 0.5 }) {
            side = fitting
            fx = x(side)
        } else {
            side = room(preferred.opposite) > room(preferred) + 0.5 ? preferred.opposite : preferred
            fx = min(max(x(side), bounds.minX), bounds.maxX - width)
        }
        fx = fx.rounded()

        let fy = max(overview.minY, bounds.minY)
        let height = min(size.height, max(0, bounds.maxY - fy))
        return FloatingTileDetailPlacement(frame: CGRect(x: fx, y: fy, width: width, height: height), side: side,
                                           scrolls: size.height > height + 0.5)
    }

    /// First enabled stat spans 2×2 cells, the next two span 2×1, the rest 1×1; packed in saved
    /// order into the first free position (rows top to bottom, columns left to right).
    static func packTiles(kinds: [StatKind], columns: Int, metrics m: FloatingTileMetrics) -> [StatKind: CGRect] {
        let top = m.barHeight + m.gap
        var occupied = Set<[Int]>()
        var frames: [StatKind: CGRect] = [:]
        for (index, kind) in kinds.enumerated() {
            let span: (w: Int, h: Int) = index == 0 ? (2, 2) : (index < 3 ? (2, 1) : (1, 1))
            let w = min(span.w, columns)
            var row = 0
            placing: while true {
                for column in 0...(columns - w) {
                    let cells = (row..<(row + span.h)).flatMap { r in (column..<(column + w)).map { [r, $0] } }
                    if cells.allSatisfy({ !occupied.contains($0) }) {
                        cells.forEach { occupied.insert($0) }
                        frames[kind] = CGRect(
                            x: CGFloat(column) * (m.columnWidth + m.gap),
                            y: top + CGFloat(row) * (m.rowHeight + m.gap),
                            width: CGFloat(w) * m.columnWidth + CGFloat(w - 1) * m.gap,
                            height: CGFloat(span.h) * m.rowHeight + CGFloat(span.h - 1) * m.gap)
                        break placing
                    }
                }
                row += 1
            }
        }
        return frames
    }

    /// Frames of the targets reachable in the given mode, for focus traversal. With a detail open
    /// only its primary and the group bar remain (the other primaries are hidden).
    func targetFrames(open: StatKind?) -> [FloatingTileTarget: CGRect] {
        var frames = barItemFrames
        for (kind, frame) in tileFrames where open == nil || open == kind { frames[.tile(kind)] = frame }
        return frames
    }

    /// The visual neighbour of `target` in `direction`, from actual frames (not list indices).
    func neighbour(of target: FloatingTileTarget, _ direction: FloatingTileDirection, open: StatKind?) -> FloatingTileTarget? {
        Self.neighbour(of: target, direction, in: targetFrames(open: open))
    }

    /// Candidates lie wholly beyond the source edge in `direction`; the nearest wins, with
    /// perpendicular overlap preferred and perpendicular offset penalised.
    static func neighbour(of target: FloatingTileTarget, _ direction: FloatingTileDirection,
                          in frames: [FloatingTileTarget: CGRect]) -> FloatingTileTarget? {
        guard let source = frames[target] else { return nil }
        var best: (target: FloatingTileTarget, score: CGFloat, frame: CGRect)?
        for (candidate, frame) in frames where candidate != target {
            let along: CGFloat
            let overlap: CGFloat
            let offset: CGFloat
            switch direction {
            case .right:
                guard frame.minX >= source.maxX - 0.5 else { continue }
                along = frame.minX - source.maxX
                overlap = min(frame.maxY, source.maxY) - max(frame.minY, source.minY)
                offset = abs(frame.midY - source.midY)
            case .left:
                guard frame.maxX <= source.minX + 0.5 else { continue }
                along = source.minX - frame.maxX
                overlap = min(frame.maxY, source.maxY) - max(frame.minY, source.minY)
                offset = abs(frame.midY - source.midY)
            case .down:
                guard frame.minY >= source.maxY - 0.5 else { continue }
                along = frame.minY - source.maxY
                overlap = min(frame.maxX, source.maxX) - max(frame.minX, source.minX)
                offset = abs(frame.midX - source.midX)
            case .up:
                guard frame.maxY <= source.minY + 0.5 else { continue }
                along = source.minY - frame.maxY
                overlap = min(frame.maxX, source.maxX) - max(frame.minX, source.minX)
                offset = abs(frame.midX - source.midX)
            }
            let score = along + offset * 2 + (overlap > 0 ? 0 : 10_000)
            // Equal scores resolve in reading order (top, then left), so the result is deterministic.
            let wins = best.map { b in
                score < b.score || (score == b.score && (frame.minY, frame.minX) < (b.frame.minY, b.frame.minX))
            } ?? true
            if wins { best = (candidate, score, frame) }
        }
        return best?.target
    }
}

/// Pure placement of the frozen footprint in AppKit screen coordinates (bottom-left origin).
enum FloatingTilePlacement {
    /// Distance kept from the visible frame's edge for the top/bottom anchors.
    static let edgeMargin: CGFloat = 24
    /// Margin subtracted from the region when planning, so the footprint never touches the edge.
    static let planningInset: CGFloat = 16

    /// The region a summon plans and places in: the real visible frame, or a simulated smaller
    /// one centred inside it (`--floating-tiles-frame=`), never larger than the real one.
    static func region(visible: CGRect, simulated: CGSize?) -> CGRect {
        guard let simulated else { return visible }
        let size = CGSize(width: min(simulated.width, visible.width), height: min(simulated.height, visible.height))
        return CGRect(x: (visible.midX - size.width / 2).rounded(.down), y: (visible.midY - size.height / 2).rounded(.down),
                      width: size.width, height: size.height)
    }

    /// The size the plan may use inside `region`.
    static func available(in region: CGRect) -> CGSize {
        CGSize(width: max(0, region.width - planningInset), height: max(0, region.height - planningInset))
    }

    /// The region cards may use, in the core's top-left coordinates, for a core placed at
    /// `coreOrigin` (AppKit, bottom-left) inside `visible`. Keeps half the planning inset as margin.
    static func bounds(coreOrigin: CGPoint, coreSize: CGSize, visible: CGRect) -> CGRect {
        let inner = visible.insetBy(dx: planningInset / 2, dy: planningInset / 2)
        return CGRect(x: inner.minX - coreOrigin.x, y: coreOrigin.y + coreSize.height - inner.maxY,
                      width: inner.width, height: inner.height)
    }

    /// The host window's frame (AppKit) for a plan whose core sits at `coreOrigin`.
    static func hostFrame(coreOrigin: CGPoint, plan: FloatingTilePlan) -> CGRect {
        let coreTop = coreOrigin.y + plan.coreFrame.height
        let hostTop = coreTop + plan.coreFrame.minY
        return CGRect(x: coreOrigin.x - plan.coreFrame.minX, y: hostTop - plan.size.height,
                      width: plan.size.width, height: plan.size.height)
    }

    /// Anchor- or corner-derived origin, then clamped so the whole footprint is inside `visible`.
    static func origin(size: CGSize, anchor: PanelAnchor, cursor: CGPoint, visible: CGRect,
                       edge: FloatingTileEdge? = nil) -> CGPoint {
        var origin: CGPoint
        if let edge {
            // Aim past the corner on purpose: the clamp below must bring it back.
            let overshoot: CGFloat = 40
            let left = edge == .topLeft || edge == .bottomLeft
            let topEdge = edge == .topLeft || edge == .topRight
            origin = CGPoint(x: left ? visible.minX - overshoot : visible.maxX - size.width + overshoot,
                             y: topEdge ? visible.maxY - size.height + overshoot : visible.minY - overshoot)
        } else {
            switch anchor {
            case .cursor: origin = CGPoint(x: cursor.x - size.width / 2, y: cursor.y - size.height - 18)
            case .screenCenter: origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
            case .topCenter: origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - edgeMargin)
            case .bottomCenter: origin = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + edgeMargin)
            }
        }
        return clamp(origin: origin, size: size, in: visible)
    }

    /// Keeps the footprint inside `visible`. An oversized footprint (the `fits == false` stop
    /// condition) keeps its top-left corner, where the overview origin and group bar start.
    static func clamp(origin: CGPoint, size: CGSize, in visible: CGRect) -> CGPoint {
        CGPoint(x: size.width <= visible.width ? min(max(origin.x, visible.minX), visible.maxX - size.width) : visible.minX,
                y: size.height <= visible.height ? min(max(origin.y, visible.minY), visible.maxY - size.height)
                                                 : visible.maxY - size.height)
    }

    /// After a display change: the display holding most of the footprint (else the first, which
    /// is the menu-bar display) keeps the whole group, clamped as one unit. Nil when the frozen
    /// footprint no longer fits that display; the caller then dismisses so the next summon plans
    /// afresh, rather than letting navigation fall off screen.
    static func reclamp(frame: CGRect, visibleFrames: [CGRect]) -> CGPoint? {
        guard !visibleFrames.isEmpty else { return nil }
        func area(_ r: CGRect) -> CGFloat { let i = r.intersection(frame); return i.isNull ? 0 : i.width * i.height }
        let best = visibleFrames.enumerated().max { a, b in
            let (x, y) = (area(a.element), area(b.element))
            return x < y || (x == y && a.offset > b.offset)
        }!
        let visible = area(best.element) > 0 ? best.element : visibleFrames[0]
        guard frame.width <= visible.width + 0.5, frame.height <= visible.height + 0.5 else { return nil }
        return clamp(origin: frame.origin, size: frame.size, in: visible)
    }
}

#endif

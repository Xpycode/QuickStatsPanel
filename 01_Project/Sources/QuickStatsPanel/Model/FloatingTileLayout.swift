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
    var gap: CGFloat = 12
    var switcherWidth: CGFloat = 106
    /// The group bar (move handle, Settings, Quit) above the switcher column.
    var barHeight: CGFloat = 28
    var switcherPadding: CGFloat = 6
    var switcherItemHeight: CGFloat = 40
    var switcherAllHeight: CGFloat = 28

    var columnWidth: CGFloat { (baseWidth - gap * CGFloat(columns - 1)) / CGFloat(columns) }
}

/// Every focusable surface control of the prototype, by identity.
enum FloatingTileTarget: Hashable, Sendable {
    case tile(StatKind)
    case switcher(StatKind)
    case allStatistics
    case handle, settings, quit
}

enum FloatingTileDirection: Sendable, CaseIterable {
    case left, right, up, down
}

/// The frozen geometry of one summon, in a top-left-origin space of size `size`. Built once at
/// summon from the enabled identities and measured detail sizes; sample updates never rebuild it,
/// so tiles, the switcher and its targets cannot move during a summon.
struct FloatingTilePlan: Equatable, Sendable {
    let kinds: [StatKind]
    let metrics: FloatingTileMetrics
    /// Overview columns actually used (reduced on narrow displays).
    let columns: Int
    /// The whole footprint, which is also the host window's size.
    let size: CGSize
    let barFrame: CGRect
    let barItemFrames: [FloatingTileTarget: CGRect]
    let tileFrames: [StatKind: CGRect]
    /// Each stat's detail frame, top-left anchored at the overview origin, never overlapping the
    /// switcher, height-limited to the available space.
    let detailFrames: [StatKind: CGRect]
    /// Stats whose measured detail is taller than its frame; only these scroll.
    let scrollingDetails: Set<StatKind>
    /// The visible overview region when the overview is taller than the available space (it then
    /// scrolls inside this frame; tile frames stay in unscrolled footprint coordinates). Nil when
    /// the whole overview fits, which is the normal case.
    let overviewViewport: CGRect?
    /// Width added beside scrolling content for a legacy ("Always show") scroll bar; 0 for overlay
    /// scrollers. Applied only to content that actually scrolls.
    let scrollerReserve: CGFloat
    /// The compact empty state shown instead of tiles when no stat is enabled; nil otherwise.
    let emptyStateFrame: CGRect?
    let switcherFrame: CGRect
    let switcherItemFrames: [FloatingTileTarget: CGRect]
    /// False when even the reduced layout exceeds the available space (the prototype's stop
    /// condition: navigation would not stay reachable without clipping).
    let fits: Bool

    /// Top-left of the content area (overview and detail), below the group bar.
    var contentOrigin: CGPoint { CGPoint(x: 0, y: metrics.barHeight + metrics.gap) }

    /// Builds the plan once per summon. Columns reduce 4 → 2 only when the footprint is wider
    /// than `available`; the switcher stays at the footprint's right edge.
    static func make(kinds: [StatKind], detailSizes: [StatKind: CGSize], available: CGSize,
                     scrollerReserve: CGFloat = 0,
                     metrics: FloatingTileMetrics = FloatingTileMetrics()) -> FloatingTilePlan {
        var columns = metrics.columns
        var plan = layout(kinds: kinds, detailSizes: detailSizes, available: available,
                          scrollerReserve: scrollerReserve, metrics: metrics, columns: columns)
        // Reduce columns at summon (never on selection) while the footprint is too wide.
        while plan.size.width > available.width, columns > metrics.minimumColumns {
            columns = max(metrics.minimumColumns, columns - 2)
            plan = layout(kinds: kinds, detailSizes: detailSizes, available: available,
                          scrollerReserve: scrollerReserve, metrics: metrics, columns: columns)
        }
        return plan
    }

    private static func layout(kinds: [StatKind], detailSizes: [StatKind: CGSize], available: CGSize,
                               scrollerReserve reserve: CGFloat,
                               metrics m: FloatingTileMetrics, columns: Int) -> FloatingTilePlan {
        let top = m.barHeight + m.gap
        let maxContentHeight = max(0, available.height - top)
        let tiles = packTiles(kinds: kinds, columns: columns, metrics: m)
        let overviewWidth = CGFloat(columns) * m.columnWidth + CGFloat(columns - 1) * m.gap
        let emptyState: CGRect? = kinds.isEmpty
            ? CGRect(x: 0, y: top, width: overviewWidth, height: m.rowHeight) : nil
        // Height of the overview content below the bar.
        let overviewHeight = (emptyState?.maxY ?? tiles.values.map(\.maxY).max() ?? top) - top
        // Limited space: an overview taller than the display scrolls inside a viewport, with the
        // switcher column and group bar outside it (navigation always reachable); type never shrinks.
        let overviewViewport: CGRect? = overviewHeight > maxContentHeight + 0.5
            ? CGRect(x: 0, y: top, width: overviewWidth + reserve, height: maxContentHeight) : nil
        let overviewFootprintWidth = overviewViewport?.width ?? overviewWidth

        // Details: only an oversized card scrolls, and only it gets the scroll-bar reserve.
        var scrolling = Set<StatKind>()
        var detailWidths: [StatKind: CGFloat] = [:]
        for kind in kinds {
            guard let measured = detailSizes[kind] else { continue }
            let scrolls = measured.height > maxContentHeight + 0.5
            if scrolls { scrolling.insert(kind) }
            detailWidths[kind] = measured.width + (scrolls ? reserve : 0)
        }

        // Footprint: enlarge once to the widest detail plus gap and switcher.
        let widestDetail = detailWidths.values.max() ?? 0
        let width = max(overviewFootprintWidth, widestDetail + m.gap + m.switcherWidth, m.switcherWidth)

        // Switcher: two columns in saved order, then "All statistics".
        let switcherX = width - m.switcherWidth
        let itemWidth = (m.switcherWidth - m.switcherPadding * 3) / 2
        var items: [FloatingTileTarget: CGRect] = [:]
        for (index, kind) in kinds.enumerated() {
            let column = CGFloat(index % 2), row = CGFloat(index / 2)
            items[.switcher(kind)] = CGRect(
                x: switcherX + m.switcherPadding + column * (itemWidth + m.switcherPadding),
                y: top + m.switcherPadding + row * (m.switcherItemHeight + m.switcherPadding),
                width: itemWidth, height: m.switcherItemHeight)
        }
        let rows = CGFloat((kinds.count + 1) / 2)
        let allY = top + m.switcherPadding + rows * (m.switcherItemHeight + m.switcherPadding)
        items[.allStatistics] = CGRect(x: switcherX + m.switcherPadding, y: allY,
                                       width: m.switcherWidth - m.switcherPadding * 2, height: m.switcherAllHeight)
        let switcherHeight = allY + m.switcherAllHeight + m.switcherPadding - top
        let switcher = CGRect(x: switcherX, y: top, width: m.switcherWidth, height: switcherHeight)

        // Details: anchored at the content origin, limited to the space left of the switcher and
        // to the available height.
        let maxDetailWidth = width - m.switcherWidth - m.gap
        var details: [StatKind: CGRect] = [:]
        for kind in kinds {
            let measured = detailSizes[kind] ?? CGSize(width: maxDetailWidth, height: m.rowHeight)
            let detailWidth = detailWidths[kind] ?? measured.width
            details[kind] = CGRect(x: 0, y: top, width: min(detailWidth, maxDetailWidth),
                                   height: min(measured.height, maxContentHeight))
        }

        let contentHeight = max(overviewViewport?.height ?? overviewHeight, switcherHeight,
                                details.values.map(\.height).max() ?? 0)
        let height = top + contentHeight

        // Group bar above the switcher column: move handle, Settings, Quit.
        let bar = CGRect(x: switcherX, y: 0, width: m.switcherWidth, height: m.barHeight)
        let barItem = (m.switcherWidth - 4 * 2) / 3
        var barItems: [FloatingTileTarget: CGRect] = [:]
        for (index, target) in [FloatingTileTarget.handle, .settings, .quit].enumerated() {
            barItems[target] = CGRect(x: switcherX + 2 + CGFloat(index) * (barItem + 2), y: 2,
                                      width: barItem, height: m.barHeight - 4)
        }

        let fits = width <= available.width + 0.5 && top + switcherHeight <= available.height + 0.5
        return FloatingTilePlan(kinds: kinds, metrics: m, columns: columns,
                                size: CGSize(width: width, height: height),
                                barFrame: bar, barItemFrames: barItems, tileFrames: tiles,
                                detailFrames: details, scrollingDetails: scrolling,
                                overviewViewport: overviewViewport, scrollerReserve: reserve,
                                emptyStateFrame: emptyState, switcherFrame: switcher, switcherItemFrames: items, fits: fits)
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

    /// Frames of the targets reachable in the given mode, for focus traversal.
    func targetFrames(detail: Bool) -> [FloatingTileTarget: CGRect] {
        var frames = barItemFrames
        if detail {
            frames.merge(switcherItemFrames) { a, _ in a }
        } else {
            for (kind, frame) in tileFrames { frames[.tile(kind)] = frame }
        }
        return frames
    }

    /// The visual neighbour of `target` in `direction`, from actual frames (not list indices).
    func neighbour(of target: FloatingTileTarget, _ direction: FloatingTileDirection, detail: Bool) -> FloatingTileTarget? {
        Self.neighbour(of: target, direction, in: targetFrames(detail: detail))
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

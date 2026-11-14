import CoreGraphics
import Foundation

// MARK: - Scrolling list

/// Compact labelled list used by the side More list and the whole-list fallback. The model
/// owns the scroll offset so drawing, hit testing and wheel input agree; the list scrolls
/// independently of any detail card. View space: top-left origin, y downward.
struct RingListLayout: Equatable, Sendable {
    static let rowHeight: CGFloat = 28
    static let headerHeight: CGFloat = 28
    static let padding: CGFloat = 4

    enum Hit: Equatable, Sendable {
        case drag
        case settings
        case node(RingNode)
    }

    let size: CGSize
    let rows: [RingNode]
    /// Whole-list fallback only: a fixed drag header and a fixed Settings row.
    let hasChrome: Bool
    private(set) var offset: CGFloat = 0

    init(size: CGSize, rows: [RingNode], hasChrome: Bool) {
        self.size = size
        self.rows = rows
        self.hasChrome = hasChrome
    }

    private var headerHeight: CGFloat { hasChrome ? Self.headerHeight : 0 }
    private var footerHeight: CGFloat { hasChrome ? Self.rowHeight : 0 }

    /// Scrolling area between the fixed header and footer.
    var viewport: CGRect {
        CGRect(x: 0, y: headerHeight, width: size.width, height: max(0, size.height - headerHeight - footerHeight))
    }

    var contentHeight: CGFloat { CGFloat(rows.count) * Self.rowHeight + 2 * Self.padding }
    var maxOffset: CGFloat { max(0, contentHeight - viewport.height) }

    mutating func scroll(by delta: CGFloat) {
        offset = min(max(offset + delta, 0), maxOffset)
    }

    func scrolled(by delta: CGFloat) -> RingListLayout {
        var copy = self
        copy.scroll(by: delta)
        return copy
    }

    func rowFrame(at index: Int) -> CGRect {
        CGRect(x: 0, y: viewport.minY + Self.padding + CGFloat(index) * Self.rowHeight - offset,
               width: size.width, height: Self.rowHeight)
    }

    var headerFrame: CGRect { CGRect(x: 0, y: 0, width: size.width, height: headerHeight) }
    var footerFrame: CGRect { CGRect(x: 0, y: size.height - footerHeight, width: size.width, height: footerHeight) }

    func hit(at point: CGPoint) -> Hit? {
        guard CGRect(origin: .zero, size: size).contains(point) else { return nil }
        if hasChrome {
            if point.y < headerHeight { return .drag }
            if point.y >= size.height - footerHeight { return .settings }
        }
        guard viewport.contains(point) else { return nil }
        for index in rows.indices where rowFrame(at: index).contains(point) { return .node(rows[index]) }
        return nil
    }
}

// MARK: - Plan

enum RingSide: CaseIterable, Sendable {
    case right, left, above, below
}

/// Frozen result of the pre-summon geometry choice: presentation mode, host-fitted frames
/// and the reserved child frames. Screen coordinates (bottom-left origin, y up, points).
struct RingPlan: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        /// The base ring with a fixed side column: More as a scrolling list above the single
        /// detail card. With nothing in More the column holds the card alone.
        case sideList
        /// The entire presentation is one compact list (favourites first, then Settings).
        case wholeList
    }

    var mode: Mode
    /// The panel that carries the ring (or, for `wholeList`, the list).
    var baseFrame: CGRect
    /// Side list frame; `nil` when nothing is in More.
    var moreSurface: CGRect?
    /// Screen frames of parent targets, used for travel regions and detail placement.
    var nodeFrames: [RingNode: CGRect]
    /// Reserved detail frame per stat, fixed for the summon.
    var detailFrames: [StatKind: CGRect]
    /// Details taller than their reserved slot: the card scrolls instead of clipping.
    var scrollingDetails: Set<StatKind>
    var side: RingSide
    /// True when no arrangement fit around a fixed base, so surfaces were clamped individually.
    var isClamped: Bool

    /// Every frame the plan can show; used by tests and the display-fit check.
    var allFrames: [CGRect] {
        [baseFrame] + (moreSurface.map { [$0] } ?? []) + Array(detailFrames.values)
    }

    static let empty = RingPlan(mode: .sideList, baseFrame: .zero, moreSurface: nil, nodeFrames: [:],
                                detailFrames: [:], scrollingDetails: [], side: .right, isClamped: false)
}

// MARK: - Placement

enum RingPlacement {
    static let gap: CGFloat = 6
    /// Width of the side area beside the base ring.
    static let sideAreaWidth: CGFloat = 380
    static let listMaxHeight: CGFloat = 224
    /// A tall detail may be scrolled in a capped slot, but never below this height.
    static let minScrollingDetailHeight: CGFloat = 240
    static let wholeListWidth: CGFloat = 300

    struct Input {
        /// Visible frame of the host display, in screen points (origin may be negative).
        var visible: CGRect
        /// Where the base ring wants to be (anchor or cursor), before edge fitting.
        var preferredBase: CGRect
        /// Frozen ring layout of the summon; the base panel is its ring-only footprint.
        var layout: RingLayout
        /// Enabled non-favourites in order: the rows of the side More list.
        var moreKinds: [StatKind]
        /// Enabled stats in order, for the whole-list fallback.
        var enabledKinds: [StatKind]
        /// Measured detail card per stat (injected: the real cards live in `Views/`).
        var detailSizes: [StatKind: CGSize]
        /// Backing scale of the host display; frame origins snap to its pixel grid.
        var scale: CGFloat = 1
        /// Summon may shift the base inward; after a drag the base stays where the user put it.
        var canShift = true
        var allowWholeList = true
        /// A dragged whole-list panel keeps its presentation: only the detail frames are re-chosen.
        var forceWholeList = false
    }

    static func resolve(_ input: Input) -> RingPlan {
        if input.forceWholeList { return wholeListPlan(input) }
        if let plan = sideListPlan(input, clamped: false) { return plan }
        if input.allowWholeList { return wholeListPlan(input) }
        return sideListPlan(input, clamped: true) ?? .empty
    }

    // MARK: Helpers

    private static func maxDetail(_ input: Input) -> CGSize {
        CGSize(width: input.detailSizes.values.map { ceil($0.width) }.max() ?? 0,
               height: input.detailSizes.values.map { ceil($0.height) }.max() ?? 0)
    }

    /// Screen frame of a view-space rect of a panel whose screen frame is `panel`.
    static func screenFrame(_ local: CGRect, in panel: CGRect) -> CGRect {
        CGRect(x: panel.minX + local.minX, y: panel.maxY - local.maxY, width: local.width, height: local.height)
    }

    private static func snap(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        let s = max(scale, 1)
        return (value * s).rounded() / s
    }

    /// Origin for a layout whose bounds relative to the base origin are `rel`: the preferred
    /// origin moved the least that keeps `rel` inside `visible`, snapped to the pixel grid
    /// without leaving the allowed range. `nil` when it cannot fit (or must not move).
    private static func fitOrigin(preferred: CGPoint, rel: CGRect, visible: CGRect,
                                  canShift: Bool, scale: CGFloat) -> CGPoint? {
        let loX = visible.minX - rel.minX, hiX = visible.maxX - rel.maxX
        let loY = visible.minY - rel.minY, hiY = visible.maxY - rel.maxY
        guard loX <= hiX + 0.001, loY <= hiY + 0.001 else { return nil }
        func place(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            var v = snap(min(max(value, lo), max(lo, hi)), scale: scale)
            if v < lo { v = ceil(lo * scale) / scale }
            if v > hi { v = floor(hi * scale) / scale }
            return v
        }
        let x = place(preferred.x, loX, hiX), y = place(preferred.y, loY, hiY)
        if !canShift && (abs(x - preferred.x) > 0.5 / max(scale, 1) || abs(y - preferred.y) > 0.5 / max(scale, 1)) {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    /// Detail card beside `footprint` on `side`, vertically (or horizontally) centred on
    /// `parent` and clamped to `visible` on the cross axis. Never covers the footprint.
    static func besideFrame(size: CGSize, parent: CGRect, footprint: CGRect, side: RingSide,
                            visible: CGRect, scale: CGFloat = 1) -> CGRect {
        var x: CGFloat, y: CGFloat
        switch side {
        case .right: x = footprint.maxX + gap; y = parent.midY - size.height / 2
        case .left: x = footprint.minX - gap - size.width; y = parent.midY - size.height / 2
        case .above: y = footprint.maxY + gap; x = parent.midX - size.width / 2
        case .below: y = footprint.minY - gap - size.height; x = parent.midX - size.width / 2
        }
        if side == .right || side == .left {
            if visible.height >= size.height { y = min(max(y, visible.minY), visible.maxY - size.height) } else { y = visible.minY }
        } else {
            if visible.width >= size.width { x = min(max(x, visible.minX), visible.maxX - size.width) } else { x = visible.minX }
        }
        return CGRect(x: snap(x, scale: scale), y: snap(y, scale: scale), width: size.width, height: size.height)
    }

    private static func relativeDetailRect(_ size: CGSize, beside s: CGRect, side: RingSide) -> CGRect {
        switch side {
        case .right: return CGRect(x: s.maxX + gap, y: s.midY - size.height / 2, width: size.width, height: size.height)
        case .left: return CGRect(x: s.minX - gap - size.width, y: s.midY - size.height / 2, width: size.width, height: size.height)
        case .above: return CGRect(x: s.midX - size.width / 2, y: s.maxY + gap, width: size.width, height: size.height)
        case .below: return CGRect(x: s.midX - size.width / 2, y: s.minY - gap - size.height, width: size.width, height: size.height)
        }
    }

    private static func baseNodeFrames(_ layout: RingLayout, baseFrame: CGRect) -> [RingNode: CGRect] {
        var frames: [RingNode: CGRect] = [:]
        for favourite in layout.favourites {
            frames[.wedge(favourite.kind)] = screenFrame(favourite.sector.boundingFrame, in: baseFrame)
        }
        if let more = layout.more { frames[.more] = screenFrame(more.sector.boundingFrame, in: baseFrame) }
        return frames
    }

    private static func cap(_ size: CGSize, visible: CGRect) -> (size: CGSize, scrolls: Bool) {
        let s = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard s.height > visible.height else { return (s, false) }
        return (CGSize(width: s.width, height: visible.height), true)
    }

    // MARK: Side list

    private static func sideListPlan(_ input: Input, clamped: Bool) -> RingPlan? {
        let size = input.layout.preset.footprintRingOnly
        let base = CGRect(origin: .zero, size: size)
        let dMax = maxDetail(input)
        let hasList = !input.moreKinds.isEmpty
        // Nothing to show beside the ring (no More list, no detail card): no column is reserved.
        let hasColumn = hasList || dMax != .zero
        let width = hasColumn ? sideAreaWidth : 0
        if !clamped, dMax.width > sideAreaWidth { return nil }

        let listHeight = hasList
            ? min(CGFloat(input.moreKinds.count) * RingListLayout.rowHeight + 2 * RingListLayout.padding, listMaxHeight) : 0
        let listBlock = hasList ? listHeight + gap : 0
        let available = input.visible.height - listBlock
        var slotHeight = min(dMax.height, available)
        if clamped {
            slotHeight = min(dMax.height, max(available, 120))
        } else if slotHeight < min(dMax.height, minScrollingDetailHeight) {
            return nil
        }
        let columnHeight = listBlock + slotHeight

        func column(_ side: RingSide) -> CGRect {
            let x = side == .right ? base.maxX + gap : base.minX - gap - width
            // Snapped so an odd column height cannot leave the column's frames on half pixels.
            return CGRect(x: x, y: snap(base.midY - columnHeight / 2, scale: input.scale),
                          width: width, height: columnHeight)
        }

        var chosenSide = RingSide.right
        let origin: CGPoint
        if clamped {
            // No fit around a fixed base: take the roomier side and clamp each surface alone.
            let room: (RingSide) -> CGFloat = { side in
                side == .right ? input.visible.maxX - input.preferredBase.maxX : input.preferredBase.minX - input.visible.minX
            }
            chosenSide = room(.right) >= room(.left) ? .right : .left
            origin = input.preferredBase.origin
        } else {
            var best: (side: RingSide, origin: CGPoint, distance: CGFloat)?
            for side in [RingSide.right, .left] {
                guard let o = fitOrigin(preferred: input.preferredBase.origin,
                                        rel: hasColumn ? base.union(column(side)) : base,
                                        visible: input.visible, canShift: input.canShift, scale: input.scale) else { continue }
                let d = hypot(o.x - input.preferredBase.minX, o.y - input.preferredBase.minY)
                if best == nil || d < best!.distance - 0.001 { best = (side, o, d) }
            }
            guard let found = best else { return nil }
            chosenSide = found.side
            origin = found.origin
        }

        let baseFrame = CGRect(origin: origin, size: size)
        var columnFrame = column(chosenSide).offsetBy(dx: origin.x, dy: origin.y)
        if clamped {
            columnFrame.origin.x = min(max(columnFrame.minX, input.visible.minX), max(input.visible.minX, input.visible.maxX - columnFrame.width))
            columnFrame.origin.y = min(max(columnFrame.minY, input.visible.minY), max(input.visible.minY, input.visible.maxY - columnFrame.height))
        }
        let listFrame = hasList
            ? CGRect(x: columnFrame.minX, y: columnFrame.maxY - listHeight, width: width, height: listHeight) : nil
        let slot = CGRect(x: columnFrame.minX, y: columnFrame.minY, width: width, height: slotHeight)

        var nodes = baseNodeFrames(input.layout, baseFrame: baseFrame)
        var details: [StatKind: CGRect] = [:]
        var scrolling = Set<StatKind>()
        let kinds = input.layout.favourites.map(\.kind) + input.moreKinds
        for kind in input.moreKinds { if let listFrame { nodes[.moreItem(kind)] = listFrame } }
        for kind in kinds {
            guard let size = input.detailSizes[kind] else { continue }
            let w = min(ceil(size.width), width), h = min(ceil(size.height), slotHeight)
            details[kind] = CGRect(x: slot.minX, y: slot.maxY - h, width: w, height: h)
            if ceil(size.height) > slotHeight || ceil(size.width) > width { scrolling.insert(kind) }
        }
        return RingPlan(mode: .sideList, baseFrame: baseFrame, moreSurface: listFrame, nodeFrames: nodes,
                        detailFrames: details, scrollingDetails: scrolling, side: chosenSide, isClamped: clamped)
    }

    // MARK: Whole list

    private static func wholeListPlan(_ input: Input) -> RingPlan {
        let visible = input.visible
        let rows = input.enabledKinds
        let natural = RingListLayout.headerHeight + RingListLayout.rowHeight
            + CGFloat(rows.count) * RingListLayout.rowHeight + 2 * RingListLayout.padding
        // A dragged panel is already where it is: the plan must describe the real frame.
        let fixed = !input.canShift
        let size = fixed ? input.preferredBase.size
            : CGSize(width: min(wholeListWidth, visible.width), height: min(natural, visible.height))
        let dMax = maxDetail(input)
        let rel = CGRect(origin: .zero, size: size)
        let preferred = fixed ? input.preferredBase.origin
            : CGPoint(x: input.preferredBase.midX - size.width / 2, y: input.preferredBase.midY - size.height / 2)

        var best: (side: RingSide, origin: CGPoint, distance: CGFloat)?
        for side in RingSide.allCases {
            let bounds = dMax == .zero ? rel : rel.union(relativeDetailRect(dMax, beside: rel, side: side))
            guard let origin = fitOrigin(preferred: preferred, rel: bounds, visible: visible, canShift: input.canShift,
                                         scale: input.scale) else { continue }
            let d = hypot(origin.x - preferred.x, origin.y - preferred.y)
            if best == nil || d < best!.distance - 0.001 { best = (side, origin, d) }
        }
        var clamped = false
        let side: RingSide, origin: CGPoint
        if let best {
            side = best.side; origin = fixed ? preferred : best.origin
        } else {
            clamped = true
            side = (visible.maxX - preferred.x - size.width) >= (preferred.x - visible.minX) ? .right : .left
            origin = fixed ? preferred
                : (fitOrigin(preferred: preferred, rel: rel, visible: visible, canShift: true, scale: input.scale) ?? preferred)
        }
        let listFrame = CGRect(origin: origin, size: size)

        var nodes: [RingNode: CGRect] = [:]
        var details: [StatKind: CGRect] = [:]
        var scrolling = Set<StatKind>()
        for kind in rows {
            nodes[.wedge(kind)] = listFrame
            guard let detailSize = input.detailSizes[kind] else { continue }
            let capped = cap(detailSize, visible: visible)
            details[kind] = besideFrame(size: capped.size, parent: listFrame, footprint: listFrame, side: side,
                                        visible: visible, scale: input.scale)
            if capped.scrolls { scrolling.insert(kind) }
        }
        return RingPlan(mode: .wholeList, baseFrame: listFrame, moreSurface: nil, nodeFrames: nodes,
                        detailFrames: details, scrollingDetails: scrolling, side: side, isClamped: clamped)
    }
}

extension RingPlacement.Input {
    /// Convenience for the snapshot's own favourites, More entries and enabled stats.
    init(snapshot: RingSnapshot, visible: CGRect, preferredBase: CGRect, detailSizes: [StatKind: CGSize],
         scale: CGFloat = 1, canShift: Bool = true, allowWholeList: Bool = true) {
        self.init(visible: visible, preferredBase: preferredBase, layout: snapshot.layout,
                  moreKinds: snapshot.moreKinds,
                  enabledKinds: snapshot.enabledKinds, detailSizes: detailSizes, scale: scale,
                  canShift: canShift, allowWholeList: allowWholeList)
    }
}

import CoreGraphics
import Foundation

// MARK: - Outer More ring

/// Second annulus holding every enabled non-favourite stat (D-034 baseline: radii 274-410,
/// text centred at radius 342, 820 x 820 footprint centred on the base ring). Same
/// conventions as `RingGeometry`: view space is top-left origin with y growing downward,
/// angles are radians clockwise from twelve o'clock, slots are frozen at construction.
struct RingMoreGeometry: Equatable, Sendable {
    static let innerRadius: CGFloat = 274
    static let outerRadius: CGFloat = 410
    static let textRadius: CGFloat = 342
    static let footprint = CGSize(width: 820, height: 820)
    static let maxEntries = 12

    struct Entry: Equatable, Sendable {
        let kind: StatKind
        let slot: Int
        let centerAngle: Double
        let halfSpan: Double
        let textRect: CGRect
    }

    let size = RingMoreGeometry.footprint
    let center = CGPoint(x: RingMoreGeometry.footprint.width / 2, y: RingMoreGeometry.footprint.height / 2)
    let entries: [Entry]

    init(items: [(kind: StatKind, textSize: CGSize)]) {
        let center = CGPoint(x: Self.footprint.width / 2, y: Self.footprint.height / 2)
        let used = Array(items.prefix(Self.maxEntries))
        let n = used.count
        let slotSpan = n >= 2 ? 2 * Double.pi / Double(n) : RingGeometry.singleWedgeSpan
        let halfSpan: Double = n >= 2
            ? slotSpan / 2 - Double(RingGeometry.separatorGap / Self.textRadius) / 2
            : RingGeometry.singleWedgeSpan / 2
        entries = used.enumerated().map { index, item in
            let angle = n >= 2 ? slotSpan * Double(index) : 0
            let anchor = RingGeometry.point(center: center, angle: angle, radius: Self.textRadius)
            let rect = CGRect(x: anchor.x - item.textSize.width / 2, y: anchor.y - item.textSize.height / 2,
                              width: item.textSize.width, height: item.textSize.height)
            return Entry(kind: item.kind, slot: index, centerAngle: angle, halfSpan: halfSpan, textRect: rect)
        }
    }

    func target(at point: CGPoint) -> StatKind? {
        entries.first { contains(point, in: $0) }?.kind
    }

    func contains(_ point: CGPoint, in entry: Entry) -> Bool {
        let dx = point.x - center.x, dy = point.y - center.y
        let radius = hypot(dx, dy)
        guard radius >= Self.innerRadius, radius <= Self.outerRadius else { return false }
        return abs(RingGeometry.wrapped(atan2(dx, -dy) - entry.centerAngle)) <= entry.halfSpan
    }

    /// Whether `point` lies within the annulus at all (an entry or a gap between entries).
    func isOnRing(_ point: CGPoint) -> Bool {
        let radius = hypot(point.x - center.x, point.y - center.y)
        return radius >= Self.innerRadius && radius <= Self.outerRadius
    }

    func textFits(_ entry: Entry, padding: CGFloat = RingGeometry.textPadding) -> Bool {
        let rect = entry.textRect.insetBy(dx: -padding, dy: -padding)
        var x = rect.minX
        while x <= rect.maxX + 0.001 {
            if !contains(CGPoint(x: x, y: rect.minY), in: entry) || !contains(CGPoint(x: x, y: rect.maxY), in: entry) { return false }
            x += 1
        }
        var y = rect.minY
        while y <= rect.maxY + 0.001 {
            if !contains(CGPoint(x: rect.minX, y: y), in: entry) || !contains(CGPoint(x: rect.maxX, y: y), in: entry) { return false }
            y += 1
        }
        return true
    }

    /// Every entry's measured block fits its sector; the outer ring is only chosen then.
    var allTextFits: Bool { entries.allSatisfy { textFits($0) } }

    func outline(of entry: Entry) -> [CGPoint] {
        let steps = max(2, Int((2 * entry.halfSpan / (Double.pi / 90)).rounded(.up)))
        let start = entry.centerAngle - entry.halfSpan, end = entry.centerAngle + entry.halfSpan
        func angle(_ i: Int) -> Double { start + (end - start) * Double(i) / Double(steps) }
        var points: [CGPoint] = []
        for i in 0...steps { points.append(RingGeometry.point(center: center, angle: angle(i), radius: Self.outerRadius)) }
        for i in stride(from: steps, through: 0, by: -1) {
            points.append(RingGeometry.point(center: center, angle: angle(i), radius: Self.innerRadius))
        }
        return points
    }

    /// Bounding frame of an entry in view space.
    func frame(of kind: StatKind) -> CGRect? {
        guard let entry = entries.first(where: { $0.kind == kind }) else { return nil }
        let points = outline(of: entry)
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

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
        /// Full More annulus around the base ring (or just the base ring when nothing is in More).
        case outerRing
        /// More as a scrolling list above the single detail card in a fixed side column.
        case sideList
        /// The entire presentation is one compact list (favourites first, then Settings).
        case wholeList
    }

    var mode: Mode
    /// The panel that carries the ring (or, for `wholeList`, the list).
    var baseFrame: CGRect
    /// Outer-ring footprint or side list frame; `nil` when nothing is in More.
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

    static let empty = RingPlan(mode: .outerRing, baseFrame: .zero, moreSurface: nil, nodeFrames: [:],
                                detailFrames: [:], scrollingDetails: [], side: .right, isClamped: false)
}

// MARK: - Placement

enum RingPlacement {
    static let gap: CGFloat = 6
    /// Fallback image: the 520-point base ring plus a 380-point side area.
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
        var geometry: RingGeometry
        /// More entries in order with their measured worst-case text blocks.
        var moreItems: [(kind: StatKind, textSize: CGSize)]
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
        let moreGeometry = input.moreItems.isEmpty ? nil : RingMoreGeometry(items: input.moreItems)
        if moreGeometry?.allTextFits ?? true, let plan = outerRingPlan(input, moreGeometry: moreGeometry) {
            return plan
        }
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

    private static func baseNodeFrames(_ geometry: RingGeometry, baseFrame: CGRect) -> [RingNode: CGRect] {
        var frames: [RingNode: CGRect] = [:]
        for wedge in geometry.wedges {
            if let local = geometry.frame(of: .wedge(wedge.kind)) {
                frames[.wedge(wedge.kind)] = screenFrame(local, in: baseFrame)
            }
        }
        if let more = geometry.moreFrame { frames[.more] = screenFrame(more, in: baseFrame) }
        return frames
    }

    // MARK: Outer ring

    /// Chosen only when base + outer ring + detail fit the visible frame (about 820 points
    /// each way plus the card). With nothing in More the "ring" is the base alone.
    private static func outerRingPlan(_ input: Input, moreGeometry: RingMoreGeometry?) -> RingPlan? {
        let g = input.geometry
        let base = CGRect(origin: .zero, size: g.size)
        let center = CGPoint(x: base.midX, y: base.midY)
        let surface = moreGeometry == nil ? base
            : CGRect(x: center.x - RingMoreGeometry.outerRadius, y: center.y - RingMoreGeometry.outerRadius,
                     width: RingMoreGeometry.footprint.width, height: RingMoreGeometry.footprint.height)
        let dMax = maxDetail(input)
        let hasDetails = dMax != .zero

        var best: (side: RingSide, origin: CGPoint, distance: CGFloat)?
        for side in RingSide.allCases {
            var bounds = base.union(surface)
            if hasDetails { bounds = bounds.union(relativeDetailRect(dMax, beside: surface, side: side)) }
            guard let origin = fitOrigin(preferred: input.preferredBase.origin, rel: bounds, visible: input.visible,
                                         canShift: input.canShift, scale: input.scale) else { continue }
            let distance = hypot(origin.x - input.preferredBase.minX, origin.y - input.preferredBase.minY)
            if best == nil || distance < best!.distance - 0.001 { best = (side, origin, distance) }
        }
        guard let chosen = best else { return nil }

        let baseFrame = CGRect(origin: chosen.origin, size: g.size)
        let surfaceFrame = surface.offsetBy(dx: chosen.origin.x, dy: chosen.origin.y)
        var nodes = baseNodeFrames(g, baseFrame: baseFrame)
        var details: [StatKind: CGRect] = [:]
        var scrolling = Set<StatKind>()

        for wedge in g.wedges {
            guard let size = input.detailSizes[wedge.kind], let parent = nodes[.wedge(wedge.kind)] else { continue }
            let capped = cap(size, visible: input.visible)
            details[wedge.kind] = besideFrame(size: capped.size, parent: parent, footprint: baseFrame,
                                              side: chosen.side, visible: input.visible, scale: input.scale)
            if capped.scrolls { scrolling.insert(wedge.kind) }
        }
        for item in input.moreItems {
            guard let moreGeometry, let local = moreGeometry.frame(of: item.kind) else { continue }
            let frame = screenFrame(local, in: surfaceFrame)
            nodes[.moreItem(item.kind)] = frame
            guard let size = input.detailSizes[item.kind] else { continue }
            let capped = cap(size, visible: input.visible)
            details[item.kind] = besideFrame(size: capped.size, parent: frame, footprint: surfaceFrame,
                                             side: chosen.side, visible: input.visible, scale: input.scale)
            if capped.scrolls { scrolling.insert(item.kind) }
        }
        return RingPlan(mode: .outerRing, baseFrame: baseFrame, moreSurface: moreGeometry == nil ? nil : surfaceFrame,
                        nodeFrames: nodes, detailFrames: details, scrollingDetails: scrolling,
                        side: chosen.side, isClamped: false)
    }

    private static func cap(_ size: CGSize, visible: CGRect) -> (size: CGSize, scrolls: Bool) {
        let s = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard s.height > visible.height else { return (s, false) }
        return (CGSize(width: s.width, height: visible.height), true)
    }

    // MARK: Side list

    private static func sideListPlan(_ input: Input, clamped: Bool) -> RingPlan? {
        let g = input.geometry
        let base = CGRect(origin: .zero, size: g.size)
        let dMax = maxDetail(input)
        let hasList = !input.moreItems.isEmpty
        let width = sideAreaWidth
        if !clamped, dMax.width > width { return nil }

        let listHeight = hasList
            ? min(CGFloat(input.moreItems.count) * RingListLayout.rowHeight + 2 * RingListLayout.padding, listMaxHeight) : 0
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
            return CGRect(x: x, y: base.midY - columnHeight / 2, width: width, height: columnHeight)
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
                guard let o = fitOrigin(preferred: input.preferredBase.origin, rel: base.union(column(side)),
                                        visible: input.visible, canShift: input.canShift, scale: input.scale) else { continue }
                let d = hypot(o.x - input.preferredBase.minX, o.y - input.preferredBase.minY)
                if best == nil || d < best!.distance - 0.001 { best = (side, o, d) }
            }
            guard let found = best else { return nil }
            chosenSide = found.side
            origin = found.origin
        }

        let baseFrame = CGRect(origin: origin, size: g.size)
        var columnFrame = column(chosenSide).offsetBy(dx: origin.x, dy: origin.y)
        if clamped {
            columnFrame.origin.x = min(max(columnFrame.minX, input.visible.minX), max(input.visible.minX, input.visible.maxX - columnFrame.width))
            columnFrame.origin.y = min(max(columnFrame.minY, input.visible.minY), max(input.visible.minY, input.visible.maxY - columnFrame.height))
        }
        let listFrame = hasList
            ? CGRect(x: columnFrame.minX, y: columnFrame.maxY - listHeight, width: width, height: listHeight) : nil
        let slot = CGRect(x: columnFrame.minX, y: columnFrame.minY, width: width, height: slotHeight)

        var nodes = baseNodeFrames(g, baseFrame: baseFrame)
        var details: [StatKind: CGRect] = [:]
        var scrolling = Set<StatKind>()
        let kinds = g.wedges.map(\.kind) + input.moreItems.map(\.kind)
        for item in input.moreItems { if let listFrame { nodes[.moreItem(item.kind)] = listFrame } }
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
        self.init(visible: visible, preferredBase: preferredBase, geometry: snapshot.geometry,
                  moreItems: snapshot.moreEntries.map { (kind: $0.kind, textSize: snapshot.moreTextSizes[$0.kind] ?? .zero) },
                  enabledKinds: snapshot.enabledKinds, detailSizes: detailSizes, scale: scale,
                  canShift: canShift, allowWholeList: allowWholeList)
    }
}

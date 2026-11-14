import XCTest

/// Hostless checks of the outer-band arc layout: spans, label-or-sliver, hit testing.
final class RingArcLayoutTests: XCTestCase {

    private let two = 2 * Double.pi

    private func labelSize(_ text: String) -> CGSize {
        let width = ceil((text as NSString).size(withAttributes: [.font: RingTypography.labelFont]).width)
        return CGSize(width: width, height: 15)
    }

    private func subRing(_ preset: RingSizePreset, parts: Int, groups: Int = 1,
                         parentMid: Double = 0.7, parentSpan: Double = 0.6,
                         label: String? = "99") -> RingArcLayout {
        let entries = (0..<parts).map { i in
            RingArcEntry(group: groups <= 1 ? 0 : i * groups / parts, labelSize: label.map(labelSize))
        }
        return RingArcLayout(preset: preset, kind: .subRing, parentMidAngle: parentMid,
                             parentSpan: parentSpan, entries: entries)
    }

    private func assertWellFormed(_ arc: RingArcLayout, parentMid: Double, parentSpan: Double,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(arc.status, .fits, file: file, line: line)
        XCTAssertGreaterThanOrEqual(arc.span, min(parentSpan, two) - 1e-9, "span >= parent", file: file, line: line)
        XCTAssertLessThanOrEqual(arc.span, two + 1e-9, "span <= full circle", file: file, line: line)
        XCTAssertEqual(arc.startAngle + arc.span / 2, parentMid, accuracy: 1e-9, "centred on parent", file: file, line: line)
        var previousEnd = -Double.infinity
        for segment in arc.segments {
            let sector = segment.sector
            XCTAssertEqual(sector.innerRadius, arc.innerRadius, file: file, line: line)
            XCTAssertEqual(sector.outerRadius, arc.outerRadius, file: file, line: line)
            // 8-point sliver floor, measured on the narrowest chord at the band's inner radius.
            XCTAssertGreaterThanOrEqual(sector.span * Double(arc.innerRadius), 8 - 1e-9,
                                        "segment \(segment.index) width", file: file, line: line)
            XCTAssertGreaterThan(sector.startAngle, previousEnd, "disjoint, ordered clockwise", file: file, line: line)
            previousEnd = sector.endAngle
            if let frame = segment.textFrame {
                XCTAssertTrue(sector.contains(rect: frame, padding: RingLayout.textPadding),
                              "label contained in its sector", file: file, line: line)
            }
        }
        if let first = arc.segments.first, let last = arc.segments.last {
            XCTAssertGreaterThanOrEqual(first.sector.startAngle, arc.startAngle - 1e-9, file: file, line: line)
            XCTAssertLessThanOrEqual(last.sector.endAngle, arc.startAngle + arc.span + 1e-9, file: file, line: line)
        }
    }

    func testBandRadiiFollowPresetAndKind() {
        for preset in RingSizePreset.allCases {
            let sub = subRing(preset, parts: 3)
            XCTAssertEqual(sub.innerRadius, preset.outerRadius + 6)
            XCTAssertEqual(sub.outerRadius - sub.innerRadius, 44)
            let more = RingArcLayout(preset: preset, kind: .more, parentMidAngle: .pi, parentSpan: RingLayout.moreSpan,
                                     entries: [RingArcEntry(labelSize: labelSize("CPU"))], allowsSlivers: false)
            XCTAssertEqual(more.outerRadius - more.innerRadius, 64)
            XCTAssertLessThanOrEqual(more.outerRadius, preset.footprintWithBand.width / 2 + 1e-9)
        }
    }

    func testSubRingPartCountsInEveryPreset() {
        for preset in RingSizePreset.allCases {
            for parts in [2, 10, 29, 32] {
                for groups in [1, 3] {
                    let arc = subRing(preset, parts: parts, groups: groups)
                    assertWellFormed(arc, parentMid: 0.7, parentSpan: 0.6)
                    XCTAssertEqual(arc.segments.count, parts, "\(preset) \(parts) \(groups)")
                }
            }
        }
    }

    func testSpanIsAtLeastParentSpan() {
        let arc = subRing(.medium, parts: 2, parentMid: 2.0, parentSpan: 1.2)
        assertWellFormed(arc, parentMid: 2.0, parentSpan: 1.2)
        XCTAssertEqual(arc.span, 1.2, accuracy: 1e-9, "few small parts widen to the parent's span")
        let many = subRing(.medium, parts: 32, parentMid: 2.0, parentSpan: 0.3)
        XCTAssertGreaterThan(many.span, 0.3)
    }

    func testWiderGapsBetweenGroups() {
        let entries = [RingArcEntry(group: 0), RingArcEntry(group: 0), RingArcEntry(group: 1), RingArcEntry(group: 1)]
        let arc = RingArcLayout(preset: .medium, kind: .subRing, parentMidAngle: 0, parentSpan: 0, entries: entries)
        XCTAssertEqual(arc.status, .fits)
        let gaps = (1..<4).map { arc.segments[$0].sector.startAngle - arc.segments[$0 - 1].sector.endAngle }
        XCTAssertEqual(gaps[1], gaps[0] * 3, accuracy: 1e-9, "group gap is three separators")
        XCTAssertEqual(gaps[0], gaps[2], accuracy: 1e-9)
    }

    func testSliverWhenLabelDoesNotFit() {
        // A 90-point label cannot fit a 44-point-deep segment beside the horizontal axis.
        let entries = (0..<4).map { _ in RingArcEntry(group: 0, labelSize: CGSize(width: 90, height: 15)) }
        let arc = RingArcLayout(preset: .medium, kind: .subRing, parentMidAngle: .pi / 2, parentSpan: 0.3, entries: entries)
        XCTAssertEqual(arc.status, .fits)
        XCTAssertTrue(arc.segments.allSatisfy { !$0.isLabelled }, "side placement leaves 44 points for the width")
        assertWellFormed(arc, parentMid: .pi / 2, parentSpan: 0.3)
        // Entries with no label size are never labelled.
        let plain = RingArcLayout(preset: .medium, kind: .subRing, parentMidAngle: 0, parentSpan: 0.3,
                                  entries: [RingArcEntry(), RingArcEntry()])
        XCTAssertEqual(plain.labelledCount, 0)
    }

    func testShortLabelsAtTwelveAreLabelled() {
        let arc = subRing(.large, parts: 4, parentMid: 0, parentSpan: 0.5, label: "CPU")
        XCTAssertEqual(arc.labelledCount, 4)
        assertWellFormed(arc, parentMid: 0, parentSpan: 0.5)
    }

    func testOversizedSubRingFallsBackToSliversBeforeCannotFit() {
        // 32 wide labels cannot all fit a full circle at Small, so they become slivers.
        let entries = (0..<32).map { _ in RingArcEntry(group: 0, labelSize: CGSize(width: 70, height: 15)) }
        let arc = RingArcLayout(preset: .small, kind: .subRing, parentMidAngle: 0, parentSpan: 0.5, entries: entries)
        XCTAssertEqual(arc.status, .fits)
        XCTAssertEqual(arc.segments.count, 32)
        XCTAssertLessThan(arc.labelledCount, 32, "labels give way to slivers, largest first")
        assertWellFormed(arc, parentMid: 0, parentSpan: 0.5)
    }

    func testCannotFitIsReportedNotShrunk() {
        // 400 slivers cannot fit a Small band even at 8 points each.
        let entries = (0..<400).map { _ in RingArcEntry() }
        let arc = RingArcLayout(preset: .small, kind: .subRing, parentMidAngle: 0, parentSpan: 0.5, entries: entries)
        XCTAssertEqual(arc.status, .cannotFit)
        XCTAssertTrue(arc.segments.isEmpty)
        XCTAssertGreaterThan(arc.requiredSpan, two)
        XCTAssertNil(arc.entry(at: CGPoint(x: 250, y: 100)))
    }

    func testMoreArcOneToElevenEntries() {
        let names = ["CPU", "Memory", "Disk", "Network", "Battery", "GPU", "Fans", "Power", "Temperature", "Load Avg", "Uptime"]
        var cannotFit: [String] = []
        for preset in RingSizePreset.allCases {
            for count in 1...11 {
                let entries = names.prefix(count).map { name in
                    // Label + value block: name over a widest value.
                    RingArcEntry(group: 0, labelSize: CGSize(width: max(labelSize(name).width, 60), height: 36))
                }
                let arc = RingArcLayout(preset: preset, kind: .more, parentMidAngle: .pi,
                                        parentSpan: RingLayout.moreSpan, entries: Array(entries), allowsSlivers: false)
                switch arc.status {
                case .fits:
                    assertWellFormed(arc, parentMid: .pi, parentSpan: RingLayout.moreSpan)
                    XCTAssertEqual(arc.labelledCount, count, "More arc entries all carry text")
                case .cannotFit:
                    cannotFit.append("\(preset)/\(count)")
                    XCTAssertTrue(arc.segments.isEmpty)
                }
            }
        }
        print("RING-ARC more-arc cannot-fit cases (list fallback): \(cannotFit.isEmpty ? "none" : cannotFit.joined(separator: " "))")
        // One entry always fits a More arc at six o'clock.
        for preset in RingSizePreset.allCases {
            XCTAssertFalse(cannotFit.contains("\(preset)/1"))
        }
    }

    func testMoreArcWithCompactBlocksFitsOneToElevenEntries() {
        // Icon-sized blocks fit the 64-point band at every angle, so the arc reaches eleven entries.
        for preset in RingSizePreset.allCases {
            for count in 1...11 {
                let entries = (0..<count).map { _ in RingArcEntry(group: 0, labelSize: CGSize(width: 24, height: 24)) }
                let arc = RingArcLayout(preset: preset, kind: .more, parentMidAngle: .pi,
                                        parentSpan: RingLayout.moreSpan, entries: entries, allowsSlivers: false)
                assertWellFormed(arc, parentMid: .pi, parentSpan: RingLayout.moreSpan)
                XCTAssertEqual(arc.segments.count, count)
                XCTAssertEqual(arc.labelledCount, count, "\(preset) \(count)")
            }
        }
    }

    func testMoreArcWithSliversAllowedFitsOneToElevenEntries() {
        let names = ["CPU", "Memory", "Disk", "Network", "Battery", "GPU", "Fans", "Power", "Temperature", "Load Avg", "Uptime"]
        for preset in RingSizePreset.allCases {
            for count in 1...11 {
                let entries = names.prefix(count).map { RingArcEntry(group: 0, labelSize: CGSize(width: labelSize($0).width, height: 36)) }
                let arc = RingArcLayout(preset: preset, kind: .more, parentMidAngle: .pi,
                                        parentSpan: RingLayout.moreSpan, entries: Array(entries))
                assertWellFormed(arc, parentMid: .pi, parentSpan: RingLayout.moreSpan)
                XCTAssertEqual(arc.segments.count, count)
            }
        }
    }

    func testEntryHitTestingAndGaps() {
        let arc = subRing(.medium, parts: 6, parentMid: 0, parentSpan: 0.6, label: nil)
        let centre = arc.center
        let radius = (arc.innerRadius + arc.outerRadius) / 2
        for segment in arc.segments {
            let p = RingSector.point(center: centre, angle: segment.sector.centerAngle, radius: radius)
            XCTAssertEqual(arc.entry(at: p), segment.index)
        }
        // The gap between segments 0 and 1 selects nothing.
        let gapAngle = (arc.segments[0].sector.endAngle + arc.segments[1].sector.startAngle) / 2
        XCTAssertNil(arc.entry(at: RingSector.point(center: centre, angle: gapAngle, radius: radius)))
        // Inside the band's inner gap (between ring and band) and beyond the band select nothing.
        XCTAssertNil(arc.entry(at: RingSector.point(center: centre, angle: arc.segments[0].sector.centerAngle,
                                                    radius: arc.innerRadius - 3)))
        XCTAssertNil(arc.entry(at: RingSector.point(center: centre, angle: arc.segments[0].sector.centerAngle,
                                                    radius: arc.outerRadius + 3)))
    }

    func testFullCircleArcWrapsWithSeparator() {
        // Large, 32 sizable labels: forced to slivers, still < full circle; use a parent of full span.
        let arc = RingArcLayout(preset: .small, kind: .subRing, parentMidAngle: 0, parentSpan: two,
                                entries: (0..<5).map { _ in RingArcEntry() })
        XCTAssertEqual(arc.status, .fits)
        XCTAssertEqual(arc.span, two, accuracy: 1e-9)
        let first = arc.segments.first!.sector, last = arc.segments.last!.sector
        let wrapGap = first.startAngle + two - last.endAngle
        XCTAssertEqual(wrapGap * Double(arc.innerRadius), Double(RingSizePreset.separator), accuracy: 1e-6)
    }

    func testNoEntries() {
        let arc = RingArcLayout(preset: .medium, kind: .subRing, parentMidAngle: 0, parentSpan: 0.5, entries: [])
        XCTAssertEqual(arc.status, .fits)
        XCTAssertTrue(arc.segments.isEmpty)
    }
}

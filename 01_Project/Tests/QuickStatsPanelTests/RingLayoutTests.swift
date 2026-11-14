import XCTest

/// Hostless checks of the frozen ring layout: tiling, hit targets, hub and the content
/// ladder. Text is measured with AppKit fonts, which works without an application.
final class RingLayoutTests: XCTestCase {

    // MARK: Worst-case content per stat (D-008 widest strings, paired modes)

    private struct Widest {
        let kind: StatKind
        let value: String
        let secondary: String?
    }

    /// Widest value and widest secondary line per stat, from the paired display modes
    /// (the fixture "long" set): the largest reading each stat can show.
    private static let pairedWorst: [Widest] = [
        Widest(kind: .cpu, value: "100%", secondary: "888\u{00B0}C"),
        Widest(kind: .memory, value: "U 888,88 GB", secondary: "F 888,88 GB"),
        Widest(kind: .disk, value: "R 888 MB/s", secondary: "W 888 MB/s"),
        Widest(kind: .network, value: "\u{2193} 888 MB/s", secondary: "\u{2191} 888 MB/s"),
        Widest(kind: .battery, value: "100%", secondary: "888:88 to full"),
        Widest(kind: .gpu, value: "100%", secondary: nil),
        Widest(kind: .fan, value: "8888 rpm", secondary: nil),
        Widest(kind: .power, value: "888.8 W", secondary: nil),
        Widest(kind: .temps, value: "Critical", secondary: nil),
        Widest(kind: .loadAverage, value: "88.88", secondary: nil),
        Widest(kind: .uptime, value: "88d 88h", secondary: nil),
    ]

    /// Default single-value display modes (Network ships showing both directions).
    private static let defaultModes: [Widest] = [
        Widest(kind: .cpu, value: "100%", secondary: nil),
        Widest(kind: .memory, value: "888,88 GB", secondary: nil),
        Widest(kind: .disk, value: "888,88 GB", secondary: nil),
        Widest(kind: .network, value: "\u{2193} 888 MB/s", secondary: "\u{2191} 888 MB/s"),
        Widest(kind: .battery, value: "100%", secondary: nil),
        Widest(kind: .gpu, value: "100%", secondary: nil),
        Widest(kind: .fan, value: "8888 rpm", secondary: nil),
        Widest(kind: .power, value: "888.8 W", secondary: nil),
        Widest(kind: .temps, value: "Critical", secondary: nil),
        Widest(kind: .loadAverage, value: "88.88", secondary: nil),
        Widest(kind: .uptime, value: "88d 88h", secondary: nil),
    ]

    private var widest: [Widest] = RingLayoutTests.pairedWorst

    private let iconSide: CGFloat = 18

    private func textHeight(_ font: NSFont) -> CGFloat {
        ceil(("Ag" as NSString).size(withAttributes: [.font: font]).height)
    }

    private func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func sizes(for item: Widest) -> RingRungSizes {
        let reading = RingReading(value: item.value, secondary: item.secondary,
                                  widestValue: item.value, widestSecondary: item.secondary)
        let plain = RingReading(value: item.value, widestValue: item.value)
        let valueWidth = textWidth(item.value, RingTypography.valueFont)
        let valueHeight = textHeight(RingTypography.valueFont)
        return RingRungSizes(
            labelValueSecondary: item.secondary == nil ? nil
                : RingTypography.blockSize(name: item.kind.displayName, reading: reading),
            labelValue: RingTypography.blockSize(name: item.kind.displayName, reading: plain),
            iconValue: CGSize(width: max(iconSide, valueWidth),
                              height: iconSide + RingTypography.lineSpacing + valueHeight),
            icon: CGSize(width: iconSide, height: iconSide))
    }

    private func input(_ index: Int) -> RingFavouriteInput {
        let item = widest[index % widest.count]
        return RingFavouriteInput(kind: item.kind, sizes: sizes(for: item))
    }

    private func inputs(count: Int, offset: Int = 0) -> [RingFavouriteInput] {
        (0..<count).map { input(offset + $0) }
    }

    private func layout(_ preset: RingSizePreset, favourites n: Int, more: Bool, offset: Int = 0,
                        cap: RingTextCap = .label) -> RingLayout {
        RingLayout(preset: preset, favourites: inputs(count: n, offset: offset), moreCount: more ? 3 : 0,
                   cap: cap, moreContentSize: CGSize(width: 18, height: 30), settingsWordWidth: 52)
    }

    private func degrees(_ radians: Double) -> Double {
        var d = radians * 180 / .pi
        d = d.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }

    // MARK: Tiling

    func testNoOverlapForZeroToEightFavouritesWithAndWithoutMore() {
        for preset in RingSizePreset.allCases {
            for n in 0...8 {
                for more in [false, true] {
                    let l = layout(preset, favourites: n, more: more)
                    XCTAssertEqual(l.favourites.count, n)
                    XCTAssertEqual(l.more != nil, more)
                    var sectors = l.favourites.map(\.sector)
                    if let m = l.more { sectors.append(m.sector) }
                    for i in sectors.indices {
                        for j in sectors.indices where j > i {
                            let apart = abs(RingSector.wrapped(sectors[i].centerAngle - sectors[j].centerAngle))
                            XCTAssertGreaterThan(apart, sectors[i].halfSpan + sectors[j].halfSpan,
                                                 "\(preset) n=\(n) more=\(more) \(i) vs \(j)")
                        }
                    }
                }
            }
        }
    }

    func testSeparatorsAreFourPointsAtMidRadius() {
        for preset in RingSizePreset.allCases {
            for more in [false, true] {
                let l = layout(preset, favourites: 6, more: more)
                var sectors = l.favourites.map(\.sector)
                if let m = l.more { sectors.append(m.sector) }
                sectors.sort { degrees($0.startAngle) < degrees($1.startAngle) }
                for i in sectors.indices {
                    let next = sectors[(i + 1) % sectors.count]
                    var gap = degrees(next.startAngle) - degrees(sectors[i].endAngle)
                    if gap < 0 { gap += 360 }
                    let points = gap * .pi / 180 * Double(sectors[i].midRadius)
                    XCTAssertEqual(points, 4, accuracy: 0.01, "\(preset) more=\(more) gap \(i)")
                }
            }
        }
    }

    /// Independent closed form of the tiling rule, in degrees clockwise from twelve.
    private func expectedCentres(preset: RingSizePreset, count n: Int, more: Bool) -> [Double] {
        let mid = Double((preset.innerRadius + preset.outerRadius) / 2)
        let gap = 4 / mid * 180 / .pi
        if n == 1 { return [0] }
        if !more { return (0..<n).map { 360 / Double(n) * Double($0) } }
        let moreSlot = 24 + gap
        let slot = (360 - moreSlot) / Double(n)
        let unwrapped = (0..<n).map { 180 + moreSlot / 2 + (Double($0) + 0.5) * slot }
        let first = unwrapped.firstIndex { $0 >= 360 - 1e-6 }!
        return (0..<n).map { unwrapped[(first + $0) % n].truncatingRemainder(dividingBy: 360) }
    }

    func testTilingMatchesRuleForEveryPresetAndCount() {
        for preset in RingSizePreset.allCases {
            for n in 1...8 {
                for more in [false, true] {
                    let l = layout(preset, favourites: n, more: more)
                    let expected = expectedCentres(preset: preset, count: n, more: more)
                    let actual = l.favourites.map { degrees($0.sector.centerAngle) }
                    for (a, e) in zip(actual, expected) {
                        var diff = abs(a - e).truncatingRemainder(dividingBy: 360)
                        if diff > 180 { diff = 360 - diff }
                        XCTAssertEqual(diff, 0, accuracy: 1e-6, "\(preset) n=\(n) more=\(more): \(actual) vs \(expected)")
                    }
                }
            }
        }
    }

    func testMoreWedgeIsTwentyFourDegreesAtSixOClock() throws {
        for preset in RingSizePreset.allCases {
            let l = layout(preset, favourites: 5, more: true)
            let more = try XCTUnwrap(l.more)
            XCTAssertEqual(degrees(more.sector.centerAngle), 180, accuracy: 1e-9)
            XCTAssertEqual(more.sector.span * 180 / .pi, 24, accuracy: 1e-9)
            XCTAssertEqual(more.count, 3)
            XCTAssertEqual(more.sector.innerRadius, preset.innerRadius)
            XCTAssertEqual(more.sector.outerRadius, preset.outerRadius)
        }
    }

    func testFavouriteOneIsFirstClockwiseFromTwelveWithMore() {
        for n in 2...8 {
            let l = layout(.medium, favourites: n, more: true)
            let first = degrees(l.favourites[0].sector.centerAngle)
            XCTAssertTrue(first >= 0 && first < 180, "n=\(n) favourite 1 at \(first)")
            // Order proceeds clockwise one slot at a time; the step across More adds More's slot.
            let mid = Double((RingSizePreset.medium.innerRadius + RingSizePreset.medium.outerRadius) / 2)
            let gap = 4 / mid * 180 / .pi
            let moreSlot = 24 + gap
            let slot = (360 - moreSlot) / Double(n)
            for k in 1..<n {
                var step = degrees(l.favourites[k].sector.centerAngle) - degrees(l.favourites[k - 1].sector.centerAngle)
                if step < 0 { step += 360 }
                let acrossMore = abs(step - (slot + moreSlot)) < 1e-6
                XCTAssertTrue(abs(step - slot) < 1e-6 || acrossMore, "n=\(n) k=\(k) step=\(step)")
            }
        }
    }

    func testSingleFavouriteIsSixtyDegreesAtTwelve() throws {
        for more in [false, true] {
            let l = layout(.medium, favourites: 1, more: more)
            let wedge = try XCTUnwrap(l.favourites.first)
            XCTAssertEqual(degrees(wedge.sector.centerAngle), 0, accuracy: 1e-9)
            XCTAssertEqual(wedge.sector.span * 180 / .pi, 60, accuracy: 1e-9)
        }
    }

    func testNoFavouritesLeavesMoreAlone() {
        let l = layout(.medium, favourites: 0, more: true)
        XCTAssertTrue(l.favourites.isEmpty)
        XCTAssertNotNil(l.more)
        let empty = layout(.medium, favourites: 0, more: false)
        XCTAssertTrue(empty.favourites.isEmpty)
        XCTAssertNil(empty.more)
        XCTAssertNil(empty.target(at: CGPoint(x: 250, y: 100)))
    }

    func testOnlyFirstEightFavouritesAreUsed() {
        XCTAssertEqual(layout(.medium, favourites: 11, more: false).favourites.count, 8)
    }

    func testLayoutIsFrozenAndDeterministic() {
        XCTAssertEqual(layout(.medium, favourites: 6, more: true), layout(.medium, favourites: 6, more: true))
    }

    // MARK: Hit targets

    func testTargetsForFavouritesMoreAndGear() throws {
        for preset in RingSizePreset.allCases {
            let l = layout(preset, favourites: 6, more: true)
            for fav in l.favourites {
                let p = RingSector.point(center: l.center, angle: fav.sector.centerAngle, radius: fav.sector.midRadius)
                XCTAssertEqual(l.target(at: p), .favourite(fav.order))
            }
            let more = try XCTUnwrap(l.more)
            XCTAssertEqual(l.target(at: RingSector.point(center: l.center, angle: .pi, radius: more.sector.midRadius)), .more)
            XCTAssertEqual(l.target(at: CGPoint(x: l.hub.gearFrame.midX, y: l.hub.gearFrame.midY)), .gear)
        }
    }

    func testHubSeparatorsAndInactiveAnnulusSelectNothing() {
        for preset in RingSizePreset.allCases {
            for (n, more) in [(6, true), (6, false), (1, false), (1, true), (0, true)] {
                let l = layout(preset, favourites: n, more: more)
                // Hub disc outside the gear.
                let hubPoint = CGPoint(x: l.center.x, y: l.center.y + preset.hubDiscRadius - 2)
                XCTAssertTrue(l.hub.contains(hubPoint))
                XCTAssertFalse(l.hub.gearFrame.contains(hubPoint))
                XCTAssertNil(l.target(at: hubPoint), "\(preset) hub")
                // Between the hub disc and the inner radius, and beyond the outer radius.
                let strip = preset.hubDiscRadius + 3
                for angle in stride(from: 0.0, to: 360.0, by: 20) {
                    XCTAssertNil(l.target(at: RingSector.point(center: l.center, angle: angle * .pi / 180, radius: strip)))
                    XCTAssertNil(l.target(at: RingSector.point(center: l.center, angle: angle * .pi / 180,
                                                               radius: preset.outerRadius + 3)))
                }
                // The midpoint of every separator.
                var sectors = l.favourites.map(\.sector)
                if let m = l.more { sectors.append(m.sector) }
                if sectors.count >= 2 {
                    for sector in sectors {
                        let edge = RingSector.point(center: l.center,
                                                    angle: sector.endAngle + 2 / Double(sector.midRadius),
                                                    radius: sector.midRadius)
                        // Only a gap when the neighbour is adjacent; a lone wedge has an open annulus there.
                        if n >= 2 { XCTAssertNil(l.target(at: edge), "\(preset) n=\(n) more=\(more) separator") }
                    }
                }
            }
        }
        // Inactive annulus of a lone favourite.
        let lone = layout(.medium, favourites: 1, more: false)
        XCTAssertNil(lone.target(at: RingSector.point(center: lone.center, angle: .pi, radius: 120)))
        XCTAssertNil(lone.target(at: RingSector.point(center: lone.center, angle: 40 * .pi / 180, radius: 120)))
        XCTAssertEqual(lone.target(at: RingSector.point(center: lone.center, angle: 20 * .pi / 180, radius: 120)), .favourite(0))
    }

    // MARK: Hub (AC-30)

    func testHubGeometry() {
        for preset in RingSizePreset.allCases {
            let l = layout(preset, favourites: 6, more: true)
            XCTAssertEqual(l.hub.discRadius, preset.innerRadius - 6)
            XCTAssertEqual(l.hub.showsSettingsWord, l.hub.discRadius >= 58)
            XCTAssertGreaterThanOrEqual(l.hub.gearFrame.width, 28)
            XCTAssertGreaterThanOrEqual(l.hub.gearFrame.height, 28)
            let f = l.hub.gearFrame
            for corner in [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.maxY),
                           CGPoint(x: f.minX, y: f.maxY), CGPoint(x: f.maxX, y: f.minY)] {
                XCTAssertTrue(l.hub.contains(corner), "\(preset) gear target inside the disc")
            }
        }
        XCTAssertFalse(layout(.small, favourites: 6, more: true).hub.showsSettingsWord)
        XCTAssertTrue(layout(.medium, favourites: 6, more: true).hub.showsSettingsWord)
        XCTAssertTrue(layout(.large, favourites: 6, more: true).hub.showsSettingsWord)
        // Without the word the gear target is exactly the 28-point minimum.
        XCTAssertEqual(layout(.small, favourites: 6, more: true).hub.gearFrame.size, CGSize(width: 28, height: 28))
    }

    func testDefaultCentreIsFootprintMiddleAndCentreOverrideMoves() {
        let l = layout(.large, favourites: 4, more: false)
        XCTAssertEqual(l.center, CGPoint(x: 300, y: 300))
        let moved = RingLayout(preset: .large, center: CGPoint(x: 10, y: 20), favourites: inputs(count: 4), moreCount: 0)
        XCTAssertEqual(moved.hub.center, CGPoint(x: 10, y: 20))
        XCTAssertEqual(moved.favourites[0].sector.center, CGPoint(x: 10, y: 20))
    }

    // MARK: Content ladder

    func testChosenRungFramesAreContainedWithPadding() {
        for preset in RingSizePreset.allCases {
            for n in 1...8 {
                for more in [false, true] {
                    for offset in 0..<widest.count {
                        let l = layout(preset, favourites: n, more: more, offset: offset)
                        for fav in l.favourites where fav.fits {
                            XCTAssertTrue(fav.sector.contains(rect: fav.textFrame, padding: 6),
                                          "\(preset) n=\(n) more=\(more) \(fav.kind) \(fav.rung)")
                            let item = widest.first { $0.kind == fav.kind }!
                            XCTAssertEqual(fav.textFrame.size, sizes(for: item).size(for: fav.rung),
                                           "frame is the measured size, never shrunk")
                        }
                    }
                }
            }
        }
    }

    func testRichestRungIsChosen() {
        // A rung richer than the chosen one must not fit anywhere in the sector.
        for preset in RingSizePreset.allCases {
            for n in [1, 4, 8] {
                let l = layout(preset, favourites: n, more: true)
                for fav in l.favourites {
                    let item = widest.first { $0.kind == fav.kind }!
                    let rungSizes = sizes(for: item)
                    for richer in RingContentRung.allCases where richer > fav.rung {
                        guard let size = rungSizes.size(for: richer) else { continue }
                        XCTAssertNil(fav.sector.textFrame(fitting: size, padding: 6), "\(preset) n=\(n) \(fav.kind) \(richer)")
                    }
                }
            }
        }
    }

    func testCapLimitsTheRung() {
        let rich = layout(.large, favourites: 1, more: false)
        XCTAssertEqual(rich.favourites[0].rung, .labelValueSecondary, "a 60-degree Large wedge holds the full ladder")
        XCTAssertEqual(layout(.large, favourites: 1, more: false, cap: .iconValue).favourites[0].rung, .iconValue)
        XCTAssertEqual(layout(.large, favourites: 1, more: false, cap: .icon).favourites[0].rung, .icon)
        // A stat with no secondary line tops out at label + value under .label.
        XCTAssertEqual(layout(.large, favourites: 1, more: false, offset: 5).favourites[0].rung, .labelValue)
    }

    func testUnfittableWedgeIsReportedNotShrunk() {
        let huge = RingRungSizes(labelValueSecondary: nil, labelValue: CGSize(width: 400, height: 90),
                                 iconValue: CGSize(width: 300, height: 90), icon: CGSize(width: 300, height: 90))
        let l = RingLayout(preset: .small, favourites: [RingFavouriteInput(kind: .cpu, sizes: huge)], moreCount: 0)
        XCTAssertFalse(l.favourites[0].fits)
        XCTAssertEqual(l.favourites[0].rung, .icon)
        XCTAssertEqual(l.favourites[0].textFrame.size, huge.icon, "size is never reduced")
        XCTAssertEqual(l.unfitFavourites.count, 1)
    }

    // MARK: Rung matrix (AC-29)

    private func letter(_ fav: RingLayout.Favourite) -> Character {
        if !fav.fits { return "X" }
        switch fav.rung {
        case .labelValueSecondary: return "S"
        case .labelValue: return "L"
        case .iconValue: return "I"
        case .icon: return "O"
        }
    }

    func testRungMatrix() {
        var stops: [String] = []
        for (name, dataset) in [("paired-worst", Self.pairedWorst), ("default-modes", Self.defaultModes)] {
            widest = dataset
            stops += runMatrix(named: name)
        }
        widest = Self.pairedWorst
        // Reported, not worked around: Medium + eight favourites + More below icon + value.
        print("RING-MATRIX STOP-CONDITION (Medium/8/More below icon+value): \(stops.isEmpty ? "none" : stops.joined(separator: "; "))")
    }

    /// Prints the matrix for the current dataset and returns the Medium/8/More cells that
    /// fall below icon + value. Icon-only must fit everywhere.
    private func runMatrix(named name: String) -> [String] {
        let counts = [1, 2, 3, 4, 5, 6, 7, 8]
        let rank: [Character: Int] = ["X": -1, "O": 0, "I": 1, "L": 2, "S": 3]
        func pad(_ text: String, _ width: Int) -> String { text.padding(toLength: width, withPad: " ", startingAt: 0) }
        var lines: [String] = []
        lines.append("RING-MATRIX [\(name)] legend: S=label+value+secondary L=label+value I=icon+value O=icon only X=does not fit")
        lines.append("RING-MATRIX [\(name)] worst rung of each stat over every slot it can occupy; 13/16/12 pt, 6 pt padding")
        lines.append("RING-MATRIX [\(name)] preset n more | " + widest.map { pad(String($0.kind.displayName.prefix(5)), 5) }.joined(separator: " "))
        var mediumEightMore: [String] = []
        var unfit: [String] = []
        for preset in RingSizePreset.allCases {
            for n in counts {
                for more in [false, true] {
                    var worst: [StatKind: Character] = [:]
                    for offset in 0..<widest.count {
                        let l = layout(preset, favourites: n, more: more, offset: offset)
                        for fav in l.favourites {
                            let c = letter(fav)
                            if let existing = worst[fav.kind], rank[existing]! <= rank[c]! { continue }
                            worst[fav.kind] = c
                        }
                    }
                    let cells = widest.map { pad(worst[$0.kind].map { String($0) } ?? "-", 5) }.joined(separator: " ")
                    lines.append("RING-MATRIX [\(name)] \(pad(preset.rawValue, 6)) \(n) \(more ? "yes" : "no ") | \(cells)")
                    for (kind, c) in worst {
                        if c == "X" { unfit.append("\(preset) n=\(n) more=\(more) \(kind)") }
                        if preset == .medium && n == 8 && more && rank[c]! < 1 { mediumEightMore.append("\(name):\(kind)=\(c)") }
                    }
                }
            }
        }
        let report = lines.joined(separator: "\n")
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "ring-rung-matrix-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(unfit.isEmpty, "icon-only did not fit: \(unfit)")
        return mediumEightMore
    }
}

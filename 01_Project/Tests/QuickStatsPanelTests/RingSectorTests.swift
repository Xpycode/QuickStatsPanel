import XCTest

/// Hostless checks of the annular-sector primitive, the size presets and the fill scales.
final class RingSectorTests: XCTestCase {

    private let origin = CGPoint(x: 300, y: 300)

    private func sector(inner: CGFloat = 65, outer: CGFloat = 180, centre degrees: Double = 0,
                        half halfDegrees: Double = 20) -> RingSector {
        RingSector(center: origin, innerRadius: inner, outerRadius: outer,
                   centerAngle: degrees * .pi / 180, halfSpan: halfDegrees * .pi / 180)
    }

    // MARK: Presets (spec table)

    func testPresetTable() {
        let table: [(RingSizePreset, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (.small, 260, 47, 83, 400), (.medium, 360, 65, 115, 500), (.large, 460, 83, 147, 600),
        ]
        for (preset, diameter, inner, depth, footprint) in table {
            XCTAssertEqual(preset.outerDiameter, diameter)
            XCTAssertEqual(preset.innerRadius, inner)
            XCTAssertEqual(preset.wedgeDepth, depth)
            XCTAssertEqual(preset.footprintRingOnly, CGSize(width: diameter, height: diameter))
            XCTAssertEqual(preset.footprintWithBand, CGSize(width: footprint, height: footprint))
            XCTAssertEqual(preset.bandInnerRadius, preset.outerRadius + 6)
            XCTAssertEqual(preset.hubDiscRadius, inner - 6)
        }
        XCTAssertEqual(RingSizePreset.separator, 4)
        XCTAssertEqual(RingSizePreset.subRingDepth, 44)
        XCTAssertEqual(RingSizePreset.moreArcDepth, 64)
        let textSizes: [CGFloat] = [RingSizePreset.labelTextSize, RingSizePreset.valueTextSize, RingSizePreset.secondaryTextSize]
        XCTAssertEqual(textSizes, [13, 16, 12])
        XCTAssertEqual(RingSizePreset.allCases.map(\.showsSettingsWord), [false, true, true])
    }

    // MARK: Fill scales (AC-24)

    func testAreaFillRatioHoldsForManyFractions() {
        let s = sector(inner: 47, outer: 130, half: 25)
        for step in 0...100 {
            let f = Double(step) / 100
            let filled = s.filled(to: f, scale: .area)
            XCTAssertEqual(filled.area / s.area, f, accuracy: 0.005, "area fraction at \(f)")
        }
    }

    func testLinearFillRatioHoldsForManyFractions() {
        let s = sector(inner: 83, outer: 230, half: 25)
        for step in 0...100 {
            let f = Double(step) / 100
            let filled = s.filled(to: f, scale: .linear)
            XCTAssertEqual(Double(filled.depth / s.depth), f, accuracy: 0.005, "depth fraction at \(f)")
        }
    }

    func testFillEdgesAndClamping() {
        for scale in RingFillScale.allCases {
            XCTAssertEqual(scale.radius(fraction: 0, inner: 65, outer: 180), 65, accuracy: 1e-9)
            XCTAssertEqual(scale.radius(fraction: 1, inner: 65, outer: 180), 180, accuracy: 1e-9)
            XCTAssertEqual(scale.radius(fraction: -3, inner: 65, outer: 180), 65, accuracy: 1e-9)
            XCTAssertEqual(scale.radius(fraction: 7, inner: 65, outer: 180), 180, accuracy: 1e-9)
            XCTAssertEqual(scale.radius(fraction: .nan, inner: 65, outer: 180), 65, accuracy: 1e-9)
            XCTAssertEqual(scale.radius(fraction: .infinity, inner: 65, outer: 180), 180, accuracy: 1e-9)
            XCTAssertEqual(scale.radius(fraction: -.infinity, inner: 65, outer: 180), 65, accuracy: 1e-9)
        }
        let s = sector()
        XCTAssertEqual(s.filled(to: 0, scale: .area).area, 0, accuracy: 1e-9)
        XCTAssertEqual(s.filled(to: 1, scale: .area).area, s.area, accuracy: 1e-6)
        XCTAssertEqual(s.filled(to: 9, scale: .area).area, s.area, accuracy: 1e-6)
    }

    func testAreaFillFormula() {
        let r = RingFillScale.area.radius(fraction: 0.5, inner: 47, outer: 130)
        let r0 = 47.0, r1 = 130.0
        let expected: Double = (r0 * r0 + 0.5 * (r1 * r1 - r0 * r0)).squareRoot()
        XCTAssertEqual(Double(r), expected, accuracy: 1e-9)
    }

    func testCumulativeRadiiAccumulateAndClamp() {
        for scale in RingFillScale.allCases {
            let radii = scale.cumulativeRadii(fractions: [0.2, 0.3, 0.1], inner: 65, outer: 180)
            XCTAssertEqual(radii.count, 3)
            XCTAssertEqual(radii[0], scale.radius(fraction: 0.2, inner: 65, outer: 180), accuracy: 1e-9)
            XCTAssertEqual(radii[1], scale.radius(fraction: 0.5, inner: 65, outer: 180), accuracy: 1e-9)
            XCTAssertEqual(radii[2], scale.radius(fraction: 0.6, inner: 65, outer: 180), accuracy: 1e-9)
            let over = scale.cumulativeRadii(fractions: [0.8, 0.8, .nan, -1], inner: 65, outer: 180)
            XCTAssertEqual(over, [scale.radius(fraction: 0.8, inner: 65, outer: 180), 180, 180, 180])
        }
    }

    func testReferenceRadiiAndEightPointRule() {
        for preset in RingSizePreset.allCases {
            for scale in RingFillScale.allCases {
                let radii = scale.referenceRadii(inner: preset.innerRadius, outer: preset.outerRadius)
                XCTAssertEqual(radii.count, 3, "\(preset) \(scale)")
                XCTAssertEqual(radii, radii.sorted())
            }
        }
        // 44-point sub-ring depth, linear: 11-point spacing keeps all three.
        XCTAssertEqual(RingFillScale.linear.referenceRadii(inner: 236, outer: 280).count, 3)
        // 24 points deep, linear: 6-point spacing is under 8, so only the 50 % arc stays.
        XCTAssertEqual(RingFillScale.linear.referenceRadii(inner: 100, outer: 124), [112])
        // Equal-area spacing is tighter near the outside; the rule applies to either gap.
        let tight = RingFillScale.area.referenceRadii(inner: 100, outer: 130)
        XCTAssertEqual(tight.count, 1)
        XCTAssertEqual(tight[0], RingFillScale.area.radius(fraction: 0.5, inner: 100, outer: 130), accuracy: 1e-9)
    }

    // MARK: Containment, frames, constructors

    func testContainsUsesAngleConventionTwelveClockwise() {
        let s = sector(centre: 90, half: 10)
        // Three o'clock is at +x with y unchanged in view space.
        XCTAssertTrue(s.contains(CGPoint(x: origin.x + 120, y: origin.y)))
        XCTAssertFalse(s.contains(CGPoint(x: origin.x, y: origin.y - 120)))
        XCTAssertFalse(s.contains(CGPoint(x: origin.x, y: origin.y + 120)))
        let twelve = sector(centre: 0, half: 10)
        XCTAssertTrue(twelve.contains(CGPoint(x: origin.x, y: origin.y - 120)))
        XCTAssertTrue(twelve.contains(CGPoint(x: origin.x + 120 * sin(0.1), y: origin.y - 120 * cos(0.1))))
        XCTAssertFalse(twelve.contains(CGPoint(x: origin.x + 120 * sin(0.4), y: origin.y - 120 * cos(0.4))))
    }

    func testRadialBoundsAndWraparound() {
        let s = sector(centre: 180, half: 30)
        XCTAssertFalse(s.contains(CGPoint(x: origin.x, y: origin.y + 60)), "inside inner radius")
        XCTAssertFalse(s.contains(CGPoint(x: origin.x, y: origin.y + 190)), "outside outer radius")
        XCTAssertTrue(s.contains(CGPoint(x: origin.x, y: origin.y + 120)))
        // A sector straddling twelve o'clock via a negative centre angle.
        let across = sector(centre: -10, half: 30)
        XCTAssertTrue(across.contains(CGPoint(x: origin.x, y: origin.y - 120)))
        XCTAssertTrue(across.contains(RingSector.point(center: origin, angle: -35 * .pi / 180, radius: 120)))
        XCTAssertFalse(across.contains(RingSector.point(center: origin, angle: 25 * .pi / 180, radius: 120)))
        let wrapped = sector(centre: 350, half: 20)
        XCTAssertTrue(wrapped.contains(RingSector.point(center: origin, angle: 5 * .pi / 180, radius: 120)))
    }

    func testFullAnnulusContainsAllAngles() {
        let ring = RingSector(center: origin, innerRadius: 100, outerRadius: 150, centerAngle: .pi, halfSpan: .pi)
        for degrees in stride(from: 0.0, to: 360.0, by: 15) {
            XCTAssertTrue(ring.contains(RingSector.point(center: origin, angle: degrees * .pi / 180, radius: 120)))
        }
        XCTAssertFalse(ring.contains(origin))
        XCTAssertEqual(ring.boundingFrame, CGRect(x: 150, y: 150, width: 300, height: 300))
    }

    func testBoundingFrameIsExactAndContainsOutline() {
        for centre in stride(from: -180.0, through: 180.0, by: 30) {
            for half in [5.0, 20, 60, 120, 179] {
                let s = sector(centre: centre, half: half)
                let frame = s.boundingFrame
                let outline = s.outline
                // Vertices undershoot the true arc by at most the sagitta of one outline step.
                let tolerance = Double(s.outerRadius) * (1 - cos(RingSector.outlineStep / 2)) + 1e-6
                XCTAssertEqual(Double(outline.map(\.x).min()!), Double(frame.minX), accuracy: tolerance, "\(centre) \(half)")
                XCTAssertEqual(Double(outline.map(\.x).max()!), Double(frame.maxX), accuracy: tolerance)
                XCTAssertEqual(Double(outline.map(\.y).min()!), Double(frame.minY), accuracy: tolerance)
                XCTAssertEqual(Double(outline.map(\.y).max()!), Double(frame.maxY), accuracy: tolerance)
            }
        }
        // Polyline vertices can undershoot the true arc by the sagitta at 2 degrees; the
        // exact frame therefore covers every sampled arc point.
        let s = sector(centre: 0, half: 20)
        let top = s.boundingFrame.minY
        XCTAssertEqual(top, origin.y - s.outerRadius, accuracy: 1e-9)
    }

    func testOutlineStepAndPath() {
        let s = sector(centre: 0, half: 20)
        let outline = s.outline
        XCTAssertEqual(outline.count, 2 * (Int((s.span / RingSector.outlineStep).rounded(.up)) + 1))
        for p in outline {
            let r = hypot(p.x - origin.x, p.y - origin.y)
            XCTAssertTrue(abs(r - s.outerRadius) < 1e-6 || abs(r - s.innerRadius) < 1e-6)
        }
        XCTAssertTrue(s.cgPath.contains(RingSector.point(center: origin, angle: 0, radius: 120)))
        XCTAssertFalse(s.cgPath.contains(RingSector.point(center: origin, angle: 1, radius: 120)))
        XCTAssertEqual(s.cgPath.boundingBox.minY, s.boundingFrame.minY, accuracy: 0.5)
    }

    func testRectContainment() {
        let s = sector(inner: 65, outer: 180, centre: 0, half: 20)
        let inside = CGRect(x: origin.x - 20, y: origin.y - 140, width: 40, height: 20)
        XCTAssertTrue(s.contains(rect: inside))
        XCTAssertTrue(s.contains(rect: inside, padding: 6))
        XCTAssertFalse(s.contains(rect: inside, padding: 40), "padding grows the rect")
        // Too wide at the narrow inner end.
        let nearInner = CGRect(x: origin.x - 30, y: origin.y - 90, width: 60, height: 20)
        XCTAssertFalse(s.contains(rect: nearInner))
        // Pokes through the outer arc.
        XCTAssertFalse(s.contains(rect: CGRect(x: origin.x - 5, y: origin.y - 190, width: 10, height: 20)))
        // Crosses the inner arc without a corner inside the inner disc.
        let wide = sector(inner: 65, outer: 180, centre: 0, half: 80)
        XCTAssertFalse(wide.contains(rect: CGRect(x: origin.x - 40, y: origin.y - 70, width: 80, height: 10)))
        XCTAssertTrue(wide.contains(rect: CGRect(x: origin.x - 40, y: origin.y - 120, width: 80, height: 10)))
    }

    func testRectContainmentAgreesWithPointSamplingForWideSectors() {
        let s = sector(inner: 65, outer: 180, centre: 180, half: 110)
        let ok = CGRect(x: origin.x - 60, y: origin.y + 100, width: 120, height: 30)
        XCTAssertTrue(s.contains(rect: ok))
        let across = CGRect(x: origin.x - 60, y: origin.y - 100, width: 120, height: 30)
        XCTAssertFalse(s.contains(rect: across))
    }

    func testTextFrameFindsFittingPositionOrNil() {
        let s = sector(inner: 65, outer: 180, centre: 0, half: 20)
        let frame = s.textFrame(fitting: CGSize(width: 50, height: 30), padding: 6)
        XCTAssertNotNil(frame)
        XCTAssertTrue(s.contains(rect: frame!, padding: 6))
        XCTAssertNil(s.textFrame(fitting: CGSize(width: 200, height: 30), padding: 6))
    }

    func testSubSectorHalfRimAndFilledShareAngles() {
        let s = sector(inner: 65, outer: 180, centre: 40, half: 20)
        let sub = s.subSector(innerRadius: 100, outerRadius: 140)
        XCTAssertEqual(sub.centerAngle, s.centerAngle)
        XCTAssertEqual(sub.halfSpan, s.halfSpan)
        XCTAssertEqual([sub.innerRadius, sub.outerRadius], [100, 140])
        let clamped = s.subSector(innerRadius: 10, outerRadius: 999)
        XCTAssertEqual([clamped.innerRadius, clamped.outerRadius], [65, 180])

        let left = s.half(.left), right = s.half(.right)
        XCTAssertEqual(left.halfSpan, s.halfSpan / 2, accuracy: 1e-12)
        XCTAssertEqual(left.endAngle, s.centerAngle, accuracy: 1e-12)
        XCTAssertEqual(right.startAngle, s.centerAngle, accuracy: 1e-12)
        XCTAssertEqual(left.startAngle, s.startAngle, accuracy: 1e-12)
        XCTAssertEqual(right.endAngle, s.endAngle, accuracy: 1e-12)
        XCTAssertEqual(left.area + right.area, s.area, accuracy: 1e-6)

        let rim = s.rim(thickness: 6)
        XCTAssertEqual(rim.outerRadius, 180)
        XCTAssertEqual(rim.depth, 6, accuracy: 1e-9)
        // A point in the left half is not in the right half (away from the shared edge).
        let p = RingSector.point(center: origin, angle: s.centerAngle - 0.2, radius: 120)
        XCTAssertTrue(left.contains(p))
        XCTAssertFalse(right.contains(p))
    }
}

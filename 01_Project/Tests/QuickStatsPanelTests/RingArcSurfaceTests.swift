import XCTest

/// Hostless checks of what the native outer-band arcs rely on: the arc panel frame includes the
/// gap the resolver counts as arc, the hover caption has a slot reserved at summon, the route
/// from a wide sub-ring follows the rendered arc instead of its bounding box, parts draw on
/// their parent's scale and expose read-only accessibility, and fixture parents derive from
/// the chosen part set.
final class RingArcSurfaceTests: XCTestCase {

    func testCPUGroupSegmentsHaveEqualWidthsWithoutLosingPartsOrHitTargets() throws {
        for preset in RingSizePreset.allCases {
            for fixture in [RingPartFixtureName.typical, .dense] {
                let s = snapshot(eight, preset: preset, parts: fixture)
                let arc = try XCTUnwrap(s.arcs[.stat(.cpu)])
                let parts = try XCTUnwrap(s.parts[.cpu])
                XCTAssertEqual(arc.segments.count, parts.parts.count)
                for group in Set(arc.segments.map(\.group)) {
                    let segments = arc.segments.filter { $0.group == group }
                    let width = try XCTUnwrap(segments.first).sector.span
                    for segment in segments {
                        XCTAssertEqual(segment.sector.span, width, accuracy: 1e-10)
                        let point = RingSector.point(center: arc.center, angle: segment.sector.centerAngle,
                                                     radius: segment.sector.midRadius)
                        XCTAssertEqual(arc.entry(at: point), segment.index)
                        if let frame = segment.textFrame {
                            XCTAssertTrue(segment.sector.contains(rect: frame, padding: RingLayout.textPadding))
                        }
                        XCTAssertFalse(parts.parts[segment.index].name.isEmpty)
                        XCTAssertFalse(parts.parts[segment.index].valueText.isEmpty)
                    }
                }
            }
        }
    }

    private let visible = CGRect(x: 0, y: 0, width: 3000, height: 2000)
    private let all = Array(StatKind.allCases)
    private let eight: [StatKind] = [.cpu, .memory, .disk, .network, .battery, .gpu, .power, .temps]
    private let subRingKinds: [StatKind] = [.cpu, .disk, .network, .temps]

    private func reading(_ kind: StatKind) -> RingReading {
        RingReading(value: "42%", widestValue: kind.ringFallbackWidest)
    }

    private func snapshot(_ kinds: [StatKind], favourites: [StatKind]? = nil, preset: RingSizePreset = .medium,
                          parts name: RingPartFixtureName = .typical) -> RingSnapshot {
        let set = RingPartFixtures.make(name)
        return RingSnapshot.make(enabledKinds: kinds, favourites: favourites, preset: preset, reading: reading,
                                 parts: { set.list(for: $0) })
    }

    private func bandPlan(_ s: RingSnapshot) -> RingPlan {
        let preferred = CGRect(x: 1200, y: 800, width: s.size.width, height: s.size.height)
        let sizes = Dictionary(uniqueKeysWithValues: s.enabledKinds.map { ($0, CGSize(width: 300, height: 320)) })
        return RingPlacement.resolve(.init(snapshot: s, visible: visible, preferredBase: preferred, detailSizes: sizes))
    }

    private func resolver(_ s: RingSnapshot, _ plan: RingPlan, openArc: RingArcOwner?,
                          detail: StatKind? = nil) -> RingHitResolver {
        RingHitResolver(plan: plan, baseFrame: plan.baseFrame, snapshot: s, openDetailKind: detail,
                        openArc: openArc, sideList: nil, wholeList: nil)
    }

    /// Ring space (top-left of the base panel, y down) to screen points (y up).
    private func screen(_ p: CGPoint, _ plan: RingPlan) -> CGPoint {
        CGPoint(x: plan.baseFrame.minX + p.x, y: plan.baseFrame.maxY - p.y)
    }

    private func ringPoint(_ s: RingSnapshot, angle: Double, radius: CGFloat) -> CGPoint {
        RingSector.point(center: s.layout.center, angle: angle, radius: radius)
    }

    // MARK: Gap

    func testArcPanelFrameIncludesTheGapTheResolverCountsAsArc() throws {
        for preset in RingSizePreset.allCases {
            let s = snapshot(all, favourites: Array(all.prefix(6)), preset: preset)
            let plan = bandPlan(s)
            XCTAssertEqual(plan.mode, .outerBand, "\(preset)")
            XCTAssertFalse(plan.arcFrames.isEmpty)
            for (owner, frame) in plan.arcFrames {
                let arc = try XCTUnwrap(s.arcs[owner])
                let r = resolver(s, plan, openArc: owner)
                let gapRadius = preset.outerRadius + RingSizePreset.bandGap / 2
                for angle in [arc.startAngle + 1e-3, arc.parentMidAngle, arc.startAngle + arc.span - 1e-3] {
                    let gap = screen(ringPoint(s, angle: angle, radius: gapRadius), plan)
                    XCTAssertEqual(r.resolveBranch(gap).hit, .arc(owner), "\(preset) \(owner): the gap is the arc's")
                    XCTAssertTrue(frame.contains(gap), "\(preset) \(owner): the arc panel receives the gap's events")
                }
                for segment in arc.segments {
                    let p = screen(ringPoint(s, angle: segment.sector.centerAngle, radius: segment.sector.midRadius), plan)
                    XCTAssertTrue(frame.contains(p), "\(preset) \(owner) segment \(segment.index)")
                }
                XCTAssertEqual(arc.surface.innerRadius, preset.outerRadius, "the surface starts at the ring's edge")
                XCTAssertEqual(plan.arcOutlines[owner]?.count, arc.surface.outline.count)
            }
        }
    }

    // MARK: Caption slot

    func testCaptionSlotIsReservedInsideTheBandOutsideTheArcAndInsideTheArcPanel() throws {
        for preset in RingSizePreset.allCases {
            for set in [RingPartFixtureName.typical, .dense] {
                let s = snapshot(eight, preset: preset, parts: set)
                let plan = bandPlan(s)
                XCTAssertEqual(plan.mode, .outerBand)
                for kind in subRingKinds {
                    let owner = RingArcOwner.stat(kind)
                    let label = "\(preset) \(set) \(kind)"
                    let arc = try XCTUnwrap(s.arcs[owner], label)
                    let slot = try XCTUnwrap(s.captionSlots[owner], label)
                    let half = preset.footprintWithBand.width / 2
                    let footprint = CGRect(x: s.layout.center.x - half, y: s.layout.center.y - half,
                                           width: 2 * half, height: 2 * half)
                    XCTAssertTrue(footprint.insetBy(dx: -0.001, dy: -0.001).contains(slot), "\(label): inside the band footprint")
                    let nearestX = max(slot.minX - s.layout.center.x, 0, s.layout.center.x - slot.maxX)
                    let nearestY = max(slot.minY - s.layout.center.y, 0, s.layout.center.y - slot.maxY)
                    XCTAssertGreaterThan(hypot(nearestX, nearestY), arc.outerRadius, "\(label): never over the arc")
                    let parts = try XCTUnwrap(s.parts[kind]).parts
                    for part in parts {
                        let line = RingTypography.captionSize(RingCaption.text(for: part, stat: kind))
                        XCTAssertGreaterThanOrEqual(slot.width, line.width + 2 * RingCaption.horizontalPadding, label)
                        XCTAssertGreaterThanOrEqual(slot.height, line.height, label)
                    }
                    XCTAssertGreaterThanOrEqual(slot.height, RingTypography.captionSize("Ag").height,
                                                "\(label): 12-point text, never shrunk")
                    let screenSlot = RingPlacement.screenFrame(slot, in: plan.baseFrame)
                    let panel = try XCTUnwrap(plan.arcFrames[owner])
                    XCTAssertTrue(panel.insetBy(dx: -0.001, dy: -0.001).contains(screenSlot), "\(label): in the arc panel")
                    for (other, card) in plan.detailFrames {
                        XCTAssertFalse(card.intersects(screenSlot), "\(label): \(other)'s card over the caption")
                    }
                    let centre = CGPoint(x: screenSlot.midX, y: screenSlot.midY)
                    XCTAssertEqual(resolver(s, plan, openArc: owner).resolveBranch(centre).hit, .arc(owner),
                                   "\(label): the caption is inside its branch")
                    XCTAssertEqual(resolver(s, plan, openArc: nil).resolveBranch(centre).hit, .none,
                                   "\(label): a closed sub-ring's caption slot is outside")
                }
            }
        }
    }

    func testCaptionSlotIsFrozenAtSummonAndNamesACollapsedGroup() throws {
        let dense = snapshot(eight, parts: .dense)
        let busy = RingSnapshot.make(enabledKinds: eight, reading: { kind in
            RingReading(value: "99%", widestValue: kind.ringFallbackWidest, band: .hot)
        }, parts: { RingPartFixtures.make(.dense).list(for: $0) })
        XCTAssertEqual(dense.captionSlots, busy.captionSlots, "slots come from the frozen parts, not live values")
        XCTAssertEqual(dense.arcs[.stat(.cpu)]?.segments.count, 32, "dense: 32 cores, one segment each")
        let sensors = try XCTUnwrap(dense.parts[.temps])
        XCTAssertEqual(dense.arcs[.stat(.temps)]?.segments.count, sensors.parts.count, "one segment per sensor role")
        XCTAssertNotNil(dense.captionSlots[.stat(.temps)])
        let role = try XCTUnwrap(sensors.parts.first)
        XCTAssertEqual(RingCaption.text(for: role, stat: .temps),
                       "\(role.name) \(role.valueText) \u{00B7} hottest of \(role.memberCount)")
        let single = RingPartBuilder.temperature(sensors: [RingSensorInput(group: "SSD", name: "NAND", celsius: 40),
                                                           RingSensorInput(group: "GPU", name: "die", celsius: 50)])
        let plain = try XCTUnwrap(single.parts.first)
        XCTAssertEqual(RingCaption.text(for: plain, stat: .temps), "\(plain.name) \(plain.valueText)")
        // A collapsed core group still names its rule.
        let many = RingPartBuilder.cpu(cores: (0..<34).map {
            RingCoreInput(id: "c\($0)", name: "P\($0 + 1)", group: "Performance", usagePercent: Double($0))
        } + [RingCoreInput(id: "e", name: "E1", group: "Efficiency", usagePercent: 3)])
        let collapsed = try XCTUnwrap(many.parts.first { $0.id.hasSuffix(RingPartBuilder.collapsedSuffix) })
        XCTAssertTrue(RingCaption.text(for: collapsed, stat: .cpu).hasSuffix("highest of \(collapsed.memberCount)"))
        // Disk says what its percentage measures.
        let volume = try XCTUnwrap(RingPartFixtures.make(.typical).diskParts.parts.first)
        XCTAssertEqual(RingCaption.text(for: volume, stat: .disk), "\(volume.name) \(volume.valueText) used")
    }

    func testASubRingWhoseCaptionCannotFitOpensItsCardAlone() {
        let s = RingSnapshot.make(enabledKinds: eight, reading: reading,
                                  parts: { RingPartFixtures.make(.typical).list(for: $0) },
                                  measureCaption: { _ in CGSize(width: 900, height: 15) })
        for kind in subRingKinds {
            XCTAssertNil(s.arcs[.stat(kind)], "\(kind): no caption room, no arc")
            XCTAssertNil(s.captionSlots[.stat(kind)])
            XCTAssertNotNil(s.parts[kind], "\(kind): its parts are still frozen for the card")
        }
    }

    // MARK: Travel from the rendered arc

    /// A point of each favourite other than `owner`, at its sector's centre, in screen points.
    private func siblingCentres(_ s: RingSnapshot, _ plan: RingPlan, except owner: StatKind) -> [(StatKind, CGPoint)] {
        s.layout.favourites.filter { $0.kind != owner }.map { favourite in
            (favourite.kind, screen(ringPoint(s, angle: favourite.sector.centerAngle, radius: favourite.sector.midRadius), plan))
        }
    }

    func testRouteFromAWideSubRingToItsCardLeavesTheSiblingWedgesOut() throws {
        var boundingBoxCoveredASibling = false
        for preset in RingSizePreset.allCases {
            let s = snapshot(eight, preset: preset, parts: .dense)
            let plan = bandPlan(s)
            let owner = RingArcOwner.stat(.cpu)
            let outline = try XCTUnwrap(plan.arcOutlines[owner])
            let card = try XCTUnwrap(plan.detailFrames[.cpu])
            let disc = try XCTUnwrap(plan.ringDisc)
            let route = RingTravelRegion(points: outline, rects: [card], excluding: disc)
            let boundingBox = RingTravelRegion(from: try XCTUnwrap(plan.arcFrames[owner]), to: card)
            for (kind, centre) in siblingCentres(s, plan, except: .cpu) {
                XCTAssertFalse(route.contains(centre), "\(preset): \(kind) is not travel space")
                if boundingBox.contains(centre) { boundingBoxCoveredASibling = true }
            }
            // Still a route: just outside the arc, on its way towards the card.
            let arc = try XCTUnwrap(s.arcs[owner])
            let end = arc.startAngle + arc.span
            let leaving = screen(ringPoint(s, angle: end, radius: arc.outerRadius + 4), plan)
            XCTAssertTrue(route.contains(leaving), "\(preset): beside the arc's trailing end")
            XCTAssertTrue(route.contains(CGPoint(x: card.minX - 4, y: card.midY)), "\(preset): beside the card")
            XCTAssertFalse(route.contains(CGPoint(x: disc.center.x, y: disc.center.y)), "\(preset): never the hub")
        }
        XCTAssertTrue(boundingBoxCoveredASibling, "the frame-based route would have covered a sibling")
    }

    @MainActor
    func testLeavingAWideSubRingOntoASiblingResumesTheNormalDwell() throws {
        final class Clock: RingClock { var time: TimeInterval = 0; func now() -> TimeInterval { time } }
        let clock = Clock()
        let s = snapshot(eight, preset: .small, parts: .dense)
        let plan = bandPlan(s)
        let state = RingBranchState(plan: plan, clock: clock)
        state.summon(plan: plan, pointer: CGPoint(x: -500, y: -500))
        func hit(_ p: CGPoint) -> RingBranchHit {
            resolver(s, plan, openArc: state.expansion.arc?.owner, detail: state.expansion.detail?.kind).resolveBranch(p).hit
        }
        let cpu = try XCTUnwrap(s.layout.favourites.first { $0.kind == .cpu }).sector
        let onCPU = screen(ringPoint(s, angle: cpu.centerAngle, radius: cpu.midRadius), plan)
        XCTAssertEqual(hit(onCPU), .node(.wedge(.cpu)))
        state.pointerMoved(to: onCPU, hit: hit(onCPU))
        clock.time = 0.35
        XCTAssertEqual(state.fire(token: state.timerToken), [.showArc(.stat(.cpu)), .showDetail(.cpu, owner: .stat(.cpu))])

        // Out onto the far end of the sub-ring, then straight across the ring onto a sibling
        // that the parent-to-card route does not cover.
        let arc = try XCTUnwrap(s.arcs[.stat(.cpu)])
        let farEnd = screen(ringPoint(s, angle: arc.startAngle + 0.02, radius: arc.surface.midRadius), plan)
        switch hit(farEnd) {
        case .arc(.stat(.cpu)): break
        case .segment(let ref) where ref.stat == .cpu: break
        default: XCTFail("the far end of the sub-ring resolves to it: \(hit(farEnd))")
        }
        state.pointerMoved(to: farEnd, hit: hit(farEnd))
        let card = try XCTUnwrap(plan.detailFrames[.cpu])
        let parentRoute = RingTravelRegion(from: try XCTUnwrap(plan.nodeFrames[.wedge(.cpu)]), to: card)
        let boundingBoxRoute = RingTravelRegion(from: try XCTUnwrap(plan.arcFrames[.stat(.cpu)]), to: card)
        // A sibling the frame-based route would have held for the 700 ms grace.
        let (sibling, point) = try XCTUnwrap(siblingCentres(s, plan, except: .cpu).first {
            !parentRoute.contains($0.1) && boundingBoxRoute.contains($0.1)
        })
        clock.time = 0.5
        state.pointerMoved(to: point, hit: hit(point))
        XCTAssertEqual(state.expansion.detail?.kind, .cpu, "the preview survives the crossing for now")
        clock.time = 0.5 + 0.35
        let commands = state.fire(token: state.timerToken)
        XCTAssertTrue(commands.contains(.showDetail(sibling, owner: .stat(sibling))),
                      "a sibling under the pointer previews after the normal 350 ms, not after the 700 ms grace: \(commands)")
        XCTAssertEqual(state.expansion.detail?.kind, sibling)
    }

    // MARK: Panel geometry

    func testArcPanelGeometryDrawsEverySegmentWhereTheResolverHitsIt() throws {
        let s = snapshot(all, favourites: Array(all.prefix(6)), parts: .dense)
        let plan = bandPlan(s)
        for (owner, frame) in plan.arcFrames {
            let geometry = RingArcPanelGeometry(panel: frame, base: plan.baseFrame)
            let arc = try XCTUnwrap(s.arcs[owner])
            for segment in arc.segments {
                let ring = ringPoint(s, angle: segment.sector.centerAngle, radius: segment.sector.midRadius)
                let local = geometry.local(ring)
                let viaPanel = CGPoint(x: frame.minX + local.x, y: frame.maxY - local.y)
                let viaBase = screen(ring, plan)
                XCTAssertEqual(viaPanel.x, viaBase.x, accuracy: 1e-9)
                XCTAssertEqual(viaPanel.y, viaBase.y, accuracy: 1e-9)
                let moved = geometry.local(segment.sector)
                XCTAssertEqual(moved.span, segment.sector.span)
                XCTAssertTrue(moved.contains(local), "the drawn sector is the hit sector")
                XCTAssertTrue(CGRect(origin: .zero, size: geometry.size).contains(local), "inside the panel")
            }
        }
    }

    // MARK: Parts as gauges and accessibility

    func testPartGaugesUseTheParentScaleAndColourBasis() throws {
        let set = RingPartFixtures.make(.typical)
        let core = try XCTUnwrap(set.cpuParts.parts.first)
        let coreGauge = core.gauge(stat: .cpu)
        XCTAssertEqual(coreGauge.components, [RingFillComponent(component: .level, fraction: try XCTUnwrap(core.fraction))])
        XCTAssertFalse(coreGauge.usesHeatRamp)

        let volume = try XCTUnwrap(set.diskParts.parts.first)
        XCTAssertEqual(volume.gauge(stat: .disk).totalFraction, try XCTUnwrap(volume.fraction), accuracy: 1e-12)

        // Network: one level for download plus upload, and that combined rate as the label.
        let interface = try XCTUnwrap(set.networkParts.parts.first)
        let total = try XCTUnwrap(interface.raw) + (interface.rawSecondary ?? 0)
        let netGauge = interface.gauge(stat: .network)
        XCTAssertNil(netGauge.halves)
        XCTAssertEqual(netGauge.totalFraction, RingRateScale.fraction(bytesPerSecond: total), accuracy: 1e-12)
        XCTAssertEqual(interface.labelValue(stat: .network), NetworkSample.rate(total))
        XCTAssertEqual(volume.labelValue(stat: .disk), volume.valueText)

        let sensor = try XCTUnwrap(set.temperatureParts.parts.first)
        let heat = sensor.gauge(stat: .temps)
        XCTAssertTrue(heat.usesHeatRamp)
        XCTAssertEqual(heat.totalFraction, RingGaugeMapper.temperatureFraction(celsius: try XCTUnwrap(sensor.raw)), accuracy: 1e-12)

        let missing = core.unavailable().gauge(stat: .cpu)
        XCTAssertFalse(missing.isAvailable, "a missing part keeps its slot with the empty track, never a zero fill")
        XCTAssertTrue(missing.components.isEmpty)
    }

    func testSegmentAccessibilityIsReadOnlyNameValueAndRange() throws {
        let set = RingPartFixtures.make(.typical)
        for kind in subRingKinds {
            let list = try XCTUnwrap(set.list(for: kind))
            let part = try XCTUnwrap(list.parts.first)
            let info = part.accessibility(stat: kind)
            XCTAssertTrue(info.label.contains(part.name), "\(kind)")
            XCTAssertTrue(info.label.contains(part.group), "\(kind)")
            XCTAssertEqual(info.value, part.valueText)
            XCTAssertFalse(info.range.isEmpty, "\(kind) names its scale")
            XCTAssertEqual(part.unavailable().accessibility(stat: kind).value, "Unavailable")
        }
        XCTAssertEqual(StatKind.temps.ringPartRange, "30 to 100 \u{00B0}C")
    }

    // MARK: Fixture parents from the part set

    func testFixtureParentGaugesAgreeWithTheirParts() throws {
        for name in RingPartFixtureName.allCases {
            let set = RingPartFixtures.make(name)
            func gauge(_ kind: StatKind) -> RingGauge {
                RingFixtureSamples.gauge(for: kind, powerCeilingWatts: 30, parts: set)
            }
            let mean = try XCTUnwrap(set.cpuParts.parentAggregate?.primary)
            XCTAssertEqual(gauge(.cpu).totalFraction, mean / 100, accuracy: 0.005, "\(name): cores average to CPU")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(gauge(.cpu).peak), gauge(.cpu).totalFraction)

            let boot = try XCTUnwrap(set.diskParts.parentAggregate?.primary)
            XCTAssertEqual(gauge(.disk).totalFraction, boot, accuracy: 1e-9, "\(name): boot container equals Disk")

            let sum = try XCTUnwrap(set.networkParts.parentAggregate)
            let halves = try XCTUnwrap(gauge(.network).halves)
            XCTAssertEqual(halves.left, RingRateScale.fraction(bytesPerSecond: sum.primary), accuracy: 1e-9, "\(name)")
            XCTAssertEqual(halves.right, RingRateScale.fraction(bytesPerSecond: sum.secondary ?? 0), accuracy: 1e-9, "\(name)")

            if let hottest = set.temperatureParts.parentAggregate?.primary {
                XCTAssertEqual(gauge(.temps).totalFraction, RingGaugeMapper.temperatureFraction(celsius: hottest),
                               accuracy: 1e-9, "\(name): hottest sensor equals the Temperature fill")
            } else {
                XCTAssertFalse(gauge(.temps).isAvailable, "\(name): no valid sensor, no zero fill")
            }
        }
    }

    @MainActor
    func testFixtureStoreAndWedgeTextComeFromThePartSet() throws {
        for name in RingPartFixtureName.allCases {
            let set = RingPartFixtures.make(name)
            let store = StatsStore()
            store.seedRingFixture(unavailable: [], parts: set)
            XCTAssertEqual(store.cpu, set.cpu, "\(name)")
            XCTAssertEqual(store.disk, set.disk, "\(name)")
            XCTAssertEqual(store.network, set.network, "\(name)")
            XCTAssertEqual(store.temps, set.temperature, "\(name)")

            let six = try XCTUnwrap(RingFixture.named("six"))
            for kind in subRingKinds {
                let derived = six.reading(for: kind, parts: set, partText: { _ in
                    RingReading(value: "from parts", widestValue: "from parts")
                })
                XCTAssertEqual(derived.value, "from parts", "\(name) \(kind): text from the seeded store")
                XCTAssertEqual(derived.gauge, RingFixtureSamples.gauge(for: kind, powerCeilingWatts: 30, parts: set))
            }
            let paired = try XCTUnwrap(RingFixture.named("paired"))
            let kept = paired.reading(for: .cpu, parts: set, partText: { _ in RingReading(value: "x", widestValue: "x") })
            XCTAssertEqual(kept.value, "42%", "a fixture that sets its own text keeps it")
            XCTAssertEqual(kept.gauge, RingFixtureSamples.gauge(for: .cpu, powerCeilingWatts: 30, parts: set))
            XCTAssertEqual(six.reading(for: .gpu, parts: set).value, "37%", "stats without parts are unchanged")
        }
    }

    func testMinimalPartsOpenCardsWithoutArcsAndRealDataHasNoSubRing() {
        let minimal = snapshot(eight, parts: .minimal)
        let plan = bandPlan(minimal)
        XCTAssertNotNil(plan.arcFrames[.stat(.cpu)], "ten cores still make a sub-ring")
        for kind in [StatKind.disk, .network, .temps] {
            XCTAssertNil(plan.arcFrames[.stat(kind)], "\(kind): fewer than two parts")
            XCTAssertNotNil(plan.detailFrames[kind], "\(kind): its card still opens")
        }
        let real = RingSnapshot.make(enabledKinds: all, favourites: Array(all.prefix(6)), reading: reading)
        let realPlan = bandPlan(real)
        XCTAssertEqual(Set(realPlan.arcFrames.keys), [.more], "real data: no part arcs, only the More arc")
        XCTAssertTrue(real.captionSlots.isEmpty)
    }

    func testSixFavouritesOfElevenGiveAFiveEntryMoreArcOfGaugeWedges() throws {
        for preset in RingSizePreset.allCases {
            let s = snapshot(all, favourites: Array(all.prefix(6)), preset: preset)
            let arc = try XCTUnwrap(s.arcs[.more], "\(preset)")
            XCTAssertEqual(arc.segments.count, 5)
            XCTAssertNotNil(s.moreArcRung)
            XCTAssertTrue(arc.segments.allSatisfy { $0.textFrame != nil }, "\(preset): every entry carries its content")
            let plan = bandPlan(s)
            XCTAssertNotNil(plan.arcFrames[.more])
            XCTAssertNil(plan.moreSurface)
            let state = RingBranchState(plan: plan, clock: SystemRingClock())
            state.summon(plan: plan, pointer: .zero)
            XCTAssertEqual(state.click(.more), [.showArc(.more)])
            for kind in s.moreKinds {
                _ = state.click(.moreItem(kind))
                XCTAssertEqual(state.expansion.detail?.kind, kind)
                XCTAssertEqual(state.expansion.arc?.owner, .more, "\(kind): the More arc stays")
            }
        }
    }
}

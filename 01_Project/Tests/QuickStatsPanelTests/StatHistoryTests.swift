import XCTest

final class StatHistoryTests: XCTestCase {
    func testRingBufferKeepsChronologicalTail() {
        var buffer = RingBuffer<Int>(capacity: 3)
        [1, 2, 3, 4, 5].forEach { buffer.append($0) }
        XCTAssertEqual(buffer.elements, [3, 4, 5])
    }

    func testPeakRisesImmediatelyAndDecaysOncePerSample() {
        XCTAssertEqual(PeakStrategy.resolve(windowMax: 100, previous: 50), 100)
        XCTAssertEqual(PeakStrategy.resolve(windowMax: 20, previous: 100), 90)
        XCTAssertEqual(PeakStrategy.resolve(windowMax: 20, previous: 90), 81)
    }

    func testPeakDoesNotDecayDuringRepeatedRender() {
        XCTAssertEqual(PeakStrategy.resolve(windowMax: 20, previous: 90, advanced: false), 90)
    }

    // MARK: Five-minute history (D-046)

    @MainActor
    func testHistoryIsFiveMinutesAtEveryInterval() {
        XCTAssertEqual(StatsStore.historyDuration, 300)
        XCTAssertEqual(StatsStore.historyCapacity(interval: 0.5), 600)
        XCTAssertEqual(StatsStore.historyCapacity(interval: 1), 300)
        XCTAssertEqual(StatsStore.historyCapacity(interval: 5), 60)
    }

    // MARK: Bar layout (D-046)

    /// The Ring/Strip card graph: 220 pt of 2 + 1 pt bars → 73 slots.
    private func card(_ values: [Double]) -> [GraphBarLayout.Bar] {
        GraphBarLayout.bars(for: values, width: 220, barWidth: 2, barGap: 1, fit: .wholeHistory)
    }

    func testFewerSamplesThanSlotsSpreadAcrossTheFullWidth() {
        XCTAssertEqual(GraphBarLayout.slotCount(width: 220, barWidth: 2, barGap: 1), 73)
        let values = (0..<10).map(Double.init)
        let bars = card(values)
        XCTAssertEqual(bars.map(\.value), values, "one bar per sample, oldest first")
        XCTAssertEqual(bars.first?.x, 0, "no blank left side")
        XCTAssertEqual(bars.last!.x + 22, 220, accuracy: 0.001, "the last slot ends at the right edge")
        XCTAssertEqual(bars[1].x - bars[0].x, 22, accuracy: 0.001, "wider slots: 220 / 10")
        XCTAssertEqual(bars[0].width, 22 * 2 / 3, accuracy: 0.001, "bar:gap ratio kept")
        XCTAssertEqual(card([5]).first, GraphBarLayout.Bar(x: 0, width: 220 * 2 / 3, value: 5))
        XCTAssertTrue(card([]).isEmpty)
    }

    func testExactlyOneSamplePerSlotUsesEverySlot() {
        let bars = card((0..<73).map(Double.init))
        XCTAssertEqual(bars.count, 73)
        XCTAssertEqual(bars.map(\.value), (0..<73).map(Double.init))
        XCTAssertEqual(bars.last!.x + 220.0 / 73, 220, accuracy: 0.001)
    }

    func testMoreSamplesThanSlotsAverageIntoSlots() {
        // 300 samples (five minutes at 1 s) into 73 slots: every sample lands in exactly one
        // bucket, in order, and each bar is its bucket's mean.
        let values = (0..<300).map(Double.init)
        let bars = card(values)
        XCTAssertEqual(bars.count, 73)
        XCTAssertEqual(bars.first?.x, 0)
        XCTAssertEqual(bars.last!.x + 220.0 / 73, 220, accuracy: 0.001, "the whole history fits the width")
        var expected: [Double] = []
        for i in 0..<73 {
            let bucket = values[(i * 300 / 73)..<((i + 1) * 300 / 73)]
            XCTAssertFalse(bucket.isEmpty)
            expected.append(bucket.reduce(0, +) / Double(bucket.count))
        }
        XCTAssertEqual(bars.map(\.value), expected)
        XCTAssertEqual(bars.first?.value, 1.5, "first bucket is samples 0…3")
        XCTAssertEqual(bars.last?.value, 297, "last bucket is samples 295…299, ending with the newest")
        // A simple case by hand: 6 samples into 3 slots → pairs.
        let pairs = GraphBarLayout.bars(for: [0, 2, 4, 6, 8, 10], width: 9, barWidth: 2, barGap: 1, fit: .wholeHistory)
        XCTAssertEqual(pairs, [.init(x: 0, width: 2, value: 1), .init(x: 3, width: 2, value: 5),
                               .init(x: 6, width: 2, value: 9)])
    }

    func testStripTailModeIsUnchanged() {
        // The strip's 34 pt slot with 1 + 0.5 pt bars: 22 fixed slots, newest at the right edge.
        let slots = GraphBarLayout.slotCount(width: 34, barWidth: 1, barGap: 0.5)
        XCTAssertEqual(slots, 22)
        let partial = GraphBarLayout.bars(for: [1, 2, 3], width: 34, barWidth: 1, barGap: 0.5, fit: .recentTail)
        XCTAssertEqual(partial, [.init(x: 19 * 1.5, width: 1, value: 1), .init(x: 20 * 1.5, width: 1, value: 2),
                                 .init(x: 21 * 1.5, width: 1, value: 3)], "a partly filled buffer pads on the left")
        let full = GraphBarLayout.bars(for: (0..<300).map(Double.init), width: 34, barWidth: 1, barGap: 0.5,
                                       fit: .recentTail)
        XCTAssertEqual(full.map(\.value), (278..<300).map(Double.init), "only the recent tail, not averaged")
        XCTAssertEqual(full.map(\.x), (0..<22).map { CGFloat($0) * 1.5 })
        XCTAssertTrue(full.allSatisfy { $0.width == 1 })
    }
}

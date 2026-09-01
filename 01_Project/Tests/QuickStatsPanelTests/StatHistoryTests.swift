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
}

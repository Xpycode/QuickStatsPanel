import Foundation

/// Fixed-capacity history of recent samples, oldest → newest.
///
/// **Whole samples, not extracted numbers.** Storing `NetworkSample` rather than
/// `[Double]` of download rates means switching a tile's value mode (Down → Up →
/// both) re-plots the history it already has instead of blanking the graph and
/// making the user wait a minute for it to refill.
///
/// Cost is trivial: 60 samples × 5 stats × a few dozen bytes ≈ 30 KB, and the
/// samplers producing them already run continuously (`StatsStore.start`), so
/// there is no extra CPU — only the retention of values that were previously
/// computed and thrown away.
struct RingBuffer<Element>: Sendable where Element: Sendable {

    private var storage: [Element] = []
    private var writeIndex = 0

    /// Maximum retained samples. Derived from a duration ÷ the user's refresh
    /// interval, never a hardcoded count — see `StatsStore.historyCapacity`.
    let capacity: Int

    init(capacity: Int) {
        // A zero/negative capacity would make `writeIndex % capacity` trap.
        self.capacity = max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[writeIndex] = element
            writeIndex = (writeIndex + 1) % capacity
        }
    }

    /// Samples in chronological order, oldest first.
    var elements: [Element] {
        // Before the buffer fills, `storage` is already in order and `writeIndex`
        // is still 0; afterwards the oldest sample sits at the write cursor.
        guard storage.count == capacity else { return storage }
        return Array(storage[writeIndex...] + storage[..<writeIndex])
    }

    var isEmpty: Bool { storage.isEmpty }
}

// MARK: - What the graph view consumes

/// How a graph maps values to bar height.
enum GraphScale: Sendable, Equatable {
    /// A known ceiling (percentages). Stable and directly comparable over time.
    case fixed(Double)
    /// No natural ceiling: each series normalizes to its own peak, which the
    /// graph then **prints in its legend** so the scale is never a silent one.
    case perSeriesPeak
}

/// One plotted series: the values, what to call it, and the value that maps to a
/// full-height bar. Scaling is resolved *before* the view — so `ActivityGraphView`
/// divides by `peak` and never needs to know whether that came from a fixed
/// percentage ceiling or a rolling rate peak.
struct GraphSeries {
    /// Oldest → newest, in the stat's natural unit (percent, or bytes/sec).
    let values: [Double]
    /// Legend word ("Download", "Read").
    let label: String
    /// Direction glyph for the legend ("↓", "↑"); empty for single-series stats.
    let marker: String
    /// The value that maps to a full-height bar. Never zero — see `init`.
    let peak: Double
    /// `peak` formatted for the legend ("34,0 MB/s"). `nil` under `.fixed`
    /// scaling, where the ceiling is implicit and printing "100%" says nothing.
    let peakFormatted: String?

    init(values: [Double], label: String, marker: String,
         peak: Double, peakFormatted: String?) {
        self.values = values
        self.label = label
        self.marker = marker
        // An all-zero series (idle network) would otherwise divide by zero and
        // render NaN heights; clamping to a tiny epsilon draws a flat floor.
        self.peak = peak > 0 ? peak : 1
        self.peakFormatted = peakFormatted
    }
}

/// Everything `ActivityGraphView` needs.
///
/// Named for **where each series is drawn**, not for which one the tile
/// headlines — the two orderings are independent, and conflating them is how a
/// graph ends up mirrored the wrong way round. `lower` present ⇒ the mirrored
/// form (upper rises from a centre baseline, lower falls from it); absent ⇒ a
/// single series rising from the bottom edge.
struct GraphData {
    let upper: GraphSeries
    let lower: GraphSeries?

    var isMirrored: Bool { lower != nil }
}

// MARK: - Peak resolution

/// Decides the value that maps to a full-height bar for a peak-scaled series.
///
/// This is its own type (rather than a closure inline in the view) because the
/// choice needs **memory across ticks**: `previous` is the peak used last time.
/// `StatsStore` owns that memory, in the same `@ObservationIgnored` dictionary
/// shape as the band hysteresis it already keeps for tinting.
enum PeakStrategy {

    /// - Parameters:
    ///   - windowMax: largest value currently visible in the graph.
    ///   - previous: the peak used on the previous tick (`0` on the first).
    /// - Returns: the value that should map to a full-height bar.
    ///
    /// ⚠️ **Open design decision — see D-025.** The trade-off is what happens
    /// when a large spike scrolls off the left edge of the window: `windowMax`
    /// drops in a single tick, so every remaining bar jumps taller at once and
    /// the graph appears to show a surge that never happened.
    ///
    /// Three viable answers:
    ///   1. **Plain window max** — `windowMax`. Always fills the height, best
    ///      detail on quiet traffic; suffers the phantom rescale above, and an
    ///      idle graph looks identical to a saturated one.
    ///   2. **Decaying peak** — fall gradually toward `windowMax` instead of
    ///      snapping. No phantom surge; the scale reads slightly high briefly
    ///      after a spike ends.
    ///   3. **Session peak** — `max(windowMax, previous)`. Fully stable and
    ///      comparable across a whole session (this is what `PowerSampler`
    ///      already does for `loadPercent`); but one 900 MB/s burst flattens
    ///      everything after it into a floor-hugging line.
    ///
    /// The chosen behavior is option 2. `advanced` is true exactly once per new
    /// sample, never once per SwiftUI body evaluation, so opening a detail card
    /// cannot make the scale decay faster.
    static func resolve(windowMax: Double, previous: Double, advanced: Bool = true) -> Double {
        guard advanced else { return max(windowMax, previous) }
        guard previous > 0, windowMax < previous else { return windowMax }
        return max(windowMax, previous * 0.9)
    }
}

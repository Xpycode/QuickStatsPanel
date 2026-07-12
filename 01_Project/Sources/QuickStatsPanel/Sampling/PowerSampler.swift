import Foundation

// New sampler (D-019). Permission-free SoC power in watts via the IOReportPower
// wrapper (private IOReport "Energy Model" channels — see IOReport.swift). Shape =
// cumulative-counter delta-per-tick (like NetworkSampler), NOT the snapshot shape:
// the wrapper holds the previous raw sample and deltas across ticks, so this class
// only owns the long-lived subscription and the session-peak ratchet.
//
// The tile hides when the Energy Model channels don't resolve (Intel / renamed
// future chips) via `isAvailable`, mirroring Battery/GPU/Fan's hide-when-absent.
// Reads are cheap in-process IOKit calls, so the sampler runs continuously with no
// visibility gating (only the costly `top` sampler is gated).

struct PowerSample: Equatable, Sendable {
    var isAvailable: Bool      // false ⇒ hide the tile (Intel / unsupported chip)
    var cpuWatts: Double
    var gpuWatts: Double
    var aneWatts: Double
    var dramWatts: Double

    /// Drives the shared calm→busy→hot tint (0–100). STORED, not computed: it needs
    /// the sampler's cross-tick session-peak, which a value type can't carry. The
    /// sampler sets it each tick = currentTotal ÷ sessionPeakTotal × 100. (Divergence
    /// from GPU/Fan, whose loadPercent is purely computed from the snapshot.)
    var loadPercent: Double

    /// Whole-machine draw from the SMC `PSTR` key (display, SSD, everything —
    /// vs the SoC-only IOReport rows above). nil ⇒ the key is absent on this
    /// Mac and the detail row is hidden. Key presence is fixed at `start()`, so
    /// the detail card's row set never changes while it's open. (SMC power keys
    /// per exelban/stats' sensor table, MIT.)
    var systemWatts: Double? = nil   // defaulted: `makeSample` builds the SoC part;
    /// Charger input from the SMC `PDTR` key; reads ~0 W on battery. Same
    /// nil-hides-row contract as `systemWatts`.
    var dcInWatts: Double? = nil     // the sampler stamps these two after it

    static let empty = PowerSample(isAvailable: false,
                                   cpuWatts: 0, gpuWatts: 0, aneWatts: 0, dramWatts: 0,
                                   loadPercent: 0, systemWatts: nil, dcInWatts: nil)

    /// Total SoC draw = CPU+GPU+ANE+DRAM (open-question 1 default: ANE+DRAM included
    /// in the Total row and the tint). The headline stays CPU·GPU.
    var totalWatts: Double { cpuWatts + gpuWatts + aneWatts + dramWatts }

    /// Strip headline: the CPU·GPU split as integers, e.g. "8·4 W". The ⚡ glyph is
    /// the tile's SF Symbol (bolt.fill), not part of this string. Total lives in the
    /// detail card, not the headline (user choice).
    var headlineFormatted: String {
        "\(Int(cpuWatts.rounded()))·\(Int(gpuWatts.rounded())) W"
    }

    // Detail-card rows. 1 decimal — fine-grained enough to see a subsystem move
    // without the headline's integer rounding. (%.1f is locale-independent "."—
    // consistent with a watts readout.)
    var cpuFormatted: String  { String(format: "%.1f W", cpuWatts) }
    var gpuFormatted: String  { String(format: "%.1f W", gpuWatts) }
    var aneFormatted: String  { String(format: "%.1f W", aneWatts) }
    var dramFormatted: String { String(format: "%.1f W", dramWatts) }
    var totalFormatted: String { String(format: "%.1f W", totalWatts) }

    // SMC rows — nil when the key is absent (row hidden, Battery/Fan pattern).
    var systemFormatted: String? { systemWatts.map { String(format: "%.1f W", $0) } }
    var dcInFormatted: String?   { dcInWatts.map { String(format: "%.1f W", $0) } }
}

/// Polls IOReportPower on a background timer, reporting a watts snapshot each tick
/// and ratcheting the session power peak that normalizes the tint.
///
/// Thread-safety: the long-lived `IOReportPower` is created in `start()` and torn
/// down in `stop()` (its `deinit` does the CF teardown), while `tick()` reads it on
/// `queue`. A `tick()` racing a `stop()` is benign — `tick()` binds a local strong
/// reference to the reader, so a concurrent `stop()` niling the property cannot pull
/// it out from under an in-flight `read()`; that final sample is discarded as the
/// sampler tears down anyway. Same confinement FanSampler uses for its SMC handle.
final class PowerSampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (PowerSample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.PowerSampler")
    private var reader: IOReportPower?

    /// Read-only SMC connection for the whole-machine rows (System `PSTR`,
    /// DC In `PDTR`). Same lifecycle + queue confinement as FanSampler's handle.
    private var smc: SMC?
    /// Key presence, probed once in `start()` so the detail card's row set is
    /// stable for the whole session (a mid-session nil would flap the row).
    private var hasSystemKey = false
    private var hasDCInKey = false

    /// Highest total SoC watts seen this session. Ratchets up, never down (AC-5);
    /// reset in `start()` so a relaunch/`restart()` recalibrates the tint band.
    private var peakTotal: Double = 0

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (PowerSample) -> Void) {
        self.interval = interval
        self.onSample = onSample
    }

    func start() {
        reader = IOReportPower()
        smc = SMC()
        hasSystemKey = smc?.value(forKey: "PSTR") != nil
        hasDCInKey = smc?.value(forKey: "PDTR") != nil
        if !hasSystemKey && !hasDCInKey {   // nothing to read — don't hold a connection
            smc?.close()
            smc = nil
        }
        peakTotal = 0
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        reader = nil   // last strong ref drops → IOReportPower.deinit releases the CF subscription
        smc?.close()
        smc = nil
    }

    private func tick() {   // runs on `queue`
        guard let reader else { return }
        var (sample, newPeak) = Self.makeSample(from: reader.read(),
                                                available: reader.isAvailable,
                                                peak: peakTotal)
        // `?? 0` keeps the row rendered (as 0.0 W) on a transient SMC misread
        // rather than letting the card's row set flap mid-session.
        if hasSystemKey { sample.systemWatts = smc?.value(forKey: "PSTR") ?? 0 }
        if hasDCInKey { sample.dcInWatts = smc?.value(forKey: "PDTR") ?? 0 }
        peakTotal = newPeak
        onSample(sample)
    }

    /// Pure builder shared by `tick()` and the DEBUG dump so the peak-ratchet and
    /// loadPercent math have a single definition. `reading == nil` is the priming
    /// tick (or unsupported hardware): emit `0·0 W` with availability from the
    /// wrapper, leaving the peak untouched. Otherwise ratchet the peak and normalize.
    static func makeSample(from reading: IOReportPower.Reading?,
                           available: Bool,
                           peak: Double) -> (PowerSample, peak: Double) {
        guard let r = reading else {
            return (PowerSample(isAvailable: available,
                                cpuWatts: 0, gpuWatts: 0, aneWatts: 0, dramWatts: 0,
                                loadPercent: 0),
                    peak)
        }
        let total = r.cpu + r.gpu + r.ane + r.dram
        let newPeak = Swift.max(peak, total)
        let load = newPeak > 0 ? Swift.min(total / newPeak * 100, 100) : 0
        let sample = PowerSample(isAvailable: available,
                                 cpuWatts: r.cpu, gpuWatts: r.gpu,
                                 aneWatts: r.ane, dramWatts: r.dram,
                                 loadPercent: load)
        return (sample, newPeak)
    }
}

#if DEBUG
extension PowerSampler {
    /// De-risk spike (D-019 Wave 2 / T2.1): drives an IOReportPower synchronously and
    /// prints the split headline + loadPercent, exercising the same `makeSample` math
    /// `tick()` uses (peak ratchet, tint normalization). Run a CPU/GPU load while this
    /// prints: the headline numbers rise and `loadPercent` climbs toward 100 at the
    /// peak, then eases back as load drops while the peak holds. Throwaway.
    static func debugDump(ticks: Int = 8, interval: TimeInterval = 1.0) {
        let reader = IOReportPower()
        print("[PowerSampler] isAvailable = \(reader.isAvailable)")
        var peak = 0.0
        for i in 0..<ticks {
            Thread.sleep(forTimeInterval: interval)
            let (s, newPeak) = makeSample(from: reader.read(), available: reader.isAvailable, peak: peak)
            peak = newPeak
            print(String(format: "[PowerSampler] tick %d  headline \"%@\"  total %.2f W  peak %.2f W  load %.0f%%",
                         i, s.headlineFormatted, s.totalWatts, peak, s.loadPercent))
        }
    }
}
#endif

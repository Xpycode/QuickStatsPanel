import Foundation

// New sampler (roadmap Phase A, D-011). Permission-free: `getloadavg(3)` is a
// plain libc call needing no entitlement. Like BatterySampler this is an ABSOLUTE
// snapshot, not a delta — each tick reads the kernel's 1/5/15-minute run-queue
// averages directly, so it's correct on the very first summon.

struct LoadSample: Equatable, Sendable {
    var one: Double
    var five: Double
    var fifteen: Double

    static let empty = LoadSample(one: 0, five: 0, fifteen: 0)

    /// Load average is a *run-queue depth*, not a percentage: `one == 4` means ~4
    /// runnable threads competing for CPU. Normalize the 1-min figure against the
    /// number of online cores so the color band reads as saturation — `load ==
    /// cores` → ~100% (fully busy), `load > cores` → oversubscribed (clamped 100).
    var saturationPercent: Double {
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        return min(100, one / Double(cores) * 100)
    }

    var oneFormatted: String { String(format: "%.2f", one) }
    var fiveFormatted: String { String(format: "%.2f", five) }
    var fifteenFormatted: String { String(format: "%.2f", fifteen) }
}

/// Polls the system load average on a background timer. Same timer skeleton as the
/// other samplers; no delta state (absolute read each tick).
final class LoadAverageSampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (LoadSample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.LoadAverageSampler")

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (LoadSample) -> Void) {
        self.interval = interval
        self.onSample = onSample
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        self.timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        onSample(Self.readLoad())
    }

    // MARK: - Load average (getloadavg)

    /// Reads the 1/5/15-minute averages. `getloadavg` fills up to `nelem` elements
    /// and returns how many it actually wrote (or -1 on failure) — guard on `== 3`
    /// before trusting all three slots.
    private static func readLoad() -> LoadSample {
        var samples = [Double](repeating: 0, count: 3)
        let count = getloadavg(&samples, 3)
        guard count == 3 else { return .empty }
        return LoadSample(one: samples[0], five: samples[1], fifteen: samples[2])
    }
}

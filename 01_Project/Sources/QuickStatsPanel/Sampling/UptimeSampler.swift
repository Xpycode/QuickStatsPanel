import Foundation

// New sampler (roadmap Phase A, D-011). Permission-free: `kern.boottime` via
// sysctl needs no entitlement. Absolute snapshot (no delta).
//
// We use `kern.boottime` — NOT `ProcessInfo.systemUptime` — deliberately:
// `systemUptime` only counts time the Mac has been *awake*, so on any laptop that
// sleeps it reads hours/days low. `kern.boottime` is the wall-clock boot instant,
// so `now - boottime` matches what `uptime(1)` and Activity Monitor show. (The
// trade-off — it shifts if the system clock is adjusted — is the conventional
// meaning of "uptime" anyway.)

struct UptimeSample: Equatable, Sendable {
    var seconds: TimeInterval

    static let empty = UptimeSample(seconds: 0)

    /// Two largest non-zero units — "3d 4h", "4h 12m", "12m 30s", "45s" — for a
    /// stable readout that doesn't churn every second once you're at the day scale.
    var compactFormatted: String {
        let total = Int(max(0, seconds))
        let days  = total / 86_400
        let hours = (total % 86_400) / 3_600
        let mins  = (total % 3_600) / 60
        let secs  = total % 60
        if days  > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        if mins  > 0 { return "\(mins)m \(secs)s" }
        return "\(secs)s"
    }

    /// Approximate boot timestamp, reconstructed for the popover ("Booted: …").
    var bootDateFormatted: String {
        guard seconds > 0 else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSinceNow: -seconds))
    }
}

/// Polls `kern.boottime` on a background timer and reports elapsed time since boot.
/// Same skeleton as the other samplers; no delta state.
final class UptimeSampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (UptimeSample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.UptimeSampler")

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (UptimeSample) -> Void) {
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
        onSample(Self.readUptime())
    }

    // MARK: - Uptime (sysctl kern.boottime)

    private static func readUptime() -> UptimeSample {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return .empty }
        let boot = Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000.0
        let now = Date().timeIntervalSince1970
        return UptimeSample(seconds: max(0, now - boot))
    }
}

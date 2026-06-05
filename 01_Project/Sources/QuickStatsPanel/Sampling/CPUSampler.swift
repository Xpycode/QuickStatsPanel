import Foundation
import Darwin

// Ported from StatsWindow (sibling project) — see decision D-005.
// Reads host CPU load ticks and reports usage as a delta between samples.

struct CPUSample: Equatable, Sendable {
    var totalUsagePercent: Double
    var userPercent: Double
    var systemPercent: Double
    var idlePercent: Double

    static let empty = CPUSample(totalUsagePercent: 0, userPercent: 0, systemPercent: 0, idlePercent: 100)
}

/// Polls `host_statistics(HOST_CPU_LOAD_INFO)` on a background timer and reports
/// a `CPUSample` (computed from the tick delta) via `onSample`.
final class CPUSampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (CPUSample) -> Void
    private var timer: DispatchSourceTimer?
    private var previous: host_cpu_load_info?
    private let queue = DispatchQueue(label: "QuickStatsPanel.CPUSampler")

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (CPUSample) -> Void) {
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
        guard let info = Self.readHostCPULoad() else { return }
        defer { previous = info }
        guard let prev = previous else { return }   // first tick only seeds the baseline

        let user = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return }

        onSample(CPUSample(
            totalUsagePercent: ((user + system + nice) / total) * 100,
            userPercent: (user / total) * 100,
            systemPercent: (system / total) * 100,
            idlePercent: (idle / total) * 100
        ))
    }

    private static func readHostCPULoad() -> host_cpu_load_info? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &size)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}

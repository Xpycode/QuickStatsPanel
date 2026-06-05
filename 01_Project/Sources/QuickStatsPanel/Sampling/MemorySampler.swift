import Foundation
import Darwin

// Ported from StatsWindow (sibling project) — see decision D-005.

struct MemorySample: Equatable, Sendable {
    var usedBytes: UInt64
    var totalBytes: UInt64
    var pressurePercent: Double

    static let empty = MemorySample(usedBytes: 0, totalBytes: 0, pressurePercent: 0)

    var usedFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(usedBytes), countStyle: .memory)
    }

    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .memory)
    }
}

/// Polls `host_statistics64(HOST_VM_INFO64)` and reports used / total / pressure.
/// "Used" = active + wired + compressed (the App-Memory-style figure).
final class MemorySampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (MemorySample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.MemorySampler")

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (MemorySample) -> Void) {
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
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(sysconf(Int32(_SC_PAGESIZE)))   // concurrency-safe vs. the global var
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let total = ProcessInfo.processInfo.physicalMemory

        onSample(MemorySample(
            usedBytes: used,
            totalBytes: total,
            pressurePercent: total > 0 ? Double(used) / Double(total) * 100 : 0
        ))
    }
}

import Foundation
import Darwin

// Ported from StatsWindow (sibling project) — see decision D-005.

struct MemorySample: Equatable, Sendable {
    var usedBytes: UInt64
    var totalBytes: UInt64
    var pressurePercent: Double

    // Activity-Monitor-style breakdown (detail card rows, 2026-07-12). All three
    // come from the same vm_statistics64 read that already feeds `usedBytes`.
    var appBytes: UInt64 = 0         // anonymous minus purgeable ("App Memory")
    var wiredBytes: UInt64 = 0
    var compressedBytes: UInt64 = 0

    static let empty = MemorySample(usedBytes: 0, totalBytes: 0, pressurePercent: 0)

    var usedFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(usedBytes), countStyle: .memory)
    }

    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .memory)
    }

    /// Memory not currently in use. Derived rather than sampled — the same
    /// `total − used` relation `DiskSample` uses — so it can never disagree with
    /// the "Used" figure sitting next to it in the tile. Guarded against
    /// underflow: both operands are unsigned, and a stale `totalBytes` of 0 on the
    /// `.empty` sample would otherwise wrap to 16 exabytes.
    var freeBytes: UInt64 { totalBytes > usedBytes ? totalBytes - usedBytes : 0 }

    var freeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(freeBytes), countStyle: .memory)
    }

    var appFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(appBytes), countStyle: .memory)
    }

    var wiredFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(wiredBytes), countStyle: .memory)
    }

    var compressedFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(compressedBytes), countStyle: .memory)
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

        // "App Memory" = anonymous (internal) pages minus purgeable — Activity
        // Monitor's formula. Saturating: purgeable can momentarily exceed internal
        // in the same snapshot, and UInt64 underflow would render as ~18 EB.
        let internalBytes = UInt64(stats.internal_page_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let app = internalBytes > purgeable ? internalBytes - purgeable : 0

        onSample(MemorySample(
            usedBytes: used,
            totalBytes: total,
            pressurePercent: total > 0 ? Double(used) / Double(total) * 100 : 0,
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed
        ))
    }
}

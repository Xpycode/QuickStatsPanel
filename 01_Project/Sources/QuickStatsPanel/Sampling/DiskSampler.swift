import Foundation
import IOKit

// New sampler (roadmap v1). Unlike StatsWindow's FSUsageSampler — which shells
// out to `/usr/bin/fs_usage` and needs root / Full Disk Access — this stays
// permission-free, matching the app's no-permission stance (D-002/D-003):
//   • Capacity  → `statfs("/")`                       (boot-volume free/used/total)
//   • I/O rate  → IOKit `IOBlockStorageDriver` counters (delta between ticks)

struct DiskSample: Equatable, Sendable {
    // Capacity (boot volume)
    var usedBytes: UInt64
    var freeBytes: UInt64
    var totalBytes: UInt64
    // Throughput (whole-machine block storage), bytes per second
    var readBytesPerSec: Double
    var writeBytesPerSec: Double

    static let empty = DiskSample(usedBytes: 0, freeBytes: 0, totalBytes: 0,
                                  readBytesPerSec: 0, writeBytesPerSec: 0)

    /// Drives the at-a-glance color band: a fuller disk reads "hotter".
    var usedPercent: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0
    }

    var freeFormatted: String { Self.size(freeBytes) }
    var usedFormatted: String { Self.size(usedBytes) }
    var totalFormatted: String { Self.size(totalBytes) }
    var readFormatted: String { Self.rate(readBytesPerSec) }
    var writeFormatted: String { Self.rate(writeBytesPerSec) }

    private static func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
    private static func rate(_ bytesPerSec: Double) -> String {
        // A fresh formatter with allowsNonnumericFormatting = NO so an idle disk
        // reads "0 KB/s" rather than ByteCountFormatter's spelled-out "Zero KB/s".
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(max(0, bytesPerSec))) + "/s"
    }
}

/// Polls disk capacity + cumulative block-storage I/O counters on a background
/// timer, reporting capacity directly and I/O as a per-second delta.
final class DiskSampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (DiskSample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.DiskSampler")

    /// Cumulative (read, written) byte counters from the previous tick. Like
    /// CPU ticks, the counters only grow, so we report their delta over `interval`.
    private var previousIO: (read: UInt64, written: UInt64)?

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (DiskSample) -> Void) {
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
        let capacity = Self.readCapacity()

        var readRate = 0.0
        var writeRate = 0.0
        if let io = Self.readBlockStorageBytes() {
            if let prev = previousIO {
                // Counters are monotonic; guard against wraps/resets just in case.
                let dRead = io.read >= prev.read ? io.read - prev.read : 0
                let dWrite = io.written >= prev.written ? io.written - prev.written : 0
                readRate = Double(dRead) / interval
                writeRate = Double(dWrite) / interval
            }
            previousIO = io   // first tick only seeds the baseline (rates stay 0)
        }

        onSample(DiskSample(
            usedBytes: capacity?.used ?? 0,
            freeBytes: capacity?.free ?? 0,
            totalBytes: capacity?.total ?? 0,
            readBytesPerSec: readRate,
            writeBytesPerSec: writeRate
        ))
    }

    // MARK: - Capacity (statfs)

    private static func readCapacity() -> (used: UInt64, free: UInt64, total: UInt64)? {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return nil }
        let blockSize = UInt64(fs.f_bsize)
        let total = UInt64(fs.f_blocks) * blockSize
        let free = UInt64(fs.f_bavail) * blockSize        // available to non-root
        let used = total > free ? total - free : 0
        return (used, free, total)
    }

    // MARK: - I/O counters (IOKit)

    /// Sums cumulative bytes read/written across every `IOBlockStorageDriver`.
    /// Returns nil if no driver exposes counters (so the caller leaves rates at 0).
    private static func readBlockStorageBytes() -> (read: UInt64, written: UInt64)? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWritten: UInt64 = 0
        var found = false

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                // String keys per <IOKit/storage/IOBlockStorageDriver.h>.
                if let r = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value {
                    totalRead += r; found = true
                }
                if let w = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value {
                    totalWritten += w; found = true
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return found ? (totalRead, totalWritten) : nil
    }
}

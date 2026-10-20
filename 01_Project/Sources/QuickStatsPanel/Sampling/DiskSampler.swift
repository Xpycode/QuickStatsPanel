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
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }
    /// Internal (not private) so the graph legend can format a peak rate with the
    /// exact same units as the tile value it sits beneath.
    static func rate(_ bytesPerSec: Double) -> String {
        // A fresh formatter with allowsNonnumericFormatting = NO so an idle disk
        // reads "0 KB/s" rather than ByteCountFormatter's spelled-out "Zero KB/s".
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        let safe = bytesPerSec.isFinite ? min(max(0, bytesPerSec), Double(Int64.max).nextDown) : 0
        return f.string(fromByteCount: Int64(safe)) + "/s"
    }
}

/// Polls disk capacity + cumulative block-storage I/O counters on a background
/// timer, reporting capacity directly and I/O as a per-second delta.
final class DiskSampler: @unchecked Sendable {
    private let driver: TransferSamplerDriver
    var interval: TimeInterval { driver.interval }
    var generation: UUID { driver.generation }
    var sequence: UInt64 { driver.sequence }

    init(interval: TimeInterval = 1.0,
         reader: any TransferCounterReader = DiskTransferCounterReader(),
         clock: any TransferClock = SystemTransferClock(),
         automaticallySchedules: Bool = true,
         capacityProvider: (@Sendable () -> (used: UInt64, free: UInt64, total: UInt64)?)? = nil,
         onGeneration: @escaping @Sendable (UUID) -> Void = { _ in },
         onTransferEvent: @escaping @Sendable (TransferEvent) -> Void = { _ in },
         onSampleWithIdentity: (@Sendable (DiskSample, UUID, UInt64) -> Void)? = nil,
         onSample: @escaping @Sendable (DiskSample) -> Void) {
        precondition(reader.stat == .disk)
        let capacity = capacityProvider ?? { Self.readCapacity() }
        driver = TransferSamplerDriver(interval: interval, reader: reader, clock: clock,
            automaticallySchedules: automaticallySchedules, onGeneration: onGeneration,
            onEvent: onTransferEvent) { observation, generation, sequence in
                let space = capacity()
                let sample = DiskSample(usedBytes: space?.used ?? 0, freeBytes: space?.free ?? 0,
                    totalBytes: space?.total ?? 0,
                    readBytesPerSec: observation?.interval.firstBytesPerSecond ?? 0,
                    writeBytesPerSec: observation?.interval.secondBytesPerSecond ?? 0)
                onSample(sample)
                onSampleWithIdentity?(sample, generation, sequence)
            }
    }

    @discardableResult func start() -> UUID { driver.start() }
    func stop() { driver.stop() }
    func invalidate() { driver.invalidate() }
    func sampleNow(expectedGeneration: UUID? = nil) { driver.sampleNow(expectedGeneration: expectedGeneration) }
    @discardableResult func requestReset(requestID: UUID = UUID()) -> Bool { driver.requestReset(requestID: requestID) }

    // MARK: - Capacity (statfs)

    private static func readCapacity() -> (used: UInt64, free: UInt64, total: UInt64)? {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return nil }
        guard fs.f_bsize > 0 else { return nil }
        let blockSize = UInt64(fs.f_bsize)
        let totalProduct = UInt64(fs.f_blocks).multipliedReportingOverflow(by: blockSize)
        let freeProduct = UInt64(fs.f_bavail).multipliedReportingOverflow(by: blockSize)
        guard !totalProduct.overflow, !freeProduct.overflow else { return nil }
        let total = totalProduct.partialValue
        let free = freeProduct.partialValue        // available to non-root
        let used = total > free ? total - free : 0
        return (used, free, total)
    }

}

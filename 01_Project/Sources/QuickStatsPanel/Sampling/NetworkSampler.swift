import Foundation

// New sampler (roadmap v1.1). Permission-free, matching the app's no-permission
// stance (D-002/D-003): network throughput comes from `getifaddrs(3)`, a BSD call
// that needs no entitlement. Like DiskSampler's I/O counters, the per-interface
// `ifi_ibytes`/`ifi_obytes` are cumulative-since-boot, so we report the delta
// between ticks divided by the interval (bytes per second).

struct NetworkSample: Equatable, Sendable {
    var downBytesPerSec: Double   // received  (sum of counted interfaces' ifi_ibytes delta)
    var upBytesPerSec: Double     // sent      (sum of counted interfaces' ifi_obytes delta)

    static let empty = NetworkSample(downBytesPerSec: 0, upBytesPerSec: 0)

    /// Drives the at-a-glance color band. Network has no natural 0–100, so we map
    /// total throughput against a soft reference of 100 Mbit/s (12.5 MB/s) — calm
    /// when idle, hot when saturating a fast-ish link. Tunable like Theme's bands.
    var activityPercent: Double {
        let referenceBytesPerSec = 12_500_000.0
        let total = downBytesPerSec + upBytesPerSec
        return min(100, total / referenceBytesPerSec * 100)
    }

    var downFormatted: String { Self.rate(downBytesPerSec) }
    var upFormatted: String { Self.rate(upBytesPerSec) }

    private static func rate(_ bytesPerSec: Double) -> String {
        // Mirror DiskSample: allowsNonnumericFormatting = NO so idle reads "0 KB/s"
        // rather than ByteCountFormatter's spelled-out "Zero KB/s".
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(max(0, bytesPerSec))) + "/s"
    }
}

/// Polls cumulative per-interface byte counters on a background timer and reports
/// up/down throughput as a per-second delta. Structurally identical to DiskSampler.
final class NetworkSampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (NetworkSample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.NetworkSampler")

    /// Cumulative (received, sent) byte counters from the previous tick. Monotonic,
    /// so we report their delta over `interval` — same idea as DiskSampler.previousIO.
    private var previousBytes: (received: UInt64, sent: UInt64)?

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (NetworkSample) -> Void) {
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
        var downRate = 0.0
        var upRate = 0.0
        if let bytes = Self.readInterfaceBytes() {
            if let prev = previousBytes {
                // Guard against counter wraps/resets (e.g. interface bounce).
                let dDown = bytes.received >= prev.received ? bytes.received - prev.received : 0
                let dUp = bytes.sent >= prev.sent ? bytes.sent - prev.sent : 0
                downRate = Double(dDown) / interval
                upRate = Double(dUp) / interval
            }
            previousBytes = bytes   // first tick only seeds the baseline (rates stay 0)
        }
        onSample(NetworkSample(downBytesPerSec: downRate, upBytesPerSec: upRate))
    }

    // MARK: - Interface counters (getifaddrs)

    /// Sums received/sent bytes across the interfaces `shouldCount` accepts.
    /// Returns nil if `getifaddrs` fails (so the caller leaves rates at 0).
    private static func readInterfaceBytes() -> (received: UInt64, sent: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var totalReceived: UInt64 = 0
        var totalSent: UInt64 = 0

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            // Byte counters live only on the link-layer (AF_LINK) record.
            guard let addr = ifa.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPtr = ifa.ifa_data else { continue }

            let name = String(cString: ifa.ifa_name)
            let flags = Int32(ifa.ifa_flags)
            guard shouldCount(interfaceName: name, flags: flags) else { continue }

            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            totalReceived += UInt64(data.ifi_ibytes)
            totalSent += UInt64(data.ifi_obytes)
        }
        return (totalReceived, totalSent)
    }

    /// Decides whether an interface's bytes count toward the displayed throughput.
    ///
    /// TODO(user): implement this — it's the one real design choice in this sampler.
    ///
    /// `flags` is the interface's `ifa_flags`; test bits with the `IFF_*` constants,
    /// e.g. `(flags & IFF_LOOPBACK) != 0`, `(flags & IFF_UP) != 0`.
    /// `interfaceName` is the BSD name: "lo0" (loopback), "en0"/"en1" (Ethernet/
    /// Wi-Fi), "utun*"/"ipsec*" (VPN tunnels), "bridge*", "awdl0" (AirDrop), etc.
    ///
    /// Trade-offs to weigh:
    ///   • Count *everything* → simplest, but loopback (lo0) inflates the number
    ///     with local-only traffic, and tunnels can double-count VPN bytes.
    ///   • Exclude loopback only → closest to "real network I/O" with one check.
    ///   • Only physical interfaces (en*) → cleanest "internet" reading, but misses
    ///     traffic on a VPN tunnel or a USB-tethered interface.
    /// Returning `true` for all is a valid starting point you can tighten later.
    private static func shouldCount(interfaceName: String, flags: Int32) -> Bool {
        // Start simple: count every interface, including loopback (lo0). The number
        // will read higher than "internet traffic" because local-only lo0 chatter
        // (apps talking to each other, localhost servers) is included. To tighten
        // later, drop loopback with: `(flags & IFF_LOOPBACK) == 0`.
        return true
    }
}

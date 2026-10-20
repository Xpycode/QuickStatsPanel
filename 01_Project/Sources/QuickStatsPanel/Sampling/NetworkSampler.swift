import Foundation
import SystemConfiguration

// Permission-free 64-bit physical-link counters feed exact per-source accounting.
// getifaddrs is used only for display metadata, never throughput accounting.

struct NetworkSample: Equatable, Sendable {
    var downBytesPerSec: Double   // received  (sum of counted interfaces' ifi_ibytes delta)
    var upBytesPerSec: Double     // sent      (sum of counted interfaces' ifi_obytes delta)

    // Detail card rows (2026-07-12): the primary interface, pre-composed as
    // "Wi-Fi (en0)" (or bare BSD name when no friendly name resolves), and its
    // IPv4 address. nil ⇒ no active non-loopback interface → rows hidden.
    // Deliberately NO public IP: that needs an external HTTP call, and this app
    // makes zero network requests (a privacy property worth keeping).
    var interfaceName: String? = nil
    var localIP: String? = nil

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

    /// Internal (not private) so the graph legend can format a peak rate with the
    /// exact same units as the tile value it sits beneath.
    static func rate(_ bytesPerSec: Double) -> String {
        // Mirror DiskSample: allowsNonnumericFormatting = NO so idle reads "0 KB/s"
        // rather than ByteCountFormatter's spelled-out "Zero KB/s".
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        let safe = bytesPerSec.isFinite ? min(max(0, bytesPerSec), Double(Int64.max).nextDown) : 0
        return f.string(fromByteCount: Int64(safe)) + "/s"
    }
}

/// Polls cumulative per-interface byte counters on a background timer and reports
/// up/down throughput as a per-second delta. Structurally identical to DiskSampler.
final class NetworkSampler: @unchecked Sendable {
    private let driver: TransferSamplerDriver
    var interval: TimeInterval { driver.interval }
    var generation: UUID { driver.generation }
    var sequence: UInt64 { driver.sequence }

    /// Callbacks run in order on the sampler queue; consumers should enqueue immutable values
    /// onto their owner rather than block this queue. The identity callback permits rejection
    /// of a live sample whose MainActor delivery was delayed past a restart.
    init(interval: TimeInterval = 1.0,
         reader: any TransferCounterReader = NetworkTransferCounterReader(),
         clock: any TransferClock = SystemTransferClock(),
         automaticallySchedules: Bool = true,
         metadataProvider: (@Sendable () -> (interfaceName: String?, localIP: String?))? = nil,
         onGeneration: @escaping @Sendable (UUID) -> Void = { _ in },
         onTransferEvent: @escaping @Sendable (TransferEvent) -> Void = { _ in },
         onSampleWithIdentity: (@Sendable (NetworkSample, UUID, UInt64) -> Void)? = nil,
         onSample: @escaping @Sendable (NetworkSample) -> Void) {
        precondition(reader.stat == .network)
        let metadata = metadataProvider ?? { Self.displayMetadata() }
        driver = TransferSamplerDriver(interval: interval, reader: reader, clock: clock,
            automaticallySchedules: automaticallySchedules, onGeneration: onGeneration,
            onEvent: onTransferEvent) { observation, generation, sequence in
                let details = metadata()
                let sample = NetworkSample(downBytesPerSec: observation?.interval.firstBytesPerSecond ?? 0,
                    upBytesPerSec: observation?.interval.secondBytesPerSecond ?? 0,
                    interfaceName: details.interfaceName, localIP: details.localIP)
                onSample(sample)
                onSampleWithIdentity?(sample, generation, sequence)
            }
    }

    @discardableResult func start() -> UUID { driver.start() }
    func stop() { driver.stop() }
    func invalidate() { driver.invalidate() }
    func sampleNow(expectedGeneration: UUID? = nil) { driver.sampleNow(expectedGeneration: expectedGeneration) }
    @discardableResult func requestReset(requestID: UUID = UUID()) -> Bool { driver.requestReset(requestID: requestID) }

    private static func displayMetadata() -> (interfaceName: String?, localIP: String?) {
        guard let primary = primaryInterface() else { return (nil, nil) }
        let name = localizedInterfaceNames()[primary.bsdName].map { "\($0) (\(primary.bsdName))" } ?? primary.bsdName
        return (name, primary.ip)
    }

    /// The interface shown in the detail card: up, running, non-loopback, with an
    /// IPv4 address — preferring "en0", then any "en*" (built-in before adapters),
    /// then anything else (VPN tunnel, tether). One getifaddrs walk; nil when
    /// offline. Display-only — throughput accounting independently counts physical links.
    private static func primaryInterface() -> (bsdName: String, ip: String)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var candidates: [(bsdName: String, ip: String)] = []
        for ptr in Swift.sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0,
                  (flags & IFF_LOOPBACK) == 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                              &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            candidates.append((String(cString: ifa.ifa_name), String(cString: host)))
        }
        return candidates.first { $0.bsdName == "en0" }
            ?? candidates.first { $0.bsdName.hasPrefix("en") }
            ?? candidates.first
    }

    /// BSD name → localized service name ("en0" → "Wi-Fi") from SystemConfiguration
    /// (public API, permission-free). Used only for display metadata.
    private static func localizedInterfaceNames() -> [String: String] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var map: [String: String] = [:]
        for interface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            else { continue }
            map[bsd] = name
        }
        return map
    }

    /// Decides whether an interface's bytes count toward the displayed throughput.
    ///
    /// `flags` is the interface's `ifa_flags`; test bits with the `IFF_*` constants,
    /// e.g. `(flags & IFF_LOOPBACK) != 0`, `(flags & IFF_UP) != 0`.
    /// `interfaceName` is the BSD name: "lo0" (loopback), "en0"/"en1" (Ethernet/
    /// Wi-Fi), "utun*"/"ipsec*" (VPN tunnels), "bridge*", "awdl0" (AirDrop), etc.
    ///
    /// Count active physical network links. VPN/tunnel counters represent the
    /// same payload before encryption and would double-count it alongside the
    /// underlying Wi-Fi/Ethernet interface. Peer-to-peer and software bridge
    /// links are excluded for the same reason. macOS exposes built-in, USB and
    /// Thunderbolt network adapters as `en*` devices.
    static func shouldCount(interfaceName: String, flags: Int32) -> Bool {
        guard (flags & IFF_UP) != 0,
              (flags & IFF_RUNNING) != 0,
              (flags & IFF_LOOPBACK) == 0 else { return false }
        return interfaceName.hasPrefix("en")
    }
}

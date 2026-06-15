import Foundation
import IOKit

// New sampler (roadmap v1.1). Permission-free: reading IOAccelerator
// PerformanceStatistics sits at the same trust level as the IOBlockStorageDriver
// disk-I/O read — no entitlement required. The tile is hidden when no IOAccelerator
// entry exposes a utilization key (mirrors Battery's `isPresent` gate for desktops).
// Ships native arm64 only; Rosetta translation returns no GPU accelerator.

struct GPUSample: Equatable, Sendable {
    var isAvailable: Bool        // false when no IOAccelerator exposes utilization (drives hide-the-tile)
    var utilizationPercent: Double   // 0–100 GPU load
    var deviceName: String?

    static let empty = GPUSample(isAvailable: false, utilizationPercent: 0, deviceName: nil)

    /// Feeds the app's color/tint pipeline — higher load reads "hotter".
    var loadPercent: Double { utilizationPercent }

    var percentFormatted: String { "\(Int(utilizationPercent.rounded()))%" }
}

/// Polls IOAccelerator PerformanceStatistics on a background timer, reporting
/// an absolute GPU utilization snapshot each tick. GPU reads are cheap so the
/// sampler runs continuously with no visibility gating.
final class GPUSampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (GPUSample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.GPUSampler")

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (GPUSample) -> Void) {
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
        onSample(Self.readGPU())
    }

    // MARK: - IOAccelerator (IOKit)

    /// Reads the first IOAccelerator entry that exposes GPU utilization.
    /// Returns `.empty` (isAvailable: false) when none is found.
    static func readGPU() -> GPUSample {
        // kIOAcceleratorClassName == "IOAccelerator"; the constant is not bridged to Swift,
        // so we use the literal string directly (confirmed value from IOAcceleratorFamily headers).
        guard let matching = IOServiceMatching("IOAccelerator") else { return .empty }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return .empty
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any]
            else { continue }

            // Primary key reported by Apple Silicon's AGX driver; fall back to the
            // alternative key surfaced by some Intel/AMD accelerators.
            let rawUtil: Int? = (stats["Device Utilization %"] as? Int)
                             ?? (stats["GPU Activity(%)"] as? Int)
            guard let rawUtil else { continue }

            let clamped = min(max(rawUtil, 0), 100)

            // deviceName: "model" is a raw Data blob (ASCII + NUL padding) on Apple Silicon.
            // Fall back to the IOClass string when the data key is absent.
            let deviceName: String?
            if let modelData = dict["model"] as? Data {
                deviceName = String(bytes: modelData, encoding: .ascii)?
                    .trimmingCharacters(in: .init(charactersIn: "\0"))
                    .trimmingCharacters(in: .whitespaces)
                    .nilIfEmpty
            } else {
                deviceName = dict["IOClass"] as? String
            }

            return GPUSample(isAvailable: true,
                             utilizationPercent: Double(clamped),
                             deviceName: deviceName)
        }

        return .empty
    }
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

import Foundation

// New sampler (D-017, increment 1 of the GPU/temps/fans roadmap item). Permission-free:
// reads fan rpm from the AppleSMC via the read-only `SMC` reader — no entitlement, no
// root. The tile hides on fanless Macs (FNum == 0) or any SMC read failure, mirroring
// Battery's `isPresent` gate for desktops. The fastest fan drives the headline so the
// strip surfaces the fan actually ramping under load rather than an average that smooths
// it away (see IMPLEMENTATION_PLAN open-question 1).

struct FanSample: Equatable, Sendable {
    struct Fan: Equatable, Sendable {
        var current: Double   // current speed, rpm
        var min: Double       // rated minimum, rpm
        var max: Double       // rated maximum, rpm
    }

    var hasFans: Bool         // false ⇒ hide the tile (fanless Mac / SMC failure)
    var fans: [Fan]

    static let empty = FanSample(hasFans: false, fans: [])

    /// The fan spinning fastest right now. Surfaces the one ramping under load.
    var fastest: Fan? { fans.max(by: { $0.current < $1.current }) }

    /// Headline rpm = the fastest fan's current speed (0 when no fans).
    var headlineRPM: Double { fastest?.current ?? 0 }

    var headlineFormatted: String { "\(Int(headlineRPM.rounded())) rpm" }

    /// Feeds the shared tint pipeline (0–100): a fan near full tilt reads "hot",
    /// an idle fan reads "cool". Normalizes the fastest fan's current rpm across
    /// its own [min, max] rated range so idle == 0% and full tilt == 100%.
    ///
    /// Guards:
    ///   • no fastest fan ⇒ 0 (nothing to show as hot)
    ///   • max <= min     ⇒ 0 (rated range missing/zeroed on this Mac — never
    ///                        let an unknown range read as falsely hot)
    ///   • result clamped to 0…100 (idle below rated min, or current above max)
    /// `min`/`max` here are the Fan struct's own properties, which shadow the
    /// global functions, so the clamp must qualify `Swift.min`/`Swift.max`.
    var loadPercent: Double {
        guard let f = fastest, f.max > f.min else { return 0 }
        let pct = (f.current - f.min) / (f.max - f.min) * 100
        return Swift.min(Swift.max(pct, 0), 100)
    }
}

/// Polls the AppleSMC fan keys on a background timer, reporting an absolute fan
/// snapshot each tick. SMC reads are cheap in-process calls, so the sampler runs
/// continuously with no visibility gating (only the `top` sampler is gated).
///
/// Thread-safety: the long-lived `SMC` connection is created in `start()` and
/// closed in `stop()`, while `tick()` reads it on `queue`. A `tick()` racing a
/// `stop()` is benign — `SMC.value(forKey:)` guards `conn != 0` and `close()`
/// zeroes `conn`, so a read on a just-closed connection returns nil and that
/// final sample is discarded as the sampler is torn down anyway.
final class FanSampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (FanSample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.FanSampler")
    private var smc: SMC?

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (FanSample) -> Void) {
        self.interval = interval
        self.onSample = onSample
    }

    func start() {
        smc = SMC()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        smc?.close()
        smc = nil
    }

    private func tick() {   // runs on `queue`
        guard let smc else { return }
        onSample(Self.read(smc))
    }

    /// Reads `FNum` then each fan's current/min/max. Returns `.empty` (hasFans: false)
    /// when no fans are reported or none could be read.
    static func read(_ smc: SMC) -> FanSample {
        let count = smc.fanCount
        guard count > 0 else { return .empty }
        var fans: [FanSample.Fan] = []
        fans.reserveCapacity(count)
        for i in 0..<count {
            guard let current = smc.fanSpeed(i) else { continue }
            fans.append(.init(current: current,
                              min: smc.fanMin(i) ?? 0,
                              max: smc.fanMax(i) ?? 0))
        }
        guard !fans.isEmpty else { return .empty }
        return FanSample(hasFans: true, fans: fans)
    }
}

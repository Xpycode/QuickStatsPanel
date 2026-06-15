import Foundation

// Permission-free SoC power reader (D-019). Wraps Apple's PRIVATE, un-entitled
// **IOReport** framework "Energy Model" channel group: cumulative per-subsystem
// energy counters (Joules) from which we derive watts as W = ΔJoules ÷ Δseconds —
// the no-sudo path the macmon / NeoAsitop / socpowerbud tools prove. C prototypes
// live in QuickStatsPanel-Bridging-Header.h; the symbols link via `-lIOReport`.
//
// Shape (cumulative-counter delta-per-tick, like NetworkSampler — NOT macmon's
// blocking sleep-between-two-samples): subscribe ONCE at init, then each `read()`
// deltas the current sample against the previous tick's and divides by the elapsed
// time. The first `read()` has no previous sample → returns nil (the caller shows
// `0·0 W` for that one tick — the same seeding behavior as Network/Disk).
//
// Load-bearing facts:
//   • CF accounting: every Copy/Create result is `Unmanaged<…>` we own (+1). Each
//     tick creates exactly one sample (becomes the next baseline) and one delta
//     (released same tick); the previous baseline is released as the new one is
//     stored. Net per tick: zero leaked CF objects (AC-10). The subscription and
//     subscribed-channels dict are released once in `deinit`.
//   • Unit divisor comes from each channel's RUNTIME unit label (mJ/uJ/nJ), never
//     hardcoded — macmon reads all three; a hardcoded mJ (NeoAsitop's shortcut) is
//     wrong on a chip that reports uJ/nJ (AC-2).
//   • Channels are matched by PREFIX/SUFFIX, not exact full strings, and summed —
//     so multi-die Pro/Max/Ultra parts (`DIE_0_CPU Energy`, `ANE0`, `ANE1`, …)
//     aren't under-reported (AC-8).
//   • Fragility is by design: IOReport is undocumented and channel names drift per
//     chip generation. When the Energy Model CPU/GPU channels don't resolve (Intel,
//     a renamed future chip), `isAvailable` is false and the tile hides (AC-6) —
//     it never crashes and never shows wrong zeros as if real.
//
// Thread-safety: CF dicts, `Unmanaged`, and the `OpaquePointer` subscription are
// non-Sendable and MUST stay confined to one serial queue. This type is NOT
// Sendable; its owner (PowerSampler) creates it in `start()` and only ever calls
// `read()` from its own serial timer queue — exactly how FanSampler confines `SMC`.
final class IOReportPower {

    /// One subsystem's accumulated watts for a single tick.
    typealias Reading = (cpu: Double, gpu: Double, ane: Double, dram: Double)

    /// True when the subscription resolved at least one CPU or GPU "Energy Model"
    /// channel at init. Decided ONCE (independent of whether a delta exists yet),
    /// so the tile hides on unsupported hardware (AC-6) while still showing a single
    /// `0·0 W` priming tick on supported hardware (AC-7).
    let isAvailable: Bool

    /// IOReport subscription handle (CF-backed opaque pointer). Released in `deinit`.
    private let subscription: OpaquePointer?
    /// The channels the subscription actually subscribed to (OUT param of
    /// `IOReportCreateSubscription`). Needed by every `IOReportCreateSamples` call.
    private var subscribedChannels: Unmanaged<CFMutableDictionary>?

    /// Previous tick's raw sample, held to delta against. Retained (+1) while held;
    /// released when replaced or in `deinit`.
    private var previousSample: Unmanaged<CFDictionary>?
    /// Wall-clock time of the previous sample, for the exact Δseconds (we measure dt
    /// rather than assume the timer's nominal interval — a late tick must not inflate
    /// watts).
    private var previousTime: CFAbsoluteTime?

    /// IOReport "Simple" channel format (cumulative integer counter). The Energy
    /// Model energy channels are this format; we skip anything else.
    private static let kIOReportFormatSimple: Int32 = 1

    init() {
        var resolved = false
        var sub: OpaquePointer?
        var subbedOut: Unmanaged<CFMutableDictionary>?

        // Subscribe to *all* channels, then filter to the "Energy Model" group at
        // read time (all three reference tools do this; avoids the NSString* bridging
        // of IOReportCopyChannelsInGroup). `takeRetainedValue()` consumes the +1 from
        // CopyAllChannels — ARC then releases it at end of init, mirroring macmon's
        // explicit CFRelease right after subscribing.
        if let allChannels = IOReportCopyAllChannels(0, 0) {
            var subbed: Unmanaged<CFMutableDictionary>?
            sub = IOReportCreateSubscription(nil, allChannels.takeRetainedValue(), &subbed, 0, nil)
            subbedOut = subbed

            // Probe one sample purely to decide availability. Thrown away (released)
            // — the real baseline is seeded on the first `read()` so AC-7 still emits
            // one `0·0 W` priming tick.
            if let s = sub, let subbed {
                if let probe = IOReportCreateSamples(s, subbed.takeUnretainedValue(), nil) {
                    resolved = Self.hasEnergyChannels(probe.takeUnretainedValue())
                    probe.release()
                }
            }
        }

        self.subscription = sub
        self.subscribedChannels = subbedOut
        self.isAvailable = resolved
    }

    deinit {
        previousSample?.release()
        subscribedChannels?.release()
        if let sub = subscription {
            // The subscription is a CF-backed object created with a +1; release it
            // exactly once (never per-sample). `Unmanaged.fromOpaque(...).release()`
            // is the Swift equivalent of CFRelease for an OpaquePointer-typed handle.
            Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(sub)).release()
        }
    }

    /// Take one reading. Returns nil on the very first call (no baseline yet → the
    /// caller shows `0·0 W`) and on a degenerate interval. Otherwise returns the
    /// per-subsystem watts since the previous call. MUST be called on the owner's
    /// serial queue.
    func read() -> Reading? {
        guard let sub = subscription, let subbed = subscribedChannels else { return nil }
        let now = CFAbsoluteTimeGetCurrent()
        guard let cur = IOReportCreateSamples(sub, subbed.takeUnretainedValue(), nil) else { return nil }

        // First call: no previous sample → stash this one as the baseline and report
        // nothing this tick (AC-7 seeding). `cur`'s +1 is kept alive as the baseline.
        guard let prev = previousSample, let prevTime = previousTime else {
            previousSample = cur
            previousTime = now
            return nil
        }

        let dt = now - prevTime
        // Degenerate interval (clock skew / double-fire): roll the baseline forward
        // without emitting a divide-by-tiny-dt spike.
        guard dt > 0 else {
            prev.release()
            previousSample = cur
            previousTime = now
            return nil
        }

        var acc: Reading = (0, 0, 0, 0)
        if let delta = IOReportCreateSamplesDelta(prev.takeUnretainedValue(),
                                                  cur.takeUnretainedValue(), nil) {
            IOReportIterate(delta.takeUnretainedValue()) { chan in
                autoreleasepool {
                    guard let chan,
                          (IOReportChannelGetGroup(chan) ?? "") == "Energy Model",
                          IOReportChannelGetFormat(chan) == Self.kIOReportFormatSimple
                    else { return }

                    let name = IOReportChannelGetChannelName(chan) ?? ""
                    let unit = IOReportChannelGetUnitLabel(chan) ?? ""
                    let joules = Double(IOReportSimpleGetIntegerValue(chan, 0)) / Self.divisor(forUnit: unit)
                    let watts = joules / dt

                    // Prefix/suffix routing (macmon src/metrics.rs). CPU is a suffix
                    // so multi-die "DIE_n_CPU Energy" all match; ANE/DRAM are prefixes
                    // so "ANE0"/"ANE1"/"DRAM" variants all sum. GPU is a single channel.
                    if name.hasSuffix("CPU Energy")      { acc.cpu  += watts }
                    else if name == "GPU Energy"         { acc.gpu  += watts }
                    else if name.hasPrefix("ANE")        { acc.ane  += watts }
                    else if name.hasPrefix("DRAM")       { acc.dram += watts }
                }
                return 0   // kIOReportIterOk — keep iterating
            }
            delta.release()
        }

        // Advance the baseline: drop the old previous (+1), keep `cur` as the new one.
        prev.release()
        previousSample = cur
        previousTime = now
        return acc
    }

    // MARK: - Channel helpers

    /// True if `samples` contains any "Energy Model" CPU- or GPU-energy channel.
    /// Used once at init to decide `isAvailable` (presence, not value).
    private static func hasEnergyChannels(_ samples: CFDictionary) -> Bool {
        var found = false
        IOReportIterate(samples) { chan in
            guard let chan, (IOReportChannelGetGroup(chan) ?? "") == "Energy Model" else { return 0 }
            let name = IOReportChannelGetChannelName(chan) ?? ""
            if name.hasSuffix("CPU Energy") || name == "GPU Energy" { found = true }
            return 0
        }
        return found
    }

    /// Divisor that converts a channel's raw integer counter to Joules, from the
    /// channel's RUNTIME unit label. Defaults to mJ if the label is unrecognized
    /// (the common case), never assuming a fixed unit (AC-2). Handles both Unicode
    /// micro signs (U+00B5 µ and U+03BC μ).
    private static func divisor(forUnit unit: String) -> Double {
        switch unit.trimmingCharacters(in: .whitespaces) {
        case "mJ":               return 1e3
        case "uJ", "µJ", "μJ":   return 1e6
        case "nJ":               return 1e9
        default:                 return 1e3
        }
    }
}

#if DEBUG
extension IOReportPower {
    /// De-risk spike (D-019 Wave 1 / T1.1): print live CPU/GPU/ANE/DRAM/Total watts
    /// once per second, **un-elevated**, to validate the IOReport path before the
    /// sampler and tile are built on top. Cross-check the printed numbers against
    /// `sudo powermetrics --samplers cpu_power,gpu_power -i 1000` — they must be in
    /// the same ballpark. Single-threaded throwaway; not wired into the shipping app.
    static func debugDump(ticks: Int = 6, interval: TimeInterval = 1.0) {
        let power = IOReportPower()
        print("[IOReportPower] isAvailable = \(power.isAvailable)")
        guard power.isAvailable else {
            print("[IOReportPower] Energy Model CPU/GPU channels did not resolve — tile would hide (AC-6)")
            return
        }
        for i in 0..<ticks {
            Thread.sleep(forTimeInterval: interval)
            if let r = power.read() {
                let total = r.cpu + r.gpu + r.ane + r.dram
                print(String(format: "[IOReportPower] tick %d  CPU %5.2f  GPU %5.2f  ANE %5.2f  DRAM %5.2f  TOTAL %6.2f W",
                             i, r.cpu, r.gpu, r.ane, r.dram, total))
            } else {
                print("[IOReportPower] tick \(i)  (priming — no delta yet → would show 0·0 W)")
            }
        }
    }
}
#endif

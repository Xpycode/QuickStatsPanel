import Foundation
import Darwin   // libproc + mach: proc_listallpids / proc_pid_rusage / mach_absolute_time

// iStat-Menus-style "top processes" engine (roadmap fast-follow to D-012/D-013).
//
// One enumeration pass per tick reads each process's `rusage_info_v4` ONCE and
// ranks three ways from that single struct — these feed the CPU / Memory / Disk
// tile popovers (there is no standalone "Top Process" tile anymore):
//   • CPU%      ← Δ(ri_user_time + ri_system_time)        (a rate, two-tick)
//   • Memory    ← ri_phys_footprint                        (a snapshot, one tick)
//   • Disk I/O  ← Δ(ri_diskio_bytesread + _byteswritten)   (a rate, two-tick)
//
// Processes are GROUPED BY APP: a browser/editor spawns many helper processes
// ("Google Chrome Helper (Renderer)" × N), and a flat list would just repeat the
// helper name. We attribute each PID to the *outermost `.app` bundle in its
// executable path* (how Activity Monitor groups) and sum per app, so one
// "Google Chrome" row reflects the whole browser. Permission-free: reading a
// process *path* is allowed for any process.
//
// Permission-free, same XNU same-user gate as before: the kernel lets ANY process
// be *named*, but reading its rusage works only for processes owned by THIS user
// — foreign-UID procs (root daemons, WindowServer…) return EPERM from
// `proc_pid_rusage` and are skipped. So this is honestly "top *user* apps".
//
// ⚠️ UNITS: `ri_user_time`/`ri_system_time` are in MACH ABSOLUTE TIME units, NOT
// nanoseconds — the kernel writes `rm_time_mach` straight through (XNU
// osfmk/kern/bsd_kern.c `fill_task_rusage`). On Apple Silicon a mach tick is
// ~41.67 ns, so treating them as ns reads ~24× too low. We convert via
// `mach_timebase_info` and measure wall time with `mach_absolute_time()`.

/// One app's standing in a ranking. `value`'s unit depends on which list it came
/// from: CPU percent (can exceed 100 on multicore), memory bytes, or disk
/// bytes/sec — summed across all of the app's processes.
struct ProcStat: Equatable, Sendable, Identifiable {
    let name: String
    let value: Double
    var id: String { name }
}

/// Top-N app rankings for one tick, plus formatting helpers that turn a list into
/// `(name, value)` popover rows.
struct TopProcessesSample: Equatable, Sendable {
    var byCPU: [ProcStat]      // descending CPU%
    var byMemory: [ProcStat]   // descending physical-footprint bytes
    var byDiskIO: [ProcStat]   // descending (read+write) bytes/sec

    static let empty = TopProcessesSample(byCPU: [], byMemory: [], byDiskIO: [])

    func cpuRows(_ n: Int) -> [(String, String)] {
        byCPU.prefix(n).map { ($0.name, "\(Int($0.value.rounded()))%") }
    }
    func memoryRows(_ n: Int) -> [(String, String)] {
        byMemory.prefix(n).map { ($0.name, Self.bytes($0.value)) }
    }
    func diskRows(_ n: Int) -> [(String, String)] {
        byDiskIO.prefix(n).map { ($0.name, Self.rate($0.value)) }
    }

    private static func bytes(_ v: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(max(0, v)))
    }
    private static func rate(_ v: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(max(0, v))) + "/s"
    }
}

/// Enumerates processes on a background timer and reports the top user-owned apps
/// by CPU%, memory, and disk I/O. Keeps per-PID cumulative counters between ticks
/// to turn CPU/disk into rates (the same cumulative→delta trick Disk/Network use,
/// keyed per-PID instead of per-interface), plus a per-PID app-name cache.
final class TopProcessSampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (TopProcessesSample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.TopProcessSampler")

    /// How many apps to keep per list. The popover formats the top 5; a small
    /// margin keeps the ranking stable if the leader briefly drops out.
    private static let keep = 8

    // Previous-tick state for the rate deltas.
    private var prevCPU: [pid_t: UInt64] = [:]      // mach units (user + system)
    private var prevDisk: [pid_t: UInt64] = [:]     // bytes (read + written)
    private var prevWall: UInt64 = 0                 // mach_absolute_time()

    // PID → owning-app name. An executable's path is fixed for a PID's lifetime,
    // so `proc_pidpath` runs once per process; pruned to live PIDs each tick so it
    // can't grow unbounded and a recycled PID can't carry a stale name.
    private var nameCache: [pid_t: String] = [:]

    /// Seconds per mach tick — fixed for the process lifetime, so compute once.
    private static let secondsPerMachTick: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom) / 1_000_000_000
    }()

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (TopProcessesSample) -> Void) {
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
        let wall = mach_absolute_time()
        defer { prevWall = wall }
        // First tick (prevWall == 0) only seeds baselines: memory still ranks
        // (it's a snapshot), but CPU/disk rates need two ticks.
        let elapsedSec = prevWall == 0 ? 0 : Double(wall &- prevWall) * Self.secondsPerMachTick

        // 1. Enumerate PIDs: size the buffer, then fill with slack (the set can
        //    grow between the two calls).
        let needed = proc_listallpids(nil, 0)
        guard needed > 0 else { return }
        let capacity = Int(needed) / MemoryLayout<pid_t>.stride + 32
        var pids = [pid_t](repeating: 0, count: capacity)
        let filled = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride))
        let count = Int(filled) / MemoryLayout<pid_t>.stride
        guard count > 0 else { return }

        // 2. Accumulate per *app* (grouped across helper processes). Memory is a
        //    snapshot; CPU/disk need a previous sample + a real elapsed interval.
        var memByApp: [String: Double] = [:]
        var cpuByApp: [String: Double] = [:]
        var diskByApp: [String: Double] = [:]
        var curCPU: [pid_t: UInt64] = [:];   curCPU.reserveCapacity(count)
        var curDisk: [pid_t: UInt64] = [:];  curDisk.reserveCapacity(count)
        var liveNames: [pid_t: String] = [:]; liveNames.reserveCapacity(count)

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var info = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard rc == 0 else { continue }   // EPERM for foreign-UID procs → skip

            let cpuMach = info.ri_user_time &+ info.ri_system_time
            let diskBytes = info.ri_diskio_bytesread &+ info.ri_diskio_byteswritten
            curCPU[pid] = cpuMach
            curDisk[pid] = diskBytes

            // App group name — reuse last tick's cache or resolve+cache now.
            let app = nameCache[pid] ?? Self.appGroupName(forPath: Self.path(of: pid))
            liveNames[pid] = app

            if info.ri_phys_footprint > 0 {
                memByApp[app, default: 0] += Double(info.ri_phys_footprint)
            }
            guard elapsedSec > 0 else { continue }
            if let p = prevCPU[pid], cpuMach > p {
                // mach÷mach would cancel the timebase, but we convert to seconds so
                // the formula is explicit and matches the disk one.
                cpuByApp[app, default: 0] += Double(cpuMach &- p) * Self.secondsPerMachTick / elapsedSec * 100
            }
            if let p = prevDisk[pid], diskBytes > p {
                diskByApp[app, default: 0] += Double(diskBytes &- p) / elapsedSec
            }
        }
        prevCPU = curCPU
        prevDisk = curDisk
        nameCache = liveNames   // prune to live PIDs

        // 3. Rank each grouped map. Thresholds drop idle-noise apps from the rate
        //    lists (memory always shows its top apps).
        onSample(TopProcessesSample(
            byCPU: Self.rank(cpuByApp, min: 0.5),
            byMemory: Self.rank(memByApp, min: 0),
            byDiskIO: Self.rank(diskByApp, min: 1)
        ))
    }

    /// Sort an `app → value` map descending, drop sub-threshold apps, keep the top.
    private static func rank(_ byApp: [String: Double], min: Double) -> [ProcStat] {
        let stats = byApp
            .filter { $0.value >= min }
            .map { ProcStat(name: $0.key, value: $0.value) }
        return Array(stats.sorted { $0.value > $1.value }.prefix(keep))
    }

    /// Attribute an executable path to a readable group name for the popover list:
    ///   1. OUTERMOST `.app` bundle (first `.app` from the root) — helpers nested in
    ///      deeper `.app`s roll up to the top-level app; its name is already human.
    ///   2. `.xpc` / `.appex` service bundle (no `.app` ancestor, e.g. WebKit's
    ///      `com.apple.WebKit.WebContent.xpc`) — prettify the bundle id into words.
    ///   3. Plain executable (CLI tool / daemon) — its file name, but climbing past
    ///      version-like and generic launcher dirs (e.g. a tool installed as
    ///      `…/claude/versions/2.1.165` → "claude", not the bare version "2.1.165").
    ///
    /// Note: XPC services like WebKit content processes can't be attributed to the
    /// host app (Safari/Chrome) from the path — that needs the private
    /// responsibility API (see D-013). So all browsers' content procs group into a
    /// single readable "Web Content" row, summed but not split by host.
    static func appGroupName(forPath path: String) -> String {
        let parts = path.split(separator: "/")
        if let app = parts.first(where: { $0.hasSuffix(".app") }) {
            return String(app.dropLast(4))   // strip ".app"
        }
        if let svc = parts.first(where: { $0.hasSuffix(".xpc") || $0.hasSuffix(".appex") }) {
            return prettify(svc.hasSuffix(".appex") ? svc.dropLast(6) : svc.dropLast(4))
        }
        // Plain executable: usually the file name is meaningful, but version-named
        // binaries (`…/versions/2.1.165`) and generic launcher dirs aren't — climb
        // to the nearest informative ancestor.
        var i = parts.count - 1
        while i > 0 {
            let c = parts[i]
            if isVersionLike(c) || Self.genericPathComponents.contains(String(c)) { i -= 1; continue }
            return String(c)
        }
        return parts.last.map(String.init) ?? "—"
    }

    /// Path components that never make a good display name on their own — skipped
    /// while climbing a version-named executable path.
    private static let genericPathComponents: Set<String> = [
        "versions", "version", "bin", "sbin", "libexec", "current",
        "MacOS", "Contents", "Resources",
    ]

    /// A bare version token like `2.1.165` (digits and dots only) — not a name.
    private static func isVersionLike(_ s: Substring) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isNumber || $0 == "." } && s.contains(where: \.isNumber)
    }

    /// Turn a service-bundle id into a readable label:
    /// `com.apple.WebKit.WebContent` → last dot-component `WebContent` → split
    /// camelCase → `Web Content`. Non-dotted names are just camelCase-split.
    private static func prettify(_ id: Substring) -> String {
        let leaf = id.split(separator: ".").last ?? id
        var out = ""
        for ch in leaf {
            if ch.isUppercase, let prev = out.last, !prev.isUppercase || prev.isNumber {
                out.append(" ")
            }
            out.append(ch)
        }
        return out.isEmpty ? String(id) : out
    }

    /// Full executable path via `proc_pidpath` ("" if it can't be read).
    private static func path(of pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
            return String(cString: buf)
        }
        return ""
    }
}

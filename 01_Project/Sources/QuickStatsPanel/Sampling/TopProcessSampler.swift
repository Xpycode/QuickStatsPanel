import Foundation
import Darwin   // proc_pidpath for app grouping

// Activity-Monitor-style "top processes" engine, sourced from `/usr/bin/top`.
//
// WHY top instead of in-process libproc: `proc_pid_rusage` / `proc_pidinfo` are
// same-user gated by XNU — they return EPERM for processes we don't own, so an
// in-process sampler can NEVER see the heavy system processes (WindowServer,
// kernel_task) that dominate CPU on an otherwise-idle Mac. `top` is an
// Apple-signed binary carrying the private `com.apple.private.proc_info-list`
// entitlement (which third-party apps can't get), so it reports *every* process.
// We shell out and parse it — no permission prompt, since the entitlement rides
// with the `top` binary, not us. (Revises D-013, which was honestly limited to
// "top user apps". Requires the sandbox to be OFF — it is; see entitlements.)
//
// One `top -l 2 -s 1` run per tick yields two samples; we parse the SECOND, whose
// %CPU is the instantaneous delta top measured over the 1s window (so we do no
// rate math ourselves). Two rankings come from that one parse:
//   • CPU%    ← top's %CPU column (already a rate)
//   • Memory  ← top's MEM column (a snapshot)
// Disk I/O per process is intentionally absent: top has no such column (only the
// entitled API behind Activity Monitor's Disk tab does), so that list is retired.
//
// GROUPED BY APP: a browser spawns many helpers; we attribute each PID to the
// outermost `.app` in its `proc_pidpath` (permission-free for any PID) and sum, so
// "Google Chrome" is one row, not 20 helpers. Pathless procs (kernel_task) fall
// back to top's own COMMAND text.
//
// Lifecycle: this sampler is EXPENSIVE (spawns top, which itself costs CPU), so —
// unlike the cheap in-process samplers — it runs ONLY while the panel is visible.
// StatsStore starts/stops it from the panel's visibility signal.

/// One app's standing in a ranking. `value` is CPU percent or memory bytes,
/// summed across the app's processes.
struct ProcStat: Equatable, Sendable, Identifiable {
    let name: String
    let value: Double
    var id: String { name }
}

/// Top-N app rankings for one tick, plus formatters that turn a list into
/// `(name, value)` popover rows.
struct TopProcessesSample: Equatable, Sendable {
    var byCPU: [ProcStat]      // descending CPU%
    var byMemory: [ProcStat]   // descending memory bytes

    static let empty = TopProcessesSample(byCPU: [], byMemory: [])

    func cpuRows(_ n: Int) -> [(String, String)] {
        byCPU.prefix(n).map { ($0.name, Self.percent($0.value)) }
    }
    func memoryRows(_ n: Int) -> [(String, String)] {
        byMemory.prefix(n).map { ($0.name, Self.bytes($0.value)) }
    }

    /// One-decimal, locale-aware percent (e.g. "2,8%") — matches Activity Monitor's
    /// precision so an idle machine doesn't read as a wall of "0%".
    private static func percent(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return (f.string(from: NSNumber(value: v)) ?? "0,0") + "%"
    }
    private static func bytes(_ v: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(max(0, v)))
    }
}

/// Runs `top` on a background timer and reports the top apps by CPU% and memory.
/// Keeps a per-PID app-name cache so `proc_pidpath` runs once per process.
final class TopProcessSampler {
    private let interval: TimeInterval
    private let onSample: @Sendable (TopProcessesSample) -> Void
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "QuickStatsPanel.TopProcessSampler")

    /// How many apps to keep per list. The popover formats the top 10; a small
    /// margin keeps the ranking stable if the leader briefly drops out.
    private static let keep = 12

    /// PID → owning-app name. An executable's path is fixed for a PID's lifetime,
    /// so `proc_pidpath` runs once per process; pruned to live PIDs each tick.
    private var nameCache: [pid_t: String] = [:]

    /// Set when `stop()` is called so an in-flight `top` run (≤1s) doesn't emit a
    /// stale sample after the panel has hidden.
    private var cancelled = false

    init(interval: TimeInterval = 1.0, onSample: @escaping @Sendable (TopProcessesSample) -> Void) {
        self.interval = interval
        self.onSample = onSample
    }

    func start() {
        cancelled = false
        // Each tick blocks ~1s (top -l 2 -s 1), so space ticks to leave a gap and
        // avoid back-to-back top spawns; never faster than ~2s for process lists.
        let cadence = max(2.0, interval)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: cadence)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        self.timer = t
    }

    func stop() {
        cancelled = true
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard let run = runTop() else { return }
        let rows = Self.parseLastSample(run.output)
        guard !rows.isEmpty else { return }

        // Group across helper processes and sum per app.
        var cpuByApp: [String: Double] = [:]
        var memByApp: [String: Double] = [:]
        var liveNames: [pid_t: String] = [:]
        liveNames.reserveCapacity(rows.count)
        for r in rows {
            // Skip our own measurement probe — the `top` we spawned reports itself,
            // an observer-effect artifact the user shouldn't see (filter by the exact
            // PID, so a user's own terminal `top` still shows).
            if r.pid == run.pid { continue }
            let app = nameCache[r.pid] ?? Self.appGroupName(forPath: Self.path(of: r.pid),
                                                            fallback: r.command)
            liveNames[r.pid] = app
            if r.cpu > 0 { cpuByApp[app, default: 0] += r.cpu }
            if r.mem > 0 { memByApp[app, default: 0] += r.mem }
        }
        nameCache = liveNames   // prune to live PIDs

        guard !cancelled else { return }
        onSample(TopProcessesSample(byCPU: Self.rank(cpuByApp),
                                    byMemory: Self.rank(memByApp)))
    }

    /// Run `top -l 2` and return its stdout plus the PID we spawned (so the caller
    /// can filter our own probe out of the results). nil if it can't be launched.
    /// Blocks until top exits (~1s for the 2nd sample) — fine on our serial queue.
    private func runTop() -> (output: String, pid: pid_t)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        // command LAST so names with spaces don't break column splitting; -l 2 for
        // an instantaneous 2nd sample; -s 1 sets its 1s window.
        p.arguments = ["-l", "2", "-s", "1", "-o", "cpu", "-stats", "pid,cpu,mem,command"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let pid = p.processIdentifier
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return (output, pid)
    }

    /// Parse the rows of the LAST sample in top's output (the instantaneous one).
    /// top prints `[header…][PID …][rows…]` per sample; after the final "PID"
    /// header line, every remaining line is a process row.
    static func parseLastSample(_ output: String) -> [(pid: pid_t, cpu: Double, mem: Double, command: String)] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard let hdr = lines.lastIndex(where: { $0.hasPrefix("PID") }) else { return [] }
        var rows: [(pid: pid_t, cpu: Double, mem: Double, command: String)] = []
        for i in (hdr + 1)..<lines.count {
            if let r = parseRow(lines[i]) { rows.append(r) }
        }
        return rows
    }

    /// One top row: `<pid> <cpu> <mem> <command…>`. nil for headers/blank lines.
    static func parseRow(_ line: Substring) -> (pid: pid_t, cpu: Double, mem: Double, command: String)? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 4,
              let pid = pid_t(parts[0]),
              let cpu = Double(parts[1]) else { return nil }
        let mem = parseMem(parts[2])
        let command = parts[3...].joined(separator: " ")
        return (pid, cpu, mem, command)
    }

    /// Parse a top MEM token ("13M", "3360K", "1.2G", maybe a trailing "+"/"-")
    /// into bytes. Binary units, matching top.
    static func parseMem(_ s: Substring) -> Double {
        var num = ""
        var unit: Character = "B"
        for ch in s {
            if ch.isNumber || ch == "." { num.append(ch) }
            else if ch.isLetter { unit = ch; break }   // first letter is the unit
        }
        guard let v = Double(num) else { return 0 }
        switch unit {
        case "K", "k": return v * 1024
        case "M", "m": return v * 1024 * 1024
        case "G", "g": return v * 1024 * 1024 * 1024
        case "T", "t": return v * 1024 * 1024 * 1024 * 1024
        default:       return v   // "B"
        }
    }

    /// Sort an `app → value` map descending and keep the top.
    private static func rank(_ byApp: [String: Double]) -> [ProcStat] {
        byApp.map { ProcStat(name: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
            .prefix(keep)
            .map { $0 }
    }

    /// Attribute an executable path to a readable group name for the popover list:
    ///   1. OUTERMOST `.app` bundle (helpers nested deeper roll up to the top app).
    ///   2. `.xpc` / `.appex` service bundle → prettified bundle id.
    ///   3. Plain executable → its file name, climbing past version-like / generic
    ///      launcher dirs (e.g. `…/claude/versions/2.1.165` → "claude").
    /// `fallback` (top's COMMAND) is used when there's no path — e.g. kernel_task.
    static func appGroupName(forPath path: String, fallback: String) -> String {
        guard !path.isEmpty else { return fallback }
        let parts = path.split(separator: "/")
        if let app = parts.first(where: { $0.hasSuffix(".app") }) {
            return String(app.dropLast(4))
        }
        if let svc = parts.first(where: { $0.hasSuffix(".xpc") || $0.hasSuffix(".appex") }) {
            return prettify(svc.hasSuffix(".appex") ? svc.dropLast(6) : svc.dropLast(4))
        }
        var i = parts.count - 1
        while i > 0 {
            let c = parts[i]
            if isVersionLike(c) || Self.genericPathComponents.contains(String(c)) { i -= 1; continue }
            return String(c)
        }
        return parts.last.map(String.init) ?? fallback
    }

    /// Path components that never make a good display name on their own.
    private static let genericPathComponents: Set<String> = [
        "versions", "version", "bin", "sbin", "libexec", "current",
        "MacOS", "Contents", "Resources",
    ]

    /// A bare version token like `2.1.165` (digits and dots only).
    private static func isVersionLike(_ s: Substring) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isNumber || $0 == "." } && s.contains(where: \.isNumber)
    }

    /// `com.apple.WebKit.WebContent` → `WebContent` → `Web Content`.
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

    /// Full executable path via `proc_pidpath` ("" if it can't be read — e.g.
    /// kernel_task). Permission-free for any PID.
    private static func path(of pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
            return String(cString: buf)
        }
        return ""
    }
}

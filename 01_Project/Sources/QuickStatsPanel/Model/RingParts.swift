import Foundation

// Per-part content for sub-rings (D-036): CPU cores, Disk volumes, Network interfaces,
// Temperature sensors. Pure values built from plain inputs; the part list and its order are
// frozen per summon, never sorted by value.

// MARK: - Part

/// One sub-ring segment.
struct RingPart: Equatable, Sendable {
    /// Stable key used to match later readings to this frozen position.
    let id: String
    /// Position in the frozen list; kept when the part later goes missing.
    let index: Int
    let group: String
    let name: String
    let valueText: String
    /// Gauge fraction on the parent's scale: usage, used fraction, download half, or heat
    /// fraction. Nil when unavailable.
    let fraction: Double?
    /// Upload half (Network only).
    let secondFraction: Double?
    /// Underlying measure for aggregation: percent (CPU), used fraction 0...1 (Disk), bytes per
    /// second down (Network) or degrees C (Temperature). Nil when unavailable.
    let raw: Double?
    /// Upload bytes per second (Network only).
    let rawSecondary: Double?
    let isAvailable: Bool
    /// Boot container marker (Disk); the segment that must equal the Disk reading.
    let isBoot: Bool
    /// Source parts represented: 2 for paired hyperthreads, N for a collapsed group.
    let memberCount: Int

    func unavailable() -> RingPart {
        RingPart(id: id, index: index, group: group, name: name, valueText: "Unavailable",
                 fraction: nil, secondFraction: nil, raw: nil, rawSecondary: nil,
                 isAvailable: false, isBoot: isBoot, memberCount: memberCount)
    }

    func reindexed(_ newIndex: Int) -> RingPart {
        RingPart(id: id, index: newIndex, group: group, name: name, valueText: valueText,
                 fraction: fraction, secondFraction: secondFraction, raw: raw, rawSecondary: rawSecondary,
                 isAvailable: isAvailable, isBoot: isBoot, memberCount: memberCount)
    }
}

/// A later reading for a part, matched by `id`.
struct RingPartReading: Equatable, Sendable {
    let id: String
    let valueText: String
    let fraction: Double
    let secondFraction: Double?
    let raw: Double
    let rawSecondary: Double?
}

// MARK: - Aggregation

/// How a stat's parts agree with its parent reading.
enum RingPartAgreement: Equatable, Sendable {
    /// Core usages average to the CPU total.
    case mean
    /// Interface rates sum to the Network reading.
    case sum
    /// The hottest segment equals the Temperature fill.
    case hottest
    /// The boot container segment equals the Disk reading.
    case bootContainer

    var statement: String {
        switch self {
        case .mean:          return "Core usages average to the CPU total."
        case .sum:           return "Interface rates sum to the Network reading."
        case .hottest:       return "The hottest segment equals the Temperature fill."
        case .bootContainer: return "The boot container segment equals the Disk reading."
        }
    }
}

extension StatKind {
    /// The agreement rule for stats that have parts; nil for stats without a sub-ring.
    var ringPartAgreement: RingPartAgreement? {
        switch self {
        case .cpu:     return .mean
        case .disk:    return .bootContainer
        case .network: return .sum
        case .temps:   return .hottest
        default:       return nil
        }
    }
}

/// A parent-equivalent value computed from parts: percent (CPU), used fraction (Disk),
/// bytes per second down and up (Network), or degrees C (Temperature).
struct RingPartAggregate: Equatable, Sendable {
    let primary: Double
    let secondary: Double?
}

enum RingPartAggregation {
    /// Mean of `raw` over available parts, weighted by `memberCount`.
    static func mean(_ parts: [RingPart]) -> Double? {
        var weighted = 0.0, weight = 0.0
        for p in parts where p.isAvailable {
            guard let r = p.raw else { continue }
            weighted += r * Double(p.memberCount)
            weight += Double(p.memberCount)
        }
        return weight > 0 ? weighted / weight : nil
    }

    /// Sum of download and upload `raw` values over available parts.
    static func sum(_ parts: [RingPart]) -> RingPartAggregate? {
        let usable = parts.filter { $0.isAvailable && $0.raw != nil }
        guard !usable.isEmpty else { return nil }
        return RingPartAggregate(primary: usable.reduce(0) { $0 + ($1.raw ?? 0) },
                                 secondary: usable.reduce(0) { $0 + ($1.rawSecondary ?? 0) })
    }

    /// Highest `raw` over available parts.
    static func hottest(_ parts: [RingPart]) -> Double? {
        parts.filter { $0.isAvailable }.compactMap(\.raw).max()
    }

    /// `raw` of the available boot container part.
    static func bootContainer(_ parts: [RingPart]) -> Double? {
        parts.first { $0.isBoot && $0.isAvailable }?.raw
    }

    static func aggregate(_ parts: [RingPart], agreement: RingPartAgreement) -> RingPartAggregate? {
        switch agreement {
        case .mean:          return mean(parts).map { RingPartAggregate(primary: $0, secondary: nil) }
        case .sum:           return sum(parts)
        case .hottest:       return hottest(parts).map { RingPartAggregate(primary: $0, secondary: nil) }
        case .bootContainer: return bootContainer(parts).map { RingPartAggregate(primary: $0, secondary: nil) }
        }
    }
}

// MARK: - Part list

enum RingNoSubRingReason: Equatable, Sendable {
    case fewerThanTwoParts(count: Int)
}

/// A frozen part list for one stat.
struct RingPartList: Equatable, Sendable {
    /// Parts shown in a sub-ring at most, after collapsing.
    static let maximumParts = 32

    let stat: StatKind
    let parts: [RingPart]
    /// Parts before pairing and collapsing; the parent total is computed from all of them.
    let sourceCount: Int
    /// Parent value computed from every source part before any collapse. It does not change
    /// when the largest group collapses.
    let parentAggregate: RingPartAggregate?

    /// Group names in fixed display order, each once.
    var groups: [String] {
        var seen: [String] = []
        for p in parts where !seen.contains(p.group) { seen.append(p.group) }
        return seen
    }

    /// Fewer than two parts means no sub-ring; the detail card still opens.
    var hasSubRing: Bool { parts.count >= 2 }

    var noSubRingReason: RingNoSubRingReason? {
        hasSubRing ? nil : .fewerThanTwoParts(count: parts.count)
    }

    /// True when parts were collapsed to fit `maximumParts`.
    var isCollapsed: Bool { parts.contains { $0.memberCount > 1 && $0.id.hasSuffix(RingPartBuilder.collapsedSuffix) } }

    static func empty(_ stat: StatKind) -> RingPartList {
        RingPartList(stat: stat, parts: [], sourceCount: 0, parentAggregate: nil)
    }

    /// Aggregate of the parts as shown, using the stat's agreement rule. For collapsed lists
    /// compare against `parentAggregate` instead.
    func aggregate() -> RingPartAggregate? {
        stat.ringPartAgreement.flatMap { RingPartAggregation.aggregate(parts, agreement: $0) }
    }

    /// Applies a later reading while keeping every position (AC-38). A part with no matching
    /// reading keeps its index, group and name and reports unavailable. Readings for parts
    /// that were not in the frozen list are ignored.
    func updating(with readings: [RingPartReading]) -> RingPartList {
        let byID = Dictionary(readings.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let updated = parts.map { part -> RingPart in
            guard let r = byID[part.id] else { return part.unavailable() }
            return RingPart(id: part.id, index: part.index, group: part.group, name: part.name,
                            valueText: r.valueText, fraction: r.fraction, secondFraction: r.secondFraction,
                            raw: r.raw, rawSecondary: r.rawSecondary, isAvailable: true,
                            isBoot: part.isBoot, memberCount: part.memberCount)
        }
        return RingPartList(stat: stat, parts: updated, sourceCount: sourceCount, parentAggregate: parentAggregate)
    }
}

// MARK: - Inputs

struct RingCoreInput: Equatable, Sendable {
    let id: String
    let name: String
    /// Core class: "Efficiency", "Performance", "Super"; use "Cores" where the chip has none.
    let group: String
    let usagePercent: Double
    /// Shared by hyperthread siblings; nil when the core has no sibling.
    let physicalIndex: Int?

    init(id: String, name: String, group: String, usagePercent: Double, physicalIndex: Int? = nil) {
        self.id = id
        self.name = name
        self.group = group
        self.usagePercent = usagePercent
        self.physicalIndex = physicalIndex
    }
}

struct RingVolumeInput: Equatable, Sendable {
    let id: String
    let name: String
    let usedBytes: UInt64
    let totalBytes: UInt64
    let isBoot: Bool
}

struct RingInterfaceInput: Equatable, Sendable {
    let id: String
    let name: String
    let downBytesPerSec: Double
    let upBytesPerSec: Double
}

struct RingSensorInput: Equatable, Sendable {
    /// Role: CPU, GPU, SoC, SSD, Battery; anything else becomes "Other".
    let group: String
    let name: String
    let celsius: Double
}

// MARK: - Builder

enum RingPartBuilder {

    static let coreGroupOrder = ["Efficiency", "Performance", "Super"]
    static let sensorGroupOrder = ["CPU", "GPU", "SoC", "SSD", "Battery"]
    static let otherSensorGroup = "Other"
    static let volumeGroup = "Volumes"
    static let interfaceGroup = "Interfaces"
    static let collapsedSuffix = "#collapsed"

    // MARK: Per stat

    /// Cores grouped by class in fixed class order, input order kept inside a class. Above 32
    /// cores, hyperthread siblings pair first (mean usage), then the largest group collapses.
    static func cpu(cores: [RingCoreInput], groupOrder: [String] = coreGroupOrder) -> RingPartList {
        let usable = cores.filter { $0.usagePercent.isFinite }
        let all = usable.map { c -> RingPart in
            let pct = Swift.min(Swift.max(c.usagePercent, 0), 100)
            return part(id: c.id, group: c.group, name: c.name, text: percentText(pct),
                        fraction: pct / 100, raw: pct)
        }
        let parent = RingPartAggregation.mean(all).map { RingPartAggregate(primary: $0, secondary: nil) }
        let needsPairing = usable.count > RingPartList.maximumParts
        let working = needsPairing ? pairHyperthreads(usable) : usable
        let paired = working.map { c -> RingPart in
            let pct = Swift.min(Swift.max(c.usagePercent, 0), 100)
            let members = needsPairing
                ? usable.filter { $0.group == c.group && c.physicalIndex != nil && $0.physicalIndex == c.physicalIndex }.count
                : 1
            return part(id: c.id, group: c.group, name: c.name, text: percentText(pct),
                        fraction: pct / 100, raw: pct, memberCount: Swift.max(members, 1))
        }
        return finish(.cpu, parts: paired, groupOrder: groupOrder, sourceCount: usable.count, parent: parent)
    }

    /// Volumes in input order. Callers pass visible local volumes with shared containers
    /// already merged.
    static func disk(volumes: [RingVolumeInput]) -> RingPartList {
        let all = volumes.filter { $0.totalBytes > 0 }.map { v -> RingPart in
            let used = Swift.min(Double(v.usedBytes) / Double(v.totalBytes), 1)
            return part(id: v.id, group: volumeGroup, name: v.name, text: percentText(used * 100),
                        fraction: used, raw: used, isBoot: v.isBoot)
        }
        let parent = RingPartAggregation.bootContainer(all).map { RingPartAggregate(primary: $0, secondary: nil) }
        return finish(.disk, parts: all, groupOrder: [volumeGroup], sourceCount: all.count, parent: parent)
    }

    /// Exactly the interfaces the Network total sums, in input order.
    static func network(interfaces: [RingInterfaceInput]) -> RingPartList {
        let all = interfaces.map { i -> RingPart in
            let down = Swift.max(i.downBytesPerSec, 0), up = Swift.max(i.upBytesPerSec, 0)
            return part(id: i.id, group: interfaceGroup, name: i.name,
                        text: "\u{2193}\(NetworkSample.rate(down)) \u{2191}\(NetworkSample.rate(up))",
                        fraction: RingRateScale.fraction(bytesPerSecond: down),
                        secondFraction: RingRateScale.fraction(bytesPerSecond: up),
                        raw: down, rawSecondary: up)
        }
        return finish(.network, parts: all, groupOrder: [interfaceGroup], sourceCount: all.count,
                      parent: RingPartAggregation.sum(all))
    }

    /// Sensors grouped by role. Readings outside 0...110 degrees C are dropped; same-named
    /// sensors in a role merge to their hottest reading, so the hottest segment still equals
    /// the hottest valid reading.
    static func temperature(sensors: [RingSensorInput]) -> RingPartList {
        var order: [String] = []                 // "group\u{0}name" in first-seen order
        var merged: [String: RingSensorInput] = [:]
        for s in sensors where RingGaugeMapper.isValidTemperature(s.celsius) {
            let group = sensorGroupOrder.contains(s.group) ? s.group : otherSensorGroup
            let key = "\(group)\u{0}\(s.name)"
            if let existing = merged[key] {
                if s.celsius > existing.celsius { merged[key] = RingSensorInput(group: group, name: s.name, celsius: s.celsius) }
            } else {
                merged[key] = RingSensorInput(group: group, name: s.name, celsius: s.celsius)
                order.append(key)
            }
        }
        let all = order.compactMap { merged[$0] }.map { s -> RingPart in
            part(id: "\(s.group)/\(s.name)", group: s.group, name: s.name,
                 text: String(format: "%.0f\u{00B0}C", s.celsius),
                 fraction: RingGaugeMapper.temperatureFraction(celsius: s.celsius), raw: s.celsius)
        }
        return finish(.temps, parts: all, groupOrder: sensorGroupOrder + [otherSensorGroup],
                      sourceCount: all.count, parent: RingPartAggregation.hottest(all).map { RingPartAggregate(primary: $0, secondary: nil) })
    }

    // MARK: Shared steps

    /// Arranges parts into fixed group order (stable inside a group), collapses to at most 32,
    /// and assigns indices.
    static func finish(_ stat: StatKind,
                       parts: [RingPart],
                       groupOrder: [String],
                       sourceCount: Int,
                       parent: RingPartAggregate?) -> RingPartList {
        let grouped = arrange(parts, groupOrder: groupOrder)
        let collapsed = collapse(grouped)
        let indexed = collapsed.enumerated().map { $1.reindexed($0) }
        return RingPartList(stat: stat, parts: indexed, sourceCount: sourceCount, parentAggregate: parent)
    }

    /// Group order is the given order, then unlisted groups in first-seen order. Never sorts
    /// by value.
    static func arrange(_ parts: [RingPart], groupOrder: [String]) -> [RingPart] {
        var order = groupOrder
        for p in parts where !order.contains(p.group) { order.append(p.group) }
        return order.flatMap { g in parts.filter { $0.group == g } }
    }

    /// Collapses the largest group to its highest member, repeatedly, until at most 32 parts
    /// remain. Ties pick the earlier group. If every group is already a single segment and the
    /// list is still too long, the trailing segments merge into one "Other" segment.
    static func collapse(_ input: [RingPart]) -> [RingPart] {
        var parts = input
        while parts.count > RingPartList.maximumParts {
            var groups: [String] = []
            for p in parts where !groups.contains(p.group) { groups.append(p.group) }
            var target: String?
            var best = 1
            for g in groups {
                let n = parts.filter { $0.group == g }.count
                if n > best { best = n; target = g }
            }
            guard let group = target else { break }
            let members = parts.filter { $0.group == group }
            let top = members.max { weight($0) < weight($1) } ?? members[0]
            let rep = RingPart(id: top.id + collapsedSuffix, index: top.index, group: group, name: top.name,
                               valueText: top.valueText, fraction: top.fraction, secondFraction: top.secondFraction,
                               raw: top.raw, rawSecondary: top.rawSecondary, isAvailable: top.isAvailable,
                               isBoot: members.contains { $0.isBoot }, memberCount: members.reduce(0) { $0 + $1.memberCount })
            var replaced = false
            parts = parts.compactMap { p in
                guard p.group == group else { return p }
                if replaced { return nil }
                replaced = true
                return rep
            }
        }
        if parts.count > RingPartList.maximumParts {
            let keep = Array(parts.prefix(RingPartList.maximumParts - 1))
            let tail = Array(parts.dropFirst(RingPartList.maximumParts - 1))
            let top = tail.max { weight($0) < weight($1) } ?? tail[0]
            let rep = RingPart(id: top.id + collapsedSuffix, index: top.index, group: "Other", name: top.name,
                               valueText: top.valueText, fraction: top.fraction, secondFraction: top.secondFraction,
                               raw: top.raw, rawSecondary: top.rawSecondary, isAvailable: top.isAvailable,
                               isBoot: tail.contains { $0.isBoot }, memberCount: tail.reduce(0) { $0 + $1.memberCount })
            parts = keep + [rep]
        }
        return parts
    }

    /// Pairs hyperthread siblings (same class, same physical index) into one logical segment
    /// showing their mean usage. Cores without a sibling pass through in place.
    static func pairHyperthreads(_ cores: [RingCoreInput]) -> [RingCoreInput] {
        var out: [RingCoreInput] = []
        var slot: [String: Int] = [:]
        var counts: [Int: Int] = [:]
        for c in cores {
            guard let phys = c.physicalIndex else { out.append(c); continue }
            let key = "\(c.group)\u{0}\(phys)"
            if let i = slot[key] {
                let n = counts[i] ?? 1
                let mean = (out[i].usagePercent * Double(n) + c.usagePercent) / Double(n + 1)
                out[i] = RingCoreInput(id: out[i].id, name: out[i].name, group: out[i].group,
                                       usagePercent: mean, physicalIndex: phys)
                counts[i] = n + 1
            } else {
                slot[key] = out.count
                counts[out.count] = 1
                out.append(c)
            }
        }
        return out
    }

    // MARK: Helpers

    private static func weight(_ p: RingPart) -> Double { (p.raw ?? 0) + (p.rawSecondary ?? 0) }

    private static func percentText(_ percent: Double) -> String { "\(Int(percent.rounded()))%" }

    private static func part(id: String, group: String, name: String, text: String,
                             fraction: Double, secondFraction: Double? = nil,
                             raw: Double, rawSecondary: Double? = nil,
                             isBoot: Bool = false, memberCount: Int = 1) -> RingPart {
        RingPart(id: id, index: 0, group: group, name: name, valueText: text,
                 fraction: fraction, secondFraction: secondFraction, raw: raw, rawSecondary: rawSecondary,
                 isAvailable: true, isBoot: isBoot, memberCount: memberCount)
    }
}

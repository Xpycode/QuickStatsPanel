import Foundation

/// First = downloaded/read, second = uploaded/written. Hardware identities never persist.
enum TransferStat: UInt8, Codable, CaseIterable, Sendable { case network, disk }

struct TransferBytes: Codable, Equatable, Sendable {
    let first: UInt64
    let second: UInt64
    static let zero = TransferBytes(first: 0, second: 0)

    func adding(_ other: Self) -> Self? {
        let a = first.addingReportingOverflow(other.first)
        let b = second.addingReportingOverflow(other.second)
        guard !a.overflow, !b.overflow else { return nil }
        return Self(first: a.partialValue, second: b.partialValue)
    }
}

enum TransferCoverage: UInt8, Codable, Sendable { case complete, partial, missing }

struct TransferTimestamp: Equatable, Sendable {
    let continuousTime: TimeInterval
    let wallTime: Date
    /// Validated OS boot-session identity, not a hardware identifier.
    let bootID: String
    var isValid: Bool { continuousTime.isFinite && continuousTime >= 0 && wallTime.timeIntervalSince1970.isFinite && !bootID.isEmpty }
}

protocol TransferClock: Sendable { func now() -> TransferTimestamp }

/// A network incarnation changes on observed removal/reappearance or link identity change.
/// Disk registry IDs are boot-scoped. Neither identity is serialized into history.
enum TransferSourceID: Hashable, Sendable {
    case network(index: UInt32, name: String, incarnation: UInt64)
    case disk(registryID: UInt64)
}

struct TransferSourceCounter: Equatable, Sendable {
    let id: TransferSourceID
    /// nil means this enumerated source was unreadable in either direction.
    let bytes: TransferBytes?
}

enum TransferEnumeration: Sendable { case complete, failed }

struct TransferCounterSnapshot: Sendable {
    let stat: TransferStat
    let generation: UUID
    /// Strictly increasing within one sampler run, including ordered reset markers.
    let sequence: UInt64
    let timestamp: TransferTimestamp
    let enumeration: TransferEnumeration
    let sources: [TransferSourceCounter]
}

/// Implementations are invoked only on the owning sampler serial queue. A successful empty
/// network read is known offline; a disk read without physical sources is unavailable.
protocol TransferCounterReader: Sendable {
    var stat: TransferStat { get }
    func read(generation: UUID, sequence: UInt64, timestamp: TransferTimestamp) -> TransferCounterSnapshot
}

/// Persist only these aggregate intervals plus a checkpoint clock anchor. Explicit packed
/// encoding is 40 bytes: four 8-byte scalars, stat/coverage bytes, six reserved zero bytes.
/// Never persist this struct's raw memory, whose padding is unspecified.
struct TransferInterval: Codable, Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let bytes: TransferBytes
    let stat: TransferStat
    let coverage: TransferCoverage
    static let packedSize = 40
    var duration: TimeInterval { end - start }
    var isValid: Bool { start.isFinite && end.isFinite && start >= 0 && end > start && (coverage != .missing || bytes == .zero) }
    var firstBytesPerSecond: Double { duration > 0 ? Double(bytes.first) / duration : 0 }
    var secondBytesPerSecond: Double { duration > 0 ? Double(bytes.second) / duration : 0 }
}

struct TransferObservation: Sendable {
    let generation: UUID
    let sequence: UInt64
    let timestamp: TransferTimestamp
    let interval: TransferInterval
    /// Overflow is unavailable accounting, never wrapped or silently saturated.
    let accountingOverflow: Bool
}

/// The sampler emits a boundary observation first, then this marker at a higher sequence,
/// on the same queue. The owner resets only this stat after accounting that observation.
struct TransferResetMarker: Sendable {
    let stat: TransferStat
    let generation: UUID
    let sequence: UInt64
    let timestamp: TransferTimestamp
    let requestID: UUID
}

enum TransferEvent: Sendable {
    case observation(TransferObservation)
    case reset(TransferResetMarker)
}

enum TransferCadence {
    static let minimum: TimeInterval = 0.25
    static let maximum: TimeInterval = 5
    static func effective(_ proposed: TimeInterval) -> TimeInterval {
        proposed.isFinite ? min(maximum, max(minimum, proposed)) : 1
    }
    static func maximumObservedGap(for interval: TimeInterval) -> TimeInterval { max(10, 3 * effective(interval)) }
}

/// Public IOStorageProtocolCharacteristics keys classify a provider, rather than its displayed
/// product name. Virtual/file/RAM layers can duplicate backing physical I/O and are excluded.
/// Unknown metadata must be reported unreadable, preserving honest coverage.
enum TransferStorageLayer: Equatable, Sendable {
    case physical, excludedVirtual, unknown
    static func classify(interconnect: String?, location: String?) -> Self {
        if interconnect == "Virtual Interface" || location == "File" || location == "RAM" { return .excludedVirtual }
        let supportedPhysical = ["ATA", "SATA", "SAS", "ATAPI", "USB", "FireWire", "Secure Digital",
                                 "SCSI Parallel Interface", "Fibre Channel Interface", "PCI", "PCI-Express", "Apple Fabric"]
        guard let interconnect, supportedPhysical.contains(interconnect),
              let location, ["Internal", "External", "Internal/External"].contains(location) else { return .unknown }
        return .physical
    }
}

/// Queue-confined value owner; each source contributes only if its complete paired baseline
/// was observed in the immediately preceding snapshot. Healthy peers survive source failure.
struct TransferAccounting {
    let stat: TransferStat
    let generation: UUID
    let interval: TimeInterval
    private(set) var lastSequence: UInt64?
    private var previousTime: TransferTimestamp?
    private var baselines: [TransferSourceID: TransferBytes] = [:]
    private var previousIDs = Set<TransferSourceID>()
    private var previousEnumerationSucceeded = false

    init(stat: TransferStat, generation: UUID, interval: TimeInterval) {
        self.stat = stat; self.generation = generation; self.interval = TransferCadence.effective(interval)
    }

    /// Call on sleep/wake, interval replacement, stop/start and explicit discontinuities.
    mutating func invalidateBaselines() {
        baselines.removeAll(keepingCapacity: true)
        previousIDs.removeAll(keepingCapacity: true)
        previousEnumerationSucceeded = false
    }

    mutating func consume(_ snapshot: TransferCounterSnapshot) -> TransferObservation? {
        guard snapshot.stat == stat, snapshot.generation == generation,
              snapshot.timestamp.isValid,
              lastSequence.map({ snapshot.sequence > $0 }) ?? true else { return nil }
        if let previousTime, snapshot.timestamp.bootID != previousTime.bootID { return nil }
        let elapsed = previousTime.map { snapshot.timestamp.continuousTime - $0.continuousTime }
        guard elapsed.map({ $0.isFinite && $0 > 0 }) ?? true else { return nil }
        lastSequence = snapshot.sequence
        let oldTime = previousTime
        previousTime = snapshot.timestamp

        var current: [TransferSourceID: TransferBytes] = [:]
        var ids = Set<TransferSourceID>()
        var duplicated = Set<TransferSourceID>()
        var uncertain = snapshot.enumeration == .failed
        for source in snapshot.sources {
            if !ids.insert(source.id).inserted { duplicated.insert(source.id); uncertain = true }
            if let bytes = source.bytes { current[source.id] = bytes } else { uncertain = true }
        }
        // Never count one duplicated identity twice, even when duplicate values differ.
        for id in duplicated { current.removeValue(forKey: id) }
        let enumerationSucceeded = snapshot.enumeration == .complete
        if !enumerationSucceeded { current.removeAll(); ids.removeAll() }
        let oldBaselines = baselines
        let oldIDs = previousIDs
        let oldEnumerationSucceeded = previousEnumerationSucceeded
        baselines = current; previousIDs = ids; previousEnumerationSucceeded = enumerationSucceeded
        guard let oldTime, let elapsed else { return nil }

        let gap = elapsed > TransferCadence.maximumObservedGap(for: interval)
        var sum = TransferBytes.zero
        var accepted = 0
        var overflow = false
        if !gap && enumerationSucceeded {
            for (id, bytes) in current {
                guard let old = oldBaselines[id], bytes.first >= old.first, bytes.second >= old.second else {
                    uncertain = true; continue
                }
                let delta = TransferBytes(first: bytes.first - old.first, second: bytes.second - old.second)
                guard let next = sum.adding(delta) else { overflow = true; break }
                sum = next; accepted += 1
            }
        }
        let knownOffline = stat == .network && enumerationSucceeded && oldEnumerationSucceeded && ids.isEmpty && oldIDs.isEmpty
        let coverage: TransferCoverage
        if gap || overflow || !enumerationSucceeded || (accepted == 0 && !knownOffline) {
            coverage = .missing; sum = .zero
        } else if uncertain || ids != oldIDs || !oldEnumerationSucceeded || accepted != ids.count {
            coverage = .partial
        } else { coverage = .complete }
        return TransferObservation(generation: generation, sequence: snapshot.sequence, timestamp: snapshot.timestamp,
            interval: TransferInterval(start: oldTime.continuousTime, end: snapshot.timestamp.continuousTime,
                bytes: sum, stat: stat, coverage: coverage), accountingOverflow: overflow)
    }
}

/// At most four periodic and one reset-boundary record/sec/stat. Reset admission must be
/// cadence-limited/coalesced by the sampler; ordinary records are never silently truncated.
/// The second allowance is deliberately conservative and includes reset-triggered observations.
enum TransferResourceBudget {
    static let minimumResetInterval: TimeInterval = 1
    static let maximumIntervalsPerStat = 345_600 + 86_400 + 1
    static let maximumBytes = 64 * 1024 * 1024
    static let segmentDuration: TimeInterval = 300
    static let maximumRecordsPerSegmentPerStat = 1_200 + 300 + 2
    static let segmentHeaderAllowance = 4 * 1024
    static let checkpointMetadataAllowance = 512 * 1024
    static let temporaryAndQuarantineAllowance = 512 * 1024
    static var packedDayBytes: Int { 2 * maximumIntervalsPerStat * TransferInterval.packedSize }
    static var proposedDiskCeiling: Int { packedDayBytes + 2 * 289 * segmentHeaderAllowance + 2 * checkpointMetadataAllowance + temporaryAndQuarantineAllowance + 2 * maximumRecordsPerSegmentPerStat * TransferInterval.packedSize }
}

import Foundation

enum TransferTimelineWarning: String, Codable, Hashable, Sendable {
    case invalidHistory, historyClockAmbiguous, resourceLimit, accountingOverflow
}

struct TransferCumulativeEpoch: Codable, Equatable, Sendable {
    var bytes: TransferBytes
    var startedAt: Date
    var accountingOverflow: Bool
}

struct TransferTimelineWatermark: Codable, Equatable, Sendable {
    var generation: UUID?
    var admission: UInt64
    var sequence: UInt64?
    var lastEventTime: TimeInterval?
}

/// Maps the saved raw OS continuous clock onto the retained timeline's nonnegative axis.
struct TransferTimelineAnchor: Codable, Equatable, Sendable {
    var continuousTime: TimeInterval
    var timelineTime: TimeInterval
    var wallTime: Date
    var bootID: String
}

/// ArraySlice shares sealed backing storage. Taking a snapshot does not copy a day of records.
/// A repository should encode these individually, retaining stable IDs for unchanged segments;
/// the first segment's slice may shrink during retention and must be encoded as that slice.
struct TransferTimelineSegment: Sendable {
    var id: UUID
    var stat: TransferStat
    var records: ArraySlice<TransferInterval>
    var isSealed: Bool
    /// Applied lazily after a reboot. Repositories can persist this scalar in the segment
    /// reference or stream translated records; never allocate a translated full-day array.
    var timeOffset: TimeInterval = 0

    func placed(_ record: TransferInterval) -> TransferInterval {
        guard timeOffset != 0 else { return record }
        return TransferInterval(start: record.start + timeOffset, end: record.end + timeOffset,
            bytes: record.bytes, stat: record.stat, coverage: record.coverage)
    }
}

struct TransferTimelineStatSnapshot: Sendable {
    var stat: TransferStat
    var cumulative: TransferCumulativeEpoch
    var watermark: TransferTimelineWatermark
    var segments: [TransferTimelineSegment]
}

struct TransferTimelineSnapshot: Sendable {
    var anchor: TransferTimelineAnchor
    var stats: [TransferTimelineStatSnapshot]
    var warnings: Set<TransferTimelineWarning>
}

struct TransferPeriodSlot: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    var bytes: TransferBytes
    var fullyMeasuredDuration: TimeInterval
    var partialDuration: TimeInterval
    var accountingOverflow: Bool
    var duration: TimeInterval { end - start }
    var missingDuration: TimeInterval { max(0, duration - fullyMeasuredDuration - partialDuration) }
    var firstBytesPerSecond: Double { duration > 0 ? Double(bytes.first) / duration : 0 }
    var secondBytesPerSecond: Double { duration > 0 ? Double(bytes.second) / duration : 0 }
}

struct TransferPeriodResult: Sendable {
    let stat: TransferStat
    let start: TimeInterval
    let end: TimeInterval
    let bytes: TransferBytes
    let fullyMeasuredDuration: TimeInterval
    let partialDuration: TimeInterval
    let hasBoundaryEstimate: Bool
    let accountingOverflow: Bool
    let slots: [TransferPeriodSlot]
    var duration: TimeInterval { end - start }
    var missingDuration: TimeInterval { max(0, duration - fullyMeasuredDuration - partialDuration) }
}

/// Foundation-only value owner. All mutation/query work belongs on one serial history queue.
/// No timers, hardware reads, filesystem access, or MainActor work is performed here.
struct TransferTimeline: Sendable {
    static let retention: TimeInterval = 86_400
    static let maximumSegmentsPerStat = 290
    private var bootID: String
    private var axisOffset: TimeInterval = 0
    private var states: [TransferTimelineStatSnapshot]
    private var counts = [0, 0]
    private(set) var warnings = Set<TransferTimelineWarning>()

    init(now: TransferTimestamp) {
        bootID = now.bootID
        states = TransferStat.allCases.map {
            TransferTimelineStatSnapshot(stat: $0,
                cumulative: TransferCumulativeEpoch(bytes: .zero, startedAt: now.wallTime, accountingOverflow: false),
                watermark: TransferTimelineWatermark(generation: nil, admission: 0, sequence: nil, lastEventTime: nil), segments: [])
        }
        if !now.isValid || now.bootID.utf8.count > 128 { warnings.insert(.historyClockAmbiguous) }
    }

    init(restoring snapshot: TransferTimelineSnapshot, now: TransferTimestamp) {
        self.init(now: now)
        warnings.formUnion(snapshot.warnings)
        let anchor = snapshot.anchor
        let validAnchor = now.isValid && now.bootID.utf8.count <= 128 && anchor.continuousTime.isFinite && anchor.continuousTime >= 0
            && anchor.timelineTime.isFinite && anchor.timelineTime >= anchor.continuousTime
            && anchor.wallTime.timeIntervalSince1970.isFinite && !anchor.bootID.isEmpty && anchor.bootID.utf8.count <= 128
        let sameBoot = anchor.bootID == now.bootID
        var mappingValid = validAnchor
        var shift: Double = 0
        if validAnchor && sameBoot {
            mappingValid = now.continuousTime >= anchor.continuousTime
            axisOffset = anchor.timelineTime - anchor.continuousTime
        } else if validAnchor {
            let age = now.wallTime.timeIntervalSince(anchor.wallTime)
            // Date has submicrosecond representation error around contemporary epochs.
            mappingValid = age.isFinite && age >= 0 && age + 0.000_001 >= now.continuousTime
            // Make room for retained preboot history even immediately after OS boot.
            // The longest possible edge interval is accounted below before translating.
            var longest: Double = 0
            for state in snapshot.stats.prefix(2) {
                for segment in state.segments.prefix(Self.maximumSegmentsPerStat) {
                    for record in segment.records.prefix(TransferResourceBudget.maximumRecordsPerSegmentPerStat) where record.isValid {
                        longest = max(longest, record.duration)
                    }
                }
            }
            axisOffset = max(0, Self.retention + min(Self.retention, longest) - now.continuousTime)
            shift = now.continuousTime + axisOffset - age - anchor.timelineTime
            mappingValid = mappingValid && shift.isFinite
        }
        mappingValid = mappingValid && axisOffset.isFinite && (now.continuousTime + axisOffset).isFinite
        if !mappingValid {
            // A malformed persisted offset must not poison future live collection.
            axisOffset = 0; shift = 0; warnings.insert(.historyClockAmbiguous)
        }
        guard snapshot.stats.count == TransferStat.allCases.count,
              Set(snapshot.stats.map(\.stat)).count == TransferStat.allCases.count else {
            warnings.insert(.invalidHistory); return
        }
        for saved in snapshot.stats {
            let i = Int(saved.stat.rawValue)
            if saved.cumulative.startedAt.timeIntervalSince1970.isFinite {
                states[i].cumulative = saved.cumulative
            } else { warnings.insert(.invalidHistory) }
            // Keep the admission number for the next owner, but no saved generation is live.
            states[i].watermark.admission = saved.watermark.admission
            guard mappingValid else { continue }
            guard saved.segments.count <= Self.maximumSegmentsPerStat,
                  saved.segments.allSatisfy({ $0.records.count <= TransferResourceBudget.maximumRecordsPerSegmentPerStat }),
                  saved.segments.reduce(0, { $0 + $1.records.count }) <= TransferResourceBudget.maximumIntervalsPerStat else {
                warnings.insert(.resourceLimit); continue
            }
            var valid = saved.watermark.lastEventTime.map { $0.isFinite && $0 >= 0 && $0 <= anchor.timelineTime } ?? true
            if saved.watermark.sequence != nil && saved.watermark.generation == nil { valid = false }
            var previousEnd: Double?
            var ids = Set<UUID>()
            for segment in saved.segments {
                if segment.stat != saved.stat || segment.records.isEmpty || !segment.timeOffset.isFinite || !ids.insert(segment.id).inserted { valid = false; break }
                for raw in segment.records {
                    let record = segment.placed(raw)
                    if !record.isValid || record.stat != saved.stat || record.end > anchor.timelineTime
                        || (previousEnd.map { record.start < $0 } ?? false) { valid = false; break }
                    previousEnd = record.end
                }
                if !valid { break }
            }
            if let lastEvent = saved.watermark.lastEventTime, let previousEnd, lastEvent < previousEnd { valid = false }
            guard valid else { warnings.insert(.invalidHistory); continue }
            let cutoff = now.continuousTime + axisOffset - Self.retention
            for segment in saved.segments {
                var copy = segment
                copy.timeOffset += shift
                copy.isSealed = true
                copy.records = copy.records.drop { copy.placed($0).end <= cutoff }
                if !copy.records.isEmpty {
                    if copy.placed(copy.records.first!).start < 0 { valid = false; break }
                    states[i].segments.append(copy); counts[i] += copy.records.count
                }
            }
            if !valid { states[i].segments.removeAll(); counts[i] = 0; warnings.insert(.historyClockAmbiguous) }
            // Resume the final bounded chunk, rather than adding one chunk per app reopen.
            // Give the mutable chunk a new identity so prior checkpoint references stay immutable.
            if !states[i].segments.isEmpty {
                let last = states[i].segments.count - 1
                states[i].segments[last].isSealed = false
                states[i].segments[last].id = UUID()
            }
            // Preserve temporal exclusion against loaded records, but admit a fresh sampler only.
            states[i].watermark.lastEventTime = saved.watermark.lastEventTime.map { max(0, $0 + shift) }
                ?? states[i].segments.last.flatMap { segment in segment.records.last.map { segment.placed($0).end } }
        }
        maintenance(now: now)
    }

    func cumulative(for stat: TransferStat) -> TransferCumulativeEpoch { states[Int(stat.rawValue)].cumulative }
    func retainedIntervalCount(for stat: TransferStat) -> Int { counts[Int(stat.rawValue)] }
    func watermark(for stat: TransferStat) -> TransferTimelineWatermark { states[Int(stat.rawValue)].watermark }

    /// Admission is an explicit lifecycle action, never inferred from incoming callbacks.
    /// After load use watermark(for:).admission + 1; admissions themselves never wrap.
    @discardableResult mutating func admitGeneration(_ generation: UUID, for stat: TransferStat, admission: UInt64) -> Bool {
        let i = Int(stat.rawValue)
        guard admission > states[i].watermark.admission, generation != states[i].watermark.generation else { return false }
        states[i].watermark.generation = generation
        states[i].watermark.admission = admission
        states[i].watermark.sequence = nil
        return true
    }

    @discardableResult mutating func ingest(_ event: TransferEvent) -> Bool {
        let stat: TransferStat; let generation: UUID; let sequence: UInt64; let timestamp: TransferTimestamp
        switch event {
        case .observation(let observation):
            stat = observation.interval.stat; generation = observation.generation; sequence = observation.sequence; timestamp = observation.timestamp
        case .reset(let marker):
            stat = marker.stat; generation = marker.generation; sequence = marker.sequence; timestamp = marker.timestamp
        }
        let i = Int(stat.rawValue), axisTime = timestamp.continuousTime + axisOffset
        guard timestamp.isValid, timestamp.bootID == bootID, axisTime.isFinite,
              generation == states[i].watermark.generation,
              states[i].watermark.sequence.map({ sequence > $0 }) ?? true,
              states[i].watermark.lastEventTime.map({ axisTime >= $0 }) ?? true else { return false }
        switch event {
        case .observation(let observation):
            let interval = observation.interval
            guard interval.isValid, interval.end == timestamp.continuousTime,
                  states[i].watermark.lastEventTime.map({ interval.start + axisOffset >= $0 }) ?? true else { return false }
            let mapped = TransferInterval(start: interval.start + axisOffset, end: axisTime,
                bytes: interval.bytes, stat: stat, coverage: interval.coverage)
            guard mapped.isValid else { return false }
            maintenance(now: timestamp)
            // Missing coverage is represented by absence; no potentially huge sleep-gap record.
            if mapped.coverage != .missing {
                let sameSegment = states[i].segments.last.map { segment in
                    !segment.isSealed && segment.records.last.map {
                        floor(segment.placed($0).end / TransferResourceBudget.segmentDuration) == floor(mapped.end / TransferResourceBudget.segmentDuration)
                    } == true
                } ?? false
                let hasRoom = counts[i] < TransferResourceBudget.maximumIntervalsPerStat
                    && (sameSegment ? states[i].segments.last!.records.count < TransferResourceBudget.maximumRecordsPerSegmentPerStat
                        : states[i].segments.count < Self.maximumSegmentsPerStat)
                if hasRoom {
                    if sameSegment {
                        let last = states[i].segments.count - 1, offset = states[i].segments[last].timeOffset
                        let stored = TransferInterval(start: mapped.start - offset, end: mapped.end - offset,
                            bytes: mapped.bytes, stat: stat, coverage: mapped.coverage)
                        states[i].segments[last].records.append(stored)
                    } else {
                        if !states[i].segments.isEmpty { states[i].segments[states[i].segments.count - 1].isSealed = true }
                        states[i].segments.append(TransferTimelineSegment(id: UUID(), stat: stat, records: [mapped][...], isSealed: false))
                    }
                    counts[i] += 1
                } else {
                    // An unsupported producer cadence cannot consume unbounded memory or erase
                    // independently accepted cumulative bytes. Surface the resource failure.
                    warnings.insert(.resourceLimit)
                }
            }
            if let added = states[i].cumulative.bytes.adding(mapped.bytes) {
                states[i].cumulative.bytes = added
            } else { states[i].cumulative.accountingOverflow = true; warnings.insert(.accountingOverflow) }
            if observation.accountingOverflow { states[i].cumulative.accountingOverflow = true; warnings.insert(.accountingOverflow) }
        case .reset:
            // A boundary observation, if available, must already have reached this owner.
            guard states[i].watermark.sequence == nil || (states[i].watermark.lastEventTime.map({ axisTime == $0 }) ?? true) else { return false }
            states[i].cumulative = TransferCumulativeEpoch(bytes: .zero, startedAt: timestamp.wallTime, accountingOverflow: false)
            maintenance(now: timestamp)
        }
        states[i].watermark.sequence = sequence
        states[i].watermark.lastEventTime = axisTime
        return true
    }

    mutating func maintenance(now: TransferTimestamp) {
        guard now.isValid, now.bootID == bootID else { return }
        let cutoff = now.continuousTime + axisOffset - Self.retention
        for i in states.indices {
            while let first = states[i].segments.first, let raw = first.records.last, first.placed(raw).end <= cutoff {
                counts[i] -= first.records.count; states[i].segments.removeFirst()
            }
            guard !states[i].segments.isEmpty else { continue }
            var removed = 0
            for record in states[i].segments[0].records {
                if states[i].segments[0].placed(record).end > cutoff { break }; removed += 1
            }
            if removed > 0 {
                states[i].segments[0].records.removeFirst(removed); counts[i] -= removed
            }
        }
    }

    mutating func snapshot(now: TransferTimestamp) -> TransferTimelineSnapshot {
        maintenance(now: now)
        return TransferTimelineSnapshot(anchor: TransferTimelineAnchor(continuousTime: now.continuousTime,
            timelineTime: now.continuousTime + axisOffset, wallTime: now.wallTime, bootID: bootID), stats: states, warnings: warnings)
    }

    /// Queries are half-open. A cumulative allocation function at every edge guarantees that
    /// adjacent ranges and display slots conserve all integer bytes, independently of resolution.
    func query(stat: TransferStat, now: TransferTimestamp, duration proposedDuration: TimeInterval, slotCount proposedCount: Int = 120) -> TransferPeriodResult {
        let duration = proposedDuration.isFinite ? min(Self.retention, max(0, proposedDuration)) : 0
        let mappedEnd = now.continuousTime + axisOffset
        let end = now.isValid && now.bootID == bootID && mappedEnd.isFinite ? mappedEnd : 0
        let start = end - duration, count = duration > 0 ? min(120, max(1, proposedCount)) : 0
        var slots = (0..<count).map { index in
            TransferPeriodSlot(start: start + duration * Double(index) / Double(count),
                end: index + 1 == count ? end : start + duration * Double(index + 1) / Double(count),
                bytes: .zero, fullyMeasuredDuration: 0, partialDuration: 0, accountingOverflow: false)
        }
        var total = TransferBytes.zero, complete: Double = 0, partial: Double = 0
        var estimate = false, overflow = states[Int(stat.rawValue)].cumulative.accountingOverflow
        if count > 0 {
            for segment in states[Int(stat.rawValue)].segments {
                guard let first = segment.records.first, let last = segment.records.last, segment.placed(first).start < end, segment.placed(last).end > start else { continue }
                for raw in segment.records {
                    let record = segment.placed(raw)
                    guard record.start < end && record.end > start else { continue }
                    let lower = max(start, record.start), upper = min(end, record.end)
                    let bytes = Self.bytes(record, from: lower, to: upper)
                    if let sum = total.adding(bytes) { total = sum } else { overflow = true }
                    if record.coverage == .complete { complete += upper - lower }
                    if record.coverage == .partial { partial += upper - lower }
                    if lower != record.start || upper != record.end { estimate = true }
                    // Start one slot early: inverse floating-point division can round a
                    // nextDown boundary up, otherwise dropping a tiny but byteful overlap.
                    let index = max(0, min(count - 1, Int(((lower - start) / duration * Double(count)).rounded(.down))) - 1)
                    for slot in index..<count {
                        if slots[slot].start >= upper { break }
                        let a = max(lower, slots[slot].start), b = min(upper, slots[slot].end)
                        guard b > a else { continue }
                        if let sum = slots[slot].bytes.adding(Self.bytes(record, from: a, to: b)) { slots[slot].bytes = sum }
                        else { slots[slot].accountingOverflow = true; overflow = true }
                        if record.coverage == .complete { slots[slot].fullyMeasuredDuration += b - a }
                        if record.coverage == .partial { slots[slot].partialDuration += b - a }
                    }
                }
            }
        }
        return TransferPeriodResult(stat: stat, start: start, end: end, bytes: total,
            fullyMeasuredDuration: min(duration, complete), partialDuration: min(max(0, duration - complete), partial),
            hasBoundaryEstimate: estimate, accountingOverflow: overflow, slots: slots)
    }

    private static func bytes(_ record: TransferInterval, from lower: Double, to upper: Double) -> TransferBytes {
        TransferBytes(first: allocation(record.bytes.first, elapsed: upper - record.start, duration: record.duration)
            - allocation(record.bytes.first, elapsed: lower - record.start, duration: record.duration),
            second: allocation(record.bytes.second, elapsed: upper - record.start, duration: record.duration)
            - allocation(record.bytes.second, elapsed: lower - record.start, duration: record.duration))
    }

    /// floor(bytes × elapsed / duration) using the exact binary significands of the elapsed
    /// values. A 128-bit product avoids lossy UInt64→Double conversion and max-value traps.
    private static func allocation(_ bytes: UInt64, elapsed: Double, duration: Double) -> UInt64 {
        guard elapsed > 0 else { return 0 }
        guard elapsed < duration else { return bytes }
        let scale = 4_503_599_627_370_496.0 // 2^52; normalized Double significands are exact integers here.
        let numerator = UInt64(elapsed.significand * scale)
        let denominator = UInt64(duration.significand * scale)
        let exponentDifference = max(0, duration.exponent - elapsed.exponent)
        let left = min(11, exponentDifference), right = exponentDifference - left
        var product = bytes.multipliedFullWidth(by: numerator)
        if right >= 128 { return 0 }
        if right >= 64 { product = (high: 0, low: product.high >> (right - 64)) }
        else if right > 0 { product = (high: product.high >> right, low: (product.low >> right) | (product.high << (64 - right))) }
        return (denominator << left).dividingFullWidth(product).quotient
    }
}

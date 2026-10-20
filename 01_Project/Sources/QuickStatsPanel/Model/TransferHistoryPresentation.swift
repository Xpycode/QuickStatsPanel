import Foundation

enum TransferHistoryPeriod: Int, CaseIterable, Hashable, Sendable {
    case minute, hour, day
    var duration: TimeInterval {
        switch self { case .minute: return 60; case .hour: return 3_600; case .day: return 86_400 }
    }
    var title: String {
        switch self { case .minute: return "1 min"; case .hour: return "1 hour"; case .day: return "24 hours" }
    }
    /// Relative elapsed time deliberately makes no civil-clock promise across clock changes.
    var axisLabels: [String] {
        switch self {
        case .minute: return ["−1 min", "−30 s", "Now"]
        case .hour: return ["−1 h", "−30 min", "Now"]
        case .day: return ["−24 h", "−12 h", "Now"]
        }
    }
}

/// Storage owners map their status into this display contract; the presentation has no I/O.
enum TransferHistorySaveState: Equatable, Sendable {
    case loading
    case saved(Date)
    case unsaved(lastSaved: Date?)
    case saving(lastSaved: Date?)
    case failed(lastSaved: Date?, message: String)
    case recovered(lastSaved: Date?, message: String)
}

enum TransferHistoryFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]

    /// Decimal arithmetic preserves UInt64.max; no unsigned-to-signed cast or Double roundtrip.
    static func bytes(_ value: UInt64, locale: Locale = .current) -> String {
        var unit = 0, divisor: UInt64 = 1
        while unit < units.count - 1 && value / divisor >= 1_000 { unit += 1; divisor *= 1_000 }
        let decimal = NSDecimalNumber(mantissa: value, exponent: 0, isNegative: false)
            .dividing(by: NSDecimalNumber(mantissa: divisor, exponent: 0, isNegative: false))
        return "\(number(decimal, locale: locale, fractionalDigits: unit == 0 ? 0 : 1)) \(units[unit])"
    }

    static func exactBytes(_ value: UInt64, locale: Locale = .current) -> String {
        "\(number(NSDecimalNumber(mantissa: value, exponent: 0, isNegative: false), locale: locale, fractionalDigits: 0)) B"
    }

    static func rate(_ value: Double, locale: Locale = .current) -> String {
        guard value.isFinite, value >= 0 else { return "Unavailable" }
        var magnitude = value, unit = 0
        while magnitude >= 1_000 && unit < units.count - 1 { magnitude /= 1_000; unit += 1 }
        return "\(number(NSNumber(value: magnitude), locale: locale, fractionalDigits: unit == 0 ? 0 : 1)) \(units[unit])/s"
    }

    static func duration(_ value: TimeInterval, locale: Locale = .current) -> String {
        guard value.isFinite, value > 0 else { return "0 s" }
        let unit: String, scaled: Double
        if value >= 3_600 { unit = "h"; scaled = value / 3_600 }
        else if value >= 60 { unit = "min"; scaled = value / 60 }
        else { unit = "s"; scaled = value }
        // Sub-second coverage must not silently appear as a measured zero.
        if scaled < 0.1 { return "<0.1 \(unit)" }
        return "\(number(NSNumber(value: scaled), locale: locale, fractionalDigits: 1)) \(unit)"
    }

    static func date(_ value: Date, locale: Locale, timeZone: TimeZone) -> String {
        guard value.timeIntervalSince1970.isFinite else { return "Time unavailable" }
        let formatter = DateFormatter()
        formatter.locale = locale; formatter.timeZone = timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: value)
    }

    private static func number(_ value: NSNumber, locale: Locale, fractionalDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = value.doubleValue >= 1e24 ? .scientific : .decimal
        formatter.maximumFractionDigits = fractionalDigits
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: value) ?? "Unavailable"
    }

    /// The card reserves bounded warning rows; help/accessibility can repeat this full sentence.
    static func bounded(_ text: String) -> String {
        String(text.split(whereSeparator: { $0.isNewline }).joined(separator: " ").prefix(180))
    }
}

struct TransferDirectionTotal: Equatable, Sendable {
    let label: String
    let marker: String
    let value: String
    let exactValue: String
}

struct TransferPairedTotals: Equatable, Sendable {
    let first: TransferDirectionTotal
    let second: TransferDirectionTotal
}

struct TransferHistoryGraphSlot: Equatable, Sendable {
    let startFraction: Double
    let endFraction: Double
    let firstRate: Double
    let secondRate: Double
    let missingFraction: Double
    let partialFraction: Double
    let accountingUnavailable: Bool
}

/// A bounded, immutable render packet. Construct off-main with the query, then publish as a value.
struct TransferHistoryGraph: Equatable, Sendable {
    let slots: [TransferHistoryGraphSlot]
    let firstPeak: Double
    let secondPeak: Double
    let firstPeakText: String
    let secondPeakText: String
    let firstLabel: String
    let secondLabel: String
    let firstMarker: String
    let secondMarker: String
    let axisLabels: [String]

    init(result: TransferPeriodResult, period: TransferHistoryPeriod,
         firstPeak: Double? = nil, secondPeak: Double? = nil, locale: Locale = .current) {
        func fraction(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        let duration = result.duration
        slots = result.slots.prefix(120).map { slot in
            let validDuration = slot.duration.isFinite && slot.duration > 0
            let measured = validDuration && slot.fullyMeasuredDuration + slot.partialDuration > 0
            let first = slot.firstBytesPerSecond, second = slot.secondBytesPerSecond
            return TransferHistoryGraphSlot(
                startFraction: duration > 0 ? fraction((slot.start - result.start) / duration) : 0,
                endFraction: duration > 0 ? fraction((slot.end - result.start) / duration) : 0,
                firstRate: measured && first.isFinite && first >= 0 ? first : 0,
                secondRate: measured && second.isFinite && second >= 0 ? second : 0,
                missingFraction: validDuration ? fraction(slot.missingDuration / slot.duration) : 1,
                partialFraction: validDuration ? fraction(slot.partialDuration / slot.duration) : 0,
                accountingUnavailable: slot.accountingOverflow)
        }
        let currentFirst = slots.map(\.firstRate).max() ?? 0
        let currentSecond = slots.map(\.secondRate).max() ?? 0
        self.firstPeak = Self.validPeak(firstPeak, current: currentFirst)
        self.secondPeak = Self.validPeak(secondPeak, current: currentSecond)
        firstPeakText = TransferHistoryFormat.rate(self.firstPeak, locale: locale)
        secondPeakText = TransferHistoryFormat.rate(self.secondPeak, locale: locale)
        firstLabel = result.stat == .network ? "Download" : "Read"
        secondLabel = result.stat == .network ? "Upload" : "Write"
        firstMarker = result.stat == .network ? "↓" : "R"
        secondMarker = result.stat == .network ? "↑" : "W"
        axisLabels = period.axisLabels
    }

    private static func validPeak(_ value: Double?, current: Double) -> Double {
        max(0, current, value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0)
    }
}

/// Queue-confined scale memory, bounded to Network/Disk × three periods. A new revision may
/// ease a peak down; reading/reformatting a published graph can never advance that decay.
struct TransferGraphPeakCache: Sendable {
    private struct Key: Hashable, Sendable { let stat: TransferStat; let period: TransferHistoryPeriod }
    private struct Peak: Sendable { let revision: UInt64; let first: Double; let second: Double }
    private var peaks: [Key: Peak] = [:]

    mutating func graph(result: TransferPeriodResult, period: TransferHistoryPeriod, revision: UInt64,
                        locale: Locale = .current) -> TransferHistoryGraph {
        let key = Key(stat: result.stat, period: period)
        let previous = peaks[key]
        let decay = previous?.revision == revision ? 1.0 : 0.95
        let graph = TransferHistoryGraph(result: result, period: period,
            firstPeak: previous.map { $0.first * decay }, secondPeak: previous.map { $0.second * decay }, locale: locale)
        peaks[key] = Peak(revision: revision, first: graph.firstPeak, second: graph.secondPeak)
        return graph
    }
}

struct TransferHistoryPresentation: Equatable, Sendable {
    let stat: TransferStat
    let period: TransferHistoryPeriod
    let graph: TransferHistoryGraph
    let selectedTotals: TransferPairedTotals
    let cumulativeTotals: TransferPairedTotals
    let coverageText: String
    let boundaryEstimateHelp: String?
    let resetStartedText: String
    let saveText: String
    let warningText: String
    let accessibilitySummary: String

    init(result: TransferPeriodResult, period: TransferHistoryPeriod, cumulative: TransferCumulativeEpoch,
         durability: TransferHistorySaveState, warnings: Set<TransferTimelineWarning> = [],
         graph: TransferHistoryGraph? = nil, locale: Locale = .current, timeZone: TimeZone = .current) {
        stat = result.stat; self.period = period
        self.graph = graph ?? TransferHistoryGraph(result: result, period: period, locale: locale)
        let labels = result.stat == .network ? ("Downloaded", "Uploaded", "↓", "↑") : ("Read", "Written", "R", "W")
        func pair(_ bytes: TransferBytes, unavailable: Bool, estimated: Bool) -> TransferPairedTotals {
            func total(_ bytes: UInt64, label: String, marker: String) -> TransferDirectionTotal {
                TransferDirectionTotal(label: label, marker: marker,
                    value: unavailable ? "Unavailable" : (estimated ? "≈" : "") + TransferHistoryFormat.bytes(bytes, locale: locale),
                    exactValue: unavailable ? "Unavailable" : TransferHistoryFormat.exactBytes(bytes, locale: locale))
            }
            return TransferPairedTotals(first: total(bytes.first, label: labels.0, marker: labels.2),
                second: total(bytes.second, label: labels.1, marker: labels.3))
        }
        selectedTotals = pair(result.bytes, unavailable: result.accountingOverflow, estimated: result.hasBoundaryEstimate)
        cumulativeTotals = pair(cumulative.bytes, unavailable: cumulative.accountingOverflow, estimated: false)
        coverageText = "Fully measured \(TransferHistoryFormat.duration(result.fullyMeasuredDuration, locale: locale)) of \(TransferHistoryFormat.duration(result.duration, locale: locale)) · Partial \(TransferHistoryFormat.duration(result.partialDuration, locale: locale)) · Missing \(TransferHistoryFormat.duration(result.missingDuration, locale: locale))"
        boundaryEstimateHelp = result.hasBoundaryEstimate
            ? "≈ indicates a sampling boundary estimate: transfer is assumed uniform within a measured interval crossing the selected period's edge." : nil
        resetStartedText = "Started \(TransferHistoryFormat.date(cumulative.startedAt, locale: locale, timeZone: timeZone))"
        func savedSuffix(_ date: Date?) -> String {
            date.map { "Last saved \(TransferHistoryFormat.date($0, locale: locale, timeZone: timeZone))" } ?? "Not saved yet"
        }
        var messages: [String] = []
        switch durability {
        case .loading: saveText = "Loading saved history…"
        case .saved(let date): saveText = "Saved \(TransferHistoryFormat.date(date, locale: locale, timeZone: timeZone))"
        case .unsaved(let date): saveText = "Unsaved · \(savedSuffix(date))"
        case .saving(let date): saveText = "Saving… · \(savedSuffix(date))"
        case .failed(let date, let message):
            saveText = "Unsaved · \(savedSuffix(date))"; messages.append("Save failed: \(message)")
        case .recovered(let date, let message):
            saveText = "Recovered · \(savedSuffix(date))"; messages.append(message)
        }
        if result.accountingOverflow || cumulative.accountingOverflow || warnings.contains(.accountingOverflow) {
            messages.append("Accounting unavailable after byte overflow.")
        }
        if warnings.contains(.historyClockAmbiguous) { messages.append("Some history could not be placed after a clock change.") }
        if warnings.contains(.invalidHistory) { messages.append("Some history is unavailable.") }
        if warnings.contains(.resourceLimit) { messages.append("History capacity reached; some activity is missing.") }
        warningText = TransferHistoryFormat.bounded(messages.joined(separator: " "))
        accessibilitySummary = "Selected period \(period.title). \(labels.0) \(selectedTotals.first.value), \(labels.1) \(selectedTotals.second.value). \(coverageText). Partial time includes only readable sources; missing time is unobserved. \(boundaryEstimateHelp ?? "") Since reset: \(labels.0) \(cumulativeTotals.first.value), \(labels.1) \(cumulativeTotals.second.value). \(resetStartedText). \(saveText). \(messages.joined(separator: " "))"
    }
}

/// One instance per stat, retained by the detail owner for the lifetime of the process.
/// Completion means the controller has resolved the reset/save outcome, not merely queued it.
struct TransferDetailState: Equatable, Sendable {
    let stat: TransferStat
    private(set) var period: TransferHistoryPeriod = .minute
    private(set) var isConfirmingReset = false
    private(set) var isResetPending = false
    private(set) var resetError: String?
    var confirmationTitle: String { "Reset \(stat == .network ? "Network" : "Disk") totals?" }
    var confirmationHelp: String { "History is kept. Only these cumulative totals reset." }

    mutating func select(_ period: TransferHistoryPeriod) { self.period = period }
    @discardableResult mutating func requestReset() -> Bool {
        guard !isResetPending else { return false }
        isConfirmingReset = true; resetError = nil; return true
    }
    mutating func cancelReset() { isConfirmingReset = false }
    @discardableResult mutating func beginReset() -> Bool {
        guard isConfirmingReset, !isResetPending else { return false }
        isConfirmingReset = false; isResetPending = true; resetError = nil; return true
    }
    mutating func completeReset(error: String? = nil) {
        guard isResetPending else { return }
        isResetPending = false; resetError = error.map(TransferHistoryFormat.bounded)
    }
    mutating func dismiss() { cancelReset() }
}

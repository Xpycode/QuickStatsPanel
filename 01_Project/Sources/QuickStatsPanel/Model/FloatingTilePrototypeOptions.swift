import CoreGraphics
import Foundation

#if DEBUG

/// Debug launch arguments of the floating-tile prototype, parsed in one pure place. Nothing here
/// is persisted, and the prototype only ever runs on fixtures with isolated preferences and a
/// disposable transfer-history root (see `FloatingTileFixtures`).
///
///     --floating-tiles-prototype            required; without it nothing here applies
///     --floating-tiles-fixture=<name>       a `FloatingTileFixtureName` (default cpu-network)
///     --floating-tiles-frame=<W>x<H>        simulated constrained display: the summon plans and
///                                           places inside a W×H region centred in the real
///                                           visible frame (never larger than it). A model check
///                                           only; it is not native multi-display evidence.
///     --floating-tiles-edge=<corner>        top-left | top-right | bottom-left | bottom-right:
///                                           aim the footprint past that corner, so placement
///                                           must clamp it back on screen
///
/// The prototype is mutually exclusive with `--ring-prototype`: when both are given the ring
/// keeps its existing launch and this returns nil (logged by `current`). An unknown fixture name is
/// recorded in `warnings` and the default fixture is used instead.
struct FloatingTilePrototypeOptions: Equatable, Sendable {
    var fixture: FloatingTileFixtureName = .cpuNetwork
    /// `--floating-tiles-frame=`: a simulated constrained display size, or nil for the real one.
    var simulatedFrame: CGSize?
    /// `--floating-tiles-edge=`: aim the summon at a display corner, or nil for the anchor.
    var edge: FloatingTileEdge?
    /// Unique per launch: names the isolated defaults suite and the temporary history root,
    /// so nothing from an earlier run is ever read back.
    let isolationID: String
    var warnings: [String] = []

    static let prototypeFlag = "--floating-tiles-prototype"
    static let fixturePrefix = "--floating-tiles-fixture="
    static let framePrefix = "--floating-tiles-frame="
    static let edgePrefix = "--floating-tiles-edge="
    /// Smallest accepted simulated frame side; smaller values are rejected as typos.
    static let minimumSimulatedSide: CGFloat = 200
    static let historyRootPrefix = "QuickStatsPanel-floating-tiles-"

    /// Isolated `UserDefaults` suite for this launch, never the standard domain. An absolute path
    /// names a file-backed preferences domain (`<path>.plist`), so the suite lives in the process
    /// temporary directory beside the history root and never in `~/Library/Preferences`, where a
    /// removed named domain would still leave an empty plist behind.
    var defaultsSuiteName: String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.historyRootPrefix + isolationID + "-defaults").path
    }

    /// The file that backs `defaultsSuiteName`.
    var defaultsFile: URL { URL(fileURLWithPath: defaultsSuiteName + ".plist") }

    /// Disposable transfer-history root under the process temporary directory.
    var historyRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.historyRootPrefix + isolationID, isDirectory: true)
    }

    /// The process's launch options, parsed once. Read by `AppSettings.shared`'s initializer, so
    /// isolation is selected before the first singleton read on every path (including Settings).
    static let current: FloatingTilePrototypeOptions? = {
        let arguments = CommandLine.arguments
        if arguments.contains(prototypeFlag), arguments.contains(RingPrototypeOptions.prototypeFlag) {
            NSLog("%@", "\(prototypeFlag) ignored: \(RingPrototypeOptions.prototypeFlag) is also present")
        }
        let options = parse(arguments)
        for warning in options?.warnings ?? [] { NSLog("%@", warning) }
        return options
    }()

    /// `nil` unless the arguments contain `--floating-tiles-prototype` and not `--ring-prototype`.
    static func parse(_ arguments: [String], isolationID: String = UUID().uuidString) -> FloatingTilePrototypeOptions? {
        guard arguments.contains(prototypeFlag),
              !arguments.contains(RingPrototypeOptions.prototypeFlag) else { return nil }
        var options = FloatingTilePrototypeOptions(isolationID: isolationID)
        if let raw = arguments.first(where: { $0.hasPrefix(fixturePrefix) }).map({ String($0.dropFirst(fixturePrefix.count)) }) {
            if let name = FloatingTileFixtureName(rawValue: raw) {
                options.fixture = name
            } else {
                let valid = FloatingTileFixtureName.allCases.map(\.rawValue).joined(separator: ", ")
                options.warnings.append("Unknown --floating-tiles-fixture '\(raw)'; using \(FloatingTileFixtureName.cpuNetwork.rawValue). Valid: \(valid)")
            }
        }
        if let raw = value(framePrefix, in: arguments) {
            let parts = raw.lowercased().split(separator: "x").compactMap { Double($0) }
            if parts.count == 2, parts.allSatisfy({ $0.isFinite && CGFloat($0) >= minimumSimulatedSide }) {
                options.simulatedFrame = CGSize(width: parts[0], height: parts[1])
            } else {
                options.warnings.append("Ignored --floating-tiles-frame '\(raw)'; expected <width>x<height>, each at least \(Int(minimumSimulatedSide))")
            }
        }
        if let raw = value(edgePrefix, in: arguments) {
            if let edge = FloatingTileEdge(rawValue: raw) {
                options.edge = edge
            } else {
                let valid = FloatingTileEdge.allCases.map(\.rawValue).joined(separator: ", ")
                options.warnings.append("Ignored --floating-tiles-edge '\(raw)'. Valid: \(valid)")
            }
        }
        return options
    }

    private static func value(_ prefix: String, in arguments: [String]) -> String? {
        arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}

/// A display corner the summon can be aimed at (`--floating-tiles-edge=`).
enum FloatingTileEdge: String, CaseIterable, Sendable {
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
}

#endif

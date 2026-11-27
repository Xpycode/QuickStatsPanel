import Foundation

#if DEBUG

/// Debug launch arguments of the floating-tile prototype, parsed in one pure place. Nothing here
/// is persisted, and the prototype only ever runs on fixtures with isolated preferences and a
/// disposable transfer-history root (see `FloatingTileFixtures`).
///
///     --floating-tiles-prototype            required; without it nothing here applies
///     --floating-tiles-fixture=<name>       cpu-network (default) | network-cpu
///
/// The prototype is mutually exclusive with `--ring-prototype`: when both are given the ring
/// keeps its existing launch and this returns nil (logged by `current`). An unknown fixture name is
/// recorded in `warnings` and the default fixture is used instead.
struct FloatingTilePrototypeOptions: Equatable, Sendable {
    var fixture: FloatingTileFixtureName = .cpuNetwork
    /// Unique per launch: names the isolated defaults suite and the temporary history root,
    /// so nothing from an earlier run is ever read back.
    let isolationID: String
    var warnings: [String] = []

    static let prototypeFlag = "--floating-tiles-prototype"
    static let fixturePrefix = "--floating-tiles-fixture="
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
        return options
    }
}

#endif

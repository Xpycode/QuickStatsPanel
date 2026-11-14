import Foundation

#if DEBUG

/// Debug launch arguments of the gauge ring prototype, parsed in one pure place. Options are
/// launch arguments, not settings: nothing here is persisted.
///
///     --ring-prototype              required; without it nothing here applies
///     --ring-fixture=<name>         deterministic fixture mode (see `RingFixture.names`)
///     --ring-size=                  medium | small | large
///     --ring-text=                  label | icon-value | icon     (Wedge text upper rung)
///     --ring-fill=                  area | linear
///     --ring-favourites=            8, or 0...8
///     --ring-parts=                 typical | dense | minimal     (fixture mode only)
///     --ring-power-ceiling=         30, or watts
///
/// An unknown value is recorded in `warnings` and the argument's default is used instead.
struct RingPrototypeOptions: Equatable, Sendable {
    var fixtureName: String?
    var size: RingSizePreset = .medium
    var text: RingTextCap = .label
    var fill: RingFillScale = .area
    var favourites = RingLayout.maxFavourites
    var parts: RingPartFixtureName = .typical
    var powerCeilingWatts = RingGaugeMapper.defaultPowerCeilingWatts
    /// One line per ignored or defaulted argument, for the launch log.
    var warnings: [String] = []

    static let prototypeFlag = "--ring-prototype"
    static let fallbackFixtureName = "six"

    /// `nil` unless the arguments contain `--ring-prototype`.
    static func parse(_ arguments: [String]) -> RingPrototypeOptions? {
        guard arguments.contains(prototypeFlag) else { return nil }
        var options = RingPrototypeOptions()

        /// The first occurrence of `--ring-<name>=` wins.
        func value(_ name: String) -> String? {
            let prefix = "--ring-\(name)="
            return arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
        func warn(_ name: String, _ raw: String, _ valid: String, _ fallback: String) {
            options.warnings.append("Unknown --ring-\(name) '\(raw)'; using \(fallback). Valid: \(valid)")
        }

        if let raw = value("fixture") {
            if RingFixture.named(raw) != nil {
                options.fixtureName = raw
            } else {
                warn("fixture", raw, RingFixture.names.joined(separator: ", "), fallbackFixtureName)
                options.fixtureName = fallbackFixtureName
            }
        }
        if let raw = value("size") {
            if let size = RingSizePreset(rawValue: raw) { options.size = size }
            else { warn("size", raw, RingSizePreset.allCases.map(\.rawValue).joined(separator: ", "), "medium") }
        }
        if let raw = value("text") {
            switch raw {
            case "label": options.text = .label
            case "icon-value": options.text = .iconValue
            case "icon": options.text = .icon
            default: warn("text", raw, "label, icon-value, icon", "label")
            }
        }
        if let raw = value("fill") {
            if let fill = RingFillScale(rawValue: raw) { options.fill = fill }
            else { warn("fill", raw, RingFillScale.allCases.map(\.rawValue).joined(separator: ", "), "area") }
        }
        if let raw = value("favourites") {
            if let count = Int(raw), (0...RingLayout.maxFavourites).contains(count) { options.favourites = count }
            else { warn("favourites", raw, "0...\(RingLayout.maxFavourites)", "\(RingLayout.maxFavourites)") }
        }
        if let raw = value("parts") {
            if let parts = RingPartFixtureName(rawValue: raw) {
                options.parts = parts
                if options.fixtureName == nil {
                    options.warnings.append("--ring-parts has no effect without --ring-fixture; ignored")
                }
            } else {
                warn("parts", raw, RingPartFixtureName.allCases.map(\.rawValue).joined(separator: ", "), "typical")
            }
        }
        if let raw = value("power-ceiling") {
            if let watts = Double(raw), watts.isFinite, watts > 0 { options.powerCeilingWatts = watts }
            else { warn("power-ceiling", raw, "a positive number of watts", "\(Int(RingGaugeMapper.defaultPowerCeilingWatts))") }
        }
        return options
    }
}

#endif

import AudioToolbox
import Foundation

/// Describes one automatable parameter: range, taper, defaults and display.
struct ParameterSpec: Sendable, Identifiable {
    enum Format: Sendable {
        case fader          // dB, bottom of range is mute
        case decibels
        case boost          // signed dB
        case ratio
        case milliseconds
        case hertz
        case plain
        case percent
        case choice([String])
        case toggle
    }

    enum Taper: Sendable {
        case linear
        case logarithmic
    }

    let address: ECParameterAddress
    let identifier: String
    let name: String
    let shortName: String
    let range: ClosedRange<AUValue>
    let defaultValue: AUValue
    let format: Format
    var taper: Taper = .linear

    var id: AUParameterAddress { address.rawValue }

    // MARK: Normalisation (for controls)

    func normalized(_ value: AUValue) -> Double {
        let v = Double(min(max(value, range.lowerBound), range.upperBound))
        let lo = Double(range.lowerBound), hi = Double(range.upperBound)
        switch taper {
        case .linear: return (v - lo) / (hi - lo)
        case .logarithmic: return log(v / lo) / log(hi / lo)
        }
    }

    func value(fromNormalized normalized: Double) -> AUValue {
        let n = min(max(normalized, 0), 1)
        let lo = Double(range.lowerBound), hi = Double(range.upperBound)
        let raw: Double = switch taper {
        case .linear: lo + n * (hi - lo)
        case .logarithmic: lo * pow(hi / lo, n)
        }
        switch format {
        case .choice, .toggle: return AUValue(raw.rounded())
        default: return AUValue(raw)
        }
    }

    // MARK: Display

    func displayString(for value: AUValue) -> String {
        switch format {
        case .fader:
            return value <= range.lowerBound ? "−∞ dB" : signed(value, digits: 1) + " dB"
        case .decibels:
            return String(format: "%.1f dB", value)
        case .boost:
            return signed(value, digits: 1) + " dB"
        case .ratio:
            return value < 10 ? String(format: "%.1f:1", value) : String(format: "%.0f:1", value)
        case .milliseconds:
            return value < 10 ? String(format: "%.1f ms", value) : String(format: "%.0f ms", value)
        case .hertz:
            return value >= 1000 ? String(format: "%.2f kHz", value / 1000) : String(format: "%.0f Hz", value)
        case .plain:
            return String(format: "%.2f", value)
        case .percent:
            return String(format: "%.0f%%", value)
        case .choice(let labels):
            let index = Int(value.rounded())
            return labels.indices.contains(index) ? labels[index] : "\(index)"
        case .toggle:
            return value >= 0.5 ? "On" : "Off"
        }
    }

    private func signed(_ value: AUValue, digits: Int) -> String {
        let text = String(format: "%.\(digits)f", abs(value))
        return value < 0 ? "−" + text : (value > 0 ? "+" + text : text)
    }

    // MARK: AUParameter

    var unit: AudioUnitParameterUnit {
        switch format {
        case .fader, .decibels, .boost: .decibels
        case .ratio: .ratio
        case .milliseconds: .milliseconds
        case .hertz: .hertz
        case .plain: .generic
        case .percent: .percent
        case .choice: .indexed
        case .toggle: .boolean
        }
    }

    var valueStrings: [String]? {
        if case .choice(let labels) = format { labels } else { nil }
    }

    var flags: AudioUnitParameterOptions {
        var flags: AudioUnitParameterOptions = [.flag_IsReadable, .flag_IsWritable]
        switch format {
        case .choice, .toggle: break
        default: flags.insert(.flag_CanRamp)
        }
        if taper == .logarithmic { flags.insert(.flag_DisplayLogarithmic) }
        return flags
    }

    func makeParameter() -> AUParameter {
        let parameter = AUParameterTree.createParameter(
            withIdentifier: identifier,
            name: name,
            address: address.rawValue,
            min: range.lowerBound,
            max: range.upperBound,
            unit: unit,
            unitName: nil,
            flags: flags,
            valueStrings: valueStrings,
            dependentParameters: nil
        )
        parameter.value = defaultValue
        return parameter
    }
}

/// Every parameter, with defaults taken from the 1963 Motown vocal setup.
enum ParameterCatalog {
    static let naturalLevel = ParameterSpec(
        address: .naturalLevel, identifier: "naturalLevel", name: "Natural Level", shortName: "Level",
        range: -60...6, defaultValue: 0, format: .fader)

    static let exciteLevel = ParameterSpec(
        address: .exciteLevel, identifier: "exciteLevel", name: "Excite Level", shortName: "Blend",
        range: -60...6, defaultValue: -12, format: .fader)

    static let threshold = ParameterSpec(
        address: .threshold, identifier: "threshold", name: "Excite Threshold", shortName: "Threshold",
        range: -60...0, defaultValue: -35, format: .decibels)

    static let ratio = ParameterSpec(
        address: .ratio, identifier: "ratio", name: "Excite Ratio", shortName: "Ratio",
        range: 1...30, defaultValue: 20, format: .ratio, taper: .logarithmic)

    static let attack = ParameterSpec(
        address: .attack, identifier: "attack", name: "Excite Attack", shortName: "Attack",
        range: 0.1...100, defaultValue: 2, format: .milliseconds, taper: .logarithmic)

    static let release = ParameterSpec(
        address: .release, identifier: "release", name: "Excite Release", shortName: "Release",
        range: 10...2000, defaultValue: 150, format: .milliseconds, taper: .logarithmic)

    static let eqFrequency = ParameterSpec(
        address: .eqFrequency, identifier: "eqFrequency", name: "Excite EQ Frequency", shortName: "Freq",
        range: 400...16000, defaultValue: 6500, format: .hertz, taper: .logarithmic)

    static let eqGain = ParameterSpec(
        address: .eqGain, identifier: "eqGain", name: "Excite EQ Boost", shortName: "Boost",
        range: 0...24, defaultValue: 15, format: .boost)

    static let eqQ = ParameterSpec(
        address: .eqQ, identifier: "eqQ", name: "Excite EQ Q", shortName: "Q",
        range: 0.3...4, defaultValue: 0.7, format: .plain, taper: .logarithmic)

    static let eqShape = ParameterSpec(
        address: .eqShape, identifier: "eqShape", name: "Excite EQ Shape", shortName: "Shape",
        range: 0...1, defaultValue: 0, format: .choice(["Bell", "Shelf"]))

    static let outputLevel = ParameterSpec(
        address: .outputLevel, identifier: "outputLevel", name: "Output Level", shortName: "Output",
        range: -24...12, defaultValue: 0, format: .boost)

    static let exciteListen = ParameterSpec(
        address: .exciteListen, identifier: "exciteListen", name: "Excite Listen", shortName: "Excite Only",
        range: 0...1, defaultValue: 0, format: .toggle)

    /// Low-order harmonics from the body of the voice (90–500 Hz), mixed into
    /// the excite path. 0 is off; 100 % puts them at the level of that band.
    static let warmth = ParameterSpec(
        address: .warmth, identifier: "warmth", name: "Excite Warmth", shortName: "Warmth",
        range: 0...100, defaultValue: 0, format: .percent)

    /// Solos only what Warmth adds to the excite path, before Blend.
    static let warmthListen = ParameterSpec(
        address: .warmthListen, identifier: "warmthListen", name: "Warmth Listen", shortName: "Warmth Only",
        range: 0...1, defaultValue: 0, format: .toggle)

    /// Monitoring switches that are alternatives to each other in the editor.
    static let soloSwitches: [ParameterSpec] = [exciteListen, warmthListen]

    static let all: [ParameterSpec] = [
        naturalLevel, exciteLevel, threshold, ratio, attack, release,
        eqFrequency, eqGain, eqQ, eqShape, outputLevel, exciteListen, warmth, warmthListen,
    ]

    private static let byAddress: [AUParameterAddress: ParameterSpec] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.address.rawValue, $0) })

    static func spec(for address: AUParameterAddress) -> ParameterSpec? { byAddress[address] }

    static func makeParameterTree() -> AUParameterTree {
        func group(_ id: String, _ name: String, _ specs: [ParameterSpec]) -> AUParameterGroup {
            AUParameterTree.createGroup(withIdentifier: id, name: name, children: specs.map { $0.makeParameter() })
        }
        return AUParameterTree.createTree(withChildren: [
            group("natural", "Natural", [naturalLevel]),
            group("compressor", "Excite Compressor", [threshold, ratio, attack, release]),
            group("eq", "Excite EQ", [eqFrequency, eqGain, eqQ, eqShape]),
            group("warmth", "Excite Warmth", [warmth]),
            group("mix", "Mix", [exciteLevel, outputLevel, exciteListen, warmthListen]),
        ])
    }
}

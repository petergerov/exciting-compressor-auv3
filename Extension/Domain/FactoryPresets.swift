import AudioToolbox

/// A named snapshot of parameter values. Missing parameters fall back to defaults.
struct ExcitePreset: Sendable, Identifiable {
    let number: Int
    let name: String
    let values: [ECParameterAddress: AUValue]

    var id: Int { number }

    init(number: Int, name: String, overrides: [ECParameterAddress: AUValue]) {
        self.number = number
        self.name = name
        var values = Dictionary(uniqueKeysWithValues: ParameterCatalog.all.map { ($0.address, $0.defaultValue) })
        values.merge(overrides) { _, override in override }
        // Monitoring switches are never part of a preset.
        values[.exciteListen] = 0
        values[.warmthListen] = 0
        self.values = values
    }
}

/// Starting points from Bob Dennis' notes: vocals 5–8 kHz, guitars 3–5 kHz,
/// bass 800 Hz–1.5 kHz, always compressed hard and blended in "just enough".
enum FactoryPresets {
    static let all: [ExcitePreset] = [
        ExcitePreset(number: 0, name: "Motown Lead Vocal", overrides: [:]),
        ExcitePreset(number: 1, name: "Vocal Air", overrides: [
            .eqFrequency: 8000, .eqShape: 1, .eqGain: 12, .exciteLevel: -14,
        ]),
        ExcitePreset(number: 2, name: "Backing Vocals", overrides: [
            .threshold: -30, .ratio: 12, .eqFrequency: 5500, .eqGain: 12, .exciteLevel: -9,
        ]),
        ExcitePreset(number: 3, name: "Guitar Bite", overrides: [
            .attack: 5, .release: 120, .eqFrequency: 4000, .eqGain: 12, .eqQ: 0.9, .exciteLevel: -12,
        ]),
        ExcitePreset(number: 4, name: "Bass Growl", overrides: [
            .attack: 10, .release: 200, .eqFrequency: 1100, .eqGain: 12, .eqQ: 1.0, .exciteLevel: -10,
        ]),
        ExcitePreset(number: 5, name: "Subtle Presence", overrides: [
            .threshold: -30, .ratio: 8, .eqFrequency: 6000, .eqGain: 10, .exciteLevel: -20,
        ]),
        // Appended, never inserted: hosts remember factory presets by number.
        ExcitePreset(number: 6, name: "Round Lead Vocal", overrides: [
            .warmth: 45, .eqGain: 12, .exciteLevel: -10,
        ]),
    ]

    static func preset(number: Int) -> ExcitePreset? {
        all.first { $0.number == number }
    }
}

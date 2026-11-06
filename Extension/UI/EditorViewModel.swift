import AudioToolbox
import Foundation
import Observation

/// Bridges the AU parameter tree to SwiftUI. All UI-facing state is main-actor isolated;
/// parameter changes from the host or automation arrive via the tree observer.
@MainActor
@Observable
final class EditorViewModel {
    private(set) var values: [ECParameterAddress: AUValue]
    private(set) var gainReductionDB: Float = 0
    /// Decaying peak envelopes (linear) for the IN/OUT ladders.
    private(set) var inputLevel = StereoLevel.silent
    private(set) var outputLevel = StereoLevel.silent
    private(set) var presetName: String?
    let presets: [AUAudioUnitPreset]

    @ObservationIgnored private let audioUnit: ExcitingCompressorAudioUnit
    @ObservationIgnored private var observation: ParameterObservation?

    init(audioUnit: ExcitingCompressorAudioUnit) {
        self.audioUnit = audioUnit
        self.presets = audioUnit.factoryPresets ?? []
        self.presetName = audioUnit.currentPreset?.name
        self.values = Self.readValues(from: audioUnit)

        if let tree = audioUnit.parameterTree {
            observation = ParameterObservation(tree: tree) { [weak self] address, value in
                Task { @MainActor [weak self] in
                    guard let key = ECParameterAddress(rawValue: address) else { return }
                    self?.values[key] = value
                }
            }
        }
    }

    // MARK: Reading

    func value(for spec: ParameterSpec) -> AUValue {
        values[spec.address] ?? spec.defaultValue
    }

    func normalizedValue(for spec: ParameterSpec) -> Double {
        spec.normalized(value(for: spec))
    }

    func isOn(_ spec: ParameterSpec) -> Bool {
        value(for: spec) >= 0.5
    }

    private var isSoloing: Bool {
        ParameterCatalog.soloSwitches.contains { isOn($0) }
    }

    /// Whether the natural path reaches the output: not soloed away by Excite
    /// Only / Warmth Only and not faded fully down. Drives the channel's lamp.
    var isNaturalAudible: Bool {
        !isSoloing && !isFaderClosed(ParameterCatalog.naturalLevel)
    }

    /// Whether the excite path reaches the output. Both solos tap it before
    /// Blend, so it is audible then regardless of the blend level.
    var isExciteAudible: Bool {
        isSoloing || !isFaderClosed(ParameterCatalog.exciteLevel)
    }

    /// Excite Only and Warmth Only are alternatives: switching one on switches
    /// the other off, like the solo buttons on a console. (The kernel still
    /// handles both being on — from automation — by letting Warmth Only win.)
    func toggleSolo(_ spec: ParameterSpec) {
        let switchingOn = !isOn(spec)
        toggle(spec)
        guard switchingOn else { return }
        for other in ParameterCatalog.soloSwitches where other.address != spec.address && isOn(other) {
            toggle(other)
        }
    }

    private func isFaderClosed(_ spec: ParameterSpec) -> Bool {
        value(for: spec) <= spec.range.lowerBound
    }

    func toggle(_ spec: ParameterSpec) {
        beginEditing(spec)
        setValue(isOn(spec) ? 0 : 1, for: spec)
        endEditing(spec)
    }

    func select(_ index: Int, for spec: ParameterSpec) {
        beginEditing(spec)
        setValue(AUValue(index), for: spec)
        endEditing(spec)
    }

    // MARK: Editing

    func setNormalized(_ normalized: Double, for spec: ParameterSpec) {
        setValue(spec.value(fromNormalized: normalized), for: spec)
    }

    func setValue(_ value: AUValue, for spec: ParameterSpec) {
        let clamped = min(max(value, spec.range.lowerBound), spec.range.upperBound)
        guard values[spec.address] != clamped else { return }
        values[spec.address] = clamped
        send(clamped, for: spec, event: .value)
    }

    func resetToDefault(_ spec: ParameterSpec) {
        beginEditing(spec)
        setValue(spec.defaultValue, for: spec)
        endEditing(spec)
    }

    /// Touch/release bracket a gesture so hosts can record automation correctly.
    func beginEditing(_ spec: ParameterSpec) {
        send(value(for: spec), for: spec, event: .touch)
    }

    func endEditing(_ spec: ParameterSpec) {
        send(value(for: spec), for: spec, event: .release)
    }

    // MARK: Presets

    func selectPreset(_ preset: AUAudioUnitPreset) {
        audioUnit.currentPreset = preset
        presetName = audioUnit.currentPreset?.name
        values = Self.readValues(from: audioUnit)
    }

    // MARK: Metering

    /// Polls the kernel's meters while the view is on screen (cancelled by `.task`).
    func monitorMeters() async {
        let clock = ContinuousClock()
        var last = clock.now
        while !Task.isCancelled {
            let now = clock.now
            // Clamped so returning from a stall doesn't drop the meters in one step.
            updateMeters(elapsed: min((now - last) / .seconds(1), 0.1))
            last = now
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    private func updateMeters(elapsed seconds: Double) {
        // Gain reduction: instant attack, 36 dB/s fall-back for a readable bar.
        let reduction = audioUnit.gainReductionDB
        let fallen = max(reduction, gainReductionDB - Float(36 * seconds))
        assignIfChanged(\.gainReductionDB, reduction >= gainReductionDB ? reduction : fallen)

        // Levels: instant rise, falling to 72 % every 50 ms whatever the frame
        // rate. The kernel holds the max since the last read, so a transient
        // between frames still lands.
        let peaks = audioUnit.takePeakLevels()
        let decay = Float(pow(0.72, seconds / 0.05))
        assignIfChanged(\.inputLevel, Self.envelope(inputLevel, peaks.input, decay: decay))
        assignIfChanged(\.outputLevel, Self.envelope(outputLevel, peaks.output, decay: decay))
    }

    private static func envelope(_ held: StereoLevel, _ peak: StereoLevel, decay: Float) -> StereoLevel {
        // Snap to silence instead of decaying through denormals forever.
        func side(_ held: Float, _ peak: Float) -> Float {
            let next = max(held * decay, peak)
            return next < 1e-5 ? 0 : next
        }
        return StereoLevel(left: side(held.left, peak.left), right: side(held.right, peak.right))
    }

    /// Writing an unchanged value would still invalidate every view reading it.
    private func assignIfChanged<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<EditorViewModel, Value>,
                                                   _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    // MARK: Private

    private func send(_ value: AUValue, for spec: ParameterSpec, event: AUParameterAutomationEventType) {
        guard let parameter = audioUnit.parameterTree?.parameter(withAddress: spec.address.rawValue) else { return }
        parameter.setValue(value, originator: observation?.token, atHostTime: 0, eventType: event)
    }

    private static func readValues(from audioUnit: AUAudioUnit) -> [ECParameterAddress: AUValue] {
        Dictionary(uniqueKeysWithValues: ParameterCatalog.all.map { spec in
            let parameter = audioUnit.parameterTree?.parameter(withAddress: spec.address.rawValue)
            return (spec.address, parameter?.value ?? spec.defaultValue)
        })
    }
}

/// Owns a parameter-tree observer token and removes it on deinit.
private final class ParameterObservation: @unchecked Sendable {
    private let tree: AUParameterTree
    let token: AUParameterObserverToken

    init(tree: AUParameterTree, handler: @escaping @Sendable (AUParameterAddress, AUValue) -> Void) {
        self.tree = tree
        self.token = tree.token(byAddingParameterObserver: handler)
    }

    deinit {
        tree.removeParameterObserver(token)
    }
}

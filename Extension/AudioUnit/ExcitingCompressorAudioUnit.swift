import AVFoundation
import AudioToolbox
import os

/// AUv3 effect: a natural path in parallel with a heavily compressed, brightly
/// equalised "excite" path, after the Motown technique.
///
/// `@unchecked Sendable`: AUAudioUnit is used from host-chosen threads; mutable
/// state is either set during init or lives in the thread-safe C++ kernel.
public final class ExcitingCompressorAudioUnit: AUAudioUnit, @unchecked Sendable {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ExcitingCompressor", category: "AudioUnit")

    private let kernel = ECDSPKernelAdapter()
    private var _inputBusses: AUAudioUnitBusArray!
    private var _outputBusses: AUAudioUnitBusArray!
    private var _parameterTree: AUParameterTree!
    private var _currentPreset: AUAudioUnitPreset?

    private let _factoryPresets: [AUAudioUnitPreset] = FactoryPresets.all.map { preset in
        let auPreset = AUAudioUnitPreset()
        auPreset.number = preset.number
        auPreset.name = preset.name
        return auPreset
    }

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        _inputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [kernel.inputBus])
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [kernel.outputBus])

        let tree = ParameterCatalog.makeParameterTree()
        tree.implementorValueObserver = { [kernel] parameter, value in
            kernel.setValue(value, forAddress: parameter.address)
        }
        tree.implementorValueProvider = { [kernel] parameter in
            kernel.value(forAddress: parameter.address)
        }
        tree.implementorStringFromValueCallback = { parameter, valuePointer in
            let value = valuePointer?.pointee ?? parameter.value
            return ParameterCatalog.spec(for: parameter.address)?.displayString(for: value) ?? "\(value)"
        }
        _parameterTree = tree

        // Push defaults into the kernel through the observer.
        for parameter in tree.allParameters {
            parameter.value = ParameterCatalog.spec(for: parameter.address)?.defaultValue ?? parameter.value
        }

        maximumFramesToRender = 4096
        currentPreset = _factoryPresets.first
    }

    // MARK: Busses & parameters

    public override var inputBusses: AUAudioUnitBusArray { _inputBusses }
    public override var outputBusses: AUAudioUnitBusArray { _outputBusses }

    public override var parameterTree: AUParameterTree? {
        get { _parameterTree }
        set { /* fixed tree */ }
    }

    /// Mono→mono and stereo→stereo.
    public override var channelCapabilities: [NSNumber]? { [1, 1, 2, 2] }

    public override var canProcessInPlace: Bool { true }

    public override var shouldBypassEffect: Bool {
        get { kernel.isBypassed }
        set { kernel.isBypassed = newValue }
    }

    /// Excite-path gain reduction in positive dB, for metering.
    public var gainReductionDB: Float { kernel.gainReductionDB }

    /// Input and output peaks (linear) since the previous call, then cleared.
    /// One reader only: a second caller would split the peaks between them.
    func takePeakLevels() -> PeakLevels {
        PeakLevels(input: StereoLevel(kernel.takeInputPeak()),
                   output: StereoLevel(kernel.takeOutputPeak()))
    }

    // MARK: Rendering

    public override var internalRenderBlock: AUInternalRenderBlock { kernel.internalRenderBlock() }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        do {
            try kernel.allocateRenderResources(maximumFrames: maximumFramesToRender)
        } catch {
            super.deallocateRenderResources()
            throw error
        }
    }

    public override func deallocateRenderResources() {
        kernel.deallocateRenderResources()
        super.deallocateRenderResources()
    }

    // MARK: Presets

    public override var factoryPresets: [AUAudioUnitPreset]? { _factoryPresets }
    public override var supportsUserPresets: Bool { true }

    public override var currentPreset: AUAudioUnitPreset? {
        get { _currentPreset }
        set {
            guard let preset = newValue else {
                _currentPreset = nil
                return
            }

            if preset.number >= 0 {
                guard let factory = FactoryPresets.preset(number: preset.number) else { return }
                apply(factory)
                _currentPreset = preset
            } else if !userPresets.contains(where: { $0.number == preset.number && $0.name == preset.name }) {
                // Unsaved user preset (hosts name the current state this way). Note:
                // presetState(for:) raises an Objective-C exception for missing presets,
                // which Swift cannot catch, so never call it for unknown presets.
                _currentPreset = preset
            } else {
                do {
                    fullStateForDocument = try presetState(for: preset)
                    _currentPreset = preset
                } catch {
                    Self.logger.error("Failed to load user preset \(preset.name): \(error.localizedDescription)")
                }
            }
        }
    }

    private func apply(_ preset: ExcitePreset) {
        guard let tree = _parameterTree else { return }
        for (address, value) in preset.values {
            tree.parameter(withAddress: address.rawValue)?.value = value
        }
    }
}

/// Linear peak level per side.
struct StereoLevel: Sendable, Equatable {
    var left: Float
    var right: Float

    static let silent = StereoLevel(left: 0, right: 0)

    var loudest: Float { max(left, right) }
}

extension StereoLevel {
    init(_ peak: ECStereoPeak) {
        self.init(left: peak.left, right: peak.right)
    }
}

struct PeakLevels: Sendable, Equatable {
    var input: StereoLevel
    var output: StereoLevel
}

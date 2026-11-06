import AVFoundation
import CoreAudioKit

#if os(macOS)
typealias PlatformViewController = NSViewController
#else
typealias PlatformViewController = UIViewController
#endif

enum AudioEngineHostError: LocalizedError {
    case unsupportedChannelCount(Int)
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unsupportedChannelCount(let count): "Only mono or stereo files are supported (this file has \(count) channels)."
        case .unreadableFile: "The audio file could not be read."
        }
    }
}

/// Data layer: owns the AVAudioEngine graph `player → Exciting Compressor → output`.
@MainActor
final class AudioEngineHost {
    /// Must match the AudioComponents entry in the extension's Info.plist.
    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: fourCharCode("ExCp"),
        componentManufacturer: fourCharCode("Grov"),
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var effect: AVAudioUnit?
    private var buffer: AVAudioPCMBuffer?

    var isPlaying: Bool { player.isPlaying }

    /// Instantiates the plugin out of process, wires the graph, and returns its editor.
    func loadPlugin() async throws -> PlatformViewController? {
        #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif

        let unit = try await instantiateEffect()
        effect = unit
        engine.attach(player)
        engine.attach(unit)
        connect(format: engine.outputNode.outputFormat(forBus: 0))

        return await requestViewController(for: unit.auAudioUnit)
    }

    func loadFile(at url: URL) throws {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard (1...2).contains(Int(format.channelCount)) else {
            throw AudioEngineHostError.unsupportedChannelCount(Int(format.channelCount))
        }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioEngineHostError.unreadableFile
        }
        try file.read(into: pcm)

        stop()
        buffer = pcm
        connect(format: format)
    }

    func play() throws {
        guard let buffer else { return }
        if !engine.isRunning { try engine.start() }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
    }

    // MARK: Private

    private func connect(format: AVAudioFormat) {
        guard let effect else { return }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(effect)
        let busFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: format.channelCount)
        engine.connect(player, to: effect, format: busFormat)
        engine.connect(effect, to: engine.mainMixerNode, format: busFormat)
        engine.prepare()
    }

    private func instantiateEffect() async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: Self.componentDescription, options: .loadOutOfProcess) { unit, error in
                if let unit {
                    continuation.resume(returning: unit)
                } else {
                    continuation.resume(throwing: error ?? AudioEngineHostError.unreadableFile)
                }
            }
        }
    }

    private func requestViewController(for audioUnit: AUAudioUnit) async -> PlatformViewController? {
        await withCheckedContinuation { continuation in
            audioUnit.requestViewController { viewController in
                continuation.resume(returning: viewController)
            }
        }
    }
}

private func fourCharCode(_ string: StaticString) -> FourCharCode {
    string.withUTF8Buffer { bytes in
        bytes.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}

import CoreAudioKit
import SwiftUI

#if os(macOS)
typealias PlatformView = NSView
typealias PlatformHostingController = NSHostingController
#else
typealias PlatformView = UIView
typealias PlatformHostingController = UIHostingController
#endif

/// Extension principal class: creates the audio unit and hosts its SwiftUI editor.
public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    static let preferredSize = CGSize(width: 860, height: 500)

    private var audioUnit: ExcitingCompressorAudioUnit?
    private var hostingController: PlatformHostingController<EditorRootView>?

    public override func loadView() {
        view = PlatformView(frame: CGRect(origin: .zero, size: Self.preferredSize))
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = Self.preferredSize
        installEditorIfReady()
    }

    // MARK: AUAudioUnitFactory

    /// Called by the host on an arbitrary thread.
    nonisolated public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let audioUnit = try ExcitingCompressorAudioUnit(componentDescription: componentDescription, options: [])
        Task { @MainActor in
            self.audioUnit = audioUnit
            self.installEditorIfReady()
        }
        return audioUnit
    }

    // MARK: Editor

    private func installEditorIfReady() {
        guard let audioUnit, isViewLoaded, hostingController == nil else { return }

        let viewModel = EditorViewModel(audioUnit: audioUnit)
        let host = PlatformHostingController(rootView: EditorRootView(viewModel: viewModel))
        host.sizingOptions = []

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        #if os(iOS)
        host.didMove(toParent: self)
        #endif

        hostingController = host
    }
}

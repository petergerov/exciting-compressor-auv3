import Foundation
import Observation

@MainActor
@Observable
final class HostViewModel {
    enum PluginState {
        case loading
        case loaded(PlatformViewController?)
        case failed(String)
    }

    private(set) var pluginState: PluginState = .loading
    private(set) var fileName: String?
    private(set) var isPlaying = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let host = AudioEngineHost()

    var canPlay: Bool { fileName != nil }

    func loadPlugin() async {
        guard case .loading = pluginState else { return }
        do {
            pluginState = .loaded(try await host.loadPlugin())
        } catch {
            pluginState = .failed(error.localizedDescription)
        }
    }

    func openFile(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            try host.loadFile(at: url)
            fileName = url.lastPathComponent
            isPlaying = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayback() {
        if isPlaying {
            host.stop()
        } else {
            do {
                try host.play()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        isPlaying = host.isPlaying
    }
}

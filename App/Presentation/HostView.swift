import SwiftUI
import UniformTypeIdentifiers

struct HostView: View {
    @State private var viewModel = HostViewModel()
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            TransportBar(viewModel: viewModel, isImporting: $isImporting)
            Divider()
            PluginContainer(state: viewModel.pluginState)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
            viewModel.openFile(result)
        }
        .task { await viewModel.loadPlugin() }
    }
}

private struct TransportBar: View {
    let viewModel: HostViewModel
    @Binding var isImporting: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button("Open Audio File…", systemImage: "folder") { isImporting = true }

            Button(viewModel.isPlaying ? "Stop" : "Play",
                   systemImage: viewModel.isPlaying ? "stop.fill" : "play.fill") {
                viewModel.togglePlayback()
            }
            .disabled(!viewModel.canPlay)
            .keyboardShortcut(.space, modifiers: [])

            Text(viewModel.errorMessage ?? viewModel.fileName ?? "Load a vocal to hear the effect")
                .font(.callout)
                .foregroundStyle(viewModel.errorMessage == nil ? Color.secondary : Color.red)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct PluginContainer: View {
    let state: HostViewModel.PluginState

    var body: some View {
        switch state {
        case .loading:
            ProgressView("Loading Exciting Compressor…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let viewController?):
            AudioUnitViewRepresentable(viewController: viewController)
        case .loaded(nil):
            ContentUnavailableView("No Editor", systemImage: "slider.horizontal.3",
                                   description: Text("The plugin loaded but returned no view."))
        case .failed(let message):
            ContentUnavailableView("Plugin Failed to Load", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        }
    }
}

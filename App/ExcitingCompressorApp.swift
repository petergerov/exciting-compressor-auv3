import SwiftUI

/// Container app: installs the AUv3 extension and offers a quick test rig.
@main
struct ExcitingCompressorApp: App {
    var body: some Scene {
        WindowGroup {
            HostView()
                #if os(macOS)
                .frame(minWidth: 860, minHeight: 560)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 820, height: 520)
        #endif
    }
}

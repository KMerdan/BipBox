// BipboxUIDemoApp.swift — standalone entry point to preview the redesign.
//
// Build this folder as its own SwiftUI app target to see the UI, OR drop the
// other files into BipboxWorkspaceUI and host BipboxRootView() in your window.
// Delete this file when integrating into the package (the package has its own
// @main). See README-INTEGRATION.md.
import SwiftUI

@main
struct BipboxUIDemoApp: App {
    var body: some Scene {
        WindowGroup {
            BipboxRootView()
        }
        .windowStyle(.hiddenTitleBar)   // sidebar provides traffic-light room

        // The real app moves preferences here, off the main nav (⌘,):
        // Settings { SettingsView() }
    }
}

#Preview { BipboxRootView().frame(width: 1240, height: 820) }

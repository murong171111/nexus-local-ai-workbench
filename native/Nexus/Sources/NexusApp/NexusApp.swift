import SwiftUI

@main
struct NexusNativeApp: App {
    @StateObject private var appState = AppState.preview()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 560, height: 360)
        }
    }
}

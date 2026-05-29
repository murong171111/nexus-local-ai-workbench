import SwiftUI

@main
struct NexusNativeApp: App {
    @StateObject private var appState = AppState.preview()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1120, minHeight: 720)
                .onOpenURL { url in
                    Task {
                        await appState.handleDeepLink(url)
                    }
                }
        }
        .windowStyle(.titleBar)

        MenuBarExtra {
            MenuBarStatusView()
                .environmentObject(appState)
        } label: {
            Label(
                appState.menuBarSummary.menuTitle,
                systemImage: appState.menuBarSummary.systemImage
            )
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 560, height: 360)
        }
    }
}

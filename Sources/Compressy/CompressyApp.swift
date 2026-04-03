import Sparkle
import SwiftUI

@main
struct CompressyApp: App {
    private let updater_controller: SPUStandardUpdaterController

    init() {
        updater_controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater_controller.updater)
            }
        }

        Settings {
            SettingsView(settings: CompressionSettings.shared)
        }
    }
}

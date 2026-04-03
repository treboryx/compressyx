import Sparkle
import SwiftUI

struct CheckForUpdatesView: View {
    let updater: SPUUpdater

    @State private var can_check = false

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!can_check)
        .task {
            can_check = updater.canCheckForUpdates
        }
    }
}

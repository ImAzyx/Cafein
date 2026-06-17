import SwiftUI
import Sparkle

@main
struct cafeinApp: App {
    @State private var manager = SleepManager()

    // Owns the Sparkle updater for the app's lifetime; starts auto-checking on launch.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: manager, updater: updaterController.updater)
        } label: {
            MenuBarIcon(manager: manager)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarIcon: View {
    let manager: SleepManager
    var body: some View {
        Image(systemName: manager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
    }
}

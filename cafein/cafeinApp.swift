import SwiftUI

@main
struct cafeinApp: App {
    @State private var manager = SleepManager()

    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: manager)
        } label: {
            // Icon reflects current state: filled cup when keeping the Mac awake.
            Image(systemName: manager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
        .menuBarExtraStyle(.window)
    }
}

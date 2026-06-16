import SwiftUI

@main
struct cafeinApp: App {
    @State private var manager = SleepManager()

    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: manager)
        } label: {
            Image(systemName: "cup.and.saucer.fill")
                .opacity(manager.isActive ? 1 : 0.3)
        }
        .menuBarExtraStyle(.window)
    }
}

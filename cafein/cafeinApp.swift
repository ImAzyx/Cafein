import SwiftUI

@main
struct cafeinApp: App {
    @State private var manager = SleepManager()

    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: manager)
        } label: {
            Image(systemName: manager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(manager.isActive ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                        .offset(x: 3, y: -1)
                }
        }
        .menuBarExtraStyle(.window)
    }
}

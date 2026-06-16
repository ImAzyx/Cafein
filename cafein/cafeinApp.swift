import SwiftUI

@main
struct cafeinApp: App {
    @State private var manager = SleepManager()

    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: manager)
        } label: {
            Image(systemName: manager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .padding(.top, 5)
                .padding(.trailing, 5)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(manager.isActive ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
        }
        .menuBarExtraStyle(.window)
    }
}

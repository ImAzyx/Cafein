import Combine
import Sparkle
import SwiftUI

/// The dropdown panel shown from the menu bar. Reads `SleepManager` (observation
/// works through a plain `let` — no bindings are needed here) and calls its
/// methods in response to user actions.
struct MenuView: View {
    let manager: SleepManager
    let updater: SPUUpdater

    /// Duration choices. `seconds == nil` means "until disabled manually".
    private struct DurationOption: Identifiable {
        var id: String { label }
        let label: String
        let seconds: TimeInterval?
    }

    private let options: [DurationOption] = [
        .init(label: "30 minutes", seconds: 30 * 60),
        .init(label: "1 hour", seconds: 60 * 60),
        .init(label: "2 hours", seconds: 2 * 60 * 60),
        .init(label: "Until disabled", seconds: nil)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusCard
            primaryToggle
            durationSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 260)
        .animation(.easeInOut(duration: 0.2), value: manager.isActive)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(.tint)
            Text("Cafein ⚡️")
                .font(.headline)
            Spacer()
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(manager.isActive ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)
                .shadow(color: manager.isActive ? .green.opacity(0.6) : .clear, radius: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.isActive ? "No Sleep: ON" : "No Sleep: OFF")
                    .font(.subheadline.weight(.semibold))
                if let remaining = manager.remainingSeconds {
                    Text("Remaining \(formatRemaining(seconds: remaining))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } else if manager.isActive {
                    Text("Staying awake until you disable it")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Primary toggle

    private var primaryToggle: some View {
        Button(action: togglePrimary) {
            Label(
                manager.isActive ? "Disable No Sleep" : "Enable No Sleep",
                systemImage: manager.isActive ? "moon.zzz.fill" : "cup.and.saucer.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(manager.isActive ? .secondary : .accentColor)
    }

    // MARK: - Duration choices

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("KEEP AWAKE FOR")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            ForEach(options) { option in
                Button {
                    manager.enable(duration: option.seconds)
                } label: {
                    HStack {
                        Text(option.label)
                        Spacer()
                        if isSelected(option) {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isSelected(option) ? AnyShapeStyle(.tint.opacity(0.12))
                                           : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            CheckForUpdatesView(updater: updater)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Cafein", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
        }
    }

    // MARK: - Helpers

    private func isSelected(_ option: DurationOption) -> Bool {
        guard manager.isActive else { return false }
        return manager.selectedDuration == option.seconds
    }

    private func togglePrimary() {
        if manager.isActive {
            manager.disable()
        } else {
            manager.enable(duration: nil)
        }
    }
}

/// Menu row that triggers a Sparkle update check, disabled while one is in flight.
private struct CheckForUpdatesView: View {
    @StateObject private var model: CheckForUpdatesModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _model = StateObject(wrappedValue: CheckForUpdatesModel(updater: updater))
    }

    var body: some View {
        Button {
            updater.checkForUpdates()
        } label: {
            Label("Check for Updates…", systemImage: "arrow.down.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!model.canCheckForUpdates)
    }
}

private final class CheckForUpdatesModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }
}

#Preview {
    MenuView(
        manager: SleepManager(autoStartTimer: false),
        updater: SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        ).updater
    )
}

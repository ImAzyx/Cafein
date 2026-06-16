import Foundation
import Observation

/// Single source of truth for cafein's sleep-prevention state.
///
/// Owns an injected power assertion and notifier (so the state machine is
/// testable in isolation) plus a countdown timer. Marked `@MainActor` because
/// it drives SwiftUI state and a main-run-loop `Timer`.
@MainActor
@Observable
final class SleepManager {
    enum Mode: Equatable { case manual, timed }

    private(set) var isActive = false
    private(set) var mode: Mode = .manual
    private(set) var remainingSeconds: Int?
    /// The duration the user picked for the active timer (nil = "until disabled").
    /// Used by the UI to mark the selected option; not affected by countdown.
    private(set) var selectedDuration: TimeInterval?

    private let assertion: PowerAssertionControlling
    private let notifier: AutoDisableNotifying
    private let autoStartTimer: Bool
    private var timer: Timer?

    init(
        assertion: PowerAssertionControlling = IOKitPowerAssertion(),
        notifier: AutoDisableNotifying = NotificationService(),
        autoStartTimer: Bool = true
    ) {
        self.assertion = assertion
        self.notifier = notifier
        self.autoStartTimer = autoStartTimer
    }

    /// Enable sleep prevention. `duration == nil` means "until disabled".
    func enable(duration: TimeInterval?) {
        notifier.requestAuthorizationIfNeeded()
        guard assertion.acquire(reason: "cafein is keeping your Mac awake") else {
            // Acquire failed: stay inactive, don't pretend it worked.
            isActive = false
            return
        }
        invalidateTimer()
        isActive = true
        selectedDuration = duration
        if let duration {
            mode = .timed
            remainingSeconds = Int(duration)
            if autoStartTimer { startTimer() }
        } else {
            mode = .manual
            remainingSeconds = nil
        }
    }

    /// Disable sleep prevention. `notify` is `true` only on automatic timer expiry.
    func disable(notify: Bool = false) {
        invalidateTimer()
        assertion.release()
        isActive = false
        mode = .manual
        remainingSeconds = nil
        selectedDuration = nil
        if notify { notifier.notifyAutoDisabled() }
    }

    /// Decrement the countdown; auto-disables (with notification) at zero.
    /// Separated from the `Timer` so tests can drive it deterministically.
    func advanceTimer(by seconds: Int) {
        guard mode == .timed, let remaining = remainingSeconds else { return }
        let next = remaining - seconds
        if next <= 0 {
            disable(notify: true)
        } else {
            remainingSeconds = next
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; hop to the main actor to satisfy isolation.
            MainActor.assumeIsolated {
                self?.advanceTimer(by: 1)
            }
        }
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        // deinit is nonisolated in Swift 6; safe to assume main actor here because
        // SleepManager is @MainActor-isolated and can only be released from the main actor.
        MainActor.assumeIsolated {
            timer?.invalidate()
            assertion.release()
        }
    }
}

import Foundation
import IOKit.pwr_mgt

/// Abstraction over a system power assertion so `SleepManager` can be tested
/// without touching IOKit.
protocol PowerAssertionControlling: AnyObject {
    var isHeld: Bool { get }
    /// Acquire a "no idle system sleep" assertion. Returns `true` on success
    /// (or if already held). Idempotent.
    func acquire(reason: String) -> Bool
    /// Release the assertion if held. Idempotent.
    func release()
}

/// Real implementation backed by IOKit.
///
/// Uses `PreventSystemSleep` which prevents idle sleep and system sleep on AC.
/// On battery + lid closed, macOS enforces sleep at the firmware level regardless
/// of any power assertion — this is an Apple Silicon / macOS 14+ restriction.
final class IOKitPowerAssertion: PowerAssertionControlling {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isHeld = false

    func acquire(reason: String) -> Bool {
        guard !isHeld else { return true }
        let result = IOPMAssertionCreateWithName(
            "PreventUserIdleSystemSleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        isHeld = (result == kIOReturnSuccess)
        return isHeld
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isHeld = false
    }
}

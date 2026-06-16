import XCTest
@testable import cafein

private final class FakeAssertion: PowerAssertionControlling {
    var isHeld = false
    var acquireCount = 0
    var releaseCount = 0
    var acquireSucceeds = true

    func acquire(reason: String) -> Bool {
        acquireCount += 1
        if acquireSucceeds { isHeld = true }
        return isHeld
    }

    func release() {
        releaseCount += 1
        isHeld = false
    }
}

private final class FakeNotifier: AutoDisableNotifying {
    var authRequests = 0
    var autoDisableNotifications = 0

    func requestAuthorizationIfNeeded() { authRequests += 1 }
    func notifyAutoDisabled() { autoDisableNotifications += 1 }
}

@MainActor
final class SleepManagerTests: XCTestCase {
    private func makeSUT() -> (SleepManager, FakeAssertion, FakeNotifier) {
        let assertion = FakeAssertion()
        let notifier = FakeNotifier()
        let sut = SleepManager(assertion: assertion, notifier: notifier, autoStartTimer: false)
        return (sut, assertion, notifier)
    }

    func test_enableManual_acquiresAssertion_andIsActiveWithoutCountdown() {
        let (sut, assertion, _) = makeSUT()
        sut.enable(duration: nil)
        XCTAssertTrue(sut.isActive)
        XCTAssertEqual(sut.mode, .manual)
        XCTAssertNil(sut.remainingSeconds)
        XCTAssertEqual(assertion.acquireCount, 1)
        XCTAssertTrue(assertion.isHeld)
    }

    func test_enableTimed_setsRemainingSeconds_andTimedMode() {
        let (sut, _, _) = makeSUT()
        sut.enable(duration: 1800)
        XCTAssertEqual(sut.mode, .timed)
        XCTAssertEqual(sut.remainingSeconds, 1800)
        XCTAssertEqual(sut.selectedDuration, 1800)
        XCTAssertTrue(sut.isActive)
    }

    func test_disableManually_releasesAssertion_andDoesNotNotify() {
        let (sut, assertion, notifier) = makeSUT()
        sut.enable(duration: nil)
        sut.disable(notify: false)
        XCTAssertFalse(sut.isActive)
        XCTAssertFalse(assertion.isHeld)
        XCTAssertEqual(assertion.releaseCount, 1)
        XCTAssertEqual(notifier.autoDisableNotifications, 0)
    }

    func test_timerReachingZero_autoDisables_andNotifies() {
        let (sut, assertion, notifier) = makeSUT()
        sut.enable(duration: 3)
        sut.advanceTimer(by: 3)
        XCTAssertFalse(sut.isActive)
        XCTAssertNil(sut.remainingSeconds)
        XCTAssertFalse(assertion.isHeld)
        XCTAssertEqual(notifier.autoDisableNotifications, 1)
    }

    func test_failedAcquire_leavesInactive() {
        let (sut, assertion, _) = makeSUT()
        assertion.acquireSucceeds = false
        sut.enable(duration: nil)
        XCTAssertFalse(sut.isActive)
        XCTAssertFalse(assertion.isHeld)
    }

    func test_enableTimed_thenEnableManual_clearsCountdown() {
        let (sut, _, _) = makeSUT()
        sut.enable(duration: 60)
        sut.enable(duration: nil)
        XCTAssertEqual(sut.mode, .manual)
        XCTAssertNil(sut.remainingSeconds)
        XCTAssertNil(sut.selectedDuration)
    }
}

@MainActor
final class TimeFormattingTests: XCTestCase {
    func test_formatsUnderOneHour_asMinutesSeconds() {
        XCTAssertEqual(formatRemaining(seconds: 90), "1:30")
        XCTAssertEqual(formatRemaining(seconds: 5), "0:05")
    }

    func test_formatsOverOneHour_asHoursMinutesSeconds() {
        XCTAssertEqual(formatRemaining(seconds: 3661), "1:01:01")
        XCTAssertEqual(formatRemaining(seconds: 7200), "2:00:00")
    }
}

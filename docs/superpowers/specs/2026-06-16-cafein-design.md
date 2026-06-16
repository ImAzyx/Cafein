# cafein — Design Spec

**Date:** 2026-06-16
**Status:** Approved (pending implementation plan)

## Summary

`cafein` is a minimal macOS menu bar app, written in Swift + SwiftUI, that lets
the user prevent the Mac from sleeping and re-enable sleep easily. It lives only
in the menu bar (no dock icon), exposes timer options, shows live status, and
notifies the user when a timer auto-disables sleep prevention.

## Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Sleep-prevention mechanism | IOKit power assertions (`IOPMAssertionCreateWithName`) | Native, in-process, no subprocess/shell/sudo, clean create/release and state query. |
| Awake scope | System only (`kIOPMAssertionTypeNoIdleSleep`) | Prevent system idle sleep; allow the display to dim/sleep. Like `caffeinate -i`. |
| Minimum target | macOS 14 (Sonoma) | Stable `MenuBarExtra`, modern SwiftUI, broad install base in 2026. |
| Menu bar UI style | `MenuBarExtra` with `.menuBarExtraStyle(.window)` | Real SwiftUI panel for custom layout, live countdown, and indicators. |
| Dock icon | Hidden via `LSUIElement = YES` | Menu-bar-only presence. |
| Menu bar icon | `cup.and.saucer` (off) / `cup.and.saucer.fill` (on) | Reflects active state at a glance. |

## Requirements (from source spec)

- Menu bar icon with status indicator.
- Toggle: "Enable No Sleep" / "Disable No Sleep".
- Timer options: 30 minutes, 1 hour, 2 hours, Until disabled manually.
- Prevent sleep via a native macOS-safe method (IOKit power assertions). No sudo.
- Show current status in the menu: No Sleep ON/OFF, and remaining time if a timer
  is active.
- Send a macOS notification when No Sleep is **automatically** disabled (timer
  expiry).
- Quit button.
- No dock icon (`MenuBarExtra`, `LSUIElement`).
- No destructive shell commands; avoid `sudo pmset`.

## Architecture

A single-target SwiftUI app with four focused units.

### `cafeinApp.swift` — app entry point
- `@main struct cafeinApp: App`.
- Body is a single `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
- Menu bar label is an SF Symbol driven by `SleepManager.isActive`.
- Owns the `SleepManager` instance and injects it into `MenuView`.

### `SleepManager.swift` — state + IOKit + timer (single source of truth)
- `@Observable final class SleepManager`.
- State: `isActive: Bool`, `mode: Mode` (`.manual` / `.timed`), `remainingSeconds: Int?`.
- IOKit: holds an `IOPMAssertionID`. `enable(duration:)` creates a
  `kIOPMAssertionTypeNoIdleSleep` assertion; `disable(notify:)` releases it.
- Timer: a repeating 1s tick decrements `remainingSeconds`; at zero it calls
  `disable(notify: true)` (auto-disable path → notification).
- Defensive cleanup: release any held assertion on disable, on expiry, and on
  app termination, so an assertion is never leaked.
- Failure handling: if assertion creation fails, remain inactive and do not
  report success.

### `NotificationService.swift` — local notifications
- Thin wrapper over `UserNotifications`.
- Requests authorization lazily (on first enable).
- Posts a local notification when a timer auto-expires.

### `MenuView.swift` — the dropdown panel
- Observes `SleepManager`.
- Status row: ON/OFF text + colored indicator (green active / gray idle).
- Live remaining-time countdown when a timer is active (formatted mm:ss / h:mm).
- Primary toggle button: "Enable No Sleep" / "Disable No Sleep".
- Four duration choices: 30m, 1h, 2h, Until disabled manually.
- Quit button.

## Data Flow

```
MenuView (observes) ──user action──▶ SleepManager methods
       ▲                                   │
       │ @Observable re-render             ├─ IOKit assertion create/release
       └───────────────────────────────────┤
                                           ├─ Timer tick → remainingSeconds--
                                           └─ on expiry → NotificationService
cafeinApp menu bar icon ◀── isActive ── SleepManager
```

## Info.plist Settings

- `LSUIElement` = `YES` (no dock icon).
- `NSUserNotificationsUsageDescription` / notification capability as required for
  `UserNotifications` authorization.
- Minimum deployment target: macOS 14.0.

## Testing

- `SleepManager` timer/auto-disable logic is unit-testable by injecting the tick
  source / duration, so the state machine (enable → countdown → auto-disable →
  notify) can be verified without real IOKit assertions.
- The IOKit call is isolated behind a single method so state transitions can be
  tested independently of the system API.

## Non-Goals (YAGNI)

- No display-sleep prevention toggle (system-only scope chosen).
- No launch-at-login, no preferences window, no global hotkeys, no menu bar
  icon customization.
- No subprocess (`caffeinate`) fallback.
```
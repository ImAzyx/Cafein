<div align="center">

# ☕ Cafein ⚡️

**Keep your Mac awake. Nothing more.**

<br/>

[![macOS](https://img.shields.io/badge/macOS-14%20Sonoma%2B-black?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/macos/sonoma/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-%E2%9C%93-0066FF?style=for-the-badge&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![IOKit](https://img.shields.io/badge/IOKit-no%20sudo-34C759?style=for-the-badge)](https://developer.apple.com/documentation/iokit)

<br/>

*A menu bar app. A coffee cup. A single job.*

</div>

---

## The idea

Your Mac falls asleep mid-download, mid-render, mid-video call. `caffeinate` fixes it but lives in a terminal tab you forget to close. Cafein lives in the menu bar, out of your dock, and works with one click.

No subprocess. No `sudo pmset`. No preferences window. No dock icon. Just an IOKit power assertion and a cup that fills when it's on.

---

## What you get

| | |
|---|---|
| **☕ → ☕ filled** | Menu bar icon that shows state at a glance |
| **One-click toggle** | Enable / Disable No Sleep |
| **Timer options** | 30 min · 1 h · 2 h · Until disabled |
| **Live countdown** | Remaining time in the panel, updating every second |
| **Auto-notify** | macOS notification when a timer expires |
| **Clean exit** | IOKit assertion always released — no leftover wake locks |

---

## Requirements

- **macOS 14 (Sonoma)** or later
- **Xcode 15+** to build from source

---

## Build & run

```bash
open cafein.xcodeproj
```

1. **Sign it** — Target `cafein` → *Signing & Capabilities* → pick your Team.  
   Required so `UserNotifications` can actually deliver alerts.

2. **Run** — `⌘R` with the `cafein` scheme and a *My Mac* destination.  
   A cup icon appears in the menu bar. No dock icon. That's it.

### Tests

```bash
xcodebuild test \
  -project cafein.xcodeproj \
  -scheme cafein \
  -destination 'platform=macOS'
```

Or just `⌘U` in Xcode.

---

## Verify it's actually working

With No Sleep **ON**, open a terminal and run:

```bash
pmset -g assertions
```

You'll see a `PreventUserIdleSystemSleep` assertion attributed to `cafein`. Disable it (or let a timer run out) and the entry disappears.

---

## How it works

Sleep prevention happens entirely in `SleepManager.swift`. On enable, it acquires a `PreventUserIdleSystemSleep` IOKit power assertion — the same one `caffeinate -i` uses under the hood. On disable (manual or timer expiry), it releases it. The assertion is always cleaned up: on toggle off, on timer end, and in `deinit`.

```
MenuView ──action──▶ SleepManager ──────────▶ IOKit assertion
   ▲                     │                    (create / release)
   │  @Observable        ├──▶ Timer tick
   └─── re-render        └──▶ NotificationService (on expiry)

cafeinApp icon ◀── isActive ── SleepManager
```

> **One caveat:** on Apple Silicon with the lid closed on battery, macOS enforces sleep at the firmware level regardless of any user-space assertion. That's a hardware restriction, not a bug.

---

## Project layout

```
cafein/
├── cafeinApp.swift             @main · MenuBarExtra · status cup icon
├── SleepManager.swift          @Observable state machine + countdown timer
├── PowerAssertion.swift        IOKit wrapper behind a testable protocol
├── NotificationService.swift   UNUserNotificationCenter wrapper
├── MenuView.swift              dropdown panel — status · toggle · durations
└── TimeFormatting.swift        mm:ss / h:mm display formatting

cafeinTests/
└── SleepManagerTests.swift     state machine + formatter unit tests
```

`SleepManager` accepts injected `PowerAssertionControlling` and `AutoDisableNotifying` so the full enable → countdown → auto-disable → notify flow is testable without touching IOKit or the real notification center.

---

## Limitations

- Display sleep is intentionally **not** prevented — only system idle sleep. The screen will still dim.
- No launch-at-login (intentional — out of scope).
- On Apple Silicon + battery + closed lid, firmware wins. No app can override this.

---

<div align="center">

Built with SwiftUI · IOKit · zero dependencies

</div>

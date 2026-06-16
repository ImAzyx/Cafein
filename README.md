# cafein ☕

A tiny macOS **menu bar** app that prevents your Mac from sleeping, with timer
options. No dock icon, no `sudo`, no shell commands — it uses native **IOKit
power assertions**.

## Features

- Menu bar cup icon that fills when active (status indicator).
- Toggle: **Enable No Sleep** / **Disable No Sleep**.
- Timer options: **30 minutes**, **1 hour**, **2 hours**, **Until disabled**.
- Live status panel: ON/OFF and remaining time.
- macOS notification when a timer expires and sleep is re-enabled.
- Quit button. No dock icon.

## Requirements

- macOS **14 (Sonoma)** or later
- **Xcode 15** or later (to build)

## How it works

While active, cafein creates a `kIOPMAssertionTypeNoIdleSleep` IOKit power
assertion and releases it when you disable it or a timer ends. This prevents
**system** idle sleep while still allowing the display to dim. No elevated
privileges, no subprocess, no `pmset`.

## Project layout

```
cafein/
├── cafein/
│   ├── cafeinApp.swift          # @main App + MenuBarExtra + status icon
│   ├── SleepManager.swift       # @Observable state machine + countdown timer
│   ├── PowerAssertion.swift     # PowerAssertionControlling + IOKit implementation
│   ├── NotificationService.swift# AutoDisableNotifying + UserNotifications impl
│   ├── MenuView.swift           # dropdown panel UI
│   ├── TimeFormatting.swift     # remaining-seconds → display string
│   └── Info.plist               # LSUIElement = YES (no dock icon)
└── cafeinTests/
    └── SleepManagerTests.swift  # state-machine + formatter unit tests
```

## Build & run

These sources are ready to drop into an Xcode project. On a Mac:

### 1. Create the app target

1. **Xcode → File → New → Project → macOS → App.**
2. Product Name: `cafein` · Interface: **SwiftUI** · Language: **Swift**.
   Save it so `cafein.xcodeproj` sits at the repo root (next to the `cafein/`
   source folder).
3. Delete Xcode's generated `ContentView.swift` and the generated
   `cafeinApp.swift` (Move to Trash) — you'll use the ones in this repo.

### 2. Add the source files

1. In the Project Navigator, **add the files** from `cafein/` to the `cafein`
   target: `cafeinApp.swift`, `SleepManager.swift`, `PowerAssertion.swift`,
   `NotificationService.swift`, `MenuView.swift`, `TimeFormatting.swift`.
2. Add a **Unit Testing Bundle** target (File → New → Target → Unit Testing
   Bundle, name `cafeinTests`) and add `cafeinTests/SleepManagerTests.swift` to it.

### 3. Configure the target

1. Target `cafein` → **General** → Minimum Deployments → macOS **14.0**.
2. Target → **Build Settings**:
   - **Generate Info.plist File** → `No`
   - **Info.plist File** → `cafein/Info.plist`
3. Target → **Signing & Capabilities** → keep *Automatically manage signing* and
   select your team (a signed bundle is required for notifications to deliver).

### 4. Run

- Select the `cafein` scheme and a **My Mac** destination, then **⌘R**.
- A cup icon appears in the menu bar; there is **no** dock icon.
- Click it to open the panel.

### Run the tests

In Xcode press **⌘U**, or from the command line:

```bash
xcodebuild test -project cafein.xcodeproj -scheme cafein -destination 'platform=macOS'
```

## Verifying it really prevents sleep

With No Sleep ON, run:

```bash
pmset -g assertions
```

You should see a `PreventUserIdleSystemSleep` assertion attributed to `cafein`.
Disable No Sleep (or let the timer expire) and the entry disappears.

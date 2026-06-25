# Simple Pomo

A native macOS Pomodoro timer with tasks, categories and rich reports — inspired by [pomofocus.io](https://pomofocus.io), built with **SwiftUI** and **Swift Charts**.

## Features

- **Native macOS app** — pure SwiftUI/AppKit. No Electron, no web view, no Python.
- **Three phases** with auto-cycling — Pomodoro / Short Break / Long Break.
  Long break triggers automatically every N pomodoros (configurable).
- **Tasks** with categories, estimated vs. completed pomodoros, notes, and
  "set as active" selection. Quick-task list on the focus screen.
- **Categories** are first-class — assign per task, filter the task list,
  and drive the reporting breakdown.
- **Reports** with Swift Charts:
  - Toggle between **Day / Week / Month / Quarter**.
  - Stacked bar chart of focus minutes by category over time.
  - Donut chart of category share, and top-task ranking.
  - Recent sessions list.
- **Local storage** — a single JSON file under
  `~/Library/Application Support/SimplePomo/store.json`. No accounts, no cloud,
  no telemetry.
- **Sounds + notifications** — system sound (Glass/Ping/Tink/Pop/Hero/Funk/Submarine)
  on phase end plus a macOS user notification banner.
- **Keyboard shortcuts** — `Space` start/pause, `⌘R` reset, `⌘K` skip, `⌘N` new task.
- **Native settings** via standard `⌘,` Settings window (Timer/Categories/Data/About).

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ or the Swift 5.9+ command-line toolchain (already installed if you have Xcode)

## Build & run

### Quick: build a real `.app` bundle

```bash
./build_app.sh release
open build/SimplePomo.app
```

`build_app.sh` produces a double-clickable `build/SimplePomo.app` with `Info.plist`,
a generated `AppIcon.icns`, and proper Dock activation.

To install it like any other Mac app:

```bash
cp -R build/SimplePomo.app /Applications/
open /Applications/SimplePomo.app
```

### Dev loop — run via SwiftPM

```bash
swift run
```

This is the fastest iteration path (debug build, opens the window directly).

### Open in Xcode

```bash
open Package.swift
```

> **Note for zsh users:** interactive zsh does not treat `#` as a comment character
> by default, so don't paste shell commands with trailing `# ...` annotations into
> your terminal — they'll be passed as extra arguments. Either run
> `setopt interactive_comments` first, or just paste the commands without the
> trailing comments.

## Project structure

```
simple_pomo/
├── Package.swift                    SwiftPM manifest (macOS 14+, executable target)
├── build_app.sh                     Wraps SwiftPM build into a .app with icon + Info.plist
├── Sources/SimplePomo/
│   ├── App.swift                    @main, NSApplicationDelegate, Settings scene
│   ├── ContentView.swift            App shell, tab switching, themed header
│   ├── FocusView.swift              Timer card, phase tabs, controls, active-task panel
│   ├── TaskListView.swift           Task CRUD + editor sheet, category filtering
│   ├── ReportsView.swift            Day/Week/Month/Quarter charts (Swift Charts)
│   ├── SettingsView.swift           ⌘, Settings: timer, categories, data, about
│   ├── PomodoroTimer.swift          Timer engine, auto-cycle, session recording, sound
│   ├── DataStore.swift              JSON persistence in ~/Library/Application Support
│   └── Models.swift                 PomoTask, PomoSession, AppSettings, Phase, StoreData
```

## Design notes

- **Color system**: each phase has its own tint — tomato (focus), teal (short break),
  ocean blue (long break). The window background fades to the active phase's accent
  with a soft gradient.
- **Glass UI**: light translucent cards on a dark background give the app a calm,
  focus-friendly feel without distraction.
- **Single source of truth**: `DataStore` is an `ObservableObject` injected via
  `@EnvironmentObject`. Writes are debounced to disk; phase-completion events
  save immediately so you never lose a finished pomodoro.
- **Session model**: only *focus* sessions are recorded (breaks aren't reported on),
  matching how productivity is actually measured. Skipped focus sessions are
  recorded only if at least 60s of work elapsed.
- **Quarter math**: quarters are computed locally with `Calendar` from
  `month` (Q1 = Jan–Mar, Q2 = Apr–Jun, ...) so the user's region/first-weekday
  setting is respected.

## Data file

The full app state lives in:

```
~/Library/Application Support/SimplePomo/store.json
```

You can back it up, sync it (e.g. via iCloud Drive symlink), or wipe it from
**Settings → Data**. Reveal it in Finder from the same panel.

## License

MIT — do whatever you want with it.

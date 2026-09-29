# Hours Tracker

Native macOS menu bar app for tracking work hours per project.

Built with SwiftUI (`MenuBarExtra`). Lives only in the menu bar — no Dock icon.

<img width="658" height="746" alt="image" src="https://github.com/user-attachments/assets/6f788117-80e2-4f18-b17c-3fe518b16bf4" />


## Features

- **Live timer** — hero card with project picker, big elapsed time, Recording / Not running status, and Start/Stop
- **Liquid Glass** on macOS 26+ (when built with a macOS 26+ SDK); tinted fills on macOS 13–25
- **Projects** — colour dots, Today / Week / All totals, play/stop controls; click to select, double-click to start, right-click for Start / Rename / Color / Show Sessions / Delete
- **Quick add** — `+` or ⌘N, duplicate-name check, Return to add, Esc to cancel
- **Manage Projects** (⌘,) — rename, delete with confirmation, sessions grouped by day
- **Export CSV** (⌘E) — in-popover date range (Today / This Week / This Month / All Time / Custom); filter by session start in local time; **Export This Week** remains a one-shot (`project,start,end,duration_hours`)
- **Launch at Login** toggle (`SMAppService`)
- **Persistence** — JSON in `~/Library/Application Support/HoursTracker/data.json`; a running timer resumes across quit/relaunch/reboot
- Only one timer runs at a time (starting another project stops the current one)

## Requirements

- macOS 13 (Ventura) or later
- [Xcode](https://developer.apple.com/xcode/) 15+ **or** the Command Line Tools (`xcode-select --install`)

## Build & install

```bash
git clone https://github.com/AlexMassin/HoursTracker.git
cd HoursTracker
./build.sh
```

This produces an ad-hoc-signed `build/HoursTracker.app` and `build/HoursTracker.zip`.

```bash
mkdir -p ~/Applications
cp -R build/HoursTracker.app ~/Applications/
open ~/Applications/HoursTracker.app
```

`build.sh` prefers a macOS 26+ SDK when available (for Liquid Glass). Override the toolchain with:

```bash
DEVELOPER_DIR=/path/to/Developer ./build.sh
```

## Gatekeeper note

The app is **ad-hoc signed, not notarized**. Local builds normally open fine. If you download a zip (or the app gets a quarantine flag), macOS may block it:

- Right-click the app → **Open** → **Open**, or
- System Settings → Privacy & Security → **Open Anyway**, or
- `xattr -dr com.apple.quarantine ~/Applications/HoursTracker.app`

Launch at Login may need approval under System Settings → General → Login Items. It works best when the app lives in `/Applications` or `~/Applications` and is not moved afterwards.

## License

[MIT](LICENSE) © 2026 Alexander Massin

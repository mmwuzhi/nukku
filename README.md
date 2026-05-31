# Nukku

A macOS notch utility that turns the MacBook notch into an interactive panel — inspired by Alcove and NotchNook.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black) ![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange) ![SPM](https://img.shields.io/badge/build-SPM-blue)

## Features

- **Notch panel** — hover (or click) the notch to expand a full widget panel
- **HUD overlays** — volume and brightness changes show a slim indicator inside the notch, then auto-dismiss
- **Widgets**
  - Now Playing — album art, track title, playback controls via MediaRemote
  - Clock — live time display
  - System Monitor — CPU, memory, network throughput
  - File Drop — drag files in; open or reveal in Finder
  - Calendar — today's events via EventKit
- **Menu bar presence** — fully `.accessory` mode, never appears in the Dock or app switcher
- **Launch at login** — via `SMAppService`
- **Multi-screen aware** — repositions to the notch screen on display changes
- **Full-screen compatible** — stays visible in full-screen spaces

## Requirements

- macOS 26 (Tahoe) or later
- MacBook with a notch (works on non-notch Macs with menu-bar fallback)
- Xcode 26 / Swift 6.2

## Building

```bash
git clone https://github.com/mmwuzhi/nukku
cd nukku
swift run
```

Or open the directory in Xcode (File → Open… → select the folder) and run the `Nukku` scheme.

## Preferences

| Setting | Options | Default |
|---|---|---|
| Expand trigger | Hover / Click | Hover |
| Expand delay | 0 – 0.5 s | 0.1 s |
| Collapse delay | 0.1 – 1.0 s | 0.3 s |
| Launch at login | On / Off | On |

Access preferences from the status-bar menu or by clicking the gear icon in the expanded panel.

## Architecture Notes

Nukku uses a **fixed-canvas window** (700 × 340 pt) that never resizes — all animation happens inside SwiftUI via a single spring. This eliminates the tearing that occurs when AppKit window geometry changes race against SwiftUI spring interpolation.

See [`CLAUDE.md`](CLAUDE.md) for full architecture documentation, directory layout, and contribution guide.

## Privacy

- **Calendar access** — requested on first Calendar widget use; only reads today's events
- **Camera access** — not yet requested (camera widget is planned)
- **No network requests** — all data is local; no analytics, no telemetry

## License

MIT

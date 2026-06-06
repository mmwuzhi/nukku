# Nukku — Claude Code Context

## Project Overview

Nukku is a macOS notch utility app (similar to Alcove / NotchNook) built with Swift 6.2 and SwiftUI on macOS 26 (Tahoe). It lives in the MacBook notch area, using a fused Dynamic-Island-style silhouette with:

- an always-visible rest pill in the notch area
- hover/click expansion into widgets
- slim HUD overlays for volume, brightness, battery, and notifications
- collapsed media controls with browser and Spotify-aware now-playing detection

## Build & Run

```bash
# Build (macOS only — AppKit/IOKit not available on Linux)
swift build

# Run tests (cross-platform, limited to non-AppKit logic)
swift test

# Run the app — must be wrapped as .app, see below
./Scripts/package.sh --run
```

The bare executable cannot be run directly (`swift run`, `./.build/release/Nukku`) because
`UNUserNotificationCenter` and other system services require a bundle identity (Info.plist +
CFBundleIdentifier). `Scripts/package.sh` builds release, wraps it as `.build/Nukku.app`, and
ad-hoc codesigns it with the entitlements in `.entitlements/Nukku.entitlements`.

No Xcode project file — pure Swift Package Manager. Target: macOS 26+, Swift 6 strict concurrency.

## Architecture

### Fixed-Canvas Window (critical — do not revert)

The `NSPanel` is created at a fixed size (700 × 340 pt) and **never resized**. All expand/collapse animation happens inside SwiftUI via a single spring. Resizing the AppKit window during animation causes tearing; the fixed canvas eliminates this.

- Window pinned to top of the notch screen (`safeAreaInsets.top > 0`), x-centered.
- `collectionBehavior: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`
- `isFloatingPanel = true`, `becomesKeyOnlyIfNeeded = true` — clicks don't steal front-app focus.

### HitTest Passthrough

`NotchHostingView` (in `TrackingHostingView.swift`) overrides `hitTest(_:)`. It returns `nil` for any point outside the current interactive rect, letting clicks pass through to menu-bar icons. `interactiveRect` is a closure injected by `NotchWindowManager` that reads `NotchViewModel.targetInteractiveSize`.

Coordinate note: `NSHostingView.isFlipped == true` (y=0 at top). The `hitTest` parameter arrives in the superview's coordinate system; `convert(point, from: nil)` converts from window coords (y-up) to view coords (y-down).

### Hover + Transport Input

Hover detection does not use SwiftUI `.onHover`. `NotchWindowManager` owns it via AppKit:

- a global mouse-move monitor wakes tracking only when the pointer enters the top-center screen band
- once active, a 15 Hz timer samples `NSEvent.mouseLocation`
- separate screen-space rects gate:
  - the visible/clickable silhouette
  - the hover-to-expand zone
  - the collapsed media transport zone

Collapsed transport clicks are also handled at the AppKit layer through `NotchPanel.sendEvent(_:)`, so play/pause still works even when SwiftUI button delivery is flaky inside the non-activating panel.

### State Machine (`NotchViewModel`)

```
.collapsed  ──expand()──▶  .expanded
.expanded  ──collapse()──▶  .collapsed   (delayed, reads PreferencesManager.collapseDelay)
.expanded  ──forceCollapse()──▶  .collapsed   (immediate, for click-mode toggle)
```

`setActive(_ id:)` chains `deactivate → set id → activate` through `WidgetRegistry`.

Presentation is derived separately from the expand/collapse state:

- `.rest`
- `.open`
- `.hud`

`NotchViewModel.currentMetrics` resolves the fused silhouette geometry for the current presentation mode.

### Concurrency Model

- All ViewModels: `@Observable @MainActor`
- CoreAudio / IOKit callbacks: fire on background threads — capture only value types before the block, dispatch mutations via `DispatchQueue.main.async` or `Task { @MainActor in }`
- AppleScript media helpers run off-main and marshal results back through async continuations
- SwiftUI animations: single `.animation(spring, value: vm.state)` — no manual interpolation

## Directory Structure

```
Sources/Nukku/
├── Animation/          NotchAnimator.swift — spring constants
├── App/                AppDelegate (owns all VMs), NukkuApp entry point
├── Preferences/        PreferencesManager (@Observable singleton), PreferencesView
├── Services/           VolumeMonitor, BrightnessMonitor, BatteryMonitor,
│                       LaunchAtLoginService, ScreenChangeService, NotificationService
├── Utilities/          Constants.swift, Extensions (NSScreen+Notch, Color+Theme)
├── ViewModels/         NotchViewModel, MediaViewModel, CalendarViewModel,
│                       FileDropViewModel, AppLauncherViewModel,
│                       ShortcutsViewModel, CameraViewModel, HUDViewModel
├── Views/              NotchContainerView, CollapsedView, ExpandedView,
│                       NotchShapeView, HUDView
├── Widgets/
│   ├── Core/           WidgetProtocol (AnyNukkuWidgetBox), WidgetRegistry, WidgetContainer
│   ├── Media/          MediaWidget, MediaWidgetView, MediaRemoteClient,
│   │                   AudibleProcessMonitor, BrowserTabFetcher
│   ├── FileDrop/       FileDropWidget, FileDropWidgetView
│   ├── Calendar/       CalendarWidget, CalendarWidgetView, EventKitClient
│   ├── AppLauncher/    AppLauncherWidget, AppLauncherWidgetView
│   ├── Shortcuts/      ShortcutsWidget, ShortcutsWidgetView
│   └── Camera/         CameraWidget, CameraWidgetView
└── Window/             NotchPanel, NotchWindowManager, TrackingHostingView (NotchHostingView)
```

## Key Constants (`Utilities/Constants.swift`)

| Constant | Value | Notes |
|---|---|---|
| `canvasWidth` | 700 | Fixed window width — never change at runtime |
| `canvasHeight` | 340 | Fixed window height |
| `collapsedWidth` | 250 | Approx MacBook notch width |
| `collapsedHeight` | 38 (runtime) | Overwritten from `screen.safeAreaInsets.top` |
| `Geometry.rest` | `282 × 38` | Collapsed pill body-aligned content box |
| `Geometry.openBase` | `318 × 156` | Compact open silhouette for the media-first design |
| `Geometry.hud` | `348 × 64` | Volume / brightness / battery / notification HUD silhouette |
| `Geometry.tension` | `0.62` | Concave melt control for the fused notch shape |

## Media Detection

`MediaViewModel.refresh()` resolves sources in this order:

1. Spotify AppleScript path: title, artist, and player state from Spotify directly
2. MediaRemote per-app path: title, artist, artwork, and `isPlaying` when available
3. CoreAudio fallback: audible app icon plus browser audible-tab title via AppleScript

Transport control also branches by source:

- Spotify: `playpause` via AppleScript
- other apps: `MRMediaRemoteSendCommand(.togglePlayPause)`

## Adding a Widget

1. Create `Widgets/MyFeature/MyFeatureWidget.swift` using `makeWidgetBox(id:displayName:iconName:activate:deactivate:content:)`
2. Create the SwiftUI view in `Widgets/MyFeature/MyFeatureView.swift`
3. Create a ViewModel in `ViewModels/MyFeatureViewModel.swift` (`@Observable @MainActor`)
4. Register in `WidgetRegistry.registerDefaults(...)` and add the VM property to `AppDelegate`

The `activate`/`deactivate` callbacks are called automatically by `NotchViewModel.setActive(_:)` when the user switches tabs.

## Private Frameworks

- **MediaRemote**: loaded at runtime via `dlopen` / `dlsym` — no compile-time import. See `MediaRemoteClient.swift`.
- **IOKit display brightness**: `IODisplayGetFloatParameter` with service `"IODisplayConnect"`. Deprecated in macOS 12 but still functional on macOS 26.

## What's Done / What's Next

See the plan file at `.claude/plans/` for the full feature checklist. Short version:

**Done**: fixed-window arch, fused notch silhouette, collapsed media shelves, browser/Spotify-aware media detection, AppKit transport hit-testing, HUD (volume + brightness + battery + notifications), preferences, calendar auto-refresh, app launcher / shortcuts / camera widgets, packaging + hardened runtime.

**Pending**:
- Title/source attribution still has edge cases for some browser audio sessions. See `.claude/todos.md`.

## Codesigning (required before distribution)

For local development, `Scripts/package.sh` ad-hoc signs automatically. For distribution use a
real Developer ID:

```bash
NUKKU_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/package.sh
```

The script applies `--options runtime` + `--timestamp` when a real identity is provided. The
`.entitlements/Nukku.entitlements` file enables hardened runtime (blocks `DYLD_INSERT_LIBRARIES`
injection) while keeping library validation active (Apple-signed MediaRemote.framework loads
correctly). Entitlements declared: user-selected file read-write (FileDrop), calendar access
(Calendar widget), camera access (Camera widget).

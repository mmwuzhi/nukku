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
│                       FileDropViewModel, CameraViewModel, HUDViewModel
├── Views/              NotchContainerView, CollapsedView, ExpandedView,
│                       NotchShapeView, HUDView
├── Widgets/
│   ├── Core/           WidgetProtocol (AnyNukkuWidgetBox), WidgetRegistry, WidgetContainer
│   ├── Media/          MediaWidget, MediaWidgetView, SystemNowPlayingClient,
│   │                   AudibleProcessMonitor, BrowserMediaSessionProvider,
│   │                   MediaSessionModels, MediaArtworkCache
│   ├── FileDrop/       FileDropWidget, FileDropWidgetView
│   ├── Calendar/       CalendarWidget, CalendarWidgetView, EventKitClient
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

`MediaViewModel.refresh()` builds `MediaSessionSnapshot` candidates and picks the best via
`MediaSessionResolver`:

1. **System now-playing (primary):** `SystemNowPlayingClient` reads the OS now-playing pipeline via
   the vendored perl-adapter (`Vendor/MediaRemoteAdapter`). Same data Control Center sees — title,
   artist, real artwork, duration/elapsed, playback state — for any app that publishes (Spotify,
   Apple Music, Zen/Safari/Chrome, and Dia for many sites). Provider `.mediaRemote`.
2. **Browser MediaSession JS (opt-in supplement):** for scriptable browsers, read
   `navigator.mediaSession`. Requires the browser to allow JS-over-AppleScript (Dia launch flag
   `--enable-applescript-javascript`; Chromium "Allow JavaScript from Apple Events"), so it is not
   relied upon by default.
3. **CoreAudio fallback:** audible app icon + app-level playback state only.

**Why the perl-adapter:** macOS 15.4+ (incl. Tahoe 26.x) blocks direct in-process MediaRemote
(`dlopen`) behind an entitlement check in `mediaremoted`; Control Center still works because it is
entitled. The adapter shells out to `/usr/bin/perl` (Apple-entitled), which loads a helper dylib and
streams now-playing JSON. See `SystemNowPlayingClient.swift`.

Do **not** display active-tab, focused-tab, ordinary page title, or window title as a media title.
If only app-level audio can be proven (a browser that doesn't publish that page's metadata), show
app-level status copy such as `Dia 正在播放` / `Dia 已暂停` instead of guessing the track title.
When nothing is playing, the collapsed notch stays visually empty/black.

Browser MediaSession artwork URLs may be downloaded and cached in
`~/Library/Caches/Nukku/MediaArtwork/`; ordinary page favicon / `og:image` scraping is intentionally
out of scope for the current media display.

Transport control branches by source:

- Spotify: `playpause` via AppleScript
- other apps: routed through the perl-adapter (`MediaController.togglePlayPause()` / `nextTrack()` …)

## Adding a Widget

1. Create `Widgets/MyFeature/MyFeatureWidget.swift` using `makeWidgetBox(id:displayName:iconName:activate:deactivate:content:)`
2. Create the SwiftUI view in `Widgets/MyFeature/MyFeatureView.swift`
3. Create a ViewModel in `ViewModels/MyFeatureViewModel.swift` (`@Observable @MainActor`)
4. Register in `WidgetRegistry.registerDefaults(...)` and add the VM property to `AppDelegate`

The `activate`/`deactivate` callbacks are called automatically by `NotchViewModel.setActive(_:)` when the user switches tabs.

## Private Frameworks

- **MediaRemote**: accessed **out-of-process** via the vendored perl-adapter (`Vendor/MediaRemoteAdapter`, driven by `SystemNowPlayingClient.swift`). Direct in-process `dlopen` of `MediaRemote.framework` no longer works on macOS 15.4+ (entitlement-gated in `mediaremoted`).
- **IOKit display brightness**: `IODisplayGetFloatParameter` with service `"IODisplayConnect"`. Deprecated in macOS 12 but still functional on macOS 26.

## What's Done / What's Next

See the plan file at `.claude/plans/` for the full feature checklist. Short version:

**Done**: fixed-window arch, fused notch silhouette, collapsed media shelves, trusted media-session display, browser/Spotify-aware media detection, AppKit transport hit-testing, HUD (volume + brightness + battery + notifications), preferences, calendar auto-refresh, camera widget, drag-to-expand file shelf, packaging + hardened runtime.

**Pending**:
- Zen / Firefox rich browser metadata still needs a future companion extension; the current fallback
  deliberately shows app-level playback status instead of guessing titles.

## Codesigning (required before distribution)

For local development, `Scripts/package.sh` ad-hoc signs automatically. For distribution use a
real Developer ID:

```bash
NUKKU_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/package.sh
```

The script applies `--options runtime` + `--timestamp` when a real identity is provided. The
`.entitlements/Nukku.entitlements` file enables hardened runtime (blocks `DYLD_INSERT_LIBRARIES`
injection) while keeping library validation active — the bundled `libMediaRemoteAdapter.dylib` loads
because it shares the app's signing identity (ad-hoc with ad-hoc, or the same Developer ID). The perl
helper that loads the adapter out-of-process is `/usr/bin/perl`, an Apple-entitled system binary, so
it is unaffected by the app's library validation. `package.sh` signs the dylib inside-out before the
app. Entitlements declared: user-selected file read-write (FileDrop), calendar access (Calendar
widget), camera access (Camera widget), AppleEvents automation (opt-in browser MediaSession path).

Note: the packaged `.app` embeds the adapter dylib (`Contents/MacOS`) and `run.pl`
(`Contents/Resources`), so it is self-contained. Shipping a prebuilt binary to other Macs still
requires Developer ID signing + notarization to clear Gatekeeper.


---
# (merged from AGENTS.md on 2026-06-06)

# Global Instructions

## Fix completeness
Before declaring any bug fix done, grep the affected file for every occurrence of the pattern being fixed — not just the first one found. If the fix adds a guard, exclusion, or condition to one call site, check whether the same pattern exists elsewhere in the same file or module and apply the same treatment. Never close a fix after patching only the first match.

--- project-doc ---

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
│                       FileDropViewModel, CameraViewModel, HUDViewModel
├── Views/              NotchContainerView, CollapsedView, ExpandedView,
│                       NotchShapeView, HUDView
├── Widgets/
│   ├── Core/           WidgetProtocol (AnyNukkuWidgetBox), WidgetRegistry, WidgetContainer
│   ├── Media/          MediaWidget, MediaWidgetView, SystemNowPlayingClient,
│   │                   AudibleProcessMonitor, BrowserMediaSessionProvider,
│   │                   MediaSessionModels, MediaArtworkCache
│   ├── FileDrop/       FileDropWidget, FileDropWidgetView
│   ├── Calendar/       CalendarWidget, CalendarWidgetView, EventKitClient
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

`MediaViewModel.refresh()` builds `MediaSessionSnapshot` candidates and picks the best via
`MediaSessionResolver`:

1. **System now-playing (primary):** `SystemNowPlayingClient` reads the OS now-playing pipeline via
   the vendored perl-adapter (`Vendor/MediaRemoteAdapter`). Same data Control Center sees — title,
   artist, real artwork, duration/elapsed, playback state — for any app that publishes (Spotify,
   Apple Music, Zen/Safari/Chrome, and Dia for many sites). Provider `.mediaRemote`.
2. **Browser MediaSession JS (opt-in supplement):** for scriptable browsers, read
   `navigator.mediaSession`. Requires the browser to allow JS-over-AppleScript (Dia launch flag
   `--enable-applescript-javascript`; Chromium "Allow JavaScript from Apple Events"), so it is not
   relied upon by default.
3. **CoreAudio fallback:** audible app icon + app-level playback state only.

**Why the perl-adapter:** macOS 15.4+ (incl. Tahoe 26.x) blocks direct in-process MediaRemote
(`dlopen`) behind an entitlement check in `mediaremoted`; Control Center still works because it is
entitled. The adapter shells out to `/usr/bin/perl` (Apple-entitled), which loads a helper dylib and
streams now-playing JSON. See `SystemNowPlayingClient.swift`.

Do **not** display active-tab, focused-tab, ordinary page title, or window title as a media title.
If only app-level audio can be proven (a browser that doesn't publish that page's metadata), show
app-level status copy such as `Dia 正在播放` / `Dia 已暂停` instead of guessing the track title.
When nothing is playing, the collapsed notch stays visually empty/black.

Browser MediaSession artwork URLs may be downloaded and cached in
`~/Library/Caches/Nukku/MediaArtwork/`; ordinary page favicon / `og:image` scraping is intentionally
out of scope for the current media display.

Transport control branches by source:

- Spotify: `playpause` via AppleScript
- other apps: routed through the perl-adapter (`MediaController.togglePlayPause()` / `nextTrack()` …)

## Adding a Widget

1. Create `Widgets/MyFeature/MyFeatureWidget.swift` using `makeWidgetBox(id:displayName:iconName:activate:deactivate:content:)`
2. Create the SwiftUI view in `Widgets/MyFeature/MyFeatureView.swift`
3. Create a ViewModel in `ViewModels/MyFeatureViewModel.swift` (`@Observable @MainActor`)
4. Register in `WidgetRegistry.registerDefaults(...)` and add the VM property to `AppDelegate`

The `activate`/`deactivate` callbacks are called automatically by `NotchViewModel.setActive(_:)` when the user switches tabs.

## Private Frameworks

- **MediaRemote**: accessed **out-of-process** via the vendored perl-adapter (`Vendor/MediaRemoteAdapter`, driven by `SystemNowPlayingClient.swift`). Direct in-process `dlopen` of `MediaRemote.framework` no longer works on macOS 15.4+ (entitlement-gated in `mediaremoted`).
- **IOKit display brightness**: `IODisplayGetFloatParameter` with service `"IODisplayConnect"`. Deprecated in macOS 12 but still functional on macOS 26.

## What's Done / What's Next

See the plan file at `.claude/plans/` for the full feature checklist. Short version:

**Done**: fixed-window arch, fused notch silhouette, collapsed media shelves, trusted media-session display, browser/Spotify-aware media detection, AppKit transport hit-testing, HUD (volume + brightness + battery + notifications), preferences, calendar auto-refresh, camera widget, drag-to-expand file shelf, packaging + hardened runtime.

**Pending**:
- Zen / Firefox rich browser metadata still needs a future companion extension; the current fallback
  deliberately shows app-level playback status instead of guessing titles.

## Codesigning (required before distribution)

For local development, `Scripts/package.sh` ad-hoc signs automatically. For distribution use a
real Developer ID:

```bash
NUKKU_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/package.sh
```

The script applies `--options runtime` + `--timestamp` when a real identity is provided. The
`.entitlements/Nukku.entitlements` file enables hardened runtime (blocks `DYLD_INSERT_LIBRARIES`
injection) while keeping library validation active — the bundled `libMediaRemoteAdapter.dylib` loads
because it shares the app's signing identity (ad-hoc with ad-hoc, or the same Developer ID). The perl
helper that loads the adapter out-of-process is `/usr/bin/perl`, an Apple-entitled system binary, so
it is unaffected by the app's library validation. `package.sh` signs the dylib inside-out before the
app. Entitlements declared: user-selected file read-write (FileDrop), calendar access (Calendar
widget), camera access (Camera widget), AppleEvents automation (opt-in browser MediaSession path).

Note: the packaged `.app` embeds the adapter dylib (`Contents/MacOS`) and `run.pl`
(`Contents/Resources`), so it is self-contained. Shipping a prebuilt binary to other Macs still
requires Developer ID signing + notarization to clear Gatekeeper.

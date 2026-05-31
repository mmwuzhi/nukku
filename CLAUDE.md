# Nukku — Claude Code Context

## Project Overview

Nukku is a macOS notch utility app (similar to Alcove / NotchNook) built with Swift 6.2 and SwiftUI on macOS 26 (Tahoe). It lives in the MacBook notch area, expanding on hover/click to show widgets, and showing slim HUD overlays for volume/brightness changes.

## Build & Run

```bash
# Build (macOS only — AppKit/IOKit not available on Linux)
swift build

# Run tests (cross-platform, limited to non-AppKit logic)
swift test

# Run the app
swift run
```

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

### State Machine (`NotchViewModel`)

```
.collapsed  ──expand()──▶  .expanded
.expanded  ──collapse()──▶  .collapsed   (delayed, reads PreferencesManager.collapseDelay)
.expanded  ──forceCollapse()──▶  .collapsed   (immediate, for click-mode toggle)
```

`setActive(_ id:)` chains `deactivate → set id → activate` through `WidgetRegistry`.

### Concurrency Model

- All ViewModels: `@Observable @MainActor`
- CoreAudio / IOKit callbacks: fire on background threads — capture only value types before the block, dispatch mutations via `DispatchQueue.main.async` or `Task { @MainActor in }`
- SwiftUI animations: single `.animation(spring, value: vm.state)` — no Timer, no manual interpolation

## Directory Structure

```
Sources/Nukku/
├── Animation/          NotchAnimator.swift — spring constants
├── App/                AppDelegate (owns all VMs), NukkuApp entry point
├── Preferences/        PreferencesManager (@Observable singleton), PreferencesView
├── Services/           VolumeMonitor, BrightnessMonitor, LaunchAtLoginService, ScreenChangeService
├── Utilities/          Constants.swift, Extensions (NSScreen+Notch, Color+Theme)
├── ViewModels/         NotchViewModel, MediaViewModel, CalendarViewModel,
│                       SystemMonitorViewModel, FileDropViewModel, HUDViewModel
├── Views/              NotchContainerView, CollapsedView, ExpandedView,
│                       NotchShapeView, HUDView
├── Widgets/
│   ├── Core/           WidgetProtocol (AnyNukkuWidgetBox), WidgetRegistry, WidgetContainer
│   ├── Media/          MediaWidget, MediaWidgetView, MediaRemoteClient
│   ├── Clock/          ClockWidget, ClockWidgetView
│   ├── SystemMonitor/  SystemMonitorWidget + CPUMonitor, MemoryMonitor, NetworkMonitor
│   ├── FileDrop/       FileDropWidget, FileDropWidgetView
│   └── Calendar/       CalendarWidget, CalendarWidgetView, EventKitClient
└── Window/             NotchPanel, NotchWindowManager, TrackingHostingView (NotchHostingView)
```

## Key Constants (`Utilities/Constants.swift`)

| Constant | Value | Notes |
|---|---|---|
| `canvasWidth` | 700 | Fixed window width — never change at runtime |
| `canvasHeight` | 340 | Fixed window height |
| `collapsedWidth` | 250 | Approx MacBook notch width |
| `collapsedHeight` | 38 (runtime) | Overwritten from `screen.safeAreaInsets.top` |
| `expandedWidth` | 420 | Expanded panel width |
| `expandedHeight` | 260 | Expanded panel height |
| `hudWidth` | 320 | Width when HUD overlay is active |

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

**Done**: fixed-window arch, widget framework, Media/Clock/SystemMonitor/FileDrop/Calendar widgets, HUD (volume + brightness), preferences apply correctly, calendar auto-refresh.

**Pending**:
- F2: system notification interception (UNUserNotificationCenter delegate)
- F3: camera preview widget (AVCaptureSession)
- P2 visual polish: matchedGeometryEffect album art, liquid outer corners, per-model notch width, Liquid Glass background

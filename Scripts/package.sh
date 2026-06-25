#!/usr/bin/env bash
# Package the Nukku release binary as a macOS .app bundle.
#
# Usage:
#   ./Scripts/package.sh                # builds release + packages + codesigns
#   ./Scripts/package.sh --no-build     # skip swift build, use existing binary
#   ./Scripts/package.sh --run          # package then launch the app
#
# Env vars:
#   NUKKU_BUNDLE_ID      default: dev.nukku.Nukku
#   NUKKU_SIGN_IDENTITY  default: -   (ad-hoc; replace with a Developer ID to distribute)
#   NUKKU_VERSION        default: 0.1.0
#
# Output: .build/Nukku.app

set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="${NUKKU_BUNDLE_ID:-dev.nukku.Nukku}"
SIGN_IDENTITY="${NUKKU_SIGN_IDENTITY:--}"
VERSION="${NUKKU_VERSION:-0.1.0}"
NO_BUILD=0
RUN_AFTER=0

for arg in "$@"; do
    case "$arg" in
        --no-build) NO_BUILD=1 ;;
        --run)      RUN_AFTER=1 ;;
        -h|--help)
            sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

if [ "$NO_BUILD" -eq 0 ]; then
    echo "==> swift build -c release"
    swift build -c release
fi

BINARY=".build/release/Nukku"
if [ ! -f "$BINARY" ]; then
    echo "Error: $BINARY not found. Run swift build -c release first." >&2
    exit 1
fi

APP=".build/Nukku.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/Nukku"

# Bundle SwiftPM resources (localized strings, etc.). SwiftPM emits the target
# resource bundle next to the executable in the build products directory.
RESOURCE_BUNDLE=".build/release/Nukku_Nukku.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
    echo "Error: $RESOURCE_BUNDLE not found. Build release first." >&2
    exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

# Bundle the MediaRemote perl-adapter. The dynamic library goes next to the
# executable so its @loader_path rpath resolves; run.pl is embedded below.
ADAPTER_DYLIB=".build/release/libMediaRemoteAdapter.dylib"
if [ ! -f "$ADAPTER_DYLIB" ]; then
    echo "Error: $ADAPTER_DYLIB not found. Build release first." >&2
    exit 1
fi
cp "$ADAPTER_DYLIB" "$APP/Contents/MacOS/"
# Embed run.pl in Resources. The vendored MediaController resolves it via
# Bundle.main (Contents/Resources) first, so the .app is self-contained and
# codesign-clean (no content at the bundle root).
ADAPTER_RUNPL=".build/release/MediaRemoteAdapter_MediaRemoteAdapter.bundle/run.pl"
if [ ! -f "$ADAPTER_RUNPL" ]; then
    echo "Error: $ADAPTER_RUNPL not found." >&2
    exit 1
fi
cp "$ADAPTER_RUNPL" "$APP/Contents/Resources/run.pl"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Nukku</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>Nukku</string>
    <key>CFBundleDisplayName</key>
    <string>Nukku</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Nukku displays upcoming events in the notch calendar widget.</string>
    <key>NSCameraUsageDescription</key>
    <string>Nukku shows a live camera preview in the notch camera widget.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Nukku reads MediaSession playback metadata from supported browsers to show what is playing.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Nukku.</string>
</dict>
</plist>
PLIST

# Sign inside-out: nested code (the adapter dylib + its resource bundle) must be
# signed before the enclosing app, otherwise the app seal is invalid.
# For ad-hoc signing ("-"), hardened runtime + timestamp aren't applicable.
# For a real Developer ID, enable hardened runtime and timestamp for notarization.
DYLIB_IN_APP="$APP/Contents/MacOS/libMediaRemoteAdapter.dylib"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> ad-hoc codesign (adapter dylib, then app)"
    codesign --force --sign - "$DYLIB_IN_APP"
    codesign --force \
             --entitlements .entitlements/Nukku.entitlements \
             --sign - \
             "$APP"
else
    echo "==> codesign ($SIGN_IDENTITY) + hardened runtime (adapter dylib, then app)"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$DYLIB_IN_APP"
    codesign --force \
             --options runtime \
             --entitlements .entitlements/Nukku.entitlements \
             --timestamp \
             --sign "$SIGN_IDENTITY" \
             "$APP"
fi

echo "==> packaged: $APP"

if [ "$RUN_AFTER" -eq 1 ]; then
    # Kill any running instance first. `open` only re-activates an existing
    # process and would NOT load the freshly built binary.
    if pgrep -f "Nukku.app/Contents/MacOS/Nukku" >/dev/null; then
        echo "==> stopping running instance"
        pkill -f "Nukku.app/Contents/MacOS/Nukku" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -f "Nukku.app/Contents/MacOS/Nukku" >/dev/null || break
            sleep 0.3
        done
    fi
    echo "==> launching"
    open -n "$APP"
fi

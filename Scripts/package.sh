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
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Nukku.</string>
</dict>
</plist>
PLIST

# For ad-hoc signing ("-"), hardened runtime + timestamp aren't applicable.
# For a real Developer ID, enable hardened runtime and timestamp for notarization.
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> ad-hoc codesign"
    codesign --force \
             --entitlements .entitlements/Nukku.entitlements \
             --sign - \
             "$APP"
else
    echo "==> codesign ($SIGN_IDENTITY) + hardened runtime"
    codesign --force \
             --options runtime \
             --entitlements .entitlements/Nukku.entitlements \
             --timestamp \
             --sign "$SIGN_IDENTITY" \
             "$APP"
fi

echo "==> packaged: $APP"

if [ "$RUN_AFTER" -eq 1 ]; then
    echo "==> launching"
    open "$APP"
fi

#!/bin/bash
# Builds HoursTracker.app (release), ad-hoc signs it and zips it.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="HoursTracker"
BUNDLE_ID="com.alexander.hourstracker"
VERSION="1.1"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

# Pick a toolchain with the macOS 26+ SDK (needed for Liquid Glass) if the default one is older.
# Override by exporting DEVELOPER_DIR / SDKROOT yourself.
CLT=/Library/Developer/CommandLineTools
if [ -z "${DEVELOPER_DIR:-}" ]; then
    DEFAULT_SDK="$(xcrun --show-sdk-version 2>/dev/null || echo 0)"
    if [ "${DEFAULT_SDK%%.*}" -lt 26 ] && [ -x "$CLT/usr/bin/swift" ]; then
        CLT_SDK="$(DEVELOPER_DIR=$CLT xcrun --show-sdk-version 2>/dev/null || echo 0)"
        if [ "${CLT_SDK%%.*}" -ge 26 ]; then
            export DEVELOPER_DIR="$CLT"
        fi
    fi
fi
# The Command Line Tools don't ship the SwiftUIMacros plugin that the macOS 27+ SDK needs for
# @State, so with the CLT prefer the newest macOS 26.x SDK (it still has Liquid Glass).
if [ "${DEVELOPER_DIR:-}" = "$CLT" ] && [ -z "${SDKROOT:-}" ] \
   && ! ls "$CLT"/usr/lib/swift/host/plugins/ 2>/dev/null | grep -q SwiftUIMacros; then
    CUR_SDK="$(xcrun --show-sdk-version 2>/dev/null || echo 0)"
    if [ "${CUR_SDK%%.*}" -ge 27 ]; then
        SDK26="$(ls -d "$CLT"/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1 || true)"
        if [ -z "$SDK26" ] && [ -d "$CLT/SDKs/MacOSX26.sdk" ]; then SDK26="$CLT/SDKs/MacOSX26.sdk"; fi
        if [ -n "$SDK26" ]; then export SDKROOT="$SDK26"; fi
    fi
fi
echo "==> Toolchain: ${DEVELOPER_DIR:-$(xcode-select -p)}  SDK: ${SDKROOT:-$(xcrun --show-sdk-path)}"
xcrun swift --version 2>&1 | head -1

echo "==> swift build -c release"
xcrun swift build -c release
BIN_DIR="$(xcrun swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

ICNS="Resources/HoursTracker.icns"
if [ ! -f "$ICNS" ]; then
    echo "error: missing $ICNS (run iconutil -c icns on the Designer Bot iconset)" >&2
    exit 1
fi
cp "$ICNS" "$APP/Contents/Resources/HoursTracker.icns"

# Some SwiftPM/toolchain combos record the deployment target as the SDK version in
# LC_BUILD_VERSION. AppKit/SwiftUI use that "linked SDK" to decide whether to adopt the macOS 26
# design, so make sure it matches the SDK we actually compiled against.
BIN="$APP/Contents/MacOS/$APP_NAME"
SDK_VER="$(xcrun --show-sdk-version 2>/dev/null || true)"
LINKED_SDK="$(xcrun vtool -show-build "$BIN" 2>/dev/null | awk '$1=="sdk"{print $2; exit}' || true)"
if [ -n "$SDK_VER" ] && [ -n "$LINKED_SDK" ] && [ "$LINKED_SDK" != "$SDK_VER" ]; then
    echo "==> Fixing linked SDK version $LINKED_SDK -> $SDK_VER"
    xcrun vtool -set-build-version macos 13.0 "$SDK_VER" -replace -output "$BIN.tmp" "$BIN"
    mv "$BIN.tmp" "$BIN"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Hours Tracker</string>
    <key>CFBundleDisplayName</key><string>Hours Tracker</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleIconFile</key><string>HoursTracker</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo "==> Zipping"
rm -f "$BUILD_DIR/$APP_NAME.zip"
(cd "$BUILD_DIR" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip")

echo "Done: $APP and $BUILD_DIR/$APP_NAME.zip"

#!/bin/sh
# Builds app/ for the iOS simulator, bundles, signs ad-hoc, installs and launches.
# Usage: ios/build.sh [simulator name]   (default: "iPhone 17")
set -e
cd "$(dirname "$0")/.."

SIM="${1:-iPhone 17}"
APP=build/ios/NativeList.app
BUNDLE_ID=com.example.nativelist

mkdir -p "$APP"
odin build app -target:darwin_arm64 -subtarget:iphonesimulator -minimum-os-version:17.0 -debug -out:"$APP/NativeList"
cp ios/Info.plist "$APP/Info.plist"
codesign --force -s - "$APP"

xcrun simctl boot "$SIM" 2>/dev/null || true
open -b com.apple.iphonesimulator 2>/dev/null || true # GUI is optional
xcrun simctl install booted "$APP"
xcrun simctl launch --console-pty --terminate-running-process booted "$BUNDLE_ID"

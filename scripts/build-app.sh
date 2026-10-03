#!/bin/bash
# Builds dist/Hanyeong.app. Works with either Xcode or the Command Line Tools alone.
#
#   SIGN_IDENTITY  Code signing identity. Defaults to ad-hoc ("-").
#                  With ad-hoc signing, macOS asks for the Accessibility permission again
#                  after every rebuild; a real identity keeps the permission.
#   BUILD_DIR      Where SwiftPM keeps intermediate files. Defaults to .build.
set -euo pipefail
cd "$(dirname "$0")/.."

build_dir="${BUILD_DIR:-.build}"
identity="${SIGN_IDENTITY:--}"
app="dist/Hanyeong.app"

swift build -c release --scratch-path "$build_dir"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$build_dir/release/Hanyeong" "$app/Contents/MacOS/Hanyeong"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

codesign --force --sign "$identity" "$app"
echo "Built $app (signed with: $identity)"

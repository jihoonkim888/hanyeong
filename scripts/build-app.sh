#!/bin/bash
# Builds dist/Hanyeong.app. Works with either Xcode or the Command Line Tools alone.
#
#   SIGN_IDENTITY  Code signing identity. Defaults to ad-hoc ("-").
#                  With ad-hoc signing, macOS asks for the Accessibility permission again
#                  after every rebuild; a real identity keeps the permission.
#   BUILD_DIR      Where SwiftPM keeps intermediate files. Defaults to .build.
#   ARCHS          Architectures to build, such as "arm64 x86_64". Defaults to this Mac's.
#   OUT_DIR        Where the app goes. Defaults to dist.
set -euo pipefail
cd "$(dirname "$0")/.."

build_dir="${BUILD_DIR:-.build}"
identity="${SIGN_IDENTITY:--}"
archs="${ARCHS:-$(uname -m)}"
app="${OUT_DIR:-dist}/Hanyeong.app"

binaries=()
for arch in $archs; do
    swift build -c release --arch "$arch" --scratch-path "$build_dir"
    binaries+=("$build_dir/$arch-apple-macosx/release/Hanyeong")
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Hanyeong"
# The debug symbols name the directories the app was built in. Keep them out of the app.
strip -S "$app/Contents/MacOS/Hanyeong"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

codesign --force --sign "$identity" "$app"
echo "Built $app for $archs (signed with: $identity)"

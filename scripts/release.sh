#!/bin/bash
# Builds the app for both Apple Silicon and Intel and zips it for a GitHub release:
# dist/release/Hanyeong.zip. Takes the same variables as build-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

out="dist/release"
ARCHS="arm64 x86_64" OUT_DIR="$out" scripts/build-app.sh

# What gets published must not name the directories it was built in.
binary="$out/Hanyeong.app/Contents/MacOS/Hanyeong"
for path in "$HOME" "$(cd "${BUILD_DIR:-.build}" && pwd -P)"; do
    if grep -aqF "$path" "$binary"; then
        echo "error: $binary contains the local path $path" >&2
        exit 1
    fi
done

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$out/Hanyeong.app/Contents/Info.plist")
rm -f "$out/Hanyeong.zip"
ditto -c -k --keepParent --norsrc --noextattr "$out/Hanyeong.app" "$out/Hanyeong.zip"

echo "Hanyeong $version: $out/Hanyeong.zip"
shasum -a 256 "$out/Hanyeong.zip"

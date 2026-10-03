#!/bin/bash
# Runs the unit tests. Works with either Xcode or the Command Line Tools alone.
set -euo pipefail
cd "$(dirname "$0")/.."

args=()
[[ -n "${BUILD_DIR:-}" ]] && args+=(--scratch-path "$BUILD_DIR")

# The Command Line Tools ship Swift Testing but do not put it on the search path.
developer_dir="$(xcode-select -p)"
if [[ "$developer_dir" == */CommandLineTools ]]; then
    frameworks="$developer_dir/Library/Developer/Frameworks"
    libraries="$developer_dir/Library/Developer/usr/lib"
    args+=(
        -Xswiftc -F -Xswiftc "$frameworks"
        -Xswiftc -plugin-path -Xswiftc "$developer_dir/usr/lib/swift/host/plugins/testing"
        -Xlinker -F -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$frameworks"
        -Xlinker -L -Xlinker "$libraries" -Xlinker -rpath -Xlinker "$libraries"
    )
fi

swift test "${args[@]}" "$@"

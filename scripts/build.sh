#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
work="${VEIL_WORK:-$project/.work}"
generator="${VEIL_GENERATOR:-Ninja}"
cmake="${VEIL_CMAKE:-$work/toolchain/bin/cmake}"
build="$work/build"
if [ "$generator" = Xcode ]; then build="$work/xcode"; fi
"$cmake" -S "$project" -B "$build" -G "$generator" \
 -DCMAKE_BUILD_TYPE=Release -DCEF_ROOT="$work/dependencies/cef" \
 -DCMAKE_MAKE_PROGRAM="$([ "$generator" = Xcode ] && xcrun --find xcodebuild || echo "$work/toolchain/bin/ninja")"
if [ "${1:-}" = --generate-only ]; then exit 0; fi
"$cmake" --build "$build" --config Release -j "${VEIL_JOBS:-6}"
if [ "$generator" = Xcode ]; then app="$build/Release/VEIL.app"; else app="$build/VEIL.app"; fi
/usr/bin/codesign --verify --deep --strict "$app"
echo "Built: $app"
if [ "${1:-}" = --deliver ]; then
 mkdir -p "$project/dist"
 /usr/bin/ditto "$app" "$project/dist/VEIL.app"
 /usr/bin/codesign --verify --deep --strict "$project/dist/VEIL.app"
fi

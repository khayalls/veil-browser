#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
work="${VEIL_WORK:-$project/.work}"
scratch="${VEIL_SCRATCH_ROOT:-$(mktemp -d "${TMPDIR:-/tmp}/veil-build.XXXXXX")}"
mkdir -p "$scratch"
cmake_data="$("$work/toolchain/bin/python" -c 'import cmake,pathlib;print(pathlib.Path(cmake.__file__).parent / "data")')"
# Copy only this project and its already-pinned development dependencies. This
# avoids a macOS file-open stall observed for an unsigned CMake under Documents.
ditto "$cmake_data" "$scratch/cmake"
ditto "$work/toolchain/bin/ninja" "$scratch/ninja"
ditto "$work/dependencies/cef" "$scratch/cef"
mkdir -p "$scratch/source"
for item in Sources Resources Tests scripts CMakeLists.txt DEPENDENCIES.json PHOSPHOR.json; do
 ditto "$project/$item" "$scratch/source/$item"
done
generator="${VEIL_GENERATOR:-Ninja}"
build="$scratch/build"
if [ "$generator" = Xcode ]; then build="$scratch/xcode";fi
cd "$scratch"
"$scratch/cmake/bin/cmake" -S "$scratch/source" -B "$build" -G "$generator" \
 -DCMAKE_BUILD_TYPE=Release -DCEF_ROOT="$scratch/cef" \
 -DCMAKE_MAKE_PROGRAM="$([ "$generator" = Xcode ] && xcrun --find xcodebuild || echo "$scratch/ninja")"
if [ "${1:-}" = --generate-only ]; then echo "Generated: $build";exit 0;fi
"$scratch/cmake/bin/cmake" --build "$build" --config Release -j "${VEIL_JOBS:-6}"
if [ "$generator" = Xcode ];then app="$build/Release/VEIL.app";else app="$build/VEIL.app";fi
codesign --verify --deep --strict "$app"
echo "Built: $app"
if [ "${1:-}" = --deliver ];then mkdir -p "$project/dist";ditto "$app" "$project/dist/VEIL.app";codesign --verify --deep --strict "$project/dist/VEIL.app";fi

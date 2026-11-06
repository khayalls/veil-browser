#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")" && pwd)"
VEIL_GENERATOR=Xcode /bin/bash "$project/scripts/build.sh" --generate-only
open "${VEIL_WORK:-$project/.work}/xcode/VEIL.xcodeproj"

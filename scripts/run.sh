#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
work="${VEIL_WORK:-$project/.work}"
app="${VEIL_APP:-$project/dist/VEIL.app}"
if [ ! -d "$app" ];then app="$work/build/VEIL.app";fi
if [ ! -d "$app" ];then app="$work/xcode/Release/VEIL.app";fi
if [ ! -d "$app" ];then echo 'Build VEIL first, or set VEIL_APP to the .app bundle to run.' >&2;exit 1;fi
if [ "${1:-}" = --qa ]; then
 shift
 if /usr/bin/pgrep -f '^/private/tmp/VEIL-QA.app/Contents/MacOS/VEIL' >/dev/null; then echo 'Close the existing VEIL QA instance before replacing its bundle.' >&2;exit 1;fi
 /usr/bin/ditto "$app" /private/tmp/VEIL-QA.app
 /usr/bin/open -n /private/tmp/VEIL-QA.app --args --veil-qa --veil-profile-root=/private/tmp/veil-qa-suite "$@"
else
 /usr/bin/open "$app" --args "$@"
fi

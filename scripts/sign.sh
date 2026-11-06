#!/bin/bash
set -euo pipefail
app="$1"
resources="$(cd "$(dirname "$0")/../Resources" && pwd)"
identity="${VEIL_SIGN_IDENTITY:--}"
sign_process() {
  if [ "$identity" = "-" ]; then
    /usr/bin/codesign --force --sign "$identity" --entitlements "$1" "$2"
  else
    /usr/bin/codesign --force --sign "$identity" --options runtime --entitlements "$1" "$2"
  fi
}
framework="$app/Contents/Frameworks/Chromium Embedded Framework.framework"
for dependency in "$app/Contents/MacOS/"*.d; do
  if [ -f "$dependency" ]; then /bin/mv "$dependency" "$(dirname "$app")/$(basename "$dependency")"; fi
done
# Sign inside out. The browser sandbox remains enabled; these are local ad-hoc signatures.
find "$framework" -type f \( -name '*.dylib' -o -name 'Chromium Embedded Framework' \) -print0 | while IFS= read -r -d '' item; do /usr/bin/codesign --force --sign "$identity" "$item"; done
/usr/bin/codesign --force --sign "$identity" "$framework"
# CEF's generic helper also serves the GPU role in this distribution, so it
# needs allow-jit as well as the explicitly named Renderer and GPU helpers.
find "$app/Contents/Frameworks" -maxdepth 1 -name 'VEIL Helper*.app' -print0 | while IFS= read -r -d '' helper; do sign_process "$resources/entitlements.plist" "$helper"; done
sign_process "$resources/app-entitlements.plist" "$app"
/usr/bin/codesign --verify --deep --strict "$app"

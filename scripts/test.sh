#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
work="${VEIL_WORK:-$project/.work}"
mkdir -p "$work/test-state" "$work/ModuleCache"
xcrun swiftc -parse-as-library -module-cache-path "$work/ModuleCache" \
 -import-objc-header "$project/Sources/VEEngine.h" \
 "$project/Sources/Workspace.swift" "$project/Sources/WorkspaceImport.swift" "$project/Sources/WorkspaceRecovery.swift" "$project/Sources/WindowSelection.swift" "$project/Sources/TabCache.swift" "$project/Sources/FaviconStore.swift" "$project/Sources/TabSleepProtection.swift" "$project/Sources/ProcessResourceReading.swift" \
 "$project/Tests/WorkspaceTests.swift" -lsqlite3 -o "$work/workspace-tests"
"$work/workspace-tests" "$work/test-state"
xcrun clang++ -fobjc-arc -std=c++20 -I "$project/Sources" "$project/Tests/ProcessResourcesTests.mm" "$project/Sources/ProcessResources.mm" -framework Cocoa -o "$work/resource-tests"
"$work/resource-tests" > "$work/test-state/native-resource-calibration.json"
PYTHONPYCACHEPREFIX="$work/PythonCache" python3 -m py_compile "$project/scripts/bootstrap.py" "$project/Tests/fixture_server.py" "$project/Tests/benchmark.py" "$project/Tests/idle_sample.py" "$project/Tests/macos_usage.py"
PYTHONPYCACHEPREFIX="$work/PythonCache" python3 "$project/Tests/macos_usage.py" > "$work/test-state/cpu-counter-calibration.json"
PYTHONPYCACHEPREFIX="$work/PythonCache" python3 -m unittest discover -s "$project/Tests" -p 'test_public_audit.py'
plutil -lint "$project/Resources/Info.plist" "$project/Resources/entitlements.plist" "$project/Resources/app-entitlements.plist"

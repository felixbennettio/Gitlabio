#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_tmp="$(mktemp -d)"
task_simulator=""
cleanup() {
  if [ -n "$task_simulator" ]; then xcrun simctl delete "$task_simulator" >/dev/null 2>&1 || true; fi
  rm -rf "$task_tmp"
}
trap cleanup EXIT
mkdir -p "$task_root/dist/apple" "$task_root/reports" "$task_tmp/tmp"
export CLANG_MODULE_CACHE_PATH="$task_tmp/clang"
export TMPDIR="$task_tmp/tmp/"
xcodebuild -version
xcrun swiftc -parse-as-library "$task_root/scripts/app-store-connect.swift" -o "$task_tmp/app-store-connect"

# Core logic: Swift Testing suite.
swift test --package-path "$task_root/apple/GitLabCore" \
  --scratch-path "$task_tmp/swift" --cache-path "$task_tmp/swift-cache" \
  --disable-sandbox --xunit-output "$task_tmp/core.xml"
if [ -f "$task_tmp/core-swift-testing.xml" ]; then cp "$task_tmp/core-swift-testing.xml" "$task_root/reports/apple.xml"; fi

# App: unsigned device build (what TestFlight archives) and simulator UI tests with screenshots.
xcodebuild build -project "$task_root/apple/Gitlabio.xcodeproj" -scheme Gitlabio \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath "$task_tmp/device" CODE_SIGNING_ALLOWED=NO
ditto -c -k --sequesterRsrc --keepParent "$task_tmp/device/Build/Products/Debug-iphoneos/Gitlabio.app" \
  "$task_root/dist/apple/Gitlabio-device-unsigned.zip"

# A throwaway simulator so runs never depend on (or change) the runner's existing devices.
task_device_type="$(xcrun simctl list devicetypes -j | python3 -c '
import json,sys
types=[t["identifier"] for t in json.load(sys.stdin)["devicetypes"] if "iPhone" in t["name"] and "Pro" in t["name"] and "Max" not in t["name"]]
print(sorted(types)[-1])')"
task_runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json,sys
runtimes=[r for r in json.load(sys.stdin)["runtimes"] if r["platform"]=="iOS" and r["isAvailable"]]
print(sorted(runtimes,key=lambda r:[int(x) for x in r["version"].split(".")])[-1]["identifier"])')"
task_simulator="$(xcrun simctl create "Gitlabio-CI-$$" "$task_device_type" "$task_runtime")"
echo "Simulator: $task_device_type on $task_runtime"
xcrun simctl boot "$task_simulator"
xcrun simctl status_bar "$task_simulator" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true
set +e
xcodebuild test -project "$task_root/apple/Gitlabio.xcodeproj" -scheme Gitlabio \
  -destination "id=$task_simulator" -derivedDataPath "$task_tmp/sim" \
  -resultBundlePath "$task_tmp/UITests.xcresult" CODE_SIGNING_ALLOWED=NO
task_ui_status=$?
set -e
xcrun xcresulttool export attachments --path "$task_tmp/UITests.xcresult" --output-path "$task_tmp/attachments" || true
if [ -f "$task_tmp/attachments/manifest.json" ]; then
  python3 "$task_root/scripts/export-screenshots.py" "$task_tmp/attachments" "$task_root/dist/apple/screenshots"
fi
exit "$task_ui_status"

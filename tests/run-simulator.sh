#!/usr/bin/env bash
# Builds the sample app, installs it on an iOS simulator and runs the self-test inside the real
# WKWebView (Example/Sources/SelfTest.swift). Prints PASS/FAIL lines; exits 1 on any FAIL.
#   tests/run-simulator.sh                       # iPhone 14 Pro Max
#   SIM="iPhone 15" tests/run-simulator.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SIM="${SIM:-iPhone 14 Pro Max}"
DD="${DD:-/tmp/runachat-dd}"
OUT="${OUT:-/tmp/runachat-selftest}"
mkdir -p "$OUT"

echo "▶ Building the sample for the simulator …"
[ -d Example/RunaChatSample.xcodeproj ] || (cd Example && xcodegen generate >/dev/null)
xcodebuild -project Example/RunaChatSample.xcodeproj -scheme RunaChatSample -sdk iphonesimulator \
  -configuration Debug -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$DD" build \
  2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

UDID=$(xcrun simctl list devices available | grep "$SIM (" | head -1 | grep -oE "[0-9A-F-]{36}")
[ -n "$UDID" ] || { echo "no simulator named '$SIM'"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator >/dev/null 2>&1 || true

APP="$DD/Build/Products/Debug-iphonesimulator/RunaChatSample.app"
xcrun simctl terminate "$UDID" ai.askruna.chat.sample 2>/dev/null || true
xcrun simctl uninstall "$UDID" ai.askruna.chat.sample 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

echo "▶ Running the self-test …"
: > "$OUT/console.log"
xcrun simctl launch --console-pty "$UDID" ai.askruna.chat.sample --self-test > "$OUT/console.log" 2>&1 &
LAUNCH=$!
for i in $(seq 1 180); do
  grep -q "\[SelfTest\] DONE" "$OUT/console.log" && break
  sleep 1
  # screenshots at the moments the test marks
  if grep -q "ADD → delegate setQuantity" "$OUT/console.log" && [ ! -f "$OUT/added.png" ]; then xcrun simctl io "$UDID" screenshot "$OUT/added.png" >/dev/null 2>&1; fi
done
sleep 2
xcrun simctl io "$UDID" screenshot "$OUT/final.png" >/dev/null 2>&1 || true
kill $LAUNCH 2>/dev/null || true

grep -E "\[SelfTest\]|\[Sample\]" "$OUT/console.log" | sed -E 's/^.*\[(SelfTest|Sample)\] /\1: /'
grep -q "\[SelfTest\] DONE pass=[0-9]+ fail=0" "$OUT/console.log"

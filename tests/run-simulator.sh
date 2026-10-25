#!/usr/bin/env bash
# Builds the sample app, installs it on an iOS simulator and runs a self-test inside the real
# WKWebView. Prints PASS/FAIL lines; exits 1 on any FAIL.
#   tests/run-simulator.sh                       # the chat (Example/Sources/SelfTest.swift), iPhone 14 Pro Max
#   MODE=search tests/run-simulator.sh           # RunaSearchView + orderPlaced (Example/Sources/SearchSelfTest.swift)
#   SIM="iPhone 15" tests/run-simulator.sh
# The pages can come from the developer's laptop before they are live:
#   (cd runa_web/build-widget && python3 -m http.server 5521)
#   PAGE_BASE=http://quicklly.localhost:5521/ MODE=search tests/run-simulator.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SIM="${SIM:-iPhone 14 Pro Max}"
MODE="${MODE:-chat}"
ARGS=(--self-test); [ "$MODE" = search ] && ARGS=(--self-test-search)
[ -n "${PAGE_BASE:-}" ] && ARGS+=(--page-base "$PAGE_BASE")
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

echo "▶ Running the $MODE self-test …"
: > "$OUT/console.log"
xcrun simctl launch --console-pty "$UDID" ai.askruna.chat.sample "${ARGS[@]}" > "$OUT/console.log" 2>&1 &
LAUNCH=$!
for i in $(seq 1 300); do
  grep -q "\[SelfTest\] DONE" "$OUT/console.log" && break
  sleep 1
  # screenshots at the moments the test marks
  if grep -q "ADD → delegate setQuantity" "$OUT/console.log" && [ ! -f "$OUT/added.png" ]; then xcrun simctl io "$UDID" screenshot "$OUT/added.png" >/dev/null 2>&1; fi
  for shot in $(grep -oE "\[SelfTest\] SHOT [a-z-]+" "$OUT/console.log" | awk '{print $3}'); do
    [ -f "$OUT/$shot.png" ] || xcrun simctl io "$UDID" screenshot "$OUT/$shot.png" >/dev/null 2>&1 || true
  done
done
sleep 2
xcrun simctl io "$UDID" screenshot "$OUT/final.png" >/dev/null 2>&1 || true
kill $LAUNCH 2>/dev/null || true

grep -E "\[SelfTest\]|\[Sample\]" "$OUT/console.log" | sed -E 's/^.*\[(SelfTest|Sample)\] /\1: /'
if [ "$MODE" = search ]; then
  # the order page's answer carries Ask Quicklly's sales in the order (what was added from the search view)
  SALES=$(grep -E "order page→app done" "$OUT/console.log" | grep -oE '"sales": [0-9.]+' | head -1 | grep -oE '[0-9.]+$' || true)
  if [ -n "$SALES" ] && awk "BEGIN{exit !($SALES > 0)}"; then echo "SelfTest: PASS the order was reported with Ask Quicklly sales \$$SALES"; else echo "SelfTest: FAIL no Ask Quicklly sales in the order report"; exit 1; fi
  grep -qE "\[SelfTest\] DONE pass=[0-9]+ fail=0" "$OUT/console.log"
  exit $?
fi
if grep -qE "setQuantity .*minOrder=[0-9.]+ deliveryFee=[0-9.]+ range=." "$OUT/console.log"; then echo "SelfTest: PASS product carries the store's terms (minOrder, deliveryFee, range)"; else echo "SelfTest: FAIL product terms missing on setQuantity"; exit 1; fi
grep -qE "\[SelfTest\] DONE pass=[0-9]+ fail=0" "$OUT/console.log"

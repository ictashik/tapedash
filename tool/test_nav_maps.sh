#!/usr/bin/env bash
#
# REAL Google Maps on the HUD, on an emulator (docs/NAV.md, N6): nothing stands in for
# Maps. The script starts a route in Google Maps on the emulator, moves the emulator's
# position along it, and runs integration_test/nav_hud_maps_test.dart, in which the
# app (driving from the simulated car) reads Maps' own notification through its real
# listener and puts it on the HUD.
#
#   tool/test_nav_maps.sh [-s SERIAL] [--shots DIR]
#
# **Emulators only** (the app's data is cleared and flutter test uninstalls it). The
# emulator needs Google Maps, set up once by hand: signed out (Skip) and its two first
# dialogs dismissed. The script keeps Maps from floating a window over the HUD
# (picture-in-picture off for it). It prints what the HUD read of Maps, line by line.
#
# The position is stepped south from a point in Bangalore, which is not Maps' route, so
# Maps reroutes now and then: that is Maps saying "Rerouting...", read by the HUD too.

set -euo pipefail
cd "$(dirname "$0")/.."

PKG="io.github.ictashik.tapedash"
MAPS="com.google.android.apps.maps"
SERIAL=""
SHOTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    -s) SERIAL="$2"; shift ;;
    --shots) SHOTS="$2"; shift ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
  shift
done

ADB=(adb)
SPIKE=(tool/nav_spike.sh)
FLUTTER_DEVICE=()
if [ -n "$SERIAL" ]; then
  ADB=(adb -s "$SERIAL")
  SPIKE=(tool/nav_spike.sh -s "$SERIAL")
  FLUTTER_DEVICE=(-d "$SERIAL")
fi
TARGET="${SERIAL:-$(adb get-serialno 2> /dev/null || true)}"
case "$TARGET" in
  emulator-*) ;;
  *)
    echo "tool/test_nav_maps.sh runs on an emulator only (this device: '${TARGET:-none}')." >&2
    exit 64
    ;;
esac
SHOTS="${SHOTS:-$(mktemp -d "${TMPDIR:-/tmp}/tapedash-nav-maps.XXXXXX")}"
mkdir -p "$SHOTS"
LOG="$SHOTS/maps.log"

STEP_PID=""
SHOT_PID=""
SERVER_PID=""
cleanup() {
  [ -n "$STEP_PID" ] && kill "$STEP_PID" 2> /dev/null || true
  [ -n "$SHOT_PID" ] && kill "$SHOT_PID" 2> /dev/null || true
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2> /dev/null || true
  pkill -f "tool/sim_server.dart --port 35000" 2> /dev/null || true
  "${ADB[@]}" shell am force-stop "$MAPS" > /dev/null 2>&1 || true
  "${SPIKE[@]}" disable > /dev/null 2>&1 || true
}
trap cleanup EXIT

# Taps the middle of the first thing on screen whose text is $1, if there is one.
tap_text() {
  "${ADB[@]}" shell uiautomator dump /sdcard/tapedash-ui.xml > /dev/null 2>&1 || return 1
  local xy
  xy="$("${ADB[@]}" exec-out cat /sdcard/tapedash-ui.xml | python3 -I -c '
import re, sys
xml = sys.stdin.read()
for m in re.finditer(r"<node[^>]*text=\"([^\"]*)\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"", xml):
    if m.group(1).strip().lower() == sys.argv[1].lower():
        x0, y0, x1, y1 = map(int, m.groups()[1:])
        print((x0 + x1) // 2, (y0 + y1) // 2)
        break
' "$1")"
  [ -n "$xy" ] || return 1
  # shellcheck disable=SC2086
  "${ADB[@]}" shell input tap $xy
}

echo "== build and install the debug app"
flutter build apk --debug --target-platform android-arm64 > "$SHOTS/build.log" 2>&1 || { tail -20 "$SHOTS/build.log"; exit 1; }
"${ADB[@]}" install -r build/app/outputs/flutter-apk/app-debug.apk > /dev/null

echo "== Google Maps navigating, with no floating window"
"${ADB[@]}" shell am force-stop "$MAPS"
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS; do
  "${ADB[@]}" shell pm grant "$MAPS" "android.permission.$p" > /dev/null 2>&1 || true
done
# Maps shrinks to a floating window when you leave it during a route; on the glass
# that would be a bright map. This is the switch Android's settings has for it.
"${ADB[@]}" shell cmd appops set "$MAPS" PICTURE_IN_PICTURE deny > /dev/null 2>&1 || true
"${ADB[@]}" shell settings put secure immersive_mode_confirmations confirmed > /dev/null 2>&1 || true
"${ADB[@]}" emu geo fix 77.5946 12.9716 > /dev/null 2>&1
# Quoted for the device's shell, where a bare & would send the command to the background.
"${ADB[@]}" shell "am start -a android.intent.action.VIEW -d 'google.navigation:q=12.9352,77.6245&mode=d' -p $MAPS" > /dev/null
sleep 12
# A destination that is closed asks to continue; a route starts when it does.
tap_text "Continue" > /dev/null 2>&1 || true
sleep 6
"${ADB[@]}" exec-out screencap -p > "$SHOTS/maps-started.png" 2> /dev/null || true

echo "== the position, stepped along (background)"
(
  lat=12.9716
  while true; do
    lat="$(awk -v l="$lat" 'BEGIN { printf "%.6f", l - 0.0002 }')"
    "${ADB[@]}" emu geo fix 77.5946 "$lat" > /dev/null 2>&1 || true
    sleep 1.5
  done
) &
STEP_PID=$!

echo "== the simulated car, and the app with notification access"
"${SPIKE[@]}" disable > /dev/null 2>&1 || true
"${ADB[@]}" shell pm clear "$PKG" > /dev/null
"${ADB[@]}" shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS > /dev/null 2>&1 || true
# The app's own location question would sit over the HUD.
"${ADB[@]}" shell pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION > /dev/null 2>&1 || true
sleep 3
"${SPIKE[@]}" enable > /dev/null
pkill -f "tool/sim_server.dart --port 35000" 2> /dev/null || true
dart run tool/sim_server.dart --port 35000 --scenario city_stop_go > "$SHOTS/sim_server.log" 2>&1 &
SERVER_PID=$!
sleep 5

(
  n=0
  while true; do
    n=$((n + 1))
    "${ADB[@]}" exec-out screencap -p > "$SHOTS/shot-$(printf '%03d' "$n").png" 2> /dev/null || true
    sleep 5
  done
) &
SHOT_PID=$!

echo "== the test: real Maps on the HUD"
set +e
flutter test integration_test/nav_hud_maps_test.dart ${FLUTTER_DEVICE[@]+"${FLUTTER_DEVICE[@]}"} > "$LOG" 2>&1
STATUS=$?
set -e
grep -E "^NAV" "$LOG" || true
if [ "$STATUS" -ne 0 ]; then
  echo "FAILED (exit $STATUS). The end of the log:" >&2
  tail -40 "$LOG" >&2
else
  echo "Passed. Screenshots and logs: $SHOTS"
fi
exit "$STATUS"

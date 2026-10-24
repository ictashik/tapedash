#!/usr/bin/env bash
#
# Google Maps' turns on the HUD, end to end on an emulator or a phone (docs/NAV.md,
# N6). The car is the simulator, over the real WiFi transport; Maps is the debug
# build's stand-in, driven from the same simulated car; everything between them is
# the app's own: the notification listener, the channel, the parser and the HUD.
#
#   tool/test_nav_e2e.sh [-s SERIAL] [--scenario NAME] [--shape progress|classic] [--turn METRES]
#                        [--only drive|filter] [--shots DIR]
#
# It builds and installs the debug app, gives it notification access, starts
# tool/sim_server.dart with --nav-adb, takes a screenshot every few seconds into DIR
# (default: a folder in the system temp), and runs
# integration_test/nav_hud_e2e_test.dart (a drive), then, on a fresh launch,
# integration_test/nav_hud_filter_test.dart (only Maps' navigation notification is
# a turn). Exit 0 if both pass. Needs adb, a debug
# build's worth of disk on the device, and about four minutes.
#
# Google Maps itself is stopped first: if it were navigating, its own notification
# would be read as well as the stand-in's, and its floating window would sit over
# the HUD.
#
# **Emulators only.** It clears the app's data (`pm clear`), which would erase a
# phone's trips, price and adapter. It refuses any device that is not an emulator.
# (The app is left installed afterwards, with its capture file in the app's external
# files, to look at.)
#
# The emulator has to reach the host at 10.0.2.2, which it does by default.

set -euo pipefail
cd "$(dirname "$0")/.."

PKG="io.github.ictashik.tapedash"
SERIAL=""
SCENARIO="city_stop_go"
SHAPE="progress"
TURN="250"
ONLY=""
SHOTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    -s) SERIAL="$2"; shift ;;
    --scenario) SCENARIO="$2"; shift ;;
    --shape) SHAPE="$2"; shift ;;
    --turn) TURN="$2"; shift ;;
    --only) ONLY="$2"; shift ;;
    --shots) SHOTS="$2"; shift ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
  shift
done

ADB=(adb)
SPIKE=(tool/nav_spike.sh)
SERVER_ARGS=()
FLUTTER_DEVICE=()
if [ -n "$SERIAL" ]; then
  ADB=(adb -s "$SERIAL")
  SPIKE=(tool/nav_spike.sh -s "$SERIAL")
  SERVER_ARGS=(--nav-serial "$SERIAL")
  FLUTTER_DEVICE=(-d "$SERIAL")
fi
# Never a phone: the app's data would be cleared and the app uninstalled.
TARGET="${SERIAL:-$(adb get-serialno 2> /dev/null || true)}"
case "$TARGET" in
  emulator-*) ;;
  *)
    echo "tool/test_nav_e2e.sh runs on an emulator only (this device: '${TARGET:-none}')." >&2
    echo "It clears the app's data and flutter test uninstalls the app." >&2
    exit 64
    ;;
esac
SHOTS="${SHOTS:-$(mktemp -d "${TMPDIR:-/tmp}/tapedash-nav-e2e.XXXXXX")}"
mkdir -p "$SHOTS"
LOG="$SHOTS/e2e.log"
SERVER_LOG="$SHOTS/sim_server.log"

SERVER_PID=""
SHOT_PID=""
cleanup() {
  [ -n "$SHOT_PID" ] && kill "$SHOT_PID" 2> /dev/null || true
  [ -n "$SERVER_PID" ] && pkill -P "$SERVER_PID" 2> /dev/null || true
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2> /dev/null || true
  pkill -f "tool/sim_server.dart --port 35000" 2> /dev/null || true
  "${SPIKE[@]}" standin --remove > /dev/null 2>&1 || true
  "${SPIKE[@]}" disable > /dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== build and install the debug app"
flutter build apk --debug --target-platform android-arm64 > "$SHOTS/build.log" 2>&1 || { tail -20 "$SHOTS/build.log"; exit 1; }
"${ADB[@]}" install -r build/app/outputs/flutter-apk/app-debug.apk > /dev/null

echo "== Google Maps stopped, so that only the stand-in speaks"
"${ADB[@]}" shell am force-stop com.google.android.apps.maps
# Android's first-time notice about full-screen apps would sit over the HUD.
"${ADB[@]}" shell settings put secure immersive_mode_confirmations confirmed > /dev/null 2>&1 || true

# A first launch of the app, with its notification access and permissions.
fresh_launch() {
  "${SPIKE[@]}" disable > /dev/null 2>&1 || true
  "${ADB[@]}" shell pm clear "$PKG" > /dev/null
  "${ADB[@]}" shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS > /dev/null 2>&1 || true
  "${ADB[@]}" shell pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION > /dev/null 2>&1 || true
  sleep 3
  "${SPIKE[@]}" enable > /dev/null
}

start_server() {
  pkill -f "tool/sim_server.dart --port 35000" 2> /dev/null || true
  dart run tool/sim_server.dart --port 35000 --scenario "$SCENARIO" "$@" > "$SERVER_LOG" 2>&1 &
  SERVER_PID=$!
  sleep 5
}

STATUS=0
if [ "$ONLY" != "filter" ]; then
  echo "== a drive: the simulated car and Maps (sim_server --nav-adb)"
  fresh_launch
  start_server --nav-adb --nav-shape "$SHAPE" --nav-turn "$TURN" ${SERVER_ARGS[@]+"${SERVER_ARGS[@]}"}

  echo "== screenshots into $SHOTS"
  (
    n=0
    while true; do
      n=$((n + 1))
      "${ADB[@]}" exec-out screencap -p > "$SHOTS/shot-$(printf '%03d' "$n").png" 2> /dev/null || true
      sleep 5
    done
  ) &
  SHOT_PID=$!

  echo "== the test: a drive"
  set +e
  flutter test --no-uninstall integration_test/nav_hud_e2e_test.dart ${FLUTTER_DEVICE[@]+"${FLUTTER_DEVICE[@]}"} > "$LOG" 2>&1
  STATUS=$?
  set -e
  kill "$SHOT_PID" 2> /dev/null || true
  SHOT_PID=""
  grep -E "^(NAV|PERF)" "$LOG" || true
  grep -E "navigation:" "$SERVER_LOG" | head -6 || true
fi

if [ "$STATUS" -eq 0 ] && [ "$ONLY" != "drive" ]; then
  echo "== the test: only the navigation notification is a turn"
  "${SPIKE[@]}" standin --remove > /dev/null 2>&1 || true
  "${SPIKE[@]}" standin --remove --id 4712 > /dev/null 2>&1 || true
  # flutter test uninstalls the app when it is done: put it back for a fresh launch.
  "${ADB[@]}" install -r build/app/outputs/flutter-apk/app-debug.apk > /dev/null
  fresh_launch
  start_server
  set +e
  flutter test --no-uninstall integration_test/nav_hud_filter_test.dart ${FLUTTER_DEVICE[@]+"${FLUTTER_DEVICE[@]}"} > "$SHOTS/filter.log" 2>&1
  STATUS=$?
  set -e
  [ "$STATUS" -ne 0 ] && LOG="$SHOTS/filter.log"
fi

if [ "$STATUS" -ne 0 ]; then
  echo "FAILED (exit $STATUS). The end of the log:" >&2
  tail -40 "$LOG" >&2
else
  echo "Passed. Screenshots and logs: $SHOTS"
fi
exit "$STATUS"

#!/usr/bin/env bash
#
# The navigation listener on a real Android (docs/NAV.md, N1), with the debug
# build's stand-in for Google Maps' notification. It needs an emulator or phone on
# adb with the DEBUG build installed:
#
#   flutter build apk --debug --target-platform android-arm64   # or android-arm
#   adb install -r build/app/outputs/flutter-apk/app-debug.apk
#   tool/test_nav_emulator.sh [-s SERIAL]
#
# It checks, and exits 1 on the first that fails:
#   1. a notification from ANOTHER package is not read
#   2. the stand-in is read, with its title, its texts, its progress and its arrow
#   3. its removal is seen
#   4. once access is revoked, nothing more is read
#
# This tests TapeDash's machinery. It says nothing about Google's notification,
# which only a capture of the real Google Maps can (tool/nav_spike.sh).

set -euo pipefail

PKG="io.github.ictashik.tapedash"
DIR="/sdcard/Android/data/$PKG/files/navspike"
SPIKE="$(cd "$(dirname "$0")" && pwd)/nav_spike.sh"
ADB=(adb)
SPIKE_ARGS=()

if [ "${1:-}" = "-s" ]; then
  ADB=(adb -s "${2:?-s needs a serial}")
  SPIKE_ARGS=(-s "$2")
  shift 2
fi

# ${arr[@]+...}: an empty array is "unbound" to the bash 3.2 that macOS ships.
spike() { "$SPIKE" ${SPIKE_ARGS[@]+"${SPIKE_ARGS[@]}"} "$@"; }
fail() { echo "FAIL  $*" >&2; exit 1; }
pass() { echo "ok    $*"; }

# records PREDICATE: how many records of the capture satisfy a Python expression
# over the record `o` (a dict).
records() {
  "${ADB[@]}" shell "cat $DIR/nav.jsonl 2>/dev/null || true" | tr -d '\r' | python3 -I -c '
import json, sys
n = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    o = json.loads(line)
    if eval(sys.argv[1]):
        n += 1
print(n)
' "$1"
}

# wait_for PREDICATE SECONDS: waits until at least one record satisfies it.
wait_for() {
  local i
  for i in $(seq 1 "$2"); do
    if [ "$(records "$1")" -gt 0 ]; then return 0; fi
    sleep 1
  done
  return 1
}

"${ADB[@]}" shell pm path "$PKG" > /dev/null 2>&1 || fail "$PKG is not installed; install the debug build first"

# From a clean state, so that enabling is a fresh connection. Android unbinds a
# listener a moment after its access is taken away, and a grant made before that is
# "already bound" and gives no new connection: give it time, and try once more.
spike disable > /dev/null
sleep 3
spike clear > /dev/null
spike enable > /dev/null
if ! wait_for 'o.get("event") == "connected"' 12; then
  spike disable > /dev/null
  sleep 5
  spike clear > /dev/null
  spike enable > /dev/null
  wait_for 'o.get("event") == "connected"' 20 || fail "the listener did not connect"
fi
pass "the listener connected"

# 1. Another package.
spike other
sleep 4
if [ "$(records 'o.get("package") not in (None, "'"$PKG"'", "com.google.android.apps.maps")')" != 0 ]; then
  fail "a notification from another package was read"
fi
pass "a notification from another package was ignored"

# 2. The stand-in.
spike standin --title "300 m · Turn left onto MG Road" --short "300 m" --sub "Arrive 3:45 PM" --progress 100 --max 5000 --arrow left
wait_for 'o.get("event") == "posted" and o.get("package") == "'"$PKG"'"' 20 || fail "the stand-in was not read"
"${ADB[@]}" shell "cat $DIR/nav.jsonl" | tr -d '\r' | python3 -I -c '
import json, sys
found = {"title": False, "short": False, "sub": False, "progress": False, "arrow": False}
for line in sys.stdin:
    if not line.strip():
        continue
    o = json.loads(line)
    if o.get("event") != "posted" or "notification" not in o:
        continue
    e = o["notification"]["extras"]
    def text(k):
        v = e.get(k)
        return v.get("text") if isinstance(v, dict) else None
    def value(k):
        v = e.get(k)
        return v.get("value") if isinstance(v, dict) else None
    if text("android.title") == "300 m · Turn left onto MG Road": found["title"] = True
    if text("android.shortCriticalText") == "300 m": found["short"] = True
    if text("android.subText") == "Arrive 3:45 PM": found["sub"] = True
    if value("android.progress") == 100 and value("android.progressMax") == 5000: found["progress"] = True
    big = e.get("android.largeIcon")
    if isinstance(big, dict) and big.get("image", {}).get("width") == 126: found["arrow"] = True
missing = [k for k, ok in found.items() if not ok]
if missing:
    sys.exit("missing from the capture: " + ", ".join(missing))
' || fail "the stand-in's title, short text, sub text, progress or arrow is not in the capture"
pass "the stand-in was read: title, short text, sub text, progress and arrow"

# 3. Its removal.
spike standin --remove
wait_for 'o.get("event") == "removed" and o.get("package") == "'"$PKG"'"' 20 || fail "the removal was not seen"
pass "its removal was seen"

# 4. Revoked access.
spike disable > /dev/null
sleep 2
before="$(records 'True')"
spike standin --title "999 m" --sub "Should not be read"
sleep 5
after="$(records 'True')"
if [ "$before" != "$after" ]; then
  fail "something was read after access was revoked ($before -> $after records)"
fi
pass "nothing is read once access is revoked"

spike clear > /dev/null
echo "Navigation listener: all checks passed."

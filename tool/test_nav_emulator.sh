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
#   2. the stand-in is read, with its texts, its view names and its arrow
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

# From a clean state, so that enabling is a fresh connection.
spike disable > /dev/null
sleep 1
spike clear > /dev/null
spike enable > /dev/null
wait_for 'o.get("event") == "connected"' 20 || fail "the listener did not connect"
pass "the listener connected"

# 1. Another package.
spike other
sleep 4
if [ "$(records 'o.get("package") not in (None, "'"$PKG"'", "com.google.android.apps.maps")')" != 0 ]; then
  fail "a notification from another package was read"
fi
pass "a notification from another package was ignored"

# 2. The stand-in.
spike standin --title "300 m" --instruction "Turn left onto MG Road" --time "12 min · 5.2 km · 3:45 pm" --arrow left
wait_for 'o.get("event") == "posted" and o.get("package") == "'"$PKG"'"' 20 || fail "the stand-in was not read"
"${ADB[@]}" shell "cat $DIR/nav.jsonl" | tr -d '\r' | python3 -I -c '
import json, sys
found = {"title": False, "instruction": False, "time": False, "arrow": False, "ids": False}
for line in sys.stdin:
    if not line.strip():
        continue
    o = json.loads(line)
    if o.get("event") != "posted" or "notification" not in o:
        continue
    views = o["notification"].get("views", {})
    tree = views.get("contentView") or {}
    stack = [tree.get("tree")] if tree.get("tree") else []
    names = set()
    while stack:
        v = stack.pop()
        names.add(v.get("id"))
        if v.get("id") == "nav_title" and v.get("text") == "300 m": found["title"] = True
        if v.get("id") == "nav_description" and v.get("text") == "Turn left onto MG Road": found["instruction"] = True
        if v.get("id") == "nav_time" and "3:45 pm" in (v.get("text") or ""): found["time"] = True
        if v.get("id") == "nav_notification_icon" and v.get("image", {}).get("width") == 96: found["arrow"] = True
        stack.extend(v.get("children", []))
    found["ids"] = {"nav_title", "nav_description", "nav_time", "nav_notification_icon"} <= names
missing = [k for k, ok in found.items() if not ok]
if missing:
    sys.exit("missing from the capture: " + ", ".join(missing))
' || fail "the stand-in's texts, view names or arrow are not in the capture"
pass "the stand-in was read: texts, view names and arrow"

# 3. Its removal.
spike standin --remove
wait_for 'o.get("event") == "removed" and o.get("package") == "'"$PKG"'"' 20 || fail "the removal was not seen"
pass "its removal was seen"

# 4. Revoked access.
spike disable > /dev/null
sleep 2
before="$(records 'True')"
spike standin --title "999 m" --instruction "Should not be read"
sleep 5
after="$(records 'True')"
if [ "$before" != "$after" ]; then
  fail "something was read after access was revoked ($before -> $after records)"
fi
pass "nothing is read once access is revoked"

spike clear > /dev/null
echo "Navigation listener: all checks passed."

#!/usr/bin/env bash
#
# The navigation capture spike (docs/NAV.md, N1): grant TapeDash notification
# access over adb, let it write down what Google Maps' navigation notification
# holds, and pull the result. It needs a DEBUG build; a release build captures
# nothing.
#
#   tool/nav_spike.sh [-s SERIAL] enable      grant notification access (no Settings screens)
#   tool/nav_spike.sh [-s SERIAL] disable     revoke it
#   tool/nav_spike.sh [-s SERIAL] status      is it granted, and how much has been captured
#   tool/nav_spike.sh [-s SERIAL] pull [DEST] copy the capture to recordings/private/navspike-<time>
#   tool/nav_spike.sh [-s SERIAL] clear       delete the capture on the device
#   tool/nav_spike.sh [-s SERIAL] standin [--title T] [--instruction I] [--time X] [--arrow left|right|straight|uturn] [--remove]
#                                             post (or remove) the debug build's stand-in for Maps' notification
#   tool/nav_spike.sh [-s SERIAL] other       post a notification from ANOTHER package (the shell), to see it is ignored
#
# The capture holds street names and places. It goes to recordings/private/, which
# is git-ignored; do not commit it or send it anywhere you would not send a map of
# your commute.

set -euo pipefail

PKG="io.github.ictashik.tapedash"
COMPONENT="$PKG/$PKG.NavListenerService"
DIR="/sdcard/Android/data/$PKG/files/navspike"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB=(adb)

if [ "${1:-}" = "-s" ]; then
  ADB=(adb -s "${2:?-s needs a serial}")
  shift 2
fi

cmd="${1:-}"
[ -n "$cmd" ] || { sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }
shift

listeners() { "${ADB[@]}" shell settings get secure enabled_notification_listeners | tr -d '\r'; }

is_enabled() { listeners | tr ':' '\n' | grep -qxF "$COMPONENT"; }

case "$cmd" in
  enable)
    # Android 8 and later have `cmd notification allow_listener`. Android 7 does not,
    # and the setting is written directly (the shell is allowed to).
    "${ADB[@]}" shell cmd notification allow_listener "$COMPONENT" > /dev/null 2>&1 || true
    if ! is_enabled; then
      current="$(listeners)"
      case "$current" in
        null | "") value="$COMPONENT" ;;
        *) value="$current:$COMPONENT" ;;
      esac
      "${ADB[@]}" shell settings put secure enabled_notification_listeners "$value"
    fi
    if is_enabled; then
      echo "Notification access is on for $PKG."
      echo "Start navigation in Google Maps; then: tool/nav_spike.sh status"
    else
      echo "Could not turn notification access on. Settings > Notifications > Notification access." >&2
      exit 1
    fi
    ;;
  disable)
    "${ADB[@]}" shell cmd notification disallow_listener "$COMPONENT" > /dev/null 2>&1 || true
    if is_enabled; then
      value="$(listeners | tr ':' '\n' | grep -vxF "$COMPONENT" | paste -sd: -)"
      "${ADB[@]}" shell settings put secure enabled_notification_listeners "${value:-}"
    fi
    if is_enabled; then
      echo "Could not turn notification access off. Settings > Notifications > Notification access." >&2
      exit 1
    fi
    echo "Notification access is off for $PKG."
    ;;
  status)
    if is_enabled; then echo "access:   on"; else echo "access:   off"; fi
    lines="$("${ADB[@]}" shell "wc -l < $DIR/nav.jsonl 2>/dev/null || echo 0" | tr -d '\r ')"
    size="$("${ADB[@]}" shell "wc -c < $DIR/nav.jsonl 2>/dev/null || echo 0" | tr -d '\r ')"
    icons="$("${ADB[@]}" shell "ls $DIR/icons 2>/dev/null | wc -l" | tr -d '\r ')"
    echo "records:  $lines ($size bytes)"
    echo "images:   $icons"
    ;;
  pull)
    dest="${1:-$ROOT/recordings/private/navspike-$(date +%Y%m%d-%H%M%S)}"
    mkdir -p "$dest"
    "${ADB[@]}" pull "$DIR/." "$dest/" > /dev/null
    echo "Pulled to $dest"
    ;;
  clear)
    "${ADB[@]}" shell "rm -rf $DIR"
    echo "Cleared $DIR"
    ;;
  standin)
    title="300 m"; instruction="Turn left onto MG Road"; time="12 min · 5.2 km · 3:45 pm"; arrow="left"; remove=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) title="$2"; shift ;;
        --instruction) instruction="$2"; shift ;;
        --time) time="$2"; shift ;;
        --arrow) arrow="$2"; shift ;;
        --remove) remove=1 ;;
        *) echo "unknown option: $1" >&2; exit 64 ;;
      esac
      shift
    done
    "${ADB[@]}" shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS > /dev/null 2>&1 || true
    if [ "$remove" = 1 ]; then
      "${ADB[@]}" shell "am broadcast -n $PKG/.NavStandInReceiver --ez remove true" > /dev/null
    else
      # Quoted for the device's shell; an apostrophe in a value would break it.
      "${ADB[@]}" shell "am broadcast -n $PKG/.NavStandInReceiver --es title '$title' --es instruction '$instruction' --es time '$time' --es arrow '$arrow'" > /dev/null
    fi
    ;;
  other)
    "${ADB[@]}" shell cmd notification post -t "Not navigation" tapedash_other "A notification from another package. TapeDash must not read this." > /dev/null
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 64
    ;;
esac

#!/usr/bin/env bash
#
# Moves TapeDash's data off a phone or a watch and onto it with adb, without
# touching the device's screen (docs/EXCHANGE.md 5).
#
#   tool/adb_exchange.sh [-s SERIAL] export [SCOPES]     ask the app for an export, wait, pull it
#   tool/adb_exchange.sh [-s SERIAL] pull [DEST]         pull what is in the outbox
#   tool/adb_exchange.sh [-s SERIAL] push FILE           put a file in the inbox
#   tool/adb_exchange.sh [-s SERIAL] import [--apply]    ask the app to read the inbox, wait
#   tool/adb_exchange.sh [-s SERIAL] result              print what the last one did
#
# SCOPES is a comma list of profile, device, trips, fillups, rest (default: all but
# device). `import --apply` lets the file's setup be applied; without it the setup is
# only reported. For a watch: `adb connect <ip>:<port>` first, then -s <ip>:<port>.

set -euo pipefail

PKG="io.github.ictashik.tapedash"
DIR="/sdcard/Android/data/$PKG/files/exchange"
ADB=(adb)

if [ "${1:-}" = "-s" ]; then
  ADB=(adb -s "${2:?-s needs a serial}")
  shift 2
fi

cmd="${1:-}"
[ -n "$cmd" ] || { sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }
shift

# Starts the app (or brings the running one forward) with a request.
request() {
  "${ADB[@]}" shell am start -n "$PKG/.MainActivity" "$@" > /dev/null
}

# Waits for the app to write result.json, which it does when the work is done.
wait_for_result() {
  for _ in $(seq 1 60); do
    if "${ADB[@]}" shell "test -f $DIR/result.json && echo yes" | grep -q yes; then
      return 0
    fi
    sleep 0.5
  done
  echo "The app did not answer in 30 s. Is it installed, and was it started once, so that its folders exist?" >&2
  return 1
}

case "$cmd" in
  export)
    "${ADB[@]}" shell "rm -f $DIR/result.json"
    if [ -n "${1:-}" ]; then
      request --es tapedash.exchange export --es tapedash.scopes "$1"
    else
      request --es tapedash.exchange export
    fi
    wait_for_result
    "${ADB[@]}" shell cat "$DIR/result.json"
    dest="${EXCHANGE_DEST:-./from-device}"
    mkdir -p "$dest"
    "${ADB[@]}" pull "$DIR/outbox/." "$dest/" > /dev/null
    echo "Pulled to $dest"
    ;;
  pull)
    dest="${1:-./from-device}"
    mkdir -p "$dest"
    "${ADB[@]}" pull "$DIR/outbox/." "$dest/"
    ;;
  push)
    file="${1:?push needs a file}"
    name="$(basename "$file")"
    "${ADB[@]}" shell "mkdir -p $DIR/inbox"
    # Not `adb push` straight into the app's folder: on Android 11 and later that
    # fails ("remote fchown failed") because sync tries to chown on the scoped
    # storage. Stage it, then copy as the shell user, which is allowed.
    "${ADB[@]}" push "$file" "/data/local/tmp/$name" > /dev/null
    "${ADB[@]}" shell "cp /data/local/tmp/$name $DIR/inbox/$name && rm -f /data/local/tmp/$name"
    echo "$name is in the inbox."
    ;;
  import)
    "${ADB[@]}" shell "rm -f $DIR/result.json"
    if [ "${1:-}" = "--apply" ]; then
      request --es tapedash.exchange import --ez tapedash.apply_profile true
    else
      request --es tapedash.exchange import
    fi
    wait_for_result
    "${ADB[@]}" shell cat "$DIR/result.json"
    ;;
  result)
    "${ADB[@]}" shell cat "$DIR/result.json"
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    exit 64
    ;;
esac

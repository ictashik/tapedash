#!/usr/bin/env bash
#
# APK size budget (CLAUDE.md 3): under 20 MB per ABI, fonts included. Both
# shipped ABIs must be present, because armeabi-v7a is never dropped.
#
# Run it after:
#   flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
#
# Usage: tool/check_apk_size.sh [--root DIR]
#   --root DIR  Check the project in DIR instead of this repository.
#
# "MB" here is 1,000,000 bytes, as in the sizes the Flutter tool prints, so its
# "11.0MB" reads 11.0 here too.

set -euo pipefail

BUDGET_MB=20
ABIS="armeabi-v7a arm64-v8a"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      if [ $# -lt 2 ]; then echo "--root needs a directory" >&2; exit 2; fi
      ROOT="$(cd "$2" && pwd)"
      shift
      ;;
    -h | --help) sed -n '2,/^$/p' "$0" | sed -e 's/^# \{0,1\}//' -e '1d'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

cd "$ROOT"

FAILED=0
budget_bytes=$((BUDGET_MB * 1000000))

for abi in $ABIS; do
  apk="build/app/outputs/flutter-apk/app-$abi-release.apk"
  if [ ! -f "$apk" ]; then
    printf 'FAIL  %s is missing, so %s cannot be checked\n' "$apk" "$abi" >&2
    FAILED=1
    continue
  fi
  bytes=$(wc -c < "$apk" | tr -d ' ')
  size=$(awk -v b="$bytes" 'BEGIN { printf "%.1f", b / 1000000 }')
  if [ "$bytes" -lt "$budget_bytes" ]; then
    printf 'ok    %s: %s MB, under the %s MB budget\n' "$abi" "$size" "$BUDGET_MB"
  else
    printf 'FAIL  %s: %s MB is not under the %s MB budget\n' "$abi" "$size" "$BUDGET_MB" >&2
    FAILED=1
  fi
done

if [ "$FAILED" != 0 ]; then
  echo "APK size check FAILED." >&2
  exit 1
fi
echo "APK size check passed."

#!/usr/bin/env bash
#
# The gate to pass before every commit (CLAUDE.md 2): formatting, analysis, the
# tests, the offline check and the Android API check (nothing newer than the minimum
# Android, which lint finds and an emulator would find too late). Never commit a red
# build.
#
# Usage: tool/verify.sh [--strict]
#   --strict  CI mode; passed on to tool/check_offline.sh, which then needs a
#             release build to have run first.

set -euo pipefail
cd "$(dirname "$0")/.."

dirs=""
for d in lib test integration_test tool; do
  if [ -d "$d" ]; then dirs="$dirs $d"; fi
done

echo "== format"
# shellcheck disable=SC2086
dart format --output=none --set-exit-if-changed $dirs

echo "== analyze"
flutter analyze

echo "== test"
if [ "$(uname -s)" = "Linux" ]; then
  flutter test
else
  # Goldens are generated and compared on CI Linux only (CLAUDE.md 10).
  flutter test --exclude-tags golden
fi

echo "== offline"
tool/check_offline.sh "$@"

echo "== android api"
tool/check_android_api.sh

echo
echo "verify: all green"

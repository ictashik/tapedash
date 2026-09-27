#!/usr/bin/env bash
#
# Adds a frame to the build video: copies an image into docs/build-video/frames/
# under the next number, and records it in docs/build-video/FRAMES.md with the
# commit it was taken at and a caption.
#
# Usage: tool/build_frame.sh <image.png> <slug> "<caption>"
#
# The frames are real renders of the app (from tests, or from a device), in the
# order the app was built, so they can be cut into a video as they are.
#
# They are kept as JPEG at a quality of about 95. The grain over the void is noise,
# which PNG cannot compress: a frame is 600 KB as a PNG and 140 KB as a JPEG, and
# this folder is in git. Without ffmpeg the PNG is copied as it is.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <image.png> <slug> \"<caption>\"" >&2
  exit 2
fi
source_image="$1"
slug="$2"
caption="$3"

frames=docs/build-video/frames
index=docs/build-video/FRAMES.md
mkdir -p "$frames"

next=$(( $(find "$frames" -name '[0-9][0-9][0-9]-*' | wc -l | tr -d ' ') + 1 ))
if command -v ffmpeg >/dev/null 2>&1; then
  name=$(printf '%03d-%s.jpg' "$next" "$slug")
  ffmpeg -loglevel error -y -i "$source_image" -q:v 2 "$frames/$name"
else
  name=$(printf '%03d-%s.png' "$next" "$slug")
  cp "$source_image" "$frames/$name"
fi

if [ ! -f "$index" ]; then
  {
    echo "# Build video frames"
    echo
    echo "Real renders of TapeDash, in the order it was built. Each is 1280 x 720 (a 640 x 360 lp"
    echo "screen at 2x) unless it says otherwise. \`tool/build_frame.sh\` adds one."
    echo
    echo "| # | Frame | Taken at | What it shows |"
    echo "|---|---|---|---|"
  } > "$index"
fi
commit=$(git rev-parse --short HEAD 2>/dev/null || echo "-")
echo "| $next | [$name](frames/$name) | \`$commit\` | $caption |" >> "$index"
echo "frame $next: $name"

#!/usr/bin/env bash
#
# Rebuilds assets/fonts/ from the upstream OFL fonts (DESIGN.md 4.5).
#
# Dev-time only. It needs the network and Python 3, and the app never does. The
# fonts it produces are committed, so nobody needs to run this to build TapeDash;
# it exists so that the subsets can be reproduced and checked.
#
# It downloads the fonts from one pinned commit of github.com/google/fonts,
# checks that each file is the one that was reviewed, installs fonttools into a
# throwaway virtual environment, and runs tool/subset_fonts.py.
#
# Usage: tool/subset_fonts.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# The commit of google/fonts the sources were taken from.
GOOGLE_FONTS_SHA=23e54b51ddffbc7713c583748e3bd86f62b1fa4a
FONTTOOLS_VERSION=4.66.0

# path in google/fonts|name to save as|sha256 of the file
SOURCES="
saira/Saira%5Bwdth%2Cwght%5D.ttf|saira_Saira[wdth,wght].ttf|9d050fc5a01c85f74c4257c207d50b55d1e40c37308c642f974a2c5003231dde
saira/OFL.txt|saira_OFL.txt|f2665d4718b452b3818a877191355ac884a6b9b419d35408fe7ee487e9e8f30f
barlow/Barlow-Regular.ttf|barlow_Barlow-Regular.ttf|95aa02c7c43096e0dd44d787ba6216864a67157e402adab59b35572e0c1577ea
barlow/Barlow-Medium.ttf|barlow_Barlow-Medium.ttf|f8906f762cb73dca441da034bc363b2d8e2e68bc10d5c05e58717646c20cc4b4
barlow/Barlow-SemiBold.ttf|barlow_Barlow-SemiBold.ttf|86577cb32f8abe3673db53ca0f4221e6856751a4f6730c867e00f720f8bb1fc5
barlow/OFL.txt|barlow_OFL.txt|186d750eb496a4c17a76385f82be6aea2ac1cf2de074a811d63786cf374ea73f
barlowsemicondensed/BarlowSemiCondensed-Regular.ttf|barlowsemicondensed_BarlowSemiCondensed-Regular.ttf|e8c7242f612b13d026e18a94b63b0fd079e91a3faf009d1b6981dbb5f16d1153
barlowsemicondensed/BarlowSemiCondensed-Medium.ttf|barlowsemicondensed_BarlowSemiCondensed-Medium.ttf|4998b693a190b76f2b11315844345a8546c1e2e6a320905507a9eed04edf8b48
barlowsemicondensed/BarlowSemiCondensed-SemiBold.ttf|barlowsemicondensed_BarlowSemiCondensed-SemiBold.ttf|bd299f4bc5b44d30be8d42e9bad3a5df7d66af1cd55d0ed72a8b8916360a1424
"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "== fetch (google/fonts @ ${GOOGLE_FONTS_SHA})"
mkdir -p "$work/src"
echo "$SOURCES" | while IFS='|' read -r path name sum; do
  [ -n "$path" ] || continue
  curl -fsSL "https://raw.githubusercontent.com/google/fonts/${GOOGLE_FONTS_SHA}/ofl/${path}" \
    -o "$work/src/$name"
  actual="$(shasum -a 256 "$work/src/$name" | cut -d' ' -f1)"
  if [ "$actual" != "$sum" ]; then
    echo "error: $name is not the file that was reviewed" >&2
    echo "  expected $sum" >&2
    echo "  got      $actual" >&2
    exit 1
  fi
  echo "ok  $name"
done

echo "== fonttools ${FONTTOOLS_VERSION}"
python3 -m venv "$work/venv"
"$work/venv/bin/pip" install --quiet "fonttools==${FONTTOOLS_VERSION}"

echo "== subset"
"$work/venv/bin/python" tool/subset_fonts.py "$work/src" assets/fonts

# The licence texts travel with the fonts (OFL 1.1, clause 2). Barlow and Barlow
# Semi Condensed share one.
cp "$work/src/saira_OFL.txt" assets/fonts/OFL-Saira.txt
cp "$work/src/barlow_OFL.txt" assets/fonts/OFL-Barlow.txt

echo
echo "fonts written to assets/fonts (see MANIFEST.txt for hashes)"

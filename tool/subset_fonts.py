#!/usr/bin/env python3
"""Subsets the bundled fonts (DESIGN.md 4.5). Dev-time only: nothing here ships.

Run it through tool/subset_fonts.sh, which fetches the pinned upstream files
into a throwaway directory, checks their hashes, and gives this script a Python
that has fonttools.

    subset_fonts.py <source-dir> <out-dir>

What it does, and why:
  * Keeps only the characters the app can draw, so six Barlow files and one
    variable Saira come to a few hundred KB (the APK budget is 20 MB, CLAUDE.md 3).
  * Limits Saira's axes to the ranges the design uses: width 100 to 125 (the
    numerals are set wide, 112 to 125) and weight 300 to 800 (MONO is Light and
    the HUD is SemiBold or heavier).
  * Drops hinting: Android's renderer does not run TrueType bytecode.
  * Keeps the licence and copyright in each font's name table.
"""

import hashlib
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

# Basic Latin, plus the typography DESIGN.md 4.5 asks about: the degree sign,
# middle dot, multiplication sign, dashes, quotes, ellipsis, the minus sign and
# "approximately equal".
COMMON = (
    list(range(0x20, 0x7F))
    + [0xA0, 0xB0, 0xB7, 0xD7]
    + [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026]
    + [0x2212, 0x2248]
)

# Saira sets numerals, the wordmark, and the fault codes. It also has the rupee
# sign, which Barlow lacks, and the arrows the HUD alignment pattern uses.
SAIRA = COMMON + [0x20B9, 0x2190, 0x2191, 0x2192, 0x2193]

# Barlow sets everything else. Latin-1 covers a car's nickname.
BARLOW = COMMON + list(range(0xA1, 0x100))

FONTS = [
    # (source file, output file, characters, axis limits or None)
    (
        "saira_Saira[wdth,wght].ttf",
        "Saira-Variable.ttf",
        SAIRA,
        {"wght": (300, 800), "wdth": (100, 125)},
    ),
    ("barlow_Barlow-Regular.ttf", "Barlow-Regular.ttf", BARLOW, None),
    ("barlow_Barlow-Medium.ttf", "Barlow-Medium.ttf", BARLOW, None),
    ("barlow_Barlow-SemiBold.ttf", "Barlow-SemiBold.ttf", BARLOW, None),
    (
        "barlowsemicondensed_BarlowSemiCondensed-Regular.ttf",
        "BarlowSemiCondensed-Regular.ttf",
        BARLOW,
        None,
    ),
    (
        "barlowsemicondensed_BarlowSemiCondensed-Medium.ttf",
        "BarlowSemiCondensed-Medium.ttf",
        BARLOW,
        None,
    ),
    (
        "barlowsemicondensed_BarlowSemiCondensed-SemiBold.ttf",
        "BarlowSemiCondensed-SemiBold.ttf",
        BARLOW,
        None,
    ),
]


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def build(source, target, unicodes, limits):
    font = TTFont(source)
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.hinting = False
    options.notdef_outline = True
    options.drop_tables += ["DSIG"]
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=unicodes)
    subsetter.subset(font)
    if limits:
        # Subset first, then narrow the axes: the other way round leaves the
        # variation data out of step with the glyph list, and the subsetter
        # fails on it.
        font = instancer.instantiateVariableFont(font, limits)
    font.save(target)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    source_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    lines = ["source (sha256)  ->  output (sha256, bytes, glyphs)"]
    total = 0
    for source, target, unicodes, limits in FONTS:
        source_path = os.path.join(source_dir, source)
        target_path = os.path.join(out_dir, target)
        build(source_path, target_path, unicodes, limits)
        size = os.path.getsize(target_path)
        total += size
        glyphs = len(TTFont(target_path).getGlyphOrder())
        lines.append(
            f"{source}  {sha256(source_path)}\n"
            f"  -> {target}  {sha256(target_path)}  {size}  {glyphs}"
        )
        print(f"{target:36} {size:8} bytes  {glyphs:4} glyphs")
    print(f"{'total':36} {total:8} bytes")

    with open(os.path.join(out_dir, "MANIFEST.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()

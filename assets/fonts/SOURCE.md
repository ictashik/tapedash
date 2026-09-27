# Fonts

Three families, and nothing else (DESIGN.md 4.5). All three are under the SIL Open Font
License 1.1. The licence texts are next to the fonts: [OFL-Saira.txt](OFL-Saira.txt) and
[OFL-Barlow.txt](OFL-Barlow.txt), which covers Barlow and Barlow Semi Condensed. None of
them declares a Reserved Font Name, so a subset may keep the family name.

| Family | Used for | Files |
|---|---|---|
| **Saira** (variable) | numerals, the wordmark, fault codes, the rupee sign | `Saira-Variable.ttf` |
| **Barlow Semi Condensed** | instrument labels, button labels | `BarlowSemiCondensed-Regular/Medium/SemiBold.ttf` |
| **Barlow** | all parked UI text | `Barlow-Regular/Medium/SemiBold.ttf` |

## Where they come from

The files are subsets of the fonts in [google/fonts](https://github.com/google/fonts),
commit `23e54b51ddffbc7713c583748e3bd86f62b1fa4a`, under `ofl/saira`, `ofl/barlow` and
`ofl/barlowsemicondensed`. Upstream projects:
[Saira](https://github.com/Omnibus-Type/Saira) (Omnibus-Type) and
[Barlow](https://github.com/jpt/barlow) (Jeremy Tribby).

They were fetched once, at development time. The app never fetches anything (CLAUDE.md 1).

`tool/subset_fonts.sh` rebuilds these files. It downloads the pinned sources, checks each
against its SHA-256, and subsets them. [MANIFEST.txt](MANIFEST.txt) has the hashes of the
sources and of the results.

## What the subset is

- **Characters:** Basic Latin; the degree sign, middle dot, multiplication sign, minus sign
  (U+2212), "approximately equal", the dashes, quotes and ellipsis. Saira also keeps the rupee
  sign (U+20B9) and the four arrows. Barlow also keeps Latin-1, for a car's nickname.
- **Saira's axes** are narrowed to the range the design uses: weight 300 to 800 (MONO is Light,
  the HUD is SemiBold or heavier) and width 100 to 125 (the numerals are set wide, 112 to 125).
- **No hinting.** Android's renderer does not run TrueType bytecode.
- Each font keeps its copyright and licence in its name table.

The six Barlow files and Saira come to 333 KB in all.

## The rupee sign

**Barlow has no ₹ (U+20B9). Saira does**, and it is drawn to match Saira's numerals. So:

- Next to a number, ₹ is Saira's, in the glyph atlas with the digits.
- In a Barlow label such as `₹ THIS TRIP`, the text style lists Saira as its fallback family,
  so the ₹ comes from Saira and no other font is ever used. That ₹ is a little wider and
  squarer than Barlow's letters. The icon set also has a drawn `rupee` glyph (DESIGN.md 4.8) for
  places that want one.

`test/design/fonts_test.dart` checks these facts against the files themselves.

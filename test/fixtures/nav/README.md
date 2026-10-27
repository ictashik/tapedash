# Navigation fixtures

`maps_25_33_android16.jsonl` is **what Google Maps 25.33 really posted**, from a
capture on an Android 16 emulator (docs/NAV.md, N1): one line for each
notification, in the wire form of `NavNotification` (`title`, `text`, `subText`,
`shortCriticalText`, `progress`, `progressMax`, `template`, and the arrow as an
id and a size, without its pixels), with `t` in milliseconds from the first.

The drive is the emulator's GPS stepped along a Bangalore route, so every street
in it is on a public map and none is the human's. The texts are Google's, English,
in kilometres. A capture from a phone in another language or in miles is added as
a second file, with the street names changed.

Produced with `tool/nav_spike.sh pull`, then reduced to these fields.

`maps_26_42_android16.jsonl` is **what Google Maps 26.42 posted on the human's own
phone** (a Motorola edge 60 stylus, Android 16, English (India), kilometres), from a
drive with a faked GPS along a fixed Bangalore test route (docs/NAV.md). The classic
shape, not the progress shape: the distance in the title (`0 m` beside straight
instructions), the street in the text, `23 min · 6.7 km · 9:42 pm ETA` in the sub
text with a lower-case `pm`, 135 px arrows. Reduced from the capture to the
navigation-category records and these fields; it holds nothing but the route's own
texts. Distances and times use no-break spaces (U+00A0, U+202F), as Maps writes them.


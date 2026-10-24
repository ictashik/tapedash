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

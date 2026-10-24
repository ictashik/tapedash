# Navigation on the HUD: plan, to-dos and status

Started 2026-10-24. The contract is CLAUDE.md 1 and 4 ("Navigation notification"); the reasons are in `docs/DECISIONS.md`.

**What it is.** If the person has Google Maps navigating on the same phone, TapeDash reads Maps' navigation notification and shows, on the HUD, the next turn, the distance to it, the street, the ETA, the time and distance left, and the speed. Google Maps does the routing, the rerouting and all the talking to the internet. TapeDash stays offline and sends Maps nothing.

**What it is not.** It is not a map. Google Maps gives other apps no route geometry, so TapeDash cannot draw the road ahead. The "line" on the HUD is a schematic of the next turn, and says so (N5).

## How it works

```
Google Maps (own connection) ──posts──► Android notification ──► NavListenerService.kt
                                                                    │ 1. package filter, before anything else is read
                                                                    │ 2. read the notification's text and arrow
                                                                    ▼
                                         NavChannel ──► lib/nav/ (pure Dart): parse, hold, mark stale ──► HUD
```

- Android grants this through **Notification access** (a special access, not a `uses-permission`). On Android 13 and later a sideloaded APK may need "Allow restricted settings" in its App info first (not confirmed for `adb install`).
- GMapsParser (LGPL-3.0, studied, not copied) reads the notification's RemoteViews by view-id name: `nav_title` (distance to the turn), `title` / `lockscreen_directions` (the instruction), `nav_time` / `header_text` (time, distance, ETA), `nav_notification_icon` / `right_icon` (the arrow). **These are another project's findings about some version of Maps. Nothing here is verified against Maps as it is today until N1/N2 says so.**

## Phases and to-dos

Each box is checked when it is built, tested and committed. A box that is only built is not checked.

### N0. Contract and plan
- [x] CLAUDE.md amended (principle 1, section 4, decisions, architecture, roadmap) with the wording the human approved
- [x] This plan; `docs/DECISIONS.md` entry
- [x] `recordings/private/` is already git-ignored (checked)

### N1. The capture spike
Goal: see exactly what Maps posts. No parsing yet.
- [ ] `NavListenerService.kt`: the package filter first; then, **in a debuggable build only**, write the notification's structure to `<external files>/navspike/`: every `extras` key and value, the actions, and the RemoteViews trees (`contentView`, `bigContentView`, `headsUpContentView`, and the standard layouts rebuilt with `Notification.Builder.recoverBuilder`), each view with its class, id name, text, content description and image size; and each arrow image as a PNG. Failures are written down too (they are findings).
- [ ] `NavSources` (the allowlist; the debuggable build adds TapeDash's own package)
- [ ] Manifest: the service, `BIND_NOTIFICATION_LISTENER_SERVICE`, `<queries>` for Maps if the capture shows it is needed
- [ ] A debug-only stand-in (`src/debug/`): a receiver that posts a notification shaped like the one GMapsParser describes, so the whole path can run on an emulator. **It is a stand-in. It proves the machinery, not Google's format.**
- [ ] `tool/nav_spike.sh`: `enable`, `disable`, `status`, `pull`, `clear` for an emulator or a phone (adb)
- [ ] `tool/test_nav_emulator.sh`: the checks below, with an exit code
- [ ] `tool/check_offline.sh`: the navigation checks of CLAUDE.md 4
- [ ] Emulator checks (API 36 first, then API 24, the minSdk):
  - [ ] a notification from another package (the shell) is **not** captured
  - [ ] the stand-in is captured, with its text, its arrow and its view tree
  - [ ] revoking the access stops the capture
  - [ ] **real Google Maps navigating on the emulator** (a destination by intent, a moving location by `adb emu geo`), best effort: this is the first real data
- [ ] `docs/NAV.md` records what the capture found

### N2. Read the captures (gate)
- [ ] Decide the format from the captures: which fields exist, which are text and which are images, how localised the text is, how often Maps updates
- [ ] The human captures on their own phone (how: below) and sends the folder; the fixtures come from it (street names stripped or changed)
- [ ] Update N3 to match; record the findings in DECISIONS.md

### N3. Model, parser and simulator (pure Dart, `lib/nav/`)
- [ ] `NavState`: the turn (arrow, distance, text), the street, ETA, time left, distance left, rerouting, and when it last changed
- [ ] The parser: distances (m, km, ft, mi, decimal comma), times (12 and 24 hour), durations, the arrow; the raw text kept as the fallback
- [ ] `NavSimulator`: posts the same struct a listener would, from a scripted route, in step with the vehicle simulator's speed (so a 20-minute drive runs in seconds on the fake clock)
- [ ] Tests: fixtures in several locales; a parse failure falls back to Google's text; stale after N seconds; the distance counts down between updates by our own speed and snaps back at each update

### N4. The channel and the switch
- [ ] `NavChannel` (Kotlin) and `lib/platform/nav_channel.dart`, with a mocked-channel test
- [ ] The access state (granted or not) and a button that opens Android's Notification access screen
- [ ] Garage → Navigation (parked only, off by default, the explanation in CLAUDE.md 4); settings in `AppSettings`
- [ ] Nothing from navigation reaches trips, recordings, the exchange file or logs (a test that drives a trip and greps what was written)

### N5. The HUD layout
- [ ] DESIGN.md: the navigation HUD (optics rules of §8: one colour, strokes of 5 lp or more, no filled panels); the schematic line; the stale state; Garage copy
- [ ] The layout in `lib/ui/hud/`: the arrow, the distance, the street, ETA / time left / distance left, the speed
- [ ] The arrow: Google's bitmap as a mask in the HUD colour, or our own arrows chosen by the maneuver, whichever the capture shows to be reliable
- [ ] The schematic line: a road, a junction and a marker that closes on it as the distance falls; labelled as a sketch
- [ ] Widget tests at 640x360, 720x360, 800x360; HUD flips applied; stale state; design lint; captures

### N6. End to end on the emulator
- [ ] The app on `tool/sim_server.dart` (WiFi, `10.0.2.2:35000`) with the stand-in driven in step with the simulated drive
- [ ] Real Google Maps navigating on the emulator, if N1 got it working
- [ ] Frame timings with the HUD on, per fidelity tier, noted here and in STATUS.md
- [ ] Android 7 (API 24) emulator: the listener and the HUD

### N7. The phone (the human)
- [ ] `docs/HARDWARE_HANDOFF.md`: how to switch it on, what to check, what to report
- [ ] Maps and TapeDash together on the dash phone: memory, heat, whether Android keeps both alive
- [ ] Fixes from the first real drives; `docs/STATUS.md`; a tag

## How the human captures on their phone (N1, once it is built)

```
tool/nav_spike.sh enable           # grants TapeDash notification access over adb
# start navigation in Google Maps (anything, a minute or two is plenty), then:
tool/nav_spike.sh status           # how many records so far
tool/nav_spike.sh pull             # into recordings/private/navspike-<time>/
tool/nav_spike.sh disable          # revokes the access
```

This needs a **debug** APK (`adb install -r` keeps the trips, the price and the adapter). A release build does not capture anything. The folder holds street names and places: it stays in `recordings/private/` and is not committed.

## Risks

| Risk | What we know | What we do |
|---|---|---|
| Google changes the notification | The format is undocumented; Maps has a "glanceable directions" setting that may differ | The raw text is the fallback; captures are fixtures; a Maps update is a known cause of "nav stopped working" |
| The text is localised | Distances, times and digits vary by language | Fixtures in several locales; if a figure can't be read, show Google's own text |
| The arrow is a small bitmap | Size unknown until N1 | Use it as a mask, or draw our own arrows |
| Maps and TapeDash on a 2 GB phone | Maps navigation is heavy; unmeasured | Measure early (N6/N7); say so if it doesn't hold |
| Android 13+ restricted settings | Sideloaded APKs can be blocked from notification access | The capture script uses `cmd notification allow_listener`; the app tells the person where "Allow restricted settings" is |
| Notification access is broad | Android lets the app see every notification | The package filter first, tests, no storage, and plain words about it in Garage |
| No route geometry | Maps does not share it | A schematic, labelled as one |

## Status log

- 2026-10-24: N0 done. Plan agreed with the human; wording of the contract approved. Emulator check: an API 36 Google Play AVD (`Medium_Phone_API_36.1`) boots headless in about 25 s, has Google Maps 26.38, has internet, and `cmd notification allow_listener` exists; an API 24 AVD (`Reference_API24`) is there for the minSdk.

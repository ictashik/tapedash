# Navigation on the HUD: plan, findings, to-dos and status

Started 2026-10-24. The contract is CLAUDE.md 1 and 4 ("Navigation notification"); the reasons are in `docs/DECISIONS.md`.

**What it is.** If the person has Google Maps navigating on the same phone, TapeDash reads Maps' navigation notification and shows, on the HUD, the next turn, the distance to it, the street, the ETA, the time and distance left, and the speed. Google Maps does the routing, the rerouting and all the talking to the internet. TapeDash stays offline and sends Maps nothing.

**What it is not.** It is not a map. Google Maps gives other apps no route geometry, so TapeDash cannot draw the road ahead. The "line" on the HUD is a schematic of the next turn, and says so (N5).

**Where it works.** Only where Google Maps itself runs, on the same phone as TapeDash. An emulator's updated Maps (26.38) declares minSdk 32 (Android 12) and its system Maps (25.33) minSdk 28 (Android 9), so the 2 GB Android 7 target phone cannot run today's Maps at all. On a phone like that the switch simply is not offered.

## How it works

```
Google Maps (own connection) ──posts──► Android notification ──► NavListenerService.kt
                                                                    │ 1. package filter, before anything else is read
                                                                    │ 2. read the notification's extras and arrow
                                                                    ▼
                                         NavChannel ──► lib/nav/ (pure Dart): parse, hold, mark stale ──► HUD
```

- Android grants this through **Notification access** (a special access, not a `uses-permission`). `tool/nav_spike.sh enable` grants it over adb, which worked on the Android 16 emulator with an adb-installed APK. In the app it will be the Settings screen (N4); on Android 13 and later a sideloaded APK may need "Allow restricted settings" in its App info first (not tested here).
- A release build contains the listener and nothing that records: the capture tool, the stand-in and TapeDash's own package in the allowlist are in the `debug` source set only (`NavBuild.kt` in `release/` and `profile/` returns nothing). Verified: the release APK's dex has `NavListenerService` and neither `NavCapture` nor `NavStandInReceiver`, and a release build run on the emulator against real Maps wrote nothing.

## What Google Maps posts (captured 2026-10-24)

Captured by the spike from **real Google Maps 25.33.03** on a Google Play emulator (Android 16, API 36.1), navigating a real route in Bangalore with the emulator's GPS stepped along it at about 53 km/h (`tool/nav_spike.sh`; the files are in the scratchpad, not the repository). One notification: id 1, package `com.google.android.apps.maps`, channel `1_foreground_1`, category `navigation`, a foreground service, ongoing, group `navigation_status_notification_group`, one action **"Exit navigation"** (TapeDash never presses it). **`contentView` is null: there is no custom RemoteViews.** GMapsParser's view-id notes (`nav_title`, `nav_time`, ...) do not describe this Maps; everything is in the notification's standard extras. Reading the extras needs no RemoteViews inflation and no package visibility.

| Field | What it holds |
|---|---|
| `android.title` | Distance and instruction, see the two shapes below. A `Spanned` (bold runs) or plain text. |
| `android.text` | The street or "toward ..." line in the classic shape; `null` in the other. |
| `android.subText` | Time left, distance left and the ETA (classic) or only `Arrive 9:25 PM` (progress shape). |
| `android.largeIcon` | **The maneuver arrow: a 126x126 bitmap, white on transparent (one colour), a different bitmap per maneuver** (straight, turn left, turn right, ...). A mask to tint in the HUD colour, as it is. `null` while rerouting. |
| `android.shortCriticalText` | (progress shape) the distance to the turn alone, `650 m`; empty when there is none. |
| `android.progress`, `android.progressMax` | (progress shape) **metres along the route, and the route's length in metres** (171 of 6605, rising 20 to 45 per update at 53 km/h; back to 0 with a new max on a reroute). Remaining distance is `progressMax - progress`, as a number, in any language. |
| `android.template` | `android.app.Notification$ProgressStyle` in the progress shape; absent in the classic one. |

**Shape A, "classic"** (before navigation really starts, and probably on Android versions without ProgressStyle, which is Android 16 and later; **not yet seen on one**):
`title` `0 m`, `text` `toward Vittal Mallya Rd`, `subText` `28 min · 6.7 km · 9:25 PM ETA`.

**Shape B, "progress"** (while navigating on Android 16):
`title` `650 m · Turn right at Richmond Cir onto Mission Rd`, `text` `null`, `subText` `Arrive 9:25 PM`, `shortCriticalText` `650 m`, `progress` / `progressMax`.
Instructions without a distance appear as the whole title: `Head north`, `Head west`, `Turn left toward Vittal Mallya Rd`, `Exit the parking lot toward Vittal Mallya Rd`.

**States seen:** `Starting navigation…` (title only, no arrow), `Rerouting...` (no arrow, `subText` `Arrive ` with no time, progress 0), the notification **removed** when navigation ends.

**Texts:** a no-break space (U+00A0) between a number and its unit (`650 m`, `6.7 km`); a middle dot (U+00B7) between the parts; a real ellipsis in `Starting navigation…` and three dots in `Rerouting...`. The distance to the turn counts down in 50 m steps (650, 600, 550, ...) and Maps updated the notification about every 1 to 3 seconds while the position moved.

**What is not in it:** no remaining *time* in the progress shape (only the ETA clock time: remaining time is ETA minus now, parsed from `9:25 PM` in the phone's own format), no road number or lane, no route geometry, no speed limit.

**Not yet known (the human's phone, N2):** the shape on Android 15 and earlier (their Motorola edge 60 stylus), the text in miles or in another language (the emulator is English), what the second line says near a turn ("Then ..."), and what Maps shows for a roundabout or a highway exit.

## Phases and to-dos

Each box is checked when it is built, tested and committed. A box that is only built is not checked.

### N0. Contract and plan
- [x] CLAUDE.md amended (principle 1, section 4, decisions, architecture, roadmap) with the wording the human approved
- [x] This plan; `docs/DECISIONS.md` entry
- [x] `recordings/private/` is already git-ignored (checked)

### N1. The capture spike (done)
- [x] `NavListenerService.kt`: the package filter first; the capture tool (debug builds only) writes the extras, the actions and the RemoteViews trees to `<external files>/navspike/` (`nav.jsonl`, and each image once as a PNG)
- [x] `NavSources` (the allowlist: Maps only in a release build), `NavTap`, and `NavBuild` in `debug/`, `release/` and `profile/`
- [x] Manifest: the service with `BIND_NOTIFICATION_LISTENER_SERVICE`. **No `<queries>` was needed**, because Maps' notification uses no RemoteViews
- [x] A debug-only stand-in (`NavStandInReceiver`, `nav_stand_in.xml`): *shaped after GMapsParser's notes, which turned out not to match Maps; it is rebuilt in N6 to post the two real shapes above*
- [x] `tool/nav_spike.sh` (`enable`, `disable`, `status`, `pull`, `clear`, `standin`, `other`)
- [x] `tool/test_nav_emulator.sh`: the listener connects; a notification from another package is ignored; the stand-in is read with its texts, view names and arrow; its removal is seen; nothing is read once access is revoked
- [x] `tool/check_offline.sh`: no network code in the feature, exactly one listener service, the release allowlist is exactly Google Maps, release and profile add nothing, the filter comes first; each rule has a test that shows it failing (`test/unit/tool/check_offline_test.dart`)
- [x] Emulator, Android 16 (API 36.1): all of the above, and **real Google Maps navigating** (the capture above)
- [x] A release build: compiles (17.6 MB for arm64), strict offline check passes, the capture classes are absent from its dex, and it wrote nothing against real Maps
- [ ] Emulator, Android 7 (API 24, the minSdk): the listener, with the stand-in (Maps will not run there). *Did not start yet: `Reference_API24` has not been booted in this work.*

### N2. Read the captures (gate, partly done)
- [x] The format from the emulator's real Maps: the table above
- [ ] **The human captures on their own phone** (below) and sends the folder: Android 15's shape, miles or another language, a roundabout, a highway exit. The fixtures for N3 come from both captures (a street name is public data in the emulator's, and the human's is changed before it is committed)
- [ ] Update N3 to match; record the findings in DECISIONS.md

### N3. Model, parser and simulator (pure Dart, `lib/nav/`) (done)
- [x] `NavState` (`nav_state.dart`): the phase (idle, starting, rerouting, guiding), the turn (arrow mask, distance as Google wrote it and in metres, instruction), distance left, time left (Google's, or derived from the ETA and marked so), the ETA, and when it was received
- [x] `NavNotification` (`nav_notification.dart`): the wire format of the channel, with `NavArrow` (the manoeuvre's mask)
- [x] The parser (`nav_parser.dart`, `nav_text.dart`) for **both shapes**: the numbers where Maps puts numbers (`shortCriticalText`, `progress`, `progressMax`) and the text otherwise; m, km, ft, mi, yd; decimal comma and grouping; 12 and 24 hour clocks (through a narrow no-break space too); digits of the Indian and Arabic scripts; the parts of a classic sub text told apart by what they are, not where. **A unit it has not seen is not guessed**: Google's text is kept and the figure is null (`NavParser(units: ...)` takes more)
- [x] `NavTracker` (`nav_tracker.dart`): holds the state; **stale** after 15 s of silence with the car moving, 3 minutes standing; counts the distance to the turn down by the car's own speed between posts (a marker that moves smoothly; the text stays Google's); on the fake clock
- [x] `NavSimulator` and `NavArrows` (`nav_simulator.dart`, `nav_arrows.dart`): a route driven in step with the car, posting both real shapes with the cadence (2 s moving, 7 s standing), the 50 m steps, `Starting navigation…`, `Rerouting...` with the progress back to zero, and the removal at the end; arrows drawn in code at Maps' 126 px
- [x] Tests (`test/unit/nav/`, 101 with the architecture test): **every real notification in the capture** (`test/fixtures/nav/maps_25_33_android16.jsonl`) parses and the key ones to exact figures; the cases the capture did not have (miles, feet, a 24 hour ETA, an ETA just passed or tomorrow's, an unknown unit); the wire form; stale, the countdown and its limits; a replay of the whole capture through the tracker on a fake clock; the simulator read back by the parser in both shapes
- *The capture had 17 s of silence while the emulated car stood; the replay test uses the capture's own speed (0 until 93 s, then 14 m/s). The longest gap with the car moving was 5 s.*

### N4. The channel and the switch (done, native side verified on an emulator below)
- [x] `NavReader`, `NavBridge`, `NavChannel` (Kotlin) and `lib/platform/nav_channel.dart` with a fake: the title, text, sub text, short critical text, progress, template and the arrow's alpha mask cross as one map. **Nothing is read unless Dart is listening** (`NavBridge.posted` returns before it touches the notification), so a switch that is off opens no notification even with access granted
- [x] The access state (`access`) and a button that opens Android's own screen for it (the page of TapeDash's listener on Android 11 and later, the list before)
- [x] `<queries>` for Google Maps' package only, so that Garage can say when it is not on the phone (`mapsVersion`). No permission, and no other package becomes visible
- [x] `NavService` (`lib/app/nav_service.dart`): follows the switch, listens only while it is on, keeps the tracker, feeds it the car's speed, asks again when the app comes back to the screen (the person may have been to Android's settings); the link's status: off, no Maps, needs access, waiting, guiding, stale. In the car shell and the GPS-only shell
- [x] Garage → **Navigation** (off by default; parked only, like all of Garage): the switch, the status in words, a row that opens Android's screen when access is missing, and the plain explanation, including that access lets an app see every notification
- [x] A row in the debug overlay (the link's state only, never what Maps said)
- [x] Nothing from navigation reaches trips, recordings, the exchange file or logs: a test that pushes a distinctive street through the service and looks through everything the settings wrote, and an import-graph test that fails if any code that stores or sends data imports the navigation code (`test/unit/nav/nav_privacy_test.dart`)
- [x] `tool/check_offline.sh` now also covers `NavBridge` hand-offs and the allowlist as `setOf(GOOGLE_MAPS)`

### N5. The HUD layout
- [ ] DESIGN.md: the navigation HUD (optics rules of §8: one colour, strokes of 5 lp or more, no filled panels); the schematic line; the stale state; Garage copy
- [ ] The layout in `lib/ui/hud/`: the arrow, the distance, the street, ETA / time left / distance left, the speed
- [ ] The arrow: Google's bitmap as a mask in the HUD colour (it is already a mask: N1)
- [ ] The schematic line: a road, a junction and a marker that closes on it as the distance falls; labelled as a sketch
- [ ] Widget tests at 640x360, 720x360, 800x360; HUD flips applied; stale state; design lint; captures

### N6. End to end on the emulator
- [ ] The stand-in rebuilt to post the two real shapes (classic, and ProgressStyle on Android 16)
- [ ] The app on `tool/sim_server.dart` (WiFi, `10.0.2.2:35000`) with the stand-in driven in step with the simulated drive
- [ ] Real Google Maps navigating on the emulator with the app's HUD on (done by hand in N1 for the capture)
- [ ] Frame timings with the HUD on, per fidelity tier, noted here and in STATUS.md
- [ ] Android 7 (API 24) emulator: the listener and the HUD

### N7. The phone (the human)
- [ ] `docs/HARDWARE_HANDOFF.md`: how to switch it on, what to check, what to report
- [ ] Maps and TapeDash together on the dash phone: memory, heat, whether Android keeps both alive
- [ ] Fixes from the first real drives; `docs/STATUS.md`; a tag

## How the human captures on their phone (works now)

This needs a **debug** APK (`adb install -r` keeps the trips, the price and the adapter). A release build captures nothing. With the phone on adb:

```
flutter build apk --debug --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
tool/nav_spike.sh enable           # grants TapeDash notification access over adb
# start navigation in Google Maps and drive (a minute is enough; a roundabout, a highway exit
# and a wrong turn that makes it reroute are the most useful), then:
tool/nav_spike.sh status           # how many records so far
tool/nav_spike.sh pull             # into recordings/private/navspike-<time>/
tool/nav_spike.sh disable          # revokes the access
```

The folder holds street names and places along the route: it stays in `recordings/private/` and is not committed. Send it, or a few lines of `nav.jsonl`, as you like; names can be changed before they become a fixture.

## Emulators

- **`tapedash_nav`** (Google Play, API 36.1, 2 GB RAM, 10 GB data): made for this work, because the user's `Medium_Phone` AVD has 332 MB free and the 107 MB debug APK would not install. It has Google Maps. Boot: `emulator -avd tapedash_nav -no-window -no-audio -no-snapshot -gpu swiftshader_indirect`. **Its `.ini` pointer must say `target=android-36.1`**: one made by `avdmanager` said `android-0`, the emulator then fell back from the hypervisor to software emulation and crashed.
- Maps on an emulator: skip the sign-in, dismiss the two welcome dialogs, then `adb shell am start -a android.intent.action.VIEW -d "google.navigation:q=12.9352,77.6245&mode=d" -p com.google.android.apps.maps`; the emulator's position is set and moved with `adb emu geo fix <lon> <lat>`.
- Maps showed 0 km/h while the position stood still, and rerouted whenever the stepped positions left its route (a straight line is not a road), which is also how the rerouting states were captured.

## Risks

| Risk | What we know | What we do |
|---|---|---|
| Google changes the notification | **Seen already:** it differs between navigation states and (probably) Android versions; GMapsParser's RemoteViews no longer applies | Parse by shape; prefer numbers over text; the raw text is the fallback; captures are fixtures; a Maps update is a known cause of "nav stopped working" |
| The text is localised | Distances, times and digits vary by language; only English seen | Fixtures in more locales (the human's phone); show Google's own text if a figure can't be read |
| The arrow is a bitmap | **Resolved:** 126 px, white on transparent, one per maneuver | Tint it as a mask; check it stays crisp at HUD size (N5) |
| Maps and TapeDash on one phone | Maps navigation is heavy; unmeasured; current Maps needs Android 9 or 12 and later | Measure early (N6/N7); don't offer the switch where Maps can't run |
| Android 13+ restricted settings | Sideloaded APKs can be blocked from notification access | The capture script uses adb; the app tells the person where "Allow restricted settings" is |
| Notification access is broad | Android lets the app see every notification | The package filter first, tests, no storage, and plain words about it in Garage |
| No route geometry | Maps does not share it | A schematic, labelled as one |

## Status log

- 2026-10-24: N0 done. Plan agreed with the human; wording of the contract approved.
- 2026-10-24: N1 done on an Android 16 emulator with real Google Maps 25.33: the format is in "What Google Maps posts" above, and it is not what the plan assumed. Everything that could be checked on the emulator passes; the Android 7 emulator and the human's phone are still to do.

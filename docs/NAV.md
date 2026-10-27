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

**The human's phone (captured 2026-10-27): a Motorola edge 60 stylus, Android 16, Google Maps 26.42, English (India), kilometres.** Three drives with a fake GPS (see "How the phone was driven" below). The shape is the **classic one, not the progress shape**, so Android 16 does not by itself mean ProgressStyle: `title` is the distance (`120 m`, with a no-break space, **`0 m` or an empty string beside `Head east` and `towards ...`**), `text` the instruction or street (`Turn left`, `Sharp right`, `Residency Rd`, `towards Vittal Mallya Rd`), `subText` `23 min · 6.7 km · 9:42 pm ETA` (a **lower-case `pm` after a narrow no-break space, U+202F**), no `shortCriticalText`, no progress, no template. The arrow is a **135 x 135** mask (four seen: straight, left, right and a **hairpin for `Sharp right`**), a different bitmap per manoeuvre. `Rerouting...` is in `text` with an empty title and an **empty-string sub text** (Maps 25.33 had `Arrive `). One record of `0 min · 10 m · 9:23 pm ETA` lasted about a second in the middle of a route (Maps' own, not reproduced). The distance steps in tens of metres under 200 m, 50 below 600. The reduced capture is the fixture `test/fixtures/nav/maps_26_42_android16.jsonl`.

**The channel depends on the floating window.** With Maps' picture-in-picture **allowed** (the phone's default), all 87 navigation posts were on `1_foreground_1` (importance 3, flags 362) and Maps shrank to a floating window over the HUD. With it **denied**, Maps flipped between `1_foreground_1` and **`1_2` ("Navigation urgent updates", importance 4, flags 354: no `ONLY_ALERT_ONCE`)** about ten times in 160 s, and Android popped a dark-teal card over the HUD (5 of 15 sampled frames; the emulator's was light). The card's "Pop on screen" switch for that channel, off, removed it (0 of 75 sampled frames) while Maps went on posting to the channel.

**Not yet known:** the text in miles or in another language, what the second line says near a turn ("Then ..."), what Maps shows for a roundabout, a U-turn or a highway exit, the progress shape on any real phone, and what the **sub text** says on arrival.

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

### N5. The HUD layout (done; design review frames in `docs/design-review/nav/`)
- [x] DESIGN.md 8 (the navigation layout) and 7.8 (Garage → Navigation)
- [x] `lib/ui/hud/nav_hud.dart`: the speed on the left; on the right Google's arrow (its mask painted in the HUD colour), the distance to the turn, the instruction (three lines, cut at a word), and along the bottom the ETA, time left and distance left. It takes over from the chosen layout while Maps is guiding and gives it back when Maps stops; `HudView` and `HudHost` take a `nav`
- [x] The arrow: Google's bitmap as a mask (`NavArrowImages` makes each into an image once)
- [x] The approach line: a bold line to a ring at the junction, leaning the way the arrow turns (`NavBendReader`: tested on the three real arrows), a dot that climbs over the last 500 m counting down on the car's own speed, and filling the ring at the turn. A sketch, and DESIGN.md says so
- [x] States: `Starting navigation…` and `Rerouting...` in Maps' words; Maps gone quiet shows NO UPDATE and a dash and no figures
- [x] Tests (`test/widget/nav_hud_test.dart`, `test/unit/nav/nav_format_test.dart`, `test/unit/nav/nav_bend_test.dart`): it takes over only while guiding, never with the switch off; one colour on black at 640, 720 and 800 wide; the real arrow drawn; the figures, the line and the dot; the dot climbs; stale shows no figure; the geometry keeps to the HUD's 5 lp and 0.06H floors and clear of the speed. `test/design/capture/nav_hud_capture_test.dart` renders the frames
- Deviation, on purpose: the instruction is Google's text and runs to three lines, past the six-word limit of DESIGN.md 11 for Motion screens. It is cut at a word, and the human is asked to judge it (the review package's open question)

### N6. End to end on the emulators (done on Android 16 and Android 7; the phone is N7)
- [x] The stand-in rebuilt to post the real shape (standard extras, the arrow as a 126 px large icon, the progress and `android.shortCriticalText` in the extras), with `--id` and `--category none` for a second, non-navigation notification
- [x] `tool/sim_server.dart --nav-adb` plays Maps from the simulated car (`tool/nav_stand_in.dart`): the same car the app reads over OBD, so what Maps says and what the app measures share one truth
- [x] `tool/test_nav_e2e.sh` (**emulators only**: it clears the app's data, and `flutter test` uninstalls the app, which would erase a phone's trips): a 90 s drive through the production path, and a second test that only Maps' navigation notification is a turn
  - **Countdown against Maps** (Android 16, three runs): the distance counted down on the car's own speed agreed with Maps' next figure to a **median of 7 to 11 m, p90 about 26 m, worst 33 to 40 m**. Maps rounds to 50 m steps, so about 25 m of that is Maps' own rounding
  - A left and a right bend read from arrows that Android drew on the device; the HUD stayed on Maps through the stops at signals (no stale sample)
  - **The filter test** was shown to fail when each check is taken out of `NavBridge` (a traffic alert took the HUD over; another notification going away ended the route)
- [x] **Real Google Maps on the HUD** (`tool/test_nav_maps.sh`, emulator only): Maps 25.33 navigating on the emulator, its own notification through the real listener, channel, parser and HUD, with the position stepped along. 111 guiding reads, 54 with an arrow, instruction, distance and ETA together, the phases guiding and rerouting, three arrows read as left, right and straight
- [x] Frame cost with the HUD on, on an emulator with software GL (which says nothing about an old phone): p50 1.3 ms, p90 1.9 ms, p99 5 to 7 ms
- [x] **Android 7 (API 24), the minimum**: found and fixed a crash (below), then see the status log for the run
- [ ] Frame timings per fidelity tier on a real low-end phone: N7

**What real Maps did that the model had not**
- Near a turn Maps **drops the distance** (`80 m`, `70 m`, `50 m`, then only `Turn left onto Mission Rd`), and gives none for `Head toward ...`. The HUD takes a turn with no distance for the turn itself (the dot sits at the junction); a straight `Head toward` has no dot
- Maps counts down in **50 m steps down to about 300 m and 10 m steps below**; the simulator now does the same
- It reroutes often when the car is off its route, and says `Rerouting...` (the HUD shows Maps' words and no figures)
- It shows its own **floating window** when the person switches away during a route, which can sit over the HUD. Garage says where to turn it off
- **It pops a card over the HUD at turns (Android 16, found with the release build and real Maps, 2026-10-27).** As a turn comes up Maps moves its notification from the channel `1_foreground_1` ("Navigation", importance 3) to `1_2` (**"Navigation urgent updates"**, importance 4, high), and Android 16 pops it as a card at the top for about 6 s, over the distance and the arrow, with the status bar showing. Earlier notes said this happens "the first time" and that Do Not Disturb is the answer: **both were wrong.** Measured over 170 s drives at 30 km/h on a fresh route: **25 of 85 frames had the card** (8 cards, 15 posts into the urgent channel); with Do Not Disturb (priority only, default policy) **still 26 of 85**; with "Pop on screen" switched off for that one channel, **0 of 85**, although Maps still posted into the channel 28 times. So the remedy is Android's per-channel switch: Garage → Navigation now says so and has a row that opens Android's Maps notification page (the page opens on the emulator; the categories list is one level down). On the human's phone (probably Android 15, no Live Updates) whether Maps does this at all is unknown: it is on the checklist
- One arrow once read as `unknown` (not reproduced in two later runs); the test now prints each distinct arrow with a picture of any it cannot read

**Found by running on Android 7, and fixed:**
- `Bitmap.Config.HARDWARE` does not exist before Android 8; naming it in `NavReader` is a `NoSuchFieldError`, which is an Error and not an exception, and would have **crashed the app the first time a navigation notification arrived** on an Android 7 phone. It is guarded by the SDK version, and `NavBridge` now cannot be taken down by one unreadable notification
- `NavService` ranked "Google Maps is not on this phone" above what was arriving; the image has no Maps, so a stand-in could never take the HUD over. What is arriving now comes first
- `nav_spike.sh disable` aborted silently when TapeDash was the only listener, and `cmd notification post` does not exist on Android 7 so the "another package is ignored" check could not run: the test now says it skipped it

### N7. The phone (the human)
- [x] `docs/HARDWARE_HANDOFF.md` 5e: the capture on the human's phone, how to switch it on, what to check (including Maps' floating window and its pop-up card), what to report
- [x] `docs/STATUS.md`: what was verified on the emulators and what was not
- [x] **The capture from the human's phone, 2026-10-27** (Android 16, Maps 26.42: the classic shape): three drives, the fixture `maps_26_42_android16.jsonl`, four arrows. It found three bugs, now fixed and tested: "0 m" shown as a distance, a `Sharp right` hairpin read as a left bend, and `Rerouting...` read as `Starting`
- [ ] A capture with a roundabout, a U-turn and a highway exit, and in miles or another language
- [ ] Maps and TapeDash together **in the car**: memory, heat, whether Android keeps both alive for a whole drive (at a desk, 4 runs of 2 to 3 minutes each were fine; the phone stayed at 25 to 27 degrees)
- [ ] The human's answers to the design review package (`docs/design-review/nav/`)
- [ ] Fixes from the first real drives; a tag (suggested: `v1.1.0-nav`, after the phone)

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
| The arrow is a bitmap | **Resolved:** 126 px, white on transparent, one per maneuver | Tinted as a mask; slightly soft at the HUD's size on an emulator, to be judged on the glass |
| Maps and TapeDash on one phone | Maps navigation is heavy; unmeasured; current Maps needs Android 9 or 12 and later | Measure early (N7). Garage says when Maps is not on the phone |
| Maps' floating window over the HUD | **Seen on the emulator** (a bright map on the black) | Garage and the handoff say where to switch it off in Android's settings; the app cannot |
| Maps' own pop-up card over the HUD at a turn | **Seen on Android 16 with real Maps**: 25 of 85 frames; Do Not Disturb did not stop it; "Pop on screen" off for "Navigation urgent updates" did (0 of 85) | Garage explains it and opens Android's Maps notification page; the handoff checks whether the human's phone does it at all. Other apps' pop-ups (a call, a message) are Android's; Do Not Disturb is still the way for those |
| An Android that leaves an enabled listener unbound | **Seen on Android 7** after a kill while bound | The system is asked to bind it again, and the component is toggled; fired and recovered on the emulator, not proved to be the cause |
| A Maps that no longer sets the navigation category | Seen set on 25.33; others unknown | The bridge then shows nothing (it fails safe); the capture tells |
| Android 13+ restricted settings | Sideloaded APKs can be blocked from notification access | The capture script uses adb; the app tells the person where "Allow restricted settings" is |
| Notification access is broad | Android lets the app see every notification | The package filter first, tests, no storage, and plain words about it in Garage |
| No route geometry | Maps does not share it | A schematic, labelled as one |

## Status log

- 2026-10-24: N0 done. Plan agreed with the human; wording of the contract approved.
- 2026-10-24: N1 done on an Android 16 emulator with real Google Maps 25.33: the format is in "What Google Maps posts" above, and it is not what the plan assumed. Everything that could be checked on the emulator passes; the Android 7 emulator and the human's phone are still to do.
- 2026-10-24: N3 to N6 done. The navigation HUD works on the production path on an Android 16 emulator, against both the stand-in (driven by the simulated car) and real Google Maps. The Android 7 emulator found a crash that is fixed. **Nothing has met a real phone.**
- 2026-10-27: the **release APK with real Google Maps** on the Android 16 emulator, from the cold open to the HUD (GPS-only source, the switch on, Android's access dialog; the emulator's position stepped at 30 km/h with `geo fix`, whose fifth argument is knots; this image ignores NMEA). Real turns, distances, ETAs and long instructions on the HUD in the release build; **the card finding** (above) and its remedy; a Garage note and a row that opens Android's Maps notification page (verified on the emulator). Considered and **not** done: narrowing the listener at the OS (Android 14's `default_filter_types` and `disabled_filter_types` meta-data to Real-time only): if Maps' notification were not classed as Real-time on some phone, the HUD would silently show nothing and the person could not fix it, and the package filter and its tests already hold the contract; revisit after the human's capture says how their phone classes it.
- 2026-10-27: **the human's phone** (Motorola edge 60 stylus, Android 16, Maps 26.42), on adb, with the debug build installed over their release (`adb install -r`: data kept) and the shell allowed to mock location. Four things came out of three drives at 30 km/h on a fixed Bangalore test route: (1) the classic shape, with `0 m` beside straight instructions, which the HUD showed as "0 M" over a straight arrow (the parser now treats a zero distance as none, in both shapes); (2) the `Sharp right` hairpin was read as a left turn by the bend reader (a stem test was added: it is now `unknown`, drawn straight); (3) `Rerouting...` has an empty sub text on this Maps and was read as `Starting` (a sub text that is there is a reroute); (4) the floating window and the card are one problem seen from two sides: allowed, a bright map covers the HUD; denied, Maps pops a card at every turn unless the urgent channel's \"Pop on screen\" is off. Garage's two notes now say so and its row opens the page on the phone. The phone's settings were put back as found (channel importance, floating window, screen timeout, mock app-op). The **release** build was then installed over the debug one and driven for 100 s with real Maps: it read every turn, distance, ETA and figure as the debug build had.

## How the phone was driven (2026-10-27)

No real drive was possible, so the position was faked from the shell (`tool/phone_gps.py`, which also puts everything back). **The shell is refused until `adb shell appops set 2000 android:mock_location allow`**; then `cmd location providers add-test-provider gps` and `network` (both, so that a real network fix does not mix in), `set-test-provider-enabled <p> true`, and `set-test-provider-location <p> --location <lat>,<lon> --accuracy 5` once a second along a line from a fixed test origin in central Bangalore to a fixed destination (the human's own location is never used). The shell can send **no speed and no bearing**, so TapeDash's HUD speed stays blank when its source is an adapter that is not there, and Maps showed `--`. Afterwards `remove-test-provider` for both and `appops set 2000 android:mock_location default`; a `finally` does it even on an error, and `dumpsys location` is checked for a leftover `test provider`. Frames were read from `screencap`. **A light-pixel probe for the card found none on this phone, because its card is dark teal:** look at the frames, or probe the colour of the pill. Nothing here ran with the screen locked: the human unlocked the phone and the screen was kept on while plugged in (`svc power stayon usb`, put back to `false`).

**The capture holds more than the route.** The debug capture logs every notification Maps posts, and one of them (an account summary in the shade when the capture began) carried the human's account email in its sub text. The folders are in `recordings/private/` (git-ignored); the fixture was reduced to navigation-category records and holds no `@`. Clear the capture on the phone after pulling it (`tool/nav_spike.sh clear`).

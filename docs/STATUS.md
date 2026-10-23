# Status

Updated 2026-10-23, with the removal of Demo Mode, the GPS-only source and the steadier Bluetooth ("No demo mode, a GPS-only source, and a steadier Bluetooth" below). Before that, 2026-10-18, with the Insights ("Insights" below). Before that, 2026-10-16, with the survey drive ("The survey drive" below). Before that, 2026-09-30, after the first real drives (see "First real drive" and "The second drives" below) and the replay and the engine sound ("After the map"). Before it, at the end of phase 6, **the app was ready for real-hardware testing** (CLAUDE.md 11). Phases 0 to 6 are built, tested and committed, on the simulator. The app opens on a cold open and a choice: **CONNECT MY CAR** (a WiFi, Bluetooth or BLE ELM327) or **GPS SPEED ONLY** (the demo that used to be here was removed on 2026-10-23), and then drives, records trips, works out where the money goes, coaches, and shows Review, Coach, History, Garage and Diagnostics. **Nothing here has met a real phone, adapter or car.** The next step is yours: `docs/HARDWARE_HANDOFF.md`.

## Where we are

| Phase | State |
|---|---|
| 0. Foundation | **Done** |
| 1. Simulator | **Done** |
| 2. OBD stack on the simulator (tag `v0.1.0-sim`) | **Done** |
| 3a. Design system (tag `v0.2.0-design`) | **Done** |
| 3b. Cockpit and HUD (tag `v0.3.0-sim`) | **Done**; its review package's five open questions are still unanswered |
| 4. Trips, fuel and money (tag `v0.4.0-sim`) | **Done** (simulator only) |
| 5. Coach and review (tag `v0.5.0-sim`) | **Done** (simulator only) |
| 6. Real transports (tag `v0.6.0-handoff`) | **Done, unverified on hardware**; stopped for the handoff |
| 7. After hardware | **Started**: the first real drive is in; recordings, tuning and the fixes below are next |

**Suggested tags, none created** (placing them is your call; none has been pushed): `v0.1.0-sim` on `d5016d6`, `v0.2.0-design` on `62fb1bb`, `v0.3.0-sim` on `57cd4e2`, `v0.4.0-sim` on `f0105e3`, `v0.5.0-sim` on `2db202f`, `v0.6.0-handoff` on the commit that adds `docs/HARDWARE_HANDOFF.md`.

## No demo mode, a GPS-only source, and a steadier Bluetooth (2026-10-23)

The human's request, after the connection problem persisted on the real adapters: remove demo mode (some fallbacks still landed in it), add a mode that shows speed from the GPS alone, make the Bluetooth steadier (the adapter shows up as `OBDBLE` and `OBDII`), and build a clean APK. Reasons and choices are in `docs/DECISIONS.md` ("Demo Mode removed, a GPS-only source, and a steadier Bluetooth").

**What exists now**
- **No Demo Mode.** The app asks (CONNECT MY CAR or GPS SPEED ONLY) until a source is chosen, then keeps it. An adapter that will not connect stays "looking for your adapter" and retries; it is never replaced by anything. Garage → **Speed from** switches between the car's adapter and the GPS. A phone that was last in the old demo, with an adapter chosen, now drives from the adapter.
- **GPS only:** the speed as the hero, with distance, moving time, average, fastest and heading, the dock (Garage, HUD, Reset trip) and the HUD with the speed alone. Words for a missing permission, no receiver and no fix yet. No tach, money, coach, trips or sound. Tests: `test/unit/location/gps_drive_test.dart` (the rules, and a simulated city drive whose distance is within 3% of the car's ground truth), `test/widget/gps_app_test.dart` (the whole app on a fake receiver at 640, 720 and 800 wide).
- **One Bluetooth choice that finds both radios**, each adapter marked Classic or Low Energy and Close / Near / Far, tried before it is taken (Low Energy too), with "Try OBDBLE" offered when the pick will not open.
- **Steadier native links** (`BleChannel.kt`, `BtClassicChannel.kt`): a proper release before every reconnect, bounded retries, an optional MTU step, delayed service discovery, a short connection interval, four socket kinds with the last good one first, a watchdog on a hung connect, discovery stopped first. A 75 s limit in Dart on any open.
- **A connection log** (Garage → Adapter → Connection log, newest first) and the same lines in the debug build's recording (`@ link ...`): each attempt, the radio's status code, which socket kind worked or failed, the services the adapter lists. **If it still will not connect, a screenshot of the log says why.**

**Verified here:** the Dart side, headlessly (analyze, format, the whole test suite, the offline check; see the commit). **Not verified, and not claimed:** both Kotlin channels (they compile in the APK build; neither has met a phone since these changes), the new retry and release timings, which of the two radios your adapter does best, GPS speed on a real phone, and everything on the GPS screen as seen by an eye (I looked at one render of it at 800x360 only; the design review package is waived as for phases 4 to 6). The first thing to check with the new APK is the connection log after a failed attempt.

**Owed:** the Design Lab has no page for the GPS screen (only a capture test, `test/design/capture/gps_cluster_capture_test.dart`); no golden for it; the GPS screen at the oldest-device frame budget has not been timed; `integration_test/sim_drive_perf_test.dart` (the old demo perf test, now over WiFi to the simulator) has not been run since the change.

## A pairing gone wrong (2026-10-22)

A Bluetooth Classic adapter paired with the wrong PIN could be left bonded but unusable, and every connection then failed with no way out in the app. Now: `BtClassicChannel` can forget a pairing (`unpair`, the hidden `removeBond` by reflection) and clears a half-finished one before pairing again; the connect flow tries a Bluetooth Classic adapter before taking it and, if it will not open, offers **Forget and pair again** (the phone asks for the PIN afresh) or **Use anyway**; and the dashboard's drive lets go of the adapter while the connect flow is open, so its 10-second reopening no longer cuts across a pairing or the test. Mocked-channel and widget tests cover the Dart side. **Unverified on a phone:** `removeBond` by reflection and the bond-state waits.

## Insights (2026-10-18)

Nine ideas from the pitch, built, tested and committed: **Current, Powerflow, Power, Gears, Tank, Tolls, Cold start, Ghost and Year on Tape**, with a **Share** button on the last. They open from a new **Insights** button on the parked dock, as one full-screen form with a scrolling selector (DESIGN.md 7.14, 6.18); parked only, and it closes itself when the car moves. The Tank count also fills the Money page's fuel-left slot for a car that sends no level, marked "≈". Decisions and their reasons are in `docs/DECISIONS.md` ("Insights").

| Idea | Where it lives | What it is made from |
|---|---|---|
| Current | `lib/insights/voltage_trace.dart`, `rest_voltage_log.dart` | module voltage of a trip; a log of the battery at rest (one a day) |
| Powerflow | `powerflow.dart`, `wheel_power.dart` | speed, acceleration (no hills) and the trip's fuel |
| Power curve | `power_curve.dart` | the same wheel power against revs |
| Gearbox, found | `gearbox.dart` | revs against speed; a CVT is a fan |
| Tank without a gauge | `lib/money/fuel_ledger.dart` (`litresLeft`), `tank_reading.dart` | last full fill-up, the estimate since, the calibration |
| The Toll Map | `toll_map.dart`, `geo.dart` | stops with the engine on and a GPS fix |
| Cold-start bill | `cold_start.dart` | coolant, speed and fuel of a trip |
| Ghost commute | `ghost_commute.dart` | the GPS shapes of two trips |
| Year on Tape + Share | `year_on_tape.dart`, `year_poster.dart`, `ShareChannel.kt` | every trip; the picture is drawn by the app |

**Numbers:** `tool/verify.sh` green at 3,471 tests (with goldens excluded on this Mac). New: `test/unit/insights/` (the analyses, a made-up commute fixture, and a plausibility test against the real recordings), `test/design/insight_charts_test.dart`, `test/widget/insights/` (every tab at 640, 720 and 800 wide; the page in the shell), `test/unit/platform/image_sharer_test.dart`. Captures of every tab are in `test/design/capture/insights_capture_test.dart`, and frames 39 to 50 of the build video.

**The real drives found two bugs in the first model**, which made-up drives never would have: one wrong speed reading (46 then 95 km/h) read as 100 kW, and noise counted only when it pulls looked like work. Fixed (a median of three, a fitted slope, impossible moments dropped, "highest seen" is the edge's peak). On the City's own recordings the gearbox comes out a fan (it is a CVT), the edge peaks at about 30 kW at 3,100 rpm, and the wheels get 7 to 17% of the fuel's energy.

**Not verified, and why**
- **The Android share sheet.** `ShareChannel.kt` compiles (a debug and a release APK built) and its Dart side is tested on a mocked channel, but nobody has seen the sheet open on a phone. It adds no permission: the strict offline check passed on a release build (`--split-per-abi`, armeabi-v7a 14.8 MB and arm64-v8a 17.4 MB, under the 20 MB budget).
- **The counted tank on a real car.** Tested on the simulator and with hand-made ledgers. It starts only after a full tank is logged at Pit Stop with FULL TANK on, and it drifts if trips are missed. The City reports no fuel level, so this is the path it will take.
- **The resting-voltage reading** (`RestVoltageWatcher`) has run only against the simulator: it needs the ignition on, the engine off and a settled voltage for 8 s, which the real adapter has not yet been asked for.
- **Everything that needs GPS** (Tolls, Ghost) has been run on made-up routes with clean fixes, not on a phone's real scatter. The thresholds (150 m for a place, 180 m for a route) are guesses until a real week of driving is in.
- **The Design Lab** has no pages for these charts. They are drawn from `ChartKit` and exercised in the capture tests on made-up driving, but CLAUDE.md 12 asks for the Lab first: that is owed.
- **The gear digit** in a cluster (the pitch's "can sit in any cluster") is not built. `Gearbox.gearFor` and the learned ratios are there for it; the City is a CVT, so it would show nothing on this car.
- **Names for places.** The Toll Map has no map under it, so a place is a numbered ring. The optional offline map (CLAUDE.md 13, phase 7) is where names would come from.
- **Daylight, Night, VFD, EMBER and MONO** were captured for the Gears tab (ION and VFD) only. The golden matrix of DESIGN.md 14.1 does not exist yet for these pages, and goldens are CI-Linux-only.
- **Fidelity tiers and frame timings** of the new pages were not measured (no emulator was run).

## Phase 3b so far: every component

DESIGN.md 6 and CLAUDE.md 13 name eleven components for this phase. All eleven exist, each built in the Design Lab pattern (a capture test first, fixed against what it actually showed, then a widget-test suite against real pixels, then `tool/verify.sh`, one commit per component) rather than assembled straight into a screen.

| Component | DESIGN.md | Where | Tests |
|---|---|---|---|
| Rolling numerals (Saira and seven-segment) | 6.1 | phase 3a | phase 3a |
| Tach arc | 6.2 | `lib/ui/design/components/tach_arc.dart` | 17 |
| Vertical tape (speed/RPM, "tapes") | 6.3 | `vertical_tape.dart` | 12 |
| Shift horizon | 6.4 | `shift_horizon.dart` | 17 |
| Bar gauges | 6.5 | `bar_gauge.dart` | 8 |
| Telemetry tiles | 6.6 | `telemetry_tile.dart` | 10 |
| Eco bar | 6.7 | `eco_bar.dart` | 16, plus `glow_cache_test.dart`'s 5 (below) |
| Money readout and the Money Tape | 6.8 | `money.dart` | 9 |
| Status strip | 6.9 | `status_strip.dart` | 15 |
| Alerts (`AlertHysteresis`, the slot glyph, the critical bracket, the caution line) | 6.10 | `alerts.dart` | 18 |
| Road view | 6.11 | `road_view.dart` | 16 |

Plus `test/widget/glow_cache_test.dart` (5 tests): `GlowSprite.drawCentered`, added when the eco bar's capture shot showed its halo sitting beside the puck rather than around it (below).

**Two of these were nearly missed entirely.** CLAUDE.md 13's phase 3b bullet names all eleven, but partway through this phase a summarised context window's own running notes of "what's left" had quietly dropped the vertical tape, and it was built only because the filesystem was checked against CLAUDE.md's list directly rather than against those notes. The same direct check, repeated afterwards on principle, turned up the Money Tape missing too. Both are now built; the lesson (verify against the source document, not a summary of it) is worth remembering for the remaining phase 3b bullets below, which have not had this check run against them a second time since.

**Real bugs their own tests or capture shots found, not just written and left:**
- The tach arc's and shift horizon's segment-lighting sync skipped the very first frame (no previous index to diff against).
- `shouldRepaint` on the tach arc, shift horizon, bar gauge and telemetry tile compared values but not a swapped `SmoothedSignal` object's identity, so a fresh signal with the same current value kept showing the old paint.
- `GlowSprite.draw` was misused by halving `size` (core plus the margin on *both* sides) as if it were the core's own half-size, overshooting a centred halo by one margin per axis -- shipped once already in the shift horizon's breathing glow before the eco bar's own capture caught it in a second component. Fixed once, at the source, with `GlowSprite.drawCentered`.
- The telemetry tile's bracket colour was computed once in `build()` from a live value, not read fresh in `paint()`, so a value crossing a threshold between rebuilds left a stale colour on screen.
- The road view's hero speed numeral centred `RollingNumerals`' full fixed-width digit reservation, not the commonly-2-digit content sitting in its right two thirds, reading well right of centre; its speed streaks landed mostly off-screen because their lateral offset scaled additively against a road edge that was already most of the frame's width near the bottom.
- The Money Tape's stack-settle spring was retargeted to a bare block count while the painter treated its value as total pixel length -- tens of pixels off. Separately, normal Money Tape blocks used `money.core` (the digits' own tone) instead of `money.deep`, which DESIGN.md 6.8 asks for and which `TapePalette` had no getter for at all; both champagne tones read the same at a glance, and only a pixel-level fill-colour test caught it.

**Known, deliberate gaps, not oversights:**
- The road view's money-readout overlay (DESIGN.md 6.11's driver-side flank) is a reserved, currently-empty slot: the money engine that would feed it live is phase 4 (CLAUDE.md 13).
- The Money Tape does not yet compact groups of blocks into ₹5 and then ₹10 blocks with a merge animation and a scale label (DESIGN.md 6.8). It just keeps growing. This needs its own focused pass.

Numbers: **2,154 tests** (2,014 at the end of phase 3a), a few seconds for the whole suite excluding goldens (none exist yet; see phase 3a's own note). 22 build-video frames captured against real renders as each component landed, in `docs/build-video/`, per commit in `FRAMES.md`.

## Phase 3b: the first real screen

The Apex cluster (DESIGN.md 7.3.1, Drive's default) now exists and renders against a **real `DemoDrive`** -- the actual OBD stack (`Elm327Simulator`, `ObdSession`, `VehicleState`) from phases 1-2, not synthetic capture-only signals. This is the first place any of phase 3b's components have been driven by real (simulated) vehicle data rather than a hand-fed `SmoothedSignal` in a test.

| Piece | Where | Tests |
|---|---|---|
| `DriveSignals`: `SmoothedSignal`s bound once to a `VehicleState` (`SmoothedSignal.bind`, already built in phase 2/3a) and shared across whatever cluster is on screen | `lib/ui/pages/drive/drive_signals.dart` | 10 |
| `ApexCluster`: hero speed + tach arc, the coolant gauge, the shift horizon and status strip | `lib/ui/pages/drive/apex_cluster.dart` | 3, plus a capture test against a real `DemoDrive` |
| `WallClockTicker`: the status strip's clock, ticking on the injected `Clock`/`Scheduler`, not `DateTime.now()`/`Timer` | `lib/ui/design/motion/wall_clock.dart` | covered via `DriveSignals`' and `ApexCluster`'s own tests |
| `CenteredNumeral`: centres `RollingNumerals`' typically-lit digits, not its full (jitter-free, right-anchored) digit reservation -- DESIGN.md 9.3's reservation is correct for a corner tile and wrong for a hero readout | `lib/ui/design/components/centered_numeral.dart` | 4 |

**What `ApexCluster` honestly omits:** the driver-side flank's ₹ THIS TRIP and ₹/KM, the coolant flank's instant km/L, and the floor's eco bar and trip distance/time (DESIGN.md 7.3.1). All need `fuel/`, `money/` or `trips/`, none of which exist before phase 4; CLAUDE.md 1's honest numbers means these slots are simply absent, not faked. `DriveSignals` also exposes `gpsHasFix` and `phoneHot` as permanent, documented `false` (no native GPS or phone-temperature pipeline yet), and `lateralAcceleration` as a `SmoothedSignal` that is never ingested into (no accelerometer pipeline yet; `RoadView` already renders a valueless signal as 0/no-roll, so this is a real, working degradation, not a crash risk) -- `longitudinalAcceleration` **is** wired for real, from `VehicleState.motion`.

**`CenteredNumeral` is worth understanding before touching any other cluster's hero readout,** since Tape, Minimal and the Money page will all want the same treatment: it was built because the exact same off-centre bug hit twice (the road view's hero speed, then the Apex cluster's), and its own doc comment records two more real bugs found getting it right (an `OverflowBox` fed an unconstrained ambient height crashed outright; the first fix's width estimate undershot the real glyph atlas's digit advance by a full digit at size 100). Both are fixed at the source now, not worked around per call site.

Numbers as of this section: **2,171 tests** (2,154 at the end of "every component" above), tree clean, `dd282e9` at HEAD, nothing pushed, no tags.

## Phase 3b: the Road cluster

The Road cluster (DESIGN.md 7.3.5) is the second real screen, and stays a near-pure composition on purpose: the road view (DESIGN.md 6.11, complete since "every component" above) already draws its own overlays -- the hero speed top-centre and the RPM bar along its horizon -- and DESIGN.md 6.11's overlay list is the whole of this cluster's chrome (no status strip or flanks are named for Road, unlike Apex), so none are added. It runs on the same real `DemoDrive` + `DriveSignals` wiring as Apex.

| Piece | Where | Tests |
|---|---|---|
| `RoadCluster`: `RoadView` full-bleed on the shared `DriveSignals`, max RPM pinned to `TapeTach.defaultMaxRpm` (the tach arc's and shift horizon's own default; a per-profile range comes with phase 4's vehicle setup) | `lib/ui/pages/drive/road_cluster.dart` | 4, plus a capture test against real drives |

**What it honestly omits:** the money readout on the driver-side flank (DESIGN.md 6.11) -- `money/` is phase 4, and `RoadView` already reserves the slot and takes a `moneySlot` widget, so phase 4 only has to pass one in. The car also does not roll yet: the accelerometer pipeline does not exist, `DriveSignals.lateralAcceleration` is never ingested into, and `RoadView` renders a valueless signal as 0/no-roll (the same working degradation as before).

Two tests worth their cost, both measured through real pixels (`test/widget/pages/road_cluster_test.dart`):

- The horizon RPM bar's fill maps the cluster's rpm through the tach default max (2100/7000, ~30% of the frame) -- a cluster-level choice its own test can now pin, since `RoadView`'s own suite passes a different max.
- Night mode's headlight cone (DESIGN.md 6.11) is measurably present through the cluster's wiring: a plain-road patch below the car's base lifts against the identical daylight frame. It is subtle enough that eyeballing the night capture alone could not settle it; the pixel test did, and that is why the test exists.

The first widget-test run found a real bug -- in the test, not the component. The pixel fingerprint was written as a `Color` literal (`0xFF5CE1FF`) instead of the byte order `toByteData` reads back on this platform (`0xRRGGBBAA`, so `0x5CE1FFFF`), and the bar read as absent from the whole frame. A probe of the actual packed values settled which side was wrong (the captures plainly showed the bar). The constant now follows the convention the Apex test established (`0x1296FFFF` for accent.deep there is the same packing), with the byte order written down in the test's own comment so the next pixel test does not repeat the detour.

Numbers as of this section: **2,175 tests** (2,171 before), `1714f59` at HEAD for the feature, nothing pushed, no tags.

## Phase 3b: the Tape cluster

The Tape cluster (DESIGN.md 7.3.2, the brand layout) is the third real screen, on the same real `DemoDrive` + `DriveSignals` wiring as Apex and Road. The speed tape sits on the left and the RPM tape on the right, both with their trend vectors (the tapes carry those themselves, DESIGN.md 6.3), filling the centre zone between the shared horizon and floor zones (DESIGN.md 4.7's 0.10H/0.16H); each readout box straddles its tape's inner edge facing the centre. The shared horizon gets exactly the content Apex gives it, since the horizon is shared chrome rather than per-cluster layout -- a reading, noted in the class's doc comment for the design review to confirm.

| Piece | Where | Tests |
|---|---|---|
| `TapeCluster`: the two tapes on the centre zone's flanks, the shared horizon, the RPM tape banded at the redline | `lib/ui/pages/drive/tape_cluster.dart` | 4, plus a capture test against real drives |

**What it honestly omits:** the centre's instant km/L and eco bar, and the floor's ₹ THIS TRIP (DESIGN.md 7.3.2) -- `fuel/`, `money/` and `trips/` are phase 4, so the centre is simply empty and the floor simply absent. The speed tape's tinted band waits the same way: DESIGN.md 6.3 tints from "the user's speed threshold", which arrives with the coach's thresholds (phase 5); the RPM tape's band is real now, at the same redline the tach arc uses.

The capture pass (highway, city, aggressive_city) found no component bug this time. It did force two readings worth keeping: the trend vector's edge choice for a left-readout tape is coherent, not wrong (the line hugs the box's scale-side edge on both tapes, symmetric under mirroring -- eyeballing the highway shot suggested otherwise at first), and the corner clock glyph both it and the committed Apex frame show is shared accepted behaviour, not a cluster regression. Two setup mistakes were caught before they could look like component bugs: `NumeralFormat` used without its import (the compiler reported the misleading "not a constant expression" at the const constructor rather than "isn't defined"), and one unused import caught by the gate's analyze.

Numbers as of this section: **2,179 tests** (2,175 before), `6af6856` at HEAD for the feature, nothing pushed, no tags.

## Phase 3b: the Minimal and Telemetry clusters

The last two Drive clusters, on the same real `DemoDrive` + `DriveSignals` wiring as the first three.

| Piece | Where | Tests |
|---|---|---|
| `MinimalCluster` (DESIGN.md 7.3.3): the hero speed through `CenteredNumeral` and a thin RPM line under its digits | `lib/ui/pages/drive/minimal_cluster.dart` | 5, plus a capture test against real drives |
| `RpmLinePainter`: the line, centred and symmetric, length clamped at the tach default max; `shareFor` exposed for a direct test | same file | covered by the cluster's suite |
| `TelemetryCluster` (DESIGN.md 7.3.4): a 2x3 grid of tiles, the shift horizon and status strip on top | `lib/ui/pages/drive/telemetry_cluster.dart` | 4, plus a capture test against real drives |
| `DriveSignals.load` and `.voltage`: real sensors (`VehicleState.load`/`.voltage`, the poller's tiers since phase 2), bound like the signals before them | `lib/ui/pages/drive/drive_signals.dart` | covered by the Telemetry cluster's binding test |

**What they honestly omit:** Minimal's driver-side corner money readout (phase 4). The Telemetry grid chooses the six candidates with a real source; MAP or MAF, intake air and instant km/L stay out (km/L needs `fuel/`, phase 4), and no tile thresholds are passed (the tinted brackets would need per-vehicle limits with no real source yet).

**Design decisions these two record** (DESIGN.md silent): the RPM line is centred and symmetric under the digits, its full extent 0.25W; no unit label under Minimal's hero ("hero speed only", read literally). The Telemetry grid's cell size is the frame's geometry divided out, so it fills the centre zone at all three design aspect ratios.

The measured pixel tests earned their cost twice in the Minimal cluster: an eyeball of its capture read the hero as ~33 lp right of centre -- a false alarm a measurement probe settled (ink centred within a device pixel for 81, 88, 11 and 100 alike; a narrow digit's side bearing is what reads as offset) -- and the same probe found where the RPM line actually lands (the hero numeral's own box is much taller than its ink, the property the Apex label placement already rides on, so the line sits below where the ink suggests). The lesson: **measure, then believe; never fix from an eyeball.** The pixel-packing convention the Road cluster's test writes down (`toByteData` reads back `0xRRGGBBAA` on this platform) is now used by both new suites.

The Telemetry capture shows numerals caught mid-roll (the odometer detent transition) and the coolant numeral in its phosphor brightening phase after a 1 Hz slow-tier update -- both the numerals' own designed behaviour, covered by their component tests, not layout bugs.

Numbers as of this section: **2,188 tests** (2,179 before), `49915fa` at HEAD for the feature, nothing pushed, no tags.

## Phase 3b, still to do

**Immediate next step:** the HUD (DESIGN.md 8), then Demo Mode wired into the app shell, onboarding and the brand. See `handoff.md` at the repo root for exact next steps and session context.

## Phase 4: trips, fuel and money (2026-09-30)

**Built and tested** (all on the simulator; nothing here has met a real car):

- `fuel/`: the estimator (5E, MAF or speed-density, best fresh source; hand-computed formulas), fuel-cut handling, a gap-safe integrator, per-vehicle constants.
- `money/`: the trip computer (distance, fuel, cost, idle, instant and average km/L, fuel left; the four spend buckets summing exactly to the total; the rupee block stream), calibration, the fill-up ledger, the price and currency, the Pit Stop form's rules.
- `coach/`: thresholds and the hard-acceleration and hard-braking detector (the rest of the coach is phase 5).
- `trips/`: the trip model and repositories (in memory and SQLite), the recorder (start on rpm > 400, end after 10 s off, resume within 5 minutes, one sample a second), the fuel PID moved to the fast tier while recording.
- `platform/`: the phone's GPS through a `LocationManager` channel (`GpsChannel.kt`, `native_location_source.dart`) and the settings store on `shared_preferences`.
- UI: money on Apex, Tape and Minimal; the Money page (Motion and Parked); Pit Stop with its numpad and 900 ms save animation; the HUD's money layouts; the demo's own price and fill-ups.

**Layer 3 results (`test/e2e/trips_test.dart`, 46 tests):** every petrol profile is within 2% on distance and within about 2% on fuel over city, highway, aggressive, eco and jam drives (criteria: 5%, and 10% for speed-density), idle time within 5% and idle cost within 7%, calibration through simulated fill-ups corrects a deliberately wrong displacement, aggressive-city hard events match the scripted ones within one, eco_city costs at least 15% less than aggressive_city, the Money Tape adds up to the total and matches the buckets, the trip rules (start, end, resume at 3 minutes, a new trip at 8, never ended by a jam or a flaky adapter), an old car with no fuel PID has no money.

**Real problems found and fixed** (details in DECISIONS.md): PID 11 reads ~12% closed, so "throttle at 0" never matched and a coast counted as burning fuel (+5.7% on the sporty manual); a flat 0.85 VE over-counted idle fuel by about a fifth (the rpm-shaped VE is a generic shape and both it and the simulator's curve are "typical road engine": agreement proves the machinery, not accuracy on a real car); giving a rupee block to the bucket that crossed the line favoured one bucket.

**Not done / not verified:**
- The shared ₹ flight (Drive to Money) is not built; the speed flight from phase 3b is.
- GPS is not wired into a drive yet (the demo has no GPS; a real drive gets it in phase 6), so the GPS glyph still says no fix and the GPS fallback and cross-check for distance is tested only by the unit path, not on a device.
- `GpsChannel.kt` compiles (debug APK builds) and its Dart side is mock-tested; **it has never run on a phone.** Likewise the SQLite adapters ran only on the desktop FFI SQLite, not on an Android phone.
- The Debrief that should begin when a trip ends is phase 5; the recorder already tells the app when a trip ends and resumes.
- No design review package for this phase (waived, see CLAUDE.md 13). I did look at renders of the new screens and fixed what was wrong; they were not judged in motion, on a device, or in any livery but ION.
- The Money Tape does not yet compact into ₹5 and ₹10 blocks when full (a known gap in the component since 3b).

## Phase 5: coach, review, Garage and Diagnostics (2026-09-30)

**Built and tested** (all on the simulator; nothing here has met a real car or phone):

- `coach/`: the tip rules (rupee-ranked, at most two a trip, only when parked or after the trip), the sweet spot (10 km/h bands, at least 3 km a band, the best band and its neighbours within 3%), weekly and monthly statistics, `SampleEvents` (hard events and long idles found again in a trip's samples, for the scrubber).
- `trips/`: `TripLibrary` (the log for the screens, demo trips held but never counted), `RouteGeometry` (projection, at most 1,000 points).
- **Review** with the route trail (SPEED, THROTTLE, ₹/KM), the receipt, where-it-went, one tip, and the telemetry scrubber; **the Debrief** plays when a trip ends (4.5 s, a tap skips it); **Coach** (efficiency curve with its sweet spot, this week against last, the eight-week trend, up to three tips); **History** (trips with a mini route and barcode, Week/Month/All).
- **Garage**: car (fuel, engine size, tank, how far the fuel figures are checked), fuel price, layout, livery, driver side, the HUD (colour, flips, height, size, alignment pattern), the coach (Gentle/Normal/Sporty, speed threshold), display (reduce motion, fidelity Auto/Lite/Balanced/Full, ignition sequence), the demo (drive, car, end this trip now) and data (delete all, by slide to confirm). Every setting takes effect at once and is saved (`AppSettings`); the theme, the reel, the coach thresholds and the HUD follow it.
- **Diagnostics**: the adapter (banner, protocol in words, voltage, poll rate with a one-minute sparkline, fuel source), the PID matrix (01 to 60, lit where the car answers, tap a cell to name it), fault codes with plain-English descriptions and a stored/pending chip, READ, and CLEAR CODES by slide to confirm (parked only; the car refusing is told to the user).
- `SlideToConfirm`, a new control; `assets/dtc/dtc.json` (283 codes, written from scratch, `assets/dtc/SOURCE.md`); the dock's Garage and Diagnostics buttons are live.

**Tests:** 2,688 (`./tool/verify.sh`), including widget tests for every new screen at 640, 720 and 800 wide, the Debrief playing, skipping and being asked for before its page exists, "tips never appear while the car moves", the Garage's every control, the Diagnostics source against a whole simulated stack (`dtc_present`), and the Garage/Diagnostics flow through the real app.

**Real bugs the tests and captures found** (all fixed, each with a test that fails on the old code):
- **The Strip and the Drive reel mounted the wrong pages.** They mounted only the page at the *floored* position, so a page swiped towards on the right stayed blank until the swipe landed, and a page the snap spring overshot (Review, at the strip's end) was torn down and rebuilt, throwing away its state: the Debrief died 0.4 s in. Both now mount the page below and the page above the position.
- **The demo GPS never produced a fix.** `DemoLocationSource._release()` was async, so it ran after the replacement receiver had been created and stopped that one. Demo trips had no route.
- **A scenario cut off by its time ended while moving,** so the demo trip never ended and Review never opened. `SimulatedCar.stopWhenFinished` (off by default, so test ground truth is untouched) brakes it to a stop; the demo uses it.
- **A Garage list opened scrolled.** A picker reused the main list's scroll state, so it opened part-way down. It now starts at its top, and Back returns the page to where it was.
- The Review and Coach pages sat under the parked dock; the compact bucket breakdown's numerals overlapped its swatches; roll-up numerals rested part-way through a roll (DESIGN.md 5.6: parked numbers are set normally); the Debrief's slice shares and roll-up sources were made on every build and never released.

**Not done / not verified:**
- **Not on a phone.** Everything above ran in `flutter test` and in the desktop render used for captures. The design review package is waived for phases 4 to 6 (CLAUDE.md 13); I looked at renders of Review, the Debrief, Coach and History and fixed what was wrong, in ION only and not in motion on a device.
- **Garage items in DESIGN.md 7.8 that are not there:** the adapter (phase 6 adds it), currency and units (the money screens write ₹ directly, so a currency choice would need plumbing through all of them), max RPM/redline and the shift light, automatic brightness and Daylight/Night automation, CSV export to a chosen file (needs a native file picker), the licences screen and its QR code, and the livery picker's live previews (it is a plain list). The ignition sequence choice is read when the drive screen is built, so it applies from the next start.
- **Diagnostics:** the PID matrix does not pulse on each response, and the voltage is the module voltage the poller reads (not `ATRV`).
- The Money Tape still does not compact into ₹5 and ₹10 blocks when full; the ₹ shared-element flight from Drive to Money is still not built.
- `assets/dtc/dtc.json` covers common generic codes only; manufacturer codes are described by their system, never guessed.

## Phase 6: real transports and the connect path (2026-09-30)

**Built and tested** (the transports against mocks and a simulated adapter; nothing against hardware):

- **WiFi transport** (`lib/obd/transport/wifi_transport.dart`, the only socket code in the app) behind `NetworkGuard`: literal private, loopback and link-local addresses only, no host names, checked before any socket exists. Tested over real loopback sockets and, in real time, against `tool/sim_server.dart` through the whole OBD stack, including unplugging the adapter and plugging it back in.
- **Bluetooth Classic and BLE** through thin Kotlin channels (`BtClassicChannel.kt`, `BleChannel.kt`, `BluetoothPermissions.kt`) and one Dart side (`AdapterRadio`, `NativeLinkTransport`, both mock-channel tested). Classic: paired devices, discovery, pairing, an SPP socket tried three ways (secure, insecure, RFCOMM channel 1). BLE: scanning, GATT, finding the serial characteristics (FFE0/FFE1, FFF0/FFF1+FFF2, 18F0, OBDLink CX, then any serial-looking service), MTU, chunked serialised writes. **BLE is a thin channel and not a package, so there is no dependency and no licence to verify** (CLAUDE.md 5). **Compiles (debug APK); has never run on a phone.**
- **The connect flow** (DESIGN.md 7.11): adapter type, find and pair (permission, radio off, unsupported, PIN hint) or a WiFi address on a numpad with a Test, the car, the price (skippable), the layout; a thin progress tape; line-art scenes. Wired to CONNECT MY CAR and to Garage.
- **`LiveDrive`**: the same OBD stack as the demo over the chosen adapter, with auto-reconnect and backoff (`ObdSession`), the protocol remembered per adapter, compatibility mode, and **session recording** (raw traffic to `recordings/` in the app's external files folder, every 20 s and at the end). `DriveFeed` is what the drive screens read, demo or real; a real drive uses the real money and the phone's GPS, and the demo keeps its own money and its own simulated GPS.
- **Garage's Adapter group**: the adapter, drive from it or the demo, compatibility mode, recording, forget.
- **The display, wired to the phone** (this had never been wired; the design system had built the pieces): the ambient light drives Daylight and Night, the window brightness follows the mode, the battery temperature drives the phone-hot glyph, a dimmer screen and Lite at 30 fps above 50 C, the cold open's benchmark sets the starting tier, and Garage can hold a brightness mode or a tier.
- **The debug overlay** (CLAUDE.md 9): a long-press on a driving screen shows frames a second, the poll rate, the fuel source, the tier, the mode and lux, the battery temperature, and a way into the Design Lab.
- `docs/HARDWARE_HANDOFF.md`: how to build and install, a check at your desk against the simulator over USB, the in-car script (WiFi, Bluetooth Classic, then BLE), session recording, the design check, and what to report.

**Layer 5, on the `Reference_API24` emulator (Android 7.0, arm64, software GL; not a phone):** `integration_test/adapters_test.dart` (the Bluetooth and BLE channels answer, and refuse in words on a phone with no radio; the recordings folder is writable; the WiFi transport talks to `tool/sim_server.dart` over a real Android socket at `10.0.2.2`, with the `INTERNET` permission; a public address is refused), `connect_wifi_flow_test.dart` (**the whole connect path from first launch: cold open, CONNECT MY CAR, WiFi, Test, the car, the price, the layout, and live values on the drive screen, through the real transport, `shared_preferences` and SQLite on Android**), `app_launch_test.dart`, `device_channel_test.dart` and `demo_drive_perf_test.dart` all pass. Frame timings for the demo drive, a debug build on software GL (so about what phase 3b measured, and no evidence about a real phone): cold open p90 16.2 ms, Apex 15.1, Tape 12.0, Minimal 11.1, Telemetry 15.2, Road 13.6, HUD 17.3; the p99 of Apex (107 ms) and the cold open (104 ms) is the first frame of each screen (atlases and sprites are built on first use), and the HUD's p99 is 52 ms. The cold open chose LITE on this emulator. **Not run: any real phone, any real Bluetooth adapter, GPS, the light sensor.** To run the two that need the simulator: start `dart run tool/sim_server.dart --port 35000` on the host first.

**Real problems found and fixed** while building it: the `INTERNET` permission was missing from the manifest (a socket would have failed on a phone); the UI layer was importing transports (the architecture test caught it; the connect flow now asks an `AdapterChecker`); the display's pieces were never connected to the phone; and the dev button for the Design Lab sat on top of the connect flow's NEXT and START DRIVING buttons in a debug build (the emulator run found it), so it now shows only on the first screens and the debug overlay opens the Lab from the drive.

**Not done / not verified:**
- **Everything native and radio-related is unverified on hardware:** all three Kotlin files, Android's Bluetooth permission flow on Android 12+ and before it, pairing, discovery (before Android 12 it also needs the phone's location services on), the BLE characteristic guesses, the light sensor, the battery temperature, the brightness calls, and the real frame timings. The WiFi transport has run only against the simulator.
- **The connect flow's last step lists the layouts by name;** DESIGN.md asks for live previews.
- Not yet in Garage: currency and units, shift-light settings, CSV export, the licences screen and its QR code (see phase 5).
- The design review package is waived for phases 4 to 6; I looked at renders of the connect flow at 720 wide in ION only.

## First real drive (2026-09-30)

**What ran:** a release build on the human's own phone (a 120 Hz flagship, not the old device the app is for) and a BLE ELM327 that calls itself `OBDBLE`, in a real car, for one drive of about 10 minutes with a stop at a signal (engine on). What is known comes from two screenshots (Review and the Apex cluster with the debug overlay) and the human's account. **No recording was taken or read, no logs, no fill-up, no comparison with a trip meter.** The rest of the handoff script (WiFi, Bluetooth Classic, ignition off and on, unplugging, the HUD, night, heat) has not been done.

**Verified on hardware, by the screenshots:**
- BLE connects on a real adapter and reaches `LINK connected`; the serial-service lookup worked for this adapter.
- The fuel source came out as **MAF**; the money screens ran (Drive: 8.9 km/L, ₹21.3/km; Review: ≈₹28, 1.3 km, 8 min, 5.2 km/L).
- The light sensor (391 lux), the battery temperature (34.7 C) and the frame timing (121 fps, p90 3.4 ms, tier FULL, "detected") reach the overlay.
- The page dots lock while the car moves.

**Found:**
- **Poll rate 1.3 cycles a second** (CLAUDE.md wants at least 3 for the fast tier; the simulated Bluetooth clone gives 9). The human's decision is to accept it as what a cheap adapter gives and to smooth it in software. **(Superseded: see "The second drives". The tracking filter described here made the tach a pendulum and was removed; the stale limit that follows the signal's rhythm stays.)** A tracking filter between the samples and the spring (DESIGN.md 5.2, DECISIONS.md), and a stale limit that follows the signal's rhythm. In the simulator's model of a slow adapter the tach's error falls from 740 to 540 rpm and the speedometer's from 4.8 to 3.1 km/h. Compatibility mode has not been tried on this adapter, and neither has the poller's batching been checked (`Poller.isBatching` is not on the overlay).
- **One drive became two trips.** The human never turned the engine off, only stopped at a signal, and saw Review (8 min, ₹28) and, a minute later, a fresh trip on Drive (1:49, ₹8, 0.4 km). A trip ends when the engine has looked off for 10 s, and "the ECU stopped answering" counts; the poller called the ECU silent after three misses in a row, which is 2 s at this adapter's rate. **The poller now needs three misses *and* four seconds without an answer** (`PollConfig.silentFor`, with tests). **This is a hypothesis: nothing shows why the trip ended,** and a trip that ends and resumes would not have reset the figures on Drive as they were seen to reset. The next drive should have **Record what the adapter says** on, so that the log can say.
- **The "where it went" figures did not add up on screen.** Normal 25 plus idling 4 is 29 against a headline of ≈₹28: each was rounded alone. **Fixed:** the parts are apportioned (largest remainder) to whole numbers that add up, on Review and Money, with tests on the real signals.
- **The idling cost looked high:** ₹4 for "1 min" at ₹115 a litre (**confirmed: the price entered**) is 1.4 to 4 L/h, against 0.6 to 1 L/h for a warm engine. **Looked into, not shown to be wrong:** it was the first trip of the morning (a cold engine idles fast and rich), the attribution code holds up, and the pipeline is inside 7% of the simulator's idle fuel even behind a 1.3 Hz adapter. **One real bias was found and fixed on the way:** idle *time* came out 6.8% short behind such an adapter (each stop lost up to a sample interval at both ends); mixed intervals now count half. Whether MAF reads high at idle on this car is for the next recording (the `vitals` lines).
- **The dock's left edge was clipped on Review** (GARAGE's border cut by the screen edge). **Fixed:** the dock keeps the pages' left margin.
- Review showed no coach tip and no scrubber handle on this trip; that may be right for a short trip, and is unchecked.

**E20 (asked after the drive): the fuel figure needed correcting.** Bangalore sells E20, and the MAF method assumed plain petrol: on E20 the same air is about 7.5% more litres, so every fuel and money figure would have read about 7% low until two fill-ups calibrated it. The vehicle setup now has a petrol blend (E0, E10, E20; a new install starts with E20; Garage and the connect flow have the choice), and the simulator's ground truth burns the blend it is given, so the correction is tested end to end. **Nothing in it has been checked against a real fill-up:** whether the numbers come out right is for the first full-tank comparison in Pit Stop, and PID 5E (not this car's source) is left as the ECU gives it. See DECISIONS.md.

**For the second drive:** the build is a debug one, and **it records the drive by itself** (Garage -> Adapter -> Record what the adapter says shows it on). The log now carries the app's own notes (`@` lines: setup, connection status, engine on and off, mode, trip phase, and a `vitals` line every 5 s with speed, rpm, volts, MAF, the fuel source, L/h, distance, litres, idle seconds and idle litres), so a trip that ends when it should not, or a figure that looks wrong, can be read straight from the file.

**What this changes in "what has not been verified":** BLE is now verified to connect on one adapter; everything else on the list stands, and the tracker's tuning (`TapeTracking`) is a guess until a real recording can be replayed through it.

## The second drives (2026-09-30)

**What ran:** two long drives on the debug build (72 and 62 minutes, 15.8 and 14.5 km), the same `OBDBLE` adapter, recording on. **The recordings are read, and are in `recordings/real/`** (`session-20260930-071002-ble.log`, `session-20260930-092503-ble.log`; the third file, `...082257-ble.log`, is a connection that never came: `disconnected (unreachable)` after 15 s). Nothing was on the old phone or checked against a trip meter or a pump.

**Found:**
- **The tach was a pendulum, and I caused it.** The tracking filter (a Kalman filter running ahead of the samples) overshot at every gear change and swung back; on the real series it is worse than the spring it replaced (354 against 159 rpm RMS error, reversing 57 times a minute against the data's 25). My simulator test had approved it against a sine-wave truth, which proves nothing about a real car. **Fixed:** a playout buffer (DESIGN.md 5.2): the display shows the straight line between the two samples either side of a moment about half a second in the past. It cannot overshoot, and the needle stands still 16% of the time the revs move instead of 57%; the jerk halves; the price is the delay, about half a second at this adapter. Guarded by a fixture of the busiest 300 s of the first drive (`test/design/real_drive_smoothing_test.dart`). **Not yet seen on the phone**; if it still feels jerky, the next step is a softer spring or a longer delay (numbers in `TapePlayout`).
- **The poll rate is 1.3 a second because batching fails, and that is fixable.** Two ECUs answer every request; one has no MAF. A batch of five PIDs comes back as two interleaved multi-frame replies the parser cannot sort, so the poller falls back to single requests (140 ms each) for 60 s at a time. Batches small enough for one CAN frame (two or three PIDs) should work, but the ELM's one-response digit can return after the ECU without the PID answers, so each PID's ECUs must be learnt from the `0100` bitmaps first. Estimated gain: RPM from 1.3 to about 2.2 a second. **Not done** (it changes what the app asks of a real car); a decision for the human, and the next recording would check it.
- **The idle cost is real:** 1.27 and 1.31 L/h over the two drives, consistent with the MAF the car reports (2.4 to 3.3 g/s at 750 to 790 rpm). The first drive's ₹4 for a minute was a cold engine.
- **Idle time was 6.8% short behind a slow adapter, and E20 was not in the fuel figure;** both fixed the day before; the recordings' `vitals` lines carry `src=MAF`, `lph` and `idle_l` for the check.
- **The log's own notes worked** (setup, status, engine, mode, trip and `vitals` every 5 s), and they show the trip rules doing their job. **Drive 1** is one trip for 72 minutes, no ECU silence at all. **Drive 2** has one genuine ignition-off: at 2652 s the MAF reads 0.00 and every request after it gets `NO DATA`; the app called the ECU silent 4 s later (`silentFor`), ended the trip 10 s after that, and when the engine restarted at 2850 s (rpm 1472), 3 minutes on and inside the 5-minute window, the same trip resumed; it ended for good at 3266 s when the engine was switched off. (The `engine off (rpm 798, volts 13.7)` note prints the last readings, which are the running ones, since the ECU stops answering the moment the engine stops.) So **the hypothesis of the first drive, an ECU going silent with the engine running and splitting the trip, is not seen in either recording**; the first drive's split (a release build, no log) is still unexplained, and the four-second guard stays.

**Added:** the trip's average km/L in the floor of the Apex cluster, right after the trip km (a dash until there is some distance; absent for a car with no fuel figure). The other clusters show no trip distance and were not changed.

**Still open:** the dock and idle-cost questions are closed (see "First real drive"); the poll-rate fix above; the tach's feel on the phone; whether MAF over-reads at idle (a fill-up comparison is the check).

## After the second drives: the End trip button, the channels, and the map (2026-09-30)

Four requests from the human, all built and tested headlessly; **none seen on a phone yet.** (Confirmed: the ignition-off in drive 2 was deliberate, so the trip rules did what they should.)

- **End trip in the parked dock.** A stop with the engine running brought the dock up and offered no way to end the trip; it ended only ten seconds after the engine went off. The dock has an END TRIP button (a flag) while a trip is being recorded; it ends the trip and opens the Debrief. A trip ended by hand with the engine running **stays ended while the car stands** and the next one begins when it moves off (or after the engine has been off and on), so it does not restart itself a few seconds later. Five buttons are 783 lp of the compact ones and a 640 lp screen has 624, so **below 900 lp the dock uses a dense button** (12 lp label) and scales to fit inside both margins (about 52 lp tall at 640). My first dock test used narrow fallback fonts and did not see the overflow that the shell test did; the shell test is the one that counts.
- **Telemetry recorded whether or not it is on screen.** The tiles kept their sparkline in their own widget state, so it began when the cluster was opened. `DriveSignals` now keeps a minute of rpm, speed, throttle, load, coolant and volts (`SignalHistory`, sampled at 2 Hz on the scheduler from the start) and the tiles read it. **It is in memory: a minute, gone with the app.** The trip itself records the load, the coolant and the voltage with every second's sample now (database version 3; older trips and cars that do not report one have null).
- **Review shows them the way it shows throttle.** The selector offers RPM, LOAD, COOLANT and VOLTS beside SPEED, THROTTLE and ₹/KM (for a trip that has them): the route is coloured by the channel, the scrubber's lower trace follows it, and the cursor says its value. Coolant and volts are scaled over the range the trip covered, since a coolant that sat at 90 would look the same as one at 0. Seven choices do not fit 640 lp in equal cells, so the selector scrolls (`TapeScrollSegmented`, a chevron at an edge with more).
- **The route map is interactive.** Pinch to zoom (1 to 24 times), drag to pan, double-tap to zoom in or back out, zoom in / out / fit buttons, and a tap on the route puts the scrubber cursor on the nearest point (and the scrubber moves the view to the cursor). The line and marks keep their size at any zoom. **Limits, said plainly:** there is still no base map, only the route; the route is thinned to about 1,000 points for the whole trip (CLAUDE.md 9), so on a long trip a deep zoom shows straight runs between points 15 m or more apart, not the road; and the gestures were driven by widget tests, never by a finger.
- **A bug found on the way:** the Review heading's readout overflowed by 20 px at 720 lp with a cursor set (four readings beside the date); it now scales to fit.

**To look at on the phone:** the dock at its narrowest (is 52 lp of button comfortable?), the scrolling selector, pinch and drag on the map (does it feel like a map?), and whether a minute of history is what the Telemetry tiles should keep.

## After the map: a trip to replay, and an engine to hear (2026-09-30)

Two requests from the human: *an interactive playback of the drive, at 1x 2x 3x, like a game*, and *an engine sound that follows the tach, through the car's Bluetooth stereo*. The map basemap (OpenStreetMap) was assessed and **left out on purpose** (see "What is not built"). Everything below is built and tested headlessly; **none of it has been seen or heard on a phone.**

**The replay (Review, DESIGN.md 6.12).**
- A play button, a speed button (1x, 2x, 3x) and a stop button sit left of the scrubber (48 lp each). Play starts from the scrubber's cursor, or the start. The play head runs on the motion clock.
- The route becomes a game map: a chase camera follows an arrow for the car, the map turning with it (heading up, the default, or north up), zooming out as the car speeds up and in as it slows; a dark road under the line, and a faint ground grid that carries with the map (there is no basemap, and this is what shows the ground going by). The route behind the car is bright and the route ahead is dim. A pinch or the zoom buttons sit closer or further, a drag lets go of the car, FOLLOW (a crosshair) takes it back. The tip gives its room to the map.
- The receipt gives way to instruments: the speed large, rev and throttle bars, the ₹ so far, the distance, the time, and the marked moment as it passes ("Hard braking" and so on). Numerals rest on whole digits. **The replay ends on the receipt's own totals** (the integrals are scaled to the trip's distance and litres).
- The car stands still while the car stood (placed by the trip's odometer between route points, never by time), and a stretch where the engine was off is crossed in half a second.
- Scrubbing the band or tapping the route moves the play head. Five new icons (play, pause, stop, north, heading).
- **New code:** `TripPlayback` (pure: values between samples, totals, the odometer), `TripPlayer` (the transport on the motion clock), `RouteViewController`'s chase camera and rotation, `RouteCar`, `RouteTrail`'s car, road and grid, `TripTransport`, `ReplayHud`, `PlaybackChannel`, `ReplayEvents`, `TapeSquareButton`. About 200 new tests, and capture frames that were looked at (720 and 640 wide).

**The engine sound (DESIGN.md 5.10).**
- **Seven engines made in code** (Inline-4, Three-cylinder, V6, V8, Flat-six, Turbo four, Electric): firing-order pulses placed between samples through an exhaust pipe (a feedback comb) and body resonances, with a throttle-opened muffler, intake rush, valve tick, a turbo's whistle and hiss, pops on an overrun, and an electric whine. No audio asset, so nothing to license and nothing added to the APK. It is deterministic and renders 10 s of audio in milliseconds.
- **The revs glide** (at most 9000 up and 6000 down a second) so that a late reading is never a click; it fades out when the data goes stale or the engine goes off.
- **It runs in its own isolate** and plays through a thin Kotlin `AudioTrack` channel (`EngineAudioChannel.kt`): car audio only by default (it does not start without Bluetooth, a wire or USB, and stops when the output changes to the speaker), no audio focus (music carries on), and it stops when the app leaves the screen (no service, no new permission).
- **Garage** has an Engine sound group: on or off (off to begin with), the engine, the volume, "Also on the phone speaker" (off to begin with), a ten second test, and a status line. A Review replay has the engine too, from the recorded revs a moment ahead of the picture. The session recording notes say when it starts, stops, loses its output or runs dry.
- **To hear it without the car:** `dart run tool/render_engine.dart --out build/engine` writes every engine, for three scenes (idle, a sweep, a drive), as WAV files. Spectrograms of them were looked at (the harmonic fan rising with the revs, the turbo's whistle as its own line).
- **New code:** `lib/sound/` (profiles, `EngineSynth`, `SynthVoiceHost`, `EngineSound`, sinks), `lib/platform/engine_audio.dart`, `EngineAudioChannel.kt`, `lib/app/drive_sound.dart`, `lib/app/engine_sound_sources.dart`.

**What I could not verify, plainly.**
- **How it sounds.** I can test the pitch (a four at 3000 rpm is 100 Hz, and exact to a fraction of a sample), the level, that it never clips or clicks and is silent when off. I cannot hear it. Whether it is an engine or a buzzing synth, and which profile is best, is for your ear, and will take rounds like the tach did. The parameters are all in `EngineProfile`.
- **Everything on the phone:** the Kotlin channel compiles (debug APK builds) and is unit-tested only through a mocked channel; the isolate's use of a platform channel (`BackgroundIsolateBinaryMessenger`) is untested on a device; the car-audio detection, the route-change stop and the stop-with-the-screen are untested. **Bluetooth audio while the OBD adapter is also on Bluetooth may slow the poll rate** (a Classic adapter especially), and the audio may stutter: the session recording's poll rate, with the sound on and off, will say.
- **The sound lags.** The data is 1.3 to 2 Hz and already played out half a second late, Bluetooth audio adds about a fifth of a second: live, the sound is a second behind the real engine and glides instead of blipping. Next to a loud real engine it will drift out of step. A replay is taken a moment ahead to line up with its picture.
- **The replay** was driven by widget tests and looked at in captures; never by a finger, and never on a phone. The chase camera's feel (how wide it looks, how quickly it turns) is in `TapeReplay`; **a long trip draws 3,000 points while it replays**, so a deep zoom still shows straight chords on a very long route.

**What is not built.** A real map under the route (OpenStreetMap vector tiles, from a file you put on the phone): assessed, and worth doing after this; it needs a PMTiles and vector-tile reader and renderer of our own (flutter_map depends on `http`, which the offline check bans), attribution ("© OpenStreetMap contributors", ODbL) and a file picker. Nothing is bundled, to keep the ODbL on the data and Apache-2.0 on the app.

## The survey drive (2026-10-16)

Asked for by the human, after an analysis of the first real recordings (two drives, 115 minutes, a BLE ELM327 on a petrol City): *build the survey mode; once I drive I will connect the data.* The point is to find out what the car will report before designing an electrical page and an engine page. **Garage → Adapter → Survey drive**; the how-to is `docs/SURVEY.md`.

**What the recordings had shown, which this is built on.**
- **Two ECUs** answer every request on 29-bit CAN, with different PID sets (22 and 28; 32 PIDs between them). The dashboard read 9 of them.
- **Only one ECU's long answer survives** when both answer: the adapter sends flow control to one. That is why batches never worked for the dashboard, and why every PID is a request of its own (1.3 reads a second).
- A request takes **141 ms, or 172 ms for a batch of six** (the `slow_ble` preset's "no batches" was a wrong guess).
- Not on the car: fuel level (2F), fuel rate (5E), engine torque (61 to 63), oil temperature, any battery current. On it, and never read: ignition timing, commanded and measured air-fuel ratio, the open or closed loop status, fuel trims, both pedal sensors, the commanded throttle, absolute load, barometric pressure.

**What was built.**

| | Where |
|---|---|
| The simulator can have **several ECUs**, headers (11-bit and 29-bit IDs), `ATCRA`, physical addressing, protocol 7, Mode 06 / 0A / 09 calibration data, and the PIDs beyond the app's 11. A new profile, `petrol_cvt_twin_ecu`, has the first car's two PID sets (not in `VehicleProfiles.all`). The plain ECU is unchanged: every existing test passes. | `lib/sim/` |
| `HeadedReply` (frames with headers, ISO-TP put back together, one message per ECU), `Mode01Lengths`, `SurveySchedule` (what to ask next), `SurveyRunner` (start-up, ECU discovery, the read-once probe, the drive loop, and the ways back below), `SurveyLogReader` (a log back into per-ECU readings and marks) | `lib/obd/survey/` |
| `SurveyGuide` (the sixteen parked steps, countdown, the marks written as each begins, stops when the car moves), `SurveyDrive` (the adapter taken over from the dashboard, the log written every 20 s and at the end, parked-only finishing) and `SurveyPage` (getting ready, the checks offered, each step, the drive with nothing to touch, the checks again, finish; all prompts only while the car stands) | `lib/app/survey_drive.dart`, `lib/obd/survey/survey_guide.dart`, `lib/ui/pages/survey/` |
| The Garage row, the hand-over of the adapter in `app.dart` (the dashboard's link is closed first, and made again after) | `garage_page.dart`, `drive_shell.dart`, `app.dart` |
| `tool/record_survey.dart` (a survey log from the simulator) and `tool/survey_summary.dart` (ECUs, PIDs and rates, the other modes, marks, what the survey did; `--csv`) | `tool/` |

**Measured on the simulator**, behind an adapter given the real one's timing: the revs, speed and battery voltage are read **2.3 times a second** (the dashboard gets 1.3), the engine-state PIDs about once a second, the first ECU's oxygen sensor about every 2.5 s. It reads **only**: a test fails on any command that is not Mode 01, 03, 06, 07, 09 (PIDs 00, 04, 06, 0A) or 0A, or an AT command from a short list; never Mode 04, never the VIN.

**Numbers:** 3,354 tests pass with `tool/verify.sh` (65 golden tests are skipped on this Mac and run on CI Linux), of which about 160 are new: the simulator's second ECU and headers, the frame and length parsing, the scheduler, 23 end-to-end surveys on the simulator (two ECUs, one ECU, each way back), the drive object, the screen at three sizes, the whole app from Garage to the dashboard coming back, and the two tools.

**Ways back, each tested:** no `ATCRA` (listens to every ECU; the batch falls to what works), an `ATCRA` that lets nothing through (dropped after three requests; the car is not taken for switched off), no batches (falls to three, then one), headers in a format nobody expected (goes on without them), an adapter that resets itself, a dropped link, the ignition going off (waits, carries on without starting over), the car staying off for 30 minutes (ends and saves).

**What was not verified, plainly.**
- **Nothing here has met the real adapter or car.** Whether it takes `ATCRA`, prints 29-bit IDs as eight hex digits, prints headers-on frames in the format assumed, and lets six PIDs through to one ECU: all assumptions, each with a way back, each visible in the log (`@ survey` lines say which was used).
- The simulator's numbers (2.3 Hz and so on) are the simulator's. The real adapter may do better or worse.
- The values behind the new PIDs in the simulator are invented (right length, plausible, not data).
- The survey screen has been laid out at 640, 720 and 800 by 360 and driven by widget tests; it has not been seen on a phone, and no screenshots were taken (the per-phase design review package is waived for this work, as for phases 4 to 6).
- **No Mode 22 or UDS probing** (see DECISIONS.md): no list for this car was found, and standard OBD has no battery current. The electricity page is therefore limited to the voltage, plus the load signatures the marks make.

## Phase 3b: the review package, and where the phase stands

`docs/design-review/phase-3b/` (README, perf.md, screenshots): written, with the fixes its captures forced (`8d12e2e`), the first real emulator run of the whole app (Reference_API24: cold open, demo path, all five clusters, the HUD, all working) and the first emulator frame costs. **Phase 3b's build list is complete; the phase is not "done" in CLAUDE.md 1's sense until the human has reviewed the package** (five open questions in its README). Suggested tag once reviewed: `v0.3.0-sim` (not placed). Also suggested, still unplaced: `v0.1.0-sim`, `v0.2.0-design`.

Known gaps carried into later work, all in the review README: budgets unchecked on a real phone; no video; only ION/Normal seen; loud detent digits in Telemetry and Road; the Road cluster looks unfinished; ignition only fully in Apex; Layer 4 page-level goldens and the DESIGN.md 14.2 matrix (contrast, motion-lock, flash-rate) not written for the composed pages.

## Phase 3b: the brand (DESIGN.md 12)

The app icon (adaptive + monochrome + legacy PNGs) and the Android 12 splash icon, generated by `tool/make_brand.py`; preview at `docs/brand-icon-preview.png`; frame 38. The launch window stays plain `void` (see DECISIONS.md). The wordmark is `lib/ui/brand/wordmark.dart` (built with onboarding). **Not verified:** the icon at 48 px on a real launcher, Android 13 themed-icon tinting, the splash on a device. The debug APK builds.

## Phase 3b: onboarding (DESIGN.md 7.11)

`lib/ui/onboarding/onboarding_screen.dart` and `lib/ui/brand/wordmark.dart`: the cold open (line draws from the centre, wordmark resolves, 1.2 s), then the choice. The cold open's frame timings feed `TierDetector` and the tier goes into the theme. The demo path connects behind the choice (the demo drive starts at launch), so the ignition plays within a second of the tap (tested on a fake clock; it took 4.15 s when the drive only started on the tap). Tests: `onboarding_test.dart` (11), a capture, frame 37.

**Not done:** the connect path (adapter type, pairing, car setup, price, cluster choice, progress tape) -- needs phase 6; CONNECT MY CAR is disabled with a plain note. The choice is not remembered across launches (needs `shared_preferences`, which is a dependency to record in DECISIONS.md). The real frame timings during the cold open are unverified on a device.

## Phase 3b: Demo Mode in the app shell

`lib/app/drive_shell.dart` (`DriveShell`): the app now opens on the Strip, fed by `DemoDrive` (a simulated car through the real OBD stack), with the parked dock and the HUD over it and `DriveSignals.demoMode` putting the DEMO badge on every cluster. Time is injected (`TapeDashApp(clock:, scheduler:)`; tests use a `FakeClock`). The Design Lab dev button stays. Tests: two new in `app_shell_test.dart` (the demo car drives; double-tap toggles the HUD), a capture, frame 36.

**Not done:** onboarding (the choice between a demo and a real car; today the app goes straight to the demo), the demo scenario/profile picker (Garage), Review/Coach/History are still placeholders.

**Real bugs found by running the clusters in a real shell for the first time:** the status strip's right flank painted off the right edge in every cluster (only the clock's first digit showed; the component's tests had centred it), and the parked dock overflowed a 640 lp screen by 184 lp (only tested at 800). Both fixed in their own commits, with tests at 640/720/800.

## Phase 3b: the HUD (DESIGN.md 8)

`lib/ui/hud/`: `HudSettings` (colour, layout, the two flips, vertical position, scale, active, alignment pattern; plain state, no storage), `HudView` (pure black, one colour, Bold numerals, no halos, 5 lp strokes, labels at 0.06H; one `Transform` over everything, so the alignment pattern is mirrored exactly as the HUD is), `AlignmentPattern` (frame, crosshair and thirds grid, the wordmark, a large F, an arrow path and UP), `HudHost` (lays the HUD over the strip; a double-tap puts it down). `TheStrip.onToggleHud` is the double-tap on Drive or Money; `ParkedDock.onHud` enables the dock's HUD button. The HUD runs under `Liveries.hud(HudColor)`; a stale value is the HUD colour at 45%. Tokens: `tokens/hud.dart`. Tests: 26 in `test/widget/hud_test.dart` (settings, the mirror's maths, black-and-one-colour at 640/720/800 x 360 in all three layouts, centring, redline, the pattern through the flips, the toggles). Capture: `test/design/capture/hud_capture_test.dart`, build-video frame 35.

**Honestly absent:** the money figures (phase 4: the two money layouts say MONEY UNAVAILABLE), the persistence of the settings and the last mode (Garage), the brightness curve, wake lock and immersive mode (app shell, `DeviceChannel`), the 50 C dim, and the HUD's own alert source (the slot exists; nothing feeds it yet). Not viewed on a real windshield or a real phone.

**Real bugs found:** the parked dock never repainted its position as it rose (fixed in its own commit, `5e56153`; its test had asserted the buggy position); `CenteredNumeral` centred 54 lp off at HUD sizes (the HUD reads the atlas advance; the component itself is unchanged and its other users were not re-measured); a stale HUD numeral drew grey, a second colour.

Numbers: full suite green as of the commit after `84db5c1`, nothing pushed, no tags.

## Phase 3b: the connection states (DESIGN.md 7.12)

`ConnectionPresentation` (`ui/design/motion/`) maps the session's status to a `LinkPhase` and holds the shares; one `ConnectionLayer` sits over the Drive reel, so all five clusters get the states. Searching: standby scrim (15% etch; the status strip's corners are left alone so the adapter glyph stays readable), a sweep beam turning once per 1.6 s on the arc's ring, "Looking for your adapter". Waiting for ignition: one accent dot breathing at 0.25 Hz at the hero position, "Turn on the ignition" at full label colour. Lost: values freeze and fade to stale (already the smoothing pipeline's job), a caution line on the horizon, "Reconnecting...". Reconnection after a loss: a 300 ms accent ring re-light (my reading of the spec's "quick re-light"; the token file says so). It asks the clock for frames only while searching or waiting. Captures found and fixed: the arc's top bleeding above the scrim, and a caution line and ring both far too heavy. Gaps: the words swap at once between searching and waiting (no crossfade); the beam and dot are plain alpha shapes, not the baked glow sprite; the ring sits at the Apex arc's radius on all clusters. Not verified on a device. Frame 34.

## Phase 3b: the ignition sequence (DESIGN.md 7.13)

`DriveSignals.ignition` (`ui/design/motion/ignition_sequence.dart`) plays once per connection on the first rpm above 400: the arc wave (expo-out, 0-450 ms), the needle to redline and back (`SmoothedSignal.hold`/`release`, spring.needle), the numerals rolling up from 0 (300-900 ms), the horizon drawing out from the centre and the flank fading in (600-1,200 ms, staggered). Subtle = numerals and horizon only; Off = nothing; reduce motion = a 200 ms fade. It never delays live data: a reading arriving mid-sequence retargets. A lost link and back does not replay it (that is 7.12's quick re-light, not built). Wired into Apex only: the other four clusters get the needle sweep and numeral roll (signal-level) but not yet the arc wave, horizon draw or flank fade. Shutdown is the needle falling on spring.needle, already true; the Debrief is phase 5. Not verified: real frame timings (DESIGN.md 14: no frame above 32 ms during the sequence) -- no device or emulator here. Also fixed a latent `ShiftHorizon` bug the sweep exposed (a stale edge segment never zeroed on a fast fall). `Presence` is a documented, transient-only exception to the no-Opacity rule. Frame 33.

## Phase 3b: the shared-element flight (DESIGN.md 7.1)

Drive -> Money: the hero speed travels to Money's status corner on the strip's own `spring.page` progress, so it is interruptible and reversible mid-flight with the swipe's velocity. Ends register through `SharedElementEnd` (`lib/ui/design/motion/shared_elements.dart`); `SharedElementsLayer` in the Strip paints the one flying copy. The departing page keeps its own copy to 20% of the flight, the arriving page shows its own from 90% (`TapeMotion.sharedElementDepart/Arrive`). Not built: the trip-rupees flight (Drive floor to Money centre) -- both ends need `money/` (phase 4), so it is registered by id only. Money's page is still a placeholder. Committed `e3f2e09`; frame 32.

## Phase 3b: the Motion <-> Parked choreography

DESIGN.md 7.2's choreography is in. The mode state had been wired since phase 2 (`VehicleState.mode` -> `DriveSignals.mode`) and the dock already reacted; the rest of the screen now reacts on one shared value:

| Piece | Where | Tests |
|---|---|---|
| `ParkedShare`: the parked share (DESIGN.md 7.2), 0 in Motion and 1 parked, rising on `spring.reveal`, falling on `spring.snap` inside the 300 ms the motion return allows, cancelling whatever is in flight; hosts the choreography's one stagger formula | `lib/ui/design/motion/parked_share.dart` | 9 |
| `DriveSignals.parkedShare`: the whole screen's choreography reads this one spring | `lib/ui/pages/drive/drive_signals.dart` | 3, in the suite's own `parkedShare` group |
| The tach arc thins and dims to 60% (stagger 0): segments thinned to 60% of their radial depth, everything luminous dimmed to 60%; the etched scale is the static ground and stays put | `tach_arc.dart` + `tokens/tach.dart` | 1 pixel test (same readings at motion vs parked: full-brightness ink gone, strictly less tinted ink) |
| `ParkedScale`: the hero's transition transform, deliberately not a re-layout (the glyph atlas is per font size) | `lib/ui/design/components/parked_scale.dart` | direct `scaleFor` tests via the share's own suite; Apex and Minimal each pin the rendered shrink |
| The status strip's captions fade in on the share, the glyph columns widening with them, instead of the hard bool switch | `status_strip.dart` | the suite's own caption and width tests, re-pointed at the share |

**The reading of "thins and dims to 60%" is recorded in `tokens/tach.dart`:** both effects to the same 60% -- the segments' radial depth and the whole arc's luminous layers' brightness. The etched scale does not dim with them. **What is honestly absent (phase 4):** the flanks' unfolded detail panels (trip stats, fuel, calibration) the spec also asks for -- they need `fuel/`, `money/` or `trips/`, none of which exist yet; absent, not faked (CLAUDE.md 1). The parked dock keeps its own spring (the strip is a different subtree from the Drive page); its fall is the same `spring.snap` inside the same budget.

**Real bugs the tests or captures found:** the tach arc's first parked pixel test read the *needle's* white core as the "hero ink" (the numeral's ink sits lower than an eyeball guesses, and the needle's own white blade sits inside any wide centre-zone band) -- a probe of the actual frame settled which side was wrong; the test now counts any ink brighter than the void in a band the arc's own parts sit outside of. The parked capture (a real `DemoDrive`, stopped) first captured an arc with no values at all -- a stopped drive never polls -- so it now feeds idle readings at the fast tier's own pace.

Numbers as of this section: **2,218 tests** (2,203 before), `d177350` at HEAD for the feature, nothing pushed, no tags.

## Phase 2: what exists

Everything here is pure Dart with no Flutter imports, and is driven by callbacks on an injected clock, never by `await`. So a whole drive runs inside one `FakeClock.advance`.

| Piece | Where | Checked by |
|---|---|---|
| `Observable` and `ObservableValue`: a value that says when it changes, with no Flutter in it. It is how every layer reports upwards | `lib/core/observable.dart` | 17 tests |
| The reply parser: strips the echo, `SEARCHING...`, `BUS INIT: ...OK` and the prompt, names the 17 failures (every error string an adapter prints, plus timeout, disconnected and garbled), and rebuilds messages from single-frame and multi-frame lines in any order | `lib/obd/elm327/elm327_parser.dart`, `elm327_failure.dart` | 73 tests, and 18 that read everything the simulator prints, under every echo, linefeed and spaces setting and for every message length |
| The client: one command in flight, each reply ended by its prompt, timeouts, a missing prompt, noise and stray characters, a late reply skipped rather than taken for the next command's, and every reply timestamped at the middle of its round trip | `lib/obd/elm327/elm327_client.dart` | 65 tests, and 12 against the simulator |
| PID decoders for the eleven PIDs of CLAUDE.md 8.3, the Mode 01 answer parser, the monitor status, and supported-PID discovery (ranges `00` to `C0`, later ranges retried, a `DiscoveryResult.incomplete` flag) | `lib/obd/pids/` | 66 tests, including the datasheet's own examples |
| The start-up: settle, `ATZ`, `ATE0`, `ATL0`, `ATS0`, `ATH0`, `ATAT1`, `ATSP0` (or the remembered protocol), discovery, `ATDPN`. It tells a car that is off from an adapter that is failing, retries what may be noise, and falls back from a wrong remembered protocol | `lib/obd/elm327/elm327_init.dart` | 55 tests |
| `VehicleState`: the latest reading of each of the eleven sensors, an outlier check (10,000 rpm/s, 15 km/h in 100 ms, judged over at least 100 ms and confirmed by the next sample), smoothed speed and acceleration, engine running, motion or parked, ignition, and staleness | `lib/vehicle/` | 60 tests |
| The poller: fast, medium and slow tiers, oldest-read-first, multi-PID batching of up to 6 on CAN with the response-count digit, fallback to single requests, a per-PID backoff for a PID the car will not answer, a compatibility mode, and the achieved cycle rate | `lib/obd/poller.dart` | 58 tests |
| Fault codes: Mode 03, 07 and 04, decoding into P, C, B and U codes, and clearing that is refused unless the car is stationary and is reported back if the ECU refuses | `lib/obd/dtc/` | 51 tests |
| `ObdSession`: the whole path from the phone to the car. Connect, start up, poll, and the states of DESIGN.md 7.12 (searching, waiting for the ignition, connected, lost), reconnecting with backoff from 1 s to 10 s, probing once a second while the ignition is off, and halting on an adapter that cannot do the job | `lib/obd/obd_session.dart` | 43 tests |
| `ReplayTransport`: plays a session log back into the stack, command by command, with the recorded delays | `lib/obd/transport/replay_transport.dart` | 21 tests, including a replay of a recording made by the real stack |
| `tool/record_sim.dart` now records the **real stack's** traffic: an `ObdSession` on a `RecordingTransport` on the simulator | `tool/record_sim.dart` | 24 tests |
| `tool/crosscheck_emulator.dart`: the stack over TCP, in real time, against Ircama's ELM327-emulator, run as a separate process | `tool/` | run by hand, see below |
| Layer 3, the full stack on a fake clock against the simulator's ground truth | `test/e2e/` | 57 tests |
| The stack over a transport that delivers a microtask late, as Bluetooth and WiFi do | `test/support/async_transport.dart` | 2 tests |

Numbers: **1,499 tests** (900 at the end of phase 1), about 26 seconds for all of them, plus the 10 integration tests. About 9,600 lines under `lib/`, 20,800 under `test/` and 1,100 under `tool/`. **No dependency was added,** and `pubspec.yaml`, `pubspec.lock` and `android/` are unchanged since phase 1.

What the stack gives, measured on the simulator:

- **Speed.** A 30-minute `highway_cruise` runs through the whole stack in 2.4 s, and the 20-minute `city_stop_go` in 0.5 s to 1.8 s, depending on how often the adapter answers. CLAUDE.md asks for a few seconds.
- **Accuracy against ground truth,** over `city_stop_go`, comparing each reading with the car at the time it is stamped with: speed 0.11 km/h on average (99th percentile 0.74) and RPM 4 rpm on average (99th percentile 25). The car reports whole km/h, so half a km/h is the floor. The figures are the same on a perfect adapter, a Bluetooth clone and a flaky adapter: what an adapter's faults change is how often a reading arrives, not how right it is.
- **Timestamping at the middle of the round trip** (DESIGN.md 5.2), against stamping on arrival, on the clone: the error falls by 40% for speed (0.14 against 0.23 km/h) and 52% for RPM (9 against 19 rpm) over `aggressive_city`.
- **Poll rate.** A perfect adapter gives 37 cycles a second. The Bluetooth clone preset (80 ms +/- 40 ms, ignores `ATAT`) gives 9.3, and reads speed at 9.2 Hz on average and 8.9 Hz in its worst 10 seconds over a 10-minute drive. CLAUDE.md asks for at least 3. A flaky adapter gives 5.7 cycles a second, and in `adapter_flaky` speed stays above 3 Hz in every 10-second window while connected.
- **Time to connect,** from `start()` to connected, over `city_stop_go`: 4.1 s on a perfect adapter and 5.5 s on the clone, most of it the adapter's own reset and protocol search, which are assumed figures. A flaky adapter connected in all 60 seeds tried, in 9.6 s at the median and 19.6 s at worst.
- **What batching is worth:** the same clone, with batching off, reads speed at 2.3 Hz (2.0 in its worst window) with every tier running. See the known issues.
- **The coach's rule on polled data.** A stand-in for the coach's rule (CLAUDE.md 8.8: 2.5 m/s2 for 1 s, and -3.5 m/s2 for 0.5 s), applied to the smoothed motion the stack produces, finds 12 of 12 hard accelerations and 12 of 13 hard brakings in `aggressive_city`, and none in `eco_city`, on a perfect adapter and on the clone alike. The real coach is phase 5.

Layer 3 (CLAUDE.md 10), criterion by criterion, for what phase 2 can show:

| Criterion | State |
|---|---|
| The fast tier at 3 Hz or more on an 80 ms +/- 40 ms clone | **Met:** 8.9 Hz in the worst 10-second window over 10 minutes |
| `adapter_flaky`: no crash, reconnects | **Met:** it runs to the end connected, loses the link once at 240 s and is back at about 256 s, and none of the more than 5,000 readings checked is far from the truth |
| `adapter_flaky`: one trip, and no fuel spikes from missing data | Phase 4. What it rests on is met: a missing reading leaves a gap and the value goes stale, and nothing is invented |
| `minimal_old_car`: the gauges that can work do | **Met:** the five PIDs it has are read, the others are absent, and nothing is asked for that the car does not have. The "money unavailable" message is phase 4 |
| `dtc_present`: codes read and decoded, clearing refused while moving | **Met:** P0420 and P0171, and a clear at speed is refused without a byte sent to the car |
| `mixed_commute`: ignition off and on midway | The connection half is **met:** connected, waiting for the ignition, connected again within seconds, and the engine is seen to stop and start. Resuming or starting a trip is phase 4 |
| `traffic_jam`: long idling never ends the trip | The vehicle half is **met:** the engine is running all through and never taken to have stopped. The trip half is phase 4 |
| Distance, fuel, calibration, idle cost, eco against aggressive cost, tips, the Money Tape | Phases 4 and 5 |

## What has not been verified

- **The adapter's byte conventions against a real ELM327.** They come from the datasheet plus what real adapters are known to send (the list is in `docs/DECISIONS.md`). Phase 2 raised the confidence in them and did not remove the doubt: Ircama's emulator, written by someone else from what they saw of real adapters, agrees with the simulator on the two carriage returns before the banner, the trailing space on data lines, the blank line before every prompt, `SEARCHING...`, `A6` and the `ATDP` text, and it differs in two places that the parser reads (a space after the colon in a multi-frame line whatever the spaces setting, which the simulator now does too, and an unpadded last line). An emulator is still not an adapter.
- **The adapter's timing.** The reset, the protocol search, the ECU's answer, the adaptive-timing wait and the clone's latency are assumptions. So are all the poll rates above, which are properties of the simulator's model of a clone.
- **The client's timeouts** (1.5 s for a request, 2 s for a command, 4 s for a reset and 12 s for a protocol search) and the poller's pacing are set from those assumptions, and have never met a real adapter.
- **A real car's replies.** Only CAN, ISO 15765-4 at 500 kbaud, with one ECU, is simulated. K-line, J1850 and 29-bit CAN cars are not covered, and neither is a car where two ECUs answer the same request. The poller asks for one response (see the known issues), and this is where that shows.
- **How well the cars match real ones.** The profiles are approximations (CLAUDE.md 7.2), and nothing here has been compared with a real car.
- **The GPS error model, any real phone, the launch flash, performance, goldens and CI.** As at the end of phase 1: device checks ran on emulators only, there is no reference device, nothing animates yet, there are no goldens yet, and the GitHub workflow has parsed as YAML and never run, because there is no remote.
- **The WiFi transport against `tool/sim_server.dart`.** The server is verified with plain sockets, and the transport that will talk to it is phase 6. `tool/crosscheck_emulator.dart` has its own small TCP transport for the developer's machine, and it is not the app's.

## Known issues and notes

- **On a clone that refuses multi-PID requests, the fast tier falls below 3 Hz.** The `bluetooth_clone` preset batches, as most clones do, and reads speed at 9 Hz. A clone that also answers a multi-PID request with `?` leaves the poller to fall back to one PID at a time, which measures 2.3 Hz for speed with every tier running (about 3.2 Hz if only the fast tier is read). That is the limit of such an adapter, not a defect, and the display must cope with it. The smoothing pipeline in phase 3a interpolates between samples. Whether such adapters exist in the wild is a question for the hardware handoff.
- **A batched request ending in the count digit was refused by the third-party emulator, with `?`.** The poller took that as "no batching" and carried on with singles, which is the fallback working. An adapter that does not know the digit on a multi-PID request may still do batches without it, and trying that before giving up on batching is a small change, left for when a real adapter shows it is needed.
- **The poller and the fault-code service assume that one ECU answers,** and ask for one response (`010C1`). A car where the engine and the transmission both answer `0100` would be read from whichever answers first, which should be the engine ECU at 7E8 because its arbitration id is the lowest, and that is unchecked.
- **`AdapterMemory`, the protocol remembered per adapter, is in memory only.** The session uses it, and persisting it belongs to the app's service wiring (phase 3b), with `shared_preferences`.
- **A flaky adapter can make start-up report "waiting for the ignition" for a moment.** A random `NO DATA` during start-up looks like a car that says no, and a car that says no is a car with its ignition off. It happened in 2 of the 60 seeds tried, the probe loop (which asks once a second) found the car, and the session ended up connected. It only shows in the sequence of states.
- **Fault-code descriptions are not bundled yet.** Codes are decoded, and the JSON of descriptions, with its licence in `assets/dtc/SOURCE.md`, is phase 5.
- **Stale times differ from DESIGN.md 5.2's flat 1.5 s.** RPM, speed and throttle are stale at 1.5 s. Load, MAP, MAF and fuel rate, read every second, are stale at 3 s, and coolant, intake air, fuel level and voltage, read every four seconds, at 12 s. With one figure they would be flagged stale most of the time. The reasoning is in `docs/DECISIONS.md`.
- **`tool/sim_server.dart` binds 127.0.0.1 by default.** An emulator reaches it as `10.0.2.2`, and a phone on USB can use `adb reverse tcp:35000 tcp:35000`. `--host 0.0.0.0` serves the network, on purpose only.
- **The simulator is not in the app yet.** Demo Mode comes with the pages in phase 3b, and nothing in `lib/app/` uses it.
- **`test/unit/tool/sim_server_test.dart` runs on real sockets and real time,** about 10 seconds of the 26. It is the only such test.
- **`tool/record_sim.dart --all` takes about 10 seconds, and the ten logs are 23 MB.** They are not kept in git. It was 2.4 seconds and 0.2 to 2.6 MB each when a script stood in for the app: the real stack asks more.
- **Android 4.4 to 10 shows a one-time "Viewing full screen" notice** the first time the app goes immersive, and the user taps "Got it" once. The OS draws it and it cannot be suppressed. Expect it on old phones, and consider a line in onboarding.
- **The launcher and Android 12+ splash icons are still Flutter's default.** The brand icon is phase 3b.
- **The application ID `io.github.ictashik.tapedash` is unconfirmed.** It assumes the GitHub handle. It is cheap to rename now and effectively impossible after a release.
- **There is no NOTICE file or copyright line**, only the Apache-2.0 LICENSE.
- **Release builds are signed with the debug key** (the Flutter template's default). There is no release keystore yet.
- **The Ircama ELM327-emulator is CC BY-NC-SA 4.0.** It is only ever run as a separate process, from a virtual environment outside the repository. Nothing of it is in this repository or its dependencies, as code, text or data.

## For the hardware handoff

To copy into `docs/HARDWARE_HANDOFF.md` when phase 6 writes it:

- Record a cold start on the real phone with `adb shell screenrecord` and check that no frame is bright before the first Flutter frame.
- Check ambient light against real conditions, to tune the Daylight and Night thresholds (DESIGN.md 4.4).
- Check the accelerometer on the mounted phone, both landscape directions, and work out how much the mount's tilt has to be calibrated out.
- Check the battery temperature is reported at all, and in degrees Celsius.
- Check brightness at the floor on a real panel, and that `void` looks right on a cheap LCD (DESIGN.md 4.1).
- Check immersive mode, and what the OS shows on the first launch.
- **Record the first real adapter session byte for byte** (session recording, or a serial terminal before it exists): `ATZ`, `ATE1`, `ATI`, `ATRV`, `ATDP`, `ATSP0` then `0100`, `0902`, a multi-PID request, and a deliberately wrong `ATSP3`. Compare each reply with the conventions in `docs/DECISIONS.md` and fix the simulator, not the parser, where they differ. Once one exists it goes in `recordings/real/`, and `ReplayTransport` plays it into the stack as a regression test.
- **Measure the adapter's real round trip** with and without the response-count digit and with a multi-PID request, and compare with the 80 ms +/- 40 ms and 200 ms the simulator assumes. Note the poll rate the app reports (`ObdSession.pollRate`) and whether it batches (`Poller.isBatching`, `batchingRefused`).
- **Try a multi-PID request with and without the trailing digit** (`01 0C 0D 11 1` and `01 0C 0D 11`) on the real adapter. The third-party emulator refuses the first.
- **Check how many ECUs answer `0100`** on the real car, whether it answers multi-PID requests, and which ECU answers first.
- **Turn the ignition off and on with the adapter plugged in,** and note what the adapter prints while the car is asleep (`UNABLE TO CONNECT`, `NO DATA`, `CAN ERROR` or `BUS INIT: ...ERROR`). The session waits for the ignition after three such replies in a row and asks once a second.
- **Unplug the adapter mid-drive** and plug it back in, and check that the session goes to `lost`, retries after 1, 2, 4, 8 and then every 10 seconds, and comes back.
- **Check the outlier limits against a real car:** a rev-blip must not be rejected as impossible (`VehicleState.rejectedReadings`).
- **Compare the simulator's fuel figures with a real fill-up,** and tune the profile from real PID 5E, MAF and MAP readings.

## Phase 3a: what exists

Everything under `lib/ui/design/`, plus `lib/ui/lab/design_lab.dart` and the app shell. Full detail, deviations and open questions are in `docs/design-review/phase-3a/README.md`; this is the inventory.

| Piece | Where | Checked by |
|---|---|---|
| Fonts: Saira (variable), Barlow, Barlow Semi Condensed, all SIL OFL 1.1, subset from a pinned `google/fonts` commit, verified by SHA-256, 333 KB total | `assets/fonts/`, `tool/subset_fonts.sh` | 11 tests on the files themselves (coverage, licence, size) |
| Colour, livery, type, spacing, stroke, shape, glow, opacity and motion tokens — every value from DESIGN.md 4–5 | `lib/ui/design/tokens/` | 40 tests, value by value against the spec |
| `TapePalette`: a livery resolved in a mode, so Daylight and Night's rules live in one place; `ModeController` follows ambient light with the spec's thresholds and dwell; `Contrast` for WCAG ratios | `lib/ui/design/theme/` | 85 tests, including every livery x every mode against DESIGN.md 11's contrast rules |
| `MotionClock` (virtual time, 50 ms frame clamp, `timeDilation`, zero cost at rest), `SpringValue` (retargets an analytic simulation from position and velocity), `PhosphorBank`, `OdometerLayout` (detent and carries), `SmoothedSignal` (lead compensation, spring, 1.5 s stale fade), `Timeline` | `lib/ui/design/motion/` | 190 tests: needle overshoot and settle time, no NaN, phosphor decay within 5%, the ones column identical for 7/77/107 |
| Glyph atlas and seven-segment atlas (`drawRawAtlas` from preallocated buffers), glow-sprite cache, grain tile, VFD mesh, `Chamfer`, pixel snapping, `StaticLayer` | `lib/ui/design/render/` | 65 tests, plus device screenshots |
| The 27-glyph icon set, path strings on a 24-unit grid | `lib/ui/design/icons/icons.dart` | 12 tests: the required set, everything inside the grid, every line an axis or 45° |
| `TierDetector`, `TierGovernor`, `FrameProbe`, the fps cap on `MotionClock` | `lib/ui/design/fidelity/` | 37 tests |
| `RollingNumerals`/`SairaNumerals`, `SevenSegmentNumerals`, the chamfer button, toggle, segmented selector, slider, list row, `TouchBloom`, `TapeBackdrop` | `lib/ui/design/components/` | 85 widget tests rendering and reading real pixels |
| The design lint: no Material widgets, no colour/text-style/duration/spring literal outside `tokens/`, covering `lib/ui` and the app shell file | `test/design/design_lint_test.dart` | 33 tests, including on planted violations |
| Design Lab: numerals/controls/icons tabs, livery/mode/tier/driving/driver-side/reduce-motion/slow-motion/aspect-frame switchers, a frame-timing graph, capture-all | `lib/ui/lab/design_lab.dart` | 8 widget tests; exercised live on the API 24 emulator (screenshots in the review package) |
| App shell: fonts awaited before the first frame, the void canvas, the dev button into the Lab | `lib/app/app.dart`, `lib/main.dart` | 2 widget tests, 2 integration tests (real device) |
| `DemoDrive`, `DataSource`/`DemoControl`: a looping simulated drive into a `VehicleState`, for 3b to read | `lib/app/demo_drive.dart`, `lib/ui/dev/` | compiles; not yet exercised, since nothing reads it (see the review package) |

Numbers: **2,014 tests** (1,499 at the end of phase 2), about 30 seconds for all of them, plus 2 integration tests run on a real API 24 emulator. About 17,500 lines under `lib/`, 29,200 under `test/`, 1,400 under `tool/`. No dependency was added; the APK grew by the 333 KB of fonts plus the design system's own code, and is still well under budget: **12.0 MB (armeabi-v7a), 14.8 MB (arm64-v8a)**, both checked with `tool/check_apk_size.sh` against a real `--split-per-abi --release` build.

Two real bugs were found by writing the Lab's own tests and are already fixed: the aspect-frame switcher did nothing until it was wired to actually letterbox the capture area, and `capture-all`'s image renderer needed to be made injectable after `RenderRepaintBoundary.toImage()` was found to hang under `flutter_test` when a `tester.pump()` shares its `runAsync` block (a framework quirk, not an app bug; recorded in the shell-quirks memory). Both are in the review package's README under "What nearly shipped broken."

## What has not been verified (phase 3a)

- **No golden-image tests yet** (DESIGN.md 14.1's matrix, every page x livery x mode). There are no pages until phase 3b; pixel-level assertions on components stand in for now.
- **No frame-timing numbers from a demo drive** (DESIGN.md 9.4, CLAUDE.md 10 layer 5). There is no Drive page to profile. `docs/design-review/phase-3a/perf.md` says exactly what was and was not measured, and on what hardware (an emulator, not the reference device).
- **`DemoDrive` has not been exercised against a screen.** It compiles; the phase-2 code underneath it is already proven; the new looping-restart logic has no test of its own until phase 3b wires it to something.
- **The screen recording is not one.** `adb shell screenrecord` fails on the API 24 image (`Encoder failed`, already known per `DEV_SETUP.md`); the video in the review package is a still-frame sequence, said so plainly there.
- **Only EMBER's Daylight and Night were checked by eye on a device;** the other three liveries were checked by the automated contrast tests only.

## Known issues and notes (phase 3a)

- **The capture-all sink writes to the system temp directory,** not real app storage — there is no device-feature decision for one yet (CLAUDE.md 5). Fine for now since the Lab is dev-only; noted as an open question in the review package for when store screenshots (DESIGN.md 12) are wanted.
- **The dev button, not the debug overlay, opens the Lab.** CLAUDE.md 9's long-press debug overlay does not exist yet. The button matches its intended reachability rule (debug/profile builds, or `--dart-define=TAPEDASH_DEV=true`), and is an open question for whether it moves behind the overlay once that exists.
- **The design lint covers `lib/ui` and `lib/app/app.dart` only,** not all of `lib/app`: service wiring like `demo_drive.dart`'s poll-loop interval is not part of the design system.

## What phase 3b starts its remaining work from

Because phase 3a already did it, on top of the components section above:

- `TapeTheme`, `TapePalette` and `ModeController` are ready for a real page to read.
- `DemoDrive` and the `DataSource`/`DemoControl` interfaces are ready to wire to Drive, so pages never need to know whether Demo Mode or a real adapter is behind the `VehicleState` they read.
- `VehicleState` gives each reading as a value, the time it was measured (stamped at the middle of its round trip, DESIGN.md 5.2 step 1) and the time it arrived, after the outlier check (step 2), and says when a value is stale. `SmoothedSignal` (phase 3a) does the rest of the pipeline, steps 3 to 5.

This is the phase the Strip and the first live cluster arrive in, so it ends with a design review package covering real driving screens, not just components (CLAUDE.md 13, DESIGN.md 14.4).

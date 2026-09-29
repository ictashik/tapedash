# Status

Updated 2026-09-28, mid phase 3b: every component DESIGN.md 6 and CLAUDE.md 13 name for this phase now exists, and is built, tested and committed. All five Drive clusters (Apex, Road, Tape, Minimal, Telemetry) render against a real `DemoDrive`; the Strip (DESIGN.md 7.1) carries them as one panel -- a swipe with parallax, the page tape, the motion lock, and the parked dock -- and the Motion <-> Parked choreography (DESIGN.md 7.2) runs the whole screen's parked treatment on one shared spring. The speed's shared-element flight (Drive hero to Money's status corner) is in too; the trip-rupees flight waits on phase 4's money engine. The ignition sequence (DESIGN.md 7.13) plays in Apex. The HUD (DESIGN.md 8) is in too. Demo Mode opens the app. What remains of the phase: onboarding, the brand, and the phase's review package. Phases are in CLAUDE.md 13.

## Where we are

| Phase | State |
|---|---|
| 0. Foundation | **Done** |
| 1. Simulator | **Done** |
| 2. OBD stack on the simulator (tag `v0.1.0-sim`) | **Done** |
| 3a. Design system (tag `v0.2.0-design`) | **Done** |
| 3b. Cockpit and HUD (tag `v0.3.0-sim`) | **In progress: all components, all 5 clusters, the Strip, the dock, the Motion <-> Parked choreography and the speed shared-element flight** |
| 4 to 7 | Not started |

**Suggested tags, neither created:** `v0.1.0-sim` on `d5016d6` (end of phase 2) and `v0.2.0-design` on `62fb1bb` (end of phase 3a). Placing them is your call. Nothing has been pushed, and there is no remote.

There is something to see now: the app boots onto the `void` canvas with real grain and a vignette, and a dev button opens the Design Lab, a gallery of every component built so far in every livery and mode, running on the API 24 emulator with no exceptions. There is still no Drive page and no Strip; those are the rest of phase 3b, below. The design review package for phase 3a, with device screenshots and the two real bugs its own tests found, is `docs/design-review/phase-3a/`. Phases 0 to 2 are summarised in `docs/DECISIONS.md` and in the git history; phase 3a's design decisions are appended to the same file, below the phase 2 sections.

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

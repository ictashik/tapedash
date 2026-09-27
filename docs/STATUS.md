# Status

Updated 2026-09-27, at the end of phase 3a. Phases are in CLAUDE.md 13.

## Where we are

| Phase | State |
|---|---|
| 0. Foundation | **Done** |
| 1. Simulator | **Done** |
| 2. OBD stack on the simulator (tag `v0.1.0-sim`) | **Done** |
| 3a. Design system (tag `v0.2.0-design`) | **Done** |
| 3b. Cockpit and HUD (tag `v0.3.0-sim`) | Next |
| 4 to 7 | Not started |

**Suggested tags, neither created:** `v0.1.0-sim` on `d5016d6` (end of phase 2) and `v0.2.0-design` on the commit that adds these notes (end of phase 3a). Placing them is your call. Nothing has been pushed, and there is no remote.

There is something to see now: the app boots onto the `void` canvas with real grain and a vignette, and a dev button opens the Design Lab, a gallery of every component built so far in every livery and mode, running on the API 24 emulator with no exceptions. There is still no Drive page and no Strip; those are phase 3b. The design review package for this phase, with device screenshots and the two real bugs its own tests found, is `docs/design-review/phase-3a/`. Phases 0 to 2 are summarised in `docs/DECISIONS.md` and in the git history; phase 3a's design decisions are appended to the same file, below the phase 2 sections.

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

## Next: phase 3b, cockpit and HUD (tag `v0.3.0-sim`)

Components: tach arc, tapes, shift horizon, bar gauges, telemetry tiles, eco bar, money readout and the Money Tape, status strip, alerts, road view. The Strip navigation, Motion <-> Parked, the five Drive clusters, ignition and shutdown sequences, connection states. HUD layouts, flips, the alignment pattern. Demo Mode (wiring `DemoDrive` to a real screen), onboarding with the cold open and demo path, and the brand (icon, launch theme, wordmark). Layer 4 and 4b tests; a design review package (CLAUDE.md 13).

What it starts from, because phase 3a already does it:

- Every component it needs a base for exists and is in the Lab: numerals in both faces, the controls, the icon set, the motion core, the render primitives, the fidelity system.
- `TapeTheme`, `TapePalette` and `ModeController` are ready for a real page to read.
- `DemoDrive` and the `DataSource`/`DemoControl` interfaces are ready to wire to Drive, so pages never need to know whether Demo Mode or a real adapter is behind the `VehicleState` they read.
- `VehicleState` gives each reading as a value, the time it was measured (stamped at the middle of its round trip, DESIGN.md 5.2 step 1) and the time it arrived, after the outlier check (step 2), and says when a value is stale. `SmoothedSignal` (phase 3a) does the rest of the pipeline, steps 3 to 5.

This is the phase the tach arc, the Strip and the first live cluster arrive in, so it ends with a design review package covering real driving screens, not just components (CLAUDE.md 13, DESIGN.md 14.4).

# Status

Updated 2026-09-27, at the end of phase 2. Phases are in CLAUDE.md 13.

## Where we are

| Phase | State |
|---|---|
| 0. Foundation | **Done** |
| 1. Simulator | **Done** |
| 2. OBD stack on the simulator (tag `v0.1.0-sim`) | **Done** |
| 3a. Design system (tag `v0.2.0-design`) | Next |
| 3b to 7 | Not started |

**Suggested tag: `v0.1.0-sim`**, on the commit that adds these notes. It has not been created; placing it is your call. Nothing has been pushed, and there is no remote.

There is still nothing to see: the app is one `void` canvas. Phase 2 is headless too, and the first real visuals arrive in phase 3a. Phases 0 and 1 are summarised in `docs/DECISIONS.md` and in the git history.

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

## Next: phase 3a, the design system (tag `v0.2.0-design`)

Fonts bundled and subset (with ₹ coverage checked), tokens, liveries, Daylight and Night modes, `TapeTheme`; `MotionClock`, spring tokens, the smoothing pipeline, phosphor and the detented odometer; the glyph atlas, glow cache, static layers, grain, seven-segment renderer, chamfer shapes and icon set; fidelity tier detection and the governor; the Design Lab with capture-all, driven by the simulator; the design lint, spring, odometer and phosphor tests; and a design review package covering components and motion only (CLAUDE.md 13, DESIGN.md 14.4).

What it starts from, because phase 2 already does it:

- `VehicleState` gives each reading as a value, the time it was measured (stamped at the middle of its round trip, DESIGN.md 5.2 step 1) and the time it arrived, after the outlier check (step 2), and says when a value is stale. Steps 3 to 5, the lead compensation, the spring and the render, are the UI's, and the lead is tuned after the hardware handoff.
- Everything it exposes is an `Observable`, which the UI can listen to without rebuilding widgets (DESIGN.md 9.3), and the Design Lab can be driven by `SimulatedCar` the same way as the app will be.

What it needs from outside: the font files (Saira, Barlow and Barlow Semi Condensed, all OFL), fetched at development time from their upstream or supplied by you, and fonttools to subset them. Neither ships in the app. This is the first phase that produces something to look at, so it ends with the design review package, which is the only way you review the design (CLAUDE.md 1).

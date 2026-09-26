# Status

Updated 2026-09-27, at the end of phase 1. Phases are in CLAUDE.md 13.

## Where we are

| Phase | State |
|---|---|
| 0. Foundation | **Done** |
| 1. Simulator | **Done** |
| 2. OBD stack on the simulator (tag `v0.1.0-sim`) | Next |
| 3a to 7 | Not started |

No tag is suggested for phase 1: the roadmap's first tag is `v0.1.0-sim`, after phase 2. If a marker is wanted anyway, `v0.0.2-simulator` fits (and `v0.0.1-foundation` for phase 0).

There is still nothing to see: the app is one `void` canvas. Phase 1 is all headless, and the first real visuals arrive in phase 3a.

## Phase 1: what exists

Everything is pure Dart, so `tool/` runs it under plain `dart`.

| Piece | Where | Checked by |
|---|---|---|
| A portable, seedable random source that gives the same numbers on every platform, with forkable streams | `lib/sim/sim_random.dart` | 14 tests |
| The engine: a Willans-line model for petrol (air first) and diesel (fuel first), giving manifold pressure, air, fuel and torque that agree with each other | `lib/sim/engine_*.dart` | 40 tests, including the speed-density formula and energy conservation |
| Six vehicle profiles (CLAUDE.md 7.2), a CVT and a manual gearbox with a virtual driver | `lib/sim/vehicle_profile.dart`, `profiles.dart` | 31 tests |
| Roads made of straights and arcs, with position, heading and curvature | `lib/sim/sim_route.dart` | 22 tests against geometry worked out by hand |
| The vehicle model: warm-up, start-up, fuel cut, lateral acceleration, and **exact ground truth** (fuel, distance, idle time and fuel, every hard event) | `lib/sim/vehicle_model.dart`, `ground_truth.dart` | 85 tests, including that ground truth is recomputed independently and that the seed never changes the physics |
| A scripted driver that inverts the model to hold a speed or hit a stop without overshoot, in gentle, normal and hard styles | `lib/sim/driver.dart`, `drive_style.dart` | 32 tests |
| The ten scenarios of CLAUDE.md 7.3 and `SimulatedCar`, which runs one on a scheduler or as fast as you like | `lib/sim/scenarios.dart`, `simulated_car.dart` | 52 and 24 tests |
| The ECU: PID encoding, PID 01 with the check-engine light, the support bitmasks, Modes 03, 04, 07 and 09, sensor noise on its own stream | `lib/sim/ecu.dart` | 44 tests |
| `Elm327Simulator`: the adapter's byte-accurate text, with every AT setting, the protocol search, CAN single and multi-frame formatting, the response-count digit, and all the error strings | `lib/sim/elm327_simulator.dart` | 103 tests, with golden fixtures written by hand from the datasheet for each echo, linefeed, spaces and headers combination |
| `Elm327Device`: the adapter's serial line, with link latency split around the car being asked, one command at a time, a lost first command and a dropped link | `lib/sim/elm327_device.dart` | 24 tests |
| `AdapterQuirks` and its presets: a Bluetooth clone and a flaky one | `lib/sim/adapter_quirks.dart` | 9 tests |
| The wire round trip: for all six profiles, every PID is read back out of the ELM327 text with the CLAUDE.md 8.3 formulas and compared with the car | `test/unit/sim/wire_round_trip_test.dart` | 24 tests |
| `Transport` and `SimTransport`, with link faults from the scenario | `lib/obd/transport/` | 26 tests |
| The session log format, and `RecordingTransport` | `lib/obd/transport/session_log.dart`, `recording_transport.dart` | 28 tests, including every character of the escaping |
| `LocationSource` and `SimLocationSource`: a GPS with wander, honest accuracy, spells of bad fixes, and no heading at rest | `lib/location/` | 21 tests |
| `tool/sim_server.dart`: the car and adapter over TCP for the real WiFi transport | `tool/` | 8 tests on real sockets; run by hand too |
| `tool/record_sim.dart`: a scenario as a session log, deterministic, all ten in 2.4 s | `tool/` | 21 tests |
| Architecture rules for imports: the pure layers stay off `ui/`, `app/` and `platform/`, `core/` and `sim/` sit at the bottom, and `ui/` never touches a transport | `test/unit/architecture_test.dart` | 30 tests |

Numbers: **900 unit and widget tests** (284 at the end of phase 0), about 16 seconds for all of them, plus the 10 integration tests. About 6,000 lines under `lib/` and 11,000 under `test/`. No dependency was added.

What the simulator gives, measured:

- A 30-minute drive runs in about a quarter of a second, and all ten scenarios record as session logs in 2.4 s.
- `eco_city` uses **30% less fuel** than `aggressive_city` over the same 4.5 km, with the same waits at the signals. The spec asks for at least 15%.
- The coach's own detection rule (smoothed speed, CLAUDE.md 8.8), applied to whole km/h samples at 10 Hz, finds the scripted hard accelerations and brakings within one, and finds none in the eco run.
- Fuel: city driving about 8.7 L/100 km with 35% of the time idling, highway 5.7 L/100 km, and 1.1 L/h idling, for the default 1.5 L petrol CVT hatch.
- The simulated GPS reports an accuracy that is honest: about two fixes in three land within it.

## What has not been verified

- **The adapter's byte conventions against a real ELM327.** The message formats come from the datasheet, and its own examples are the golden fixtures. The datasheet leaves a few things open, and these follow what real adapters are known to send: the blank line before every prompt, two carriage returns before the banner after a reset, a trailing space on data lines, `0: ` in multi-frame lines, and what a wrong fixed protocol prints (the full list is in `docs/DECISIONS.md`). They are right as far as anyone has seen, and are unchecked on hardware.
- **The adapter's timing.** The datasheet gives no figures, so the reset, the protocol search, the ECU's answer and the adaptive-timing wait are assumptions.
- **How well the cars match real ones.** The profiles are approximations (CLAUDE.md 7.2). The consumption and warm-up figures are plausible, and have not been compared with any real car. A real recording replaces or tunes them after the hardware handoff.
- **The GPS error model** is plausible for a phone in a car, and unmeasured.
- **Only CAN is simulated,** with one ECU. K-line and J1850 cars, and a car where two ECUs answer the same request, are not covered yet.
- **CI on GitHub.** There is no remote yet. The workflow parses as YAML and every script it calls has been run, but the workflow itself has never executed.
- **Any real phone.** All device checks ran on emulators, which have no real sensors. So the light sensor, the accelerometer axes on a dash-mounted phone, the battery temperature reading and the brightness floor are unverified on hardware, as CLAUDE.md 11 expects.
- **The launch flash.** It could not be measured on an emulator. The launch resources are protected by a unit test instead. It needs a look on a real phone, most of all on Android 11 or older.
- **Performance.** There is no reference device and nothing animates yet.
- **Goldens.** There are none yet. They start with the design system in phase 3a.
- **The WiFi transport against `tool/sim_server.dart`.** The server is verified with plain sockets, and the transport that will talk to it is phase 6.

## Known issues and notes

- **`tool/sim_server.dart` binds 127.0.0.1 by default.** An emulator reaches it as `10.0.2.2`, and a phone on USB can use `adb reverse tcp:35000 tcp:35000`. `--host 0.0.0.0` serves the network, on purpose only.
- **The simulator is not in the app yet.** Demo Mode comes with the pages in phase 3b, and nothing in `lib/app/` uses it.
- **`test/unit/tool/sim_server_test.dart` runs on real sockets and real time,** about 10 seconds of the 16. It is the only such test.
- **Android 4.4 to 10 shows a one-time "Viewing full screen" notice** the first time the app goes immersive, and the user taps "Got it" once. The OS draws it and it cannot be suppressed. Expect it on old phones, and consider a line in onboarding.
- **The launcher and Android 12+ splash icons are still Flutter's default.** The brand icon is phase 3b.
- **The application ID `io.github.ictashik.tapedash` is unconfirmed.** It assumes the GitHub handle. It is cheap to rename now and effectively impossible after a release.
- **There is no NOTICE file or copyright line**, only the Apache-2.0 LICENSE.
- **Release builds are signed with the debug key** (the Flutter template's default). There is no release keystore yet.
- **The Ircama ELM327-emulator was read as a behavioural reference, and is CC BY-NC-SA 4.0.** Nothing from it is in this repository. Running it as a separate process to cross-check the phase 2 parser is fine; copying from it is not.

## For the hardware handoff

To copy into `docs/HARDWARE_HANDOFF.md` when phase 6 writes it:

- Record a cold start on the real phone with `adb shell screenrecord` and check that no frame is bright before the first Flutter frame.
- Check ambient light against real conditions, to tune the Daylight and Night thresholds (DESIGN.md 4.4).
- Check the accelerometer on the mounted phone, both landscape directions, and work out how much the mount's tilt has to be calibrated out.
- Check the battery temperature is reported at all, and in degrees Celsius.
- Check brightness at the floor on a real panel, and that `void` looks right on a cheap LCD (DESIGN.md 4.1).
- Check immersive mode, and what the OS shows on the first launch.
- **Record the first real adapter session byte for byte** (session recording, or a serial terminal before it exists): `ATZ`, `ATE1`, `ATI`, `ATRV`, `ATDP`, `ATSP0` then `0100`, `0902`, a multi-PID request, and a deliberately wrong `ATSP3`. Compare each reply with the conventions in `docs/DECISIONS.md` and fix the simulator, not the parser, where they differ.
- **Measure the adapter's real round trip** with and without the response-count digit and with a multi-PID request, and compare with the 80 ms +/- 40 ms and 200 ms the simulator assumes.
- **Check how many ECUs answer `0100`** on the real car, and whether it answers multi-PID requests.
- **Compare the simulator's fuel figures with a real fill-up,** and tune the profile from real PID 5E, MAF and MAP readings.

## Next: phase 2, the OBD stack on the simulator (tag `v0.1.0-sim`)

The ELM layer, the PID decoders, supported-PID discovery, the poller with batching, `VehicleState` with smoothing, and the layer 1 and layer 3 connection tests for `adapter_flaky`, `minimal_old_car` and `dtc_present` (CLAUDE.md 8 and 13).

What it will meet, because the simulator already does it:

- A clone that ignores `ATAT`, so every request without a response-count digit costs the whole 200 ms timeout.
- A lost first command, a missing prompt, garbage bytes, random `NO DATA`, and a link that drops and comes back.
- `SEARCHING...` taking seconds before the first answer.
- Multi-frame replies for multi-PID requests and for Mode 03 with three or more codes.
- An ECU that goes quiet with the ignition off, with the session still open.
- The ELM layer must wait for each prompt: `SimTransport.overlappedCommands` counts the times it did not.
- `SimTransport` delivers synchronously, and real transports will not: the layer has to work with either.

# TapeDash

TapeDash turns an old Android phone into a car dashboard, a windshield HUD and a trip computer that shows where the money goes. It runs off a cheap ELM327 OBD-II adapter.

The whole idea: buy an ELM327, plug it into the OBD port, stick an old phone to the dash with double-sided tape, and drive.

- **A dashboard built like an instrument, not an app.** Tapes, a tach arc, detented numerals, a shift horizon. See [DESIGN.md](DESIGN.md).
- **A trip computer for your wallet.** ₹ per trip, per km, and what idling cost you.
- **A gentle driving coach.** It stays quiet while you drive and speaks only when the car is stopped.

## Status

Pre-alpha. **Phases 0 (foundation), 1 (the simulator), 2 (the OBD stack on the simulator) and 3a (the design system) are done**; the cockpit and HUD are next. There is no Drive page yet, but the design system is real and running: the app boots onto the void canvas with a dev button into the Design Lab, a gallery of the components built so far (rolling numerals in Saira and as VFD seven-segments, the chamfer button, toggle, segmented selector, slider, list row, the 27-glyph icon set) in every livery and mode, tried on a real Android 7.0 emulator. See [docs/design-review/phase-3a/](docs/design-review/phase-3a/) for screenshots and what was and wasn't verified. Nothing has been tried on a real car, and nothing has been checked against a real ELM327 adapter. The plan is to build and test everything against a built-in vehicle simulator first, and to connect real hardware only after every simulator test passes. The roadmap is in [CLAUDE.md](CLAUDE.md) section 13.

The simulator is a physical car, a scripted driver, an ELM327 adapter that prints byte-accurate text, a GPS, and a set of adapter faults, all pure Dart. `dart run tool/sim_server.dart` serves it over TCP, and `dart run tool/record_sim.dart` records a drive as a replayable session log.

On top of it sits the OBD stack, also pure Dart: an ELM327 client and start-up, PID decoders, a poller with tiers and batching, fault codes, a session that reconnects, and a vehicle state that checks and smooths what it reads. In tests it reads a whole simulated drive in seconds and compares the result with the simulator's ground truth.

The design system turns that data into an instrument: tokens for every colour, spring and typeface (DESIGN.md 4–5); a motion core built on one shared vsync clock, so numerals roll with a detented mechanical feel and nothing snaps or jumps; a glyph atlas and a seven-segment renderer for the VFD livery, both drawn with batched `drawAtlas` calls rather than per-frame text layout; and a fidelity system that picks and governs how much of it a phone can afford. All of it lives in the Design Lab before it composes into a real screen.

## Principles

- **Strictly offline.** No cloud, accounts, analytics, ads or price lookups. Fuel prices are entered by you. The only network use is a local WiFi ELM327 adapter, and that is limited to private addresses.
- **Old phones first.** Targets a 2 GB RAM, 32-bit ARM phone on Android 7.0 with a 720p screen.
- **Open source, F-Droid compatible.** No Google Play Services, Firebase or proprietary SDKs.
- **Honest numbers.** Fuel and money figures are estimates and are labelled as such.

## Safety

TapeDash is an aid, not a certified instrument. Set it up while parked. It is designed so that nothing needs your attention while you drive, but you remain responsible for driving safely.

## Documents

- [CLAUDE.md](CLAUDE.md): architecture, data, offline guarantees, safety, performance budgets and the roadmap.
- [DESIGN.md](DESIGN.md): the visual, motion and interaction spec.
- [docs/STATUS.md](docs/STATUS.md): where the project is, and what has and has not been verified.
- [docs/DEV_SETUP.md](docs/DEV_SETUP.md): toolchain, building, and running on emulators and phones.
- [docs/DECISIONS.md](docs/DECISIONS.md): the choices made so far, and why.
- [docs/design-review/](docs/design-review/): what each UI phase looked like, with screenshots, and what was and wasn't verified (CLAUDE.md 1).

## Building

Android only. You need the Flutter stable SDK and an Android SDK.

```
flutter pub get
tool/verify.sh
```

`tool/verify.sh` is the gate for every commit: a format check, `flutter analyze`, `flutter test` and `tool/check_offline.sh`, which fails if the app could reach the network or pulls in Play Services or Firebase. Golden tests run on Linux CI only, so on macOS the script skips them.

## License

Apache License 2.0. See [LICENSE](LICENSE).

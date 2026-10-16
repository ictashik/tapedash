# Handoff

Updated 2026-09-30, at the end of phase 6, where CLAUDE.md 11 says to stop. Read this first, then `CLAUDE.md` and `DESIGN.md` in full (both are binding), then `docs/HARDWARE_HANDOFF.md` (what the human does next) and `docs/STATUS.md` (what exists and what is unverified).

## Where things stand

- **Phases 0 to 6 are done, on the simulator.** The app has a cold open, a demo drive, a connect flow for WiFi, Bluetooth Classic and BLE ELM327s, the five Drive clusters and the HUD, trips and money, the coach, Review with the Debrief, Coach, History, Garage, Diagnostics, and a display that follows the light and the heat.
- **Nothing has met a real phone, adapter or car.** The three Kotlin channels compile and have never run; the WiFi transport has only talked to `tool/sim_server.dart`. Do not report any of it as working on hardware.
- HEAD is on `main`; the tree was clean after the last commit. **The repo is public at github.com/ictashik/tapedash (pushed 2026-10-16); no tags exist** (suggested ones are in `docs/STATUS.md`). `./tool/verify.sh` is green: about 2,900 tests, format, analyze, the offline check.
- The human's standing instructions: phases 4 to 6 ran back to back with **no design review packages and no screenshot folders** (CLAUDE.md 13's note); they test on a real phone and car after phase 6 and report back. **The next session starts from their report.**

## What the next session does (CLAUDE.md 11, phase 7)

From the human's first real drives, in this order:

1. Put the recordings in `recordings/real/` and write a replay test for each (`ReplayTransport`, `recordings/README.md`).
2. Tune the matching simulator profile to real behaviour (latency, supported PIDs, RPM behaviour).
3. Tune the smoothing pipeline's lead compensation against the real latency (DESIGN.md 5.2).
4. Fix transport problems found, with a regression test for each. The likeliest: **BLE** (the characteristic guesses in `BleChannel.kt`), **Bluetooth Classic** (the three-socket fallback, pairing), and the Android 12+ permission flow.
5. Compare estimated fuel against their first full-tank fill-ups (`FuelLedger`, the calibration).
6. Then phase 7's list: phone-temperature protection verified, the fidelity governor tuned on real devices (`DisplayController`), polish of the signature moments, the optional offline map, F-Droid metadata, store screenshots, the release checklist and a final design review package.

Also owed and not built (all in `docs/STATUS.md`): currency and units in Garage, shift-light settings, CSV export (needs a native file picker), the licences screen with a QR code, live layout previews in the connect flow's last step, the PID matrix pulse, the Money Tape's ₹5 and ₹10 compaction, the ₹ shared-element flight, and phase 3b's five unanswered design questions.

## The map

- `lib/obd/transport/`: `wifi_transport.dart` (the only socket code; `NetworkGuard`), `native_link.dart` and `native_link_transport.dart` (both radios), `sim_transport.dart`, `replay_transport.dart`, `recording_transport.dart`, `session_log.dart`, `session_sink.dart`.
- `lib/platform/`: the Dart sides of the Kotlin channels (`adapter_radio.dart` for both Bluetooths, `native_location_source.dart`, `device_channel.dart`), `file_session_sink.dart`. Kotlin is in `android/app/src/main/kotlin/io/github/ictashik/tapedash/`.
- `lib/app/`: `app.dart` (theme, onboarding, connect flow, choosing the drive), `drive_shell.dart` (the driving surface), `live_drive.dart` and `demo_drive.dart` (both `DriveFeed`), `app_services.dart` (settings, adapters, money, trips), `display_controller.dart` (light, brightness, heat, tier), `radio_transport_factory.dart`.
- `lib/ui/pages/`: `review`, `coach`, `history`, `garage`, `diagnostics`, `money`, `pitstop`, `drive`, `strip`. `lib/ui/onboarding/connect_flow.dart`. `lib/ui/dev/debug_overlay.dart` (long-press).

## Traps that cost time, so they need not again

- **`git checkout <file>` throws away uncommitted work.** It happened once (the whole shell wiring of a phase, recovered by replaying patch scripts from the session transcript). Remove a debug line with a targeted edit, and commit in small pieces (there is a memory note).
- **`ManualMotionClock.tick(dt)` counts at most 50 ms.** A test that steps `tick(0.1)` runs at half speed; use `motion.advance(Duration)` (1/60 s steps).
- **`TheStrip` and the Drive reel mount the page below and the page above the position** (`floor` and `ceil`), not the floored one: flooring blanked the page swiped towards and tore down a page the spring overshot. Two tests fail on the old rule.
- **A horizontal drag inside a `ListView` needs several small moves in a test**: the first move only decides which way the drag goes. A single `moveBy` does nothing.
- **A `ListView` reuses its scroll state at the same place in the tree.** A picker opened over a scrolled list started scrolled; give it its own key.
- **`dart format` reflows code, so exact-string patch scripts fail silently** (`str.replace` finds nothing). Assert the anchor exists in the script, or re-read the file after formatting.
- **`flutter test` cannot await real timers or platform futures inside `testWidgets`** without `tester.runAsync`; `pump` flushes microtasks only. Fakes whose streams cancel through a `Future` are safer not awaited.
- **Do not edit `lib/` or `test/` while `./tool/verify.sh` is running** (it compiles as it goes). Poll its log for `verify: all green` or `Some tests failed`; a background `until grep` loop works; a foreground `sleep` is blocked.
- The architecture test (`test/unit/architecture_test.dart`) forbids `lib/ui` importing anything under `obd/` with `transport` in its path, and the pure directories importing Flutter or real time. The design lint (`test/design/design_lint_test.dart`) forbids Material widgets and raw colours, text styles, durations and springs under `lib/ui` outside `tokens/`.
- **Numerals roll:** a static parked figure must be rounded to the precision it is shown at (`RollUpSource`), or it rests part-way through a digit (DESIGN.md 5.6).
- The mistakes and gotchas of this Mac (zsh, no `timeout`, stray dart servers, `nc` and CR) are in the memory notes.

## How the human works with me

They give a short instruction and expect the phase's work done, tested and committed, with a plain statement of what was and was not verified. They are watching progress through the reports. They want commits in small, coherent pieces with Conventional Commit messages and no attribution lines. They do not want screenshot folders or design review packages for phases 4 to 6.

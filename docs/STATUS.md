# Status

Updated 2026-09-26, at the end of phase 0. Phases are in CLAUDE.md 13.

## Where we are

| Phase | State |
|---|---|
| 0. Foundation | **Done** |
| 1. Simulator | Next |
| 2. OBD stack on the simulator (tag `v0.1.0-sim`) | Not started |
| 3a to 7 | Not started |

No tag is suggested for phase 0: the roadmap's first tag is `v0.1.0-sim`, after phase 2. If a marker is wanted anyway, `v0.0.1-foundation` fits.

## Phase 0: what exists

The app itself is one `void` canvas in landscape with the system bars hidden. The foundations under it:

| Piece | Where | Checked by |
|---|---|---|
| Android-only Flutter project: minSdk 24, targetSdk 36, landscape in both directions, `void` launch window and splash, no permissions, Auto Backup off | `android/`, `lib/app/` | 10 tests (`launch_theme_test`, the app shell), `app_launch_test` on two emulators, screenshots |
| `Clock`, `Scheduler`, `FakeClock`: injected time, a simulated 30 minutes of 50 ms ticks in well under a second | `lib/core/` | 45 unit tests, mutation-checked |
| Units and formatting: unit conversions, Indian digit grouping, `−₹24`, no negative zero, no false precision, a dash for missing values | `lib/core/` | 104 unit tests, mutation-checked |
| Layering and injected-time rules on `lib/` | `test/unit/architecture_test.dart` | 22 tests, including fixture trees that prove the scanner detects violations |
| `tool/check_offline.sh`: banned packages, HTTP clients and sockets, manifest permissions, Play Services and Firebase on the Gradle classpath | `tool/` | 56 fixture tests, and mutation-tested against a real Play Services and Firebase dependency |
| `tool/verify.sh`, the pre-commit gate: format, analyze, tests, offline check | `tool/` | run before every commit |
| `tool/check_apk_size.sh`: under 20 MB per ABI, and both shipped ABIs present | `tool/` | 9 fixture tests |
| CI workflow | `.github/workflows/ci.yml` | **not run on GitHub**, see below |
| `DeviceFeatures` and `DeviceChannel`: keep screen on, immersive mode, brightness, battery temperature, light and acceleration sensors | `lib/platform/`, `DeviceChannel.kt` | 38 unit tests on mocked channels and fakes (including startup), and 9 integration tests on two emulators |

Numbers: 284 unit and widget tests, 10 integration tests. An empty release build is 11.0 MB (armeabi-v7a) and 13.9 MB (arm64-v8a), about 6 MB of headroom under the 20 MB budget on arm64 before fonts. Toolchain: Flutter 3.44.1 stable, Dart 3.12.1, Android Gradle Plugin 9.0.1, Gradle 9.1.0, Kotlin 2.3.20, JDK 17.

The CI steps were also run by hand on a fresh clone of the repository: `flutter pub get --enforce-lockfile`, a release build of both ABIs, `tool/verify.sh --strict` and `tool/check_apk_size.sh`. All passed.

## What has not been verified

- **CI on GitHub.** There is no remote yet. The workflow parses as YAML and every script it calls has been run, but the workflow itself has never executed.
- **Any real phone.** All device checks ran on emulators, which have no real sensors. So the light sensor, the accelerometer axes on a dash-mounted phone, the battery temperature reading and the brightness floor are unverified on hardware, as CLAUDE.md 11 expects. The axis mapping was checked by rotating an emulated phone: with the display following the phone into either landscape, gravity reads +9.8 on screen y.
- **The launch flash.** It could not be measured. With the launch colour set to solid red, no red frame shows up on an Android 7.0 or an Android 16 emulator, so a recording cannot tell a white flash from none. The launch resources are protected by a unit test instead (the Android colour equals the Dart token, and nothing is white). It needs a look on a real phone, most of all on Android 11 or older, where the launch window is what the user sees first.
- **Performance.** There is no reference device and nothing animates yet. The Android 7.0 emulator (720x1280, 2 GB) is a good proxy for the OS and a poor one for CPU and GPU speed.
- **Goldens.** There are none yet. They start with the design system in phase 3a.

## Known issues and notes

- **Android 4.4 to 10 shows a one-time "Viewing full screen" notice** the first time the app goes immersive, and the user taps "Got it" once. The OS draws it and it cannot be suppressed. Expect it on old phones, and consider a line in onboarding.
- **The launcher and Android 12+ splash icons are still Flutter's default.** The brand icon is phase 3b.
- **The application ID `io.github.ictashik.tapedash` is unconfirmed.** It assumes the GitHub handle. It is cheap to rename now and effectively impossible after a release.
- **There is no NOTICE file or copyright line**, only the Apache-2.0 LICENSE.
- **Release builds are signed with the debug key** (the Flutter template's default). There is no release keystore yet.

## For the hardware handoff

To copy into `docs/HARDWARE_HANDOFF.md` when phase 6 writes it:

- Record a cold start on the real phone with `adb shell screenrecord` and check that no frame is bright before the first Flutter frame.
- Check ambient light against real conditions, to tune the Daylight and Night thresholds (DESIGN.md 4.4).
- Check the accelerometer on the mounted phone, both landscape directions, and work out how much the mount's tilt has to be calibrated out.
- Check the battery temperature is reported at all, and in degrees Celsius.
- Check brightness at the floor on a real panel, and that `void` looks right on a cheap LCD (DESIGN.md 4.1).
- Check immersive mode, and what the OS shows on the first launch.

## Next: phase 1, the simulator

The vehicle model with ground truth, the profiles and scenarios, the ELM327 simulator with quirks, `SimTransport` and `SimLocationSource`, `tool/sim_server.dart` and `tool/record_sim.dart`, and the layer 2 tests (CLAUDE.md 7 and 13). It is pure Dart, so `tool/` can run it without Flutter.

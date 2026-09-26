# Decisions

A short running log of choices and the reasons for them, newest last. It includes design decisions where DESIGN.md is silent, and every dependency (license and reason, per CLAUDE.md 5).

## Project

- **License: Apache-2.0.** The user's choice, and the one CLAUDE.md recommends. It is permissive, has a patent grant and is accepted by F-Droid. Not GPL, which would bind the whole app.
- **Application ID: `io.github.ictashik.tapedash`.** The `io.github.<user>.<repo>` form is the usual one for an open-source app without its own domain. The GitHub handle is taken from the git identity's noreply address and has not been confirmed, and there is no remote yet. Renaming is a few lines until the first release and effectively impossible after it, so confirm it before then.
- **No remote.** The repository is local only. Nothing is pushed without the user's explicit say-so (CLAUDE.md 2).

## Toolchain

- **Flutter 3.44.1 stable, Dart 3.12.1.** Flutter stable only (CLAUDE.md 3). Android Gradle Plugin 9.0.1, Kotlin 2.3.20 and Gradle 9.1.0 come from that Flutter version's template. Needs JDK 17.
- **minSdk 24 and targetSdk 36 are Flutter's own defaults** (`flutter.minSdkVersion`, `flutter.targetSdkVersion`). Flutter's default minSdk is already Android 7.0, so there is nothing to override. We never raise it for convenience.
- **CI builds only `armeabi-v7a` and `arm64-v8a`**, the two ABIs we ship. A plain `--split-per-abi` release build also produces an x86_64 APK we do not want.

## Dependencies

| Package | License | Kind | Reason |
|---|---|---|---|
| `flutter_lints` ^6.0.0 | BSD-3-Clause | dev only | The Flutter team's analyzer rule set. Not shipped. |
| `integration_test` (Flutter SDK) | BSD-3-Clause | dev only | Runs tests on an emulator or phone (CLAUDE.md 10, layer 5). It brings dev-only tooling that is never linked into the app: `flutter_driver` and `fuchsia_remote_debug_protocol` (Flutter SDK, BSD-3-Clause), `file`, `platform`, `process`, `sync_http` and `web` (BSD-3-Clause), and `webdriver` (Apache-2.0). |

## Android

- **Launch window is `void`, in one theme only.** TapeDash is always dark (DESIGN.md 4.1), so there is no `values-night`. The launch drawable, `NormalTheme` and the Android 12+ splash background are all the `tapedash_void` colour, and `test/unit/platform/launch_theme_test.dart` fails if any of them drifts from `TapeColors.voidColor` or turns white. The default Flutter template used white and `?android:colorBackground`, which is what causes a white flash.
- **`android:allowBackup="false"`.** Android Auto Backup uploads app data to the user's Google account, and TapeDash is strictly offline. Trips leave the phone only through the CSV export.
- **Landscape comes from the manifest alone** (`sensorLandscape`, both directions). It works even with the phone's rotation lock on and avoids a portrait frame at launch, so there is no `SystemChrome` orientation call.
- **No permissions are declared yet.** Each one is added together with the feature that needs it, and must be on the allowed list in CLAUDE.md 4.
- **`uses-material-design: false`.** Material widgets and icons are banned (DESIGN.md 13.1), so the Material icon font is not bundled.

## Code

- **`TapeColors.voidColor`**, not `TapeColors.void`: `void` is a reserved word in Dart. Other tokens keep the DESIGN.md name with dots removed (`carbon900`, `etchStrong`) when they arrive in phase 3a.
- **`lib/main.dart` uses `WidgetsApp`**, not `MaterialApp`, so no Material code is linked in at all.

## Device features

- **`DeviceFeatures` is an interface**, with `DeviceChannel` (platform channels to `DeviceChannel.kt`) and `FakeDeviceFeatures` behind it. Code that needs the screen, battery or sensors takes the interface, so Daylight and Night switching and the phone-health logic can be tested headlessly.
- **One shared stream per sensor.** A Flutter `EventChannel` has one native handler, so a second `receiveBroadcastStream()` would silently take the sensor from the first listener. The streams are built once, and the sensor is only registered while something listens.
- **Brightness has a floor.** Dart clamps the level to 0..1 and rejects NaN, and the Android side never goes below 0.01, since some phones treat 0 as backlight off, which would blank the dash. The design floors (12% at night, 20% for the HUD) are policy for the brightness controller and are not enforced here.
- **Accelerometer axes are remapped in Dart.** Android reports the sensor in the phone's own axes, not the screen's. The Android side sends `[x, y, z, displayRotation]` untouched, and Dart turns it into screen axes (x right, y up the screen, z out of it), so the mapping is unit-tested and CI covers it. It matters because the app is landscape-only, so a phone held upright is still drawn rotated. Checked on emulators by rotating the emulated phone: with the display following the phone into either landscape, gravity reads +9.8 on screen y whichever rotation the OS reports.
- **Immersive mode** uses `WindowInsetsController` on Android 11+ and the legacy `systemUiVisibility` flags below, and is re-applied when the window regains focus. On Android 4.4 to 10 the OS shows a one-time "Viewing full screen" notice the first time an app goes immersive. It cannot be suppressed, and one tap on "Got it" dismisses it for good. Expect it on old phones.
- **Startup never waits on the window calls.** If hiding the bars or keeping the screen on fails, that is logged and the app starts anyway. Other errors, which would be bugs, are not swallowed.
- **Launch flash cannot be measured on emulators.** With the launch colour set to solid red, no red frame appears on either an Android 7.0 or an Android 16 emulator, so an emulator recording cannot show a white flash, broken or fixed. The launch resources are guarded by `launch_theme_test.dart` instead, and a check on a real phone is part of the hardware handoff.

## Tooling

- **`tool/verify.sh` is the pre-commit gate:** `dart format` check, `flutter analyze`, `flutter test` and `tool/check_offline.sh`. On macOS and Windows golden tests are excluded (`--exclude-tags golden`), since they are generated on CI Linux only (CLAUDE.md 10). A format check is added to the three checks in CLAUDE.md 2 so diffs carry no formatting noise.
- **`tool/check_offline.sh` goes slightly beyond CLAUDE.md 4:**
  - `url_launcher` is banned outright, not just its web-opening use. The About page shows the project URL as text plus a QR code, so nothing needs it.
  - `Image.network`, `NetworkImage` and `NetworkAssetBundle` are treated like an HTTP client, because they use one internally.
  - Sockets are confined to `lib/obd/transport/wifi_transport.dart`, as CLAUDE.md 4 states, and the script enforces it.
  - Banned Gradle groups are `com.google.android.gms`, `com.google.firebase`, `com.google.android.play` and a few other proprietary SDKs. `com.google.guava` (small Guava stubs pulled in by androidx) is fine.
  - The Gradle step is skipped locally when nothing that changes the dependency tree has changed since the last pass, tracked by a stamp in `build/`. `--strict` (CI) never skips.
  - The script has its own fixture tests (`test/unit/tool/check_offline_test.dart`), so a broken check cannot pass silently.

## CI

- **`.github/workflows/ci.yml`:** build the release APKs, then `tool/verify.sh --strict`, then `tool/check_apk_size.sh`. The build comes first because the strict offline check reads the merged release manifest it produces. It has not been run on GitHub yet, since there is no remote.
- **Actions are pinned to full commit SHAs** with the version in a comment, and the Flutter version (3.44.1) and runner image (`ubuntu-24.04`) are pinned too. A moved tag or a new runner image cannot change what CI runs or the golden images it produces. Bump them on purpose. The actions are `actions/checkout`, `actions/setup-java` and `subosito/flutter-action` (MIT, third party, used for the SDK cache).
- **`flutter pub get --enforce-lockfile`** fails CI if `pubspec.lock` is out of date, so the lockfile the offline check reads is the one that builds.
- **APK budget: under 20 MB per ABI**, checked by `tool/check_apk_size.sh`, which also fails if either `armeabi-v7a` or `arm64-v8a` is missing. "MB" is 1,000,000 bytes, matching the sizes the Flutter tool prints, which is also the stricter reading. An empty app is 11.0 MB (armeabi-v7a) and 13.9 MB (arm64-v8a), mostly the Flutter engine, so fonts and assets have about 6 MB of headroom on arm64.

## Simulator: the car (phase 1)

- **The physics is a Willans-line engine, not a lookup table.** Throttle sets manifold pressure through an orifice, air follows the speed-density formula of CLAUDE.md 8.4, fuel is air over the air-fuel ratio, and torque is the fuel's energy less pumping, friction and accessory losses. So MAF, MAP, load and fuel rate are consistent with each other by construction, which is what the fuel estimators have to be tested against. A petrol engine controls air first, and a diesel controls fuel first with a smoke limit. Fuel is cut on the overrun above 1,500 rpm while the air keeps flowing, so MAF stays non-zero with no fuel burnt, which is a trap for estimators.
- **Two powertrains.** A CVT, where engine speed follows the pedal more than road speed, and a manual, where a virtual driver changes gear with hysteresis and a dwell so the gearbox cannot hunt.
- **The physics does not depend on the seed.** Each part draws from its own forked stream, and the seed only changes the reported noise (idle wobble, sensor noise, GPS error). Two runs with different seeds burn exactly the same fuel, so a test can compare any two of them, and turning noise on can never move the ground truth.
- **Ground truth is exact and kept apart from what the ECU reports.** Cumulative fuel, distance, engine-on time, idle time and idle fuel (idle is under 2 km/h with the engine running, CLAUDE.md 8.7), and a log of every scripted hard-acceleration and hard-braking event. It is recomputed independently from the snapshots in the tests.
- **Deviations from the wording of CLAUDE.md 7.1, on purpose.**
  - Braking is 7.5 m/s2 plus drag and engine braking, about 8 m/s2 at most, and grip limits a launch to 0.36 g. The spec says "up to about 8".
  - Coolant reaches 85 C after 8 minutes of city driving and is then held at about 90 C by the thermostat, as specified, but idling warms an engine far more slowly, because a warm-up needs load: `cold_start_idle` is at 51 C after its 5 minutes. The spec's "8 to 10 minutes" holds for a drive, not for idling.
- **A scripted driver inverts the model.** It asks the vehicle model which pedal gives a wanted acceleration (`pedalForAcceleration`), so a speed is held smoothly and a stop is reached without overshoot. These what-if questions must never change the car, and must never trigger a gear change: an early version's what-if returned the clutch-out acceleration and made the driver slam the pedal to 1 and kick down for real. They are tested to change nothing.
- **Hard driving has to survive the app's own smoothing.** The coach smooths speed over about a second before it looks at acceleration (CLAUDE.md 8.8), which hides an acceleration that only just clears its threshold or does not last. A first version of the hard style passed a peak-over-threshold check and the app's detector found 6 of 12 scripted events. The hard style now asks for 3.6 and 5.0 m/s2 and the aggressive route runs at 64 km/h, and a test applies the app's rule to whole km/h samples at 10 Hz. The phase 5 requirement that detected counts match the scripted ones depends on this.
- **`eco_city` is 30% cheaper than `aggressive_city`** over the same 4.5 km (0.372 L against 0.535 L), with the same waits at the signals, so the saving is in the driving. The spec asks for at least 15%.
- **Profiles are approximations, not data from any real car** (CLAUDE.md 7.2). PID 01 is in none of the PID lists because every OBD-II ECU has it; the simulator always adds it.

## Simulator: the adapter (phase 1)

- **The byte format comes from the ELM327 datasheet, and the golden fixtures are written by hand from it.** The datasheet's own examples are the fixtures: `0100` giving `41 00 BE 1F B8 10`, the VIN as `014` and `0: 49 02 01 31 44 34`, and `01 04 05 0B 0C` as `00A` with the last line padded with zeros. All sixteen combinations of echo, linefeeds, spaces and headers are written out as literal strings, so the simulator is checked against the spec and not against itself.
- **The datasheet is written for a person at a terminal, so it leaves some byte-level conventions open.** These follow what real adapters are known to send, and **none of them has been checked against hardware**:
  - every reply ends with a blank line and then `>`, so `OK` is `OK\r\r>` (or `OK\r\n\r\n>` with linefeeds on);
  - after `ATZ` or `ATWS` the banner is preceded by two `\r`;
  - with spaces on, a data line ends with a space, as in `41 0C 1A F8 \r`;
  - a multi-frame line is `0:` and a space, then the bytes;
  - a lone carriage return repeats the last command;
  - `ATDP` names the CAN protocols as `ISO 15765-4 (CAN 11/500)`, with `AUTO, ` in front when it may search;
  - what the adapter prints for a fixed protocol the car does not speak: `BUS INIT: ...ERROR` for the K-line protocols, `NO DATA` for J1850 and 29-bit CAN, `CAN ERROR` for the other bit rates.
  The app's parser has to be tolerant of all of these anyway (CLAUDE.md 8.1), and the first real adapter session should be compared against them (see the hardware handoff notes in STATUS.md).
- **Behaviour was cross-checked against Ircama's ELM327-emulator by reading its source.** That project is CC BY-NC-SA 4.0, which is non-commercial and share-alike and so cannot be mixed into Apache-2.0 code. It was read for how real adapters are seen to behave, and nothing from it is in this repository, as code, text or data, and it is not a dependency. The optional cross-check in CLAUDE.md 7.5, running our parser against its output over TCP, is for phase 2 and needs the same care.
- **Adapter timing is an assumption, because the datasheet gives no figures:** a reset takes 0.8 s, finding a protocol 2.4 s (0.4 s if the stored one is right), an unreachable car 5 s to give up, the ECU answers in 20 ms, and adaptive timing waits 40 ms (AT1) or 25 ms (AT2) after the answer. Without adaptive timing, or on a clone that ignores it, the adapter waits its whole `ATST` timeout (200 ms) unless the request ends with a response-count digit. On the Bluetooth clone preset that makes a request without the digit about 300 ms and one with it about 100 ms, so three fast-tier PIDs asked one at a time without the digit are about 1 Hz. It is the reason the ELM layer should add the digit, or batch.
- **`AdapterQuirks.latency` is the link's round trip, and the adapter's own time comes on top of it.** The car is asked in the middle of the round trip, so a value is as old as half the latency by the time it arrives, and the app's timestamping at the midpoint of a request is exactly right. `Elm327Device` does this; `Elm327Simulator` itself has no notion of the link.
- **Only ISO 15765-4 CAN (11-bit, 500 kbaud, protocol 6) is simulated,** with one ECU at 7E8. Other protocols can be selected, but the car does not speak them. Real cars often have two ECUs answering the same request (engine and transmission), and the simulator does not do that yet: the phase 2 parser must handle it, and a second ECU is a small addition when its tests need it.
- **The adapter keeps its settings across app connections and reconnects,** as a real one does while it stays plugged in. An `ATSP` protocol is stored, an `ATSP0` is not, and `ATSP00` erases it, as the datasheet describes.
- **Concurrent commands are queued, not interrupted.** A real ELM327 stops what it is doing and prints `STOPPED` when a character arrives during an OBD request, and discards that character. The simulator does not model it: it counts commands that arrive while another is being answered (`overlappedCommands`), so the phase 2 tests can assert that the ELM layer waits for the prompt.
- **Quirks:** drop the first command after a link opens (echo included), ignore `ATAT`, refuse multi-PID requests with `?`, a rate of `NO DATA`, a rate of missing prompts, and a rate of garbage bytes, which are control characters and high bytes that cannot be mistaken for hex.

## Simulator: transports, GPS, recordings and tools (phase 1)

- **`SimTransport` delivers synchronously,** from the scheduled task that produces each piece. A listener then reads the clock at the true moment the piece arrived, which the smoothing pipeline's timestamping needs, and a whole drive can be run inside one `FakeClock.advance`. Real transports are asynchronous; the ELM layer must not depend on either.
- **Link faults come from the scenario and are judged in the car's own time,** so a restarted drive drops the link again at the same point. While the link is out, connecting fails after the connect delay with `unreachable`, and the drop itself is `lost`.
- **Simulated GPS error is a wander, not jitter.** The error of each fix carries over 85% into the next, and its variance follows the conditions: a spell in a street of tall buildings (about one a couple of minutes, a few seconds long) grows it over a few fixes and it dies away afterwards. The accuracy reported is honest: about two fixes in three land within it, which is how a real receiver reports it, so a filter that weighs fixes by accuracy can be tested against this. Standing still, there is no heading.
- **A session log is a text file, one line to an entry:** the time to the millisecond, `>` for sent, `<` for received or `!` for a change of link state, and the text escaped so it stays on one line and reads back exactly (a trailing space is significant). It has a `# tapedash-session v1` first line and `#` header lines for what was recorded. `RecordingTransport` wraps any transport, so it also records a real adapter in a real car after the hardware handoff.
- **Simulator recordings are not kept in git.** `tool/record_sim.dart` writes the same bytes every time for the same options, in about two seconds for all ten scenarios, and they are 0.2 to 2.6 MB each. Real recordings, which cannot be regenerated, go in `recordings/real/`. Until phase 2 there is no OBD stack, so a small scripted client stands in for it: it starts the adapter up, reads the PID support, reads the fault codes, and polls in tiers, one command at a time, and it retries a lost start-up and reconnects after a dropped link. It never reads an answer.
- **`tool/sim_server.dart` listens on 127.0.0.1 unless told otherwise.** An Android emulator reaches the host's loopback as 10.0.2.2, so that is all it needs, and a phone on USB can use `adb reverse`. Serving a phone over the network needs `--host 0.0.0.0` on purpose. It serves one app at a time, as a WiFi adapter does, and the newest connection takes over. It holds a new socket until the transport is up: an app that writes the moment it connects had its first command dropped, which only a real socket run showed, and the test for it fails without the fix. The drive loops by default, as Demo Mode will.
- **The tools run under plain `dart`.** `dart run tool/sim_server.dart` works in this package once `flutter pub get` has run, because everything under `lib/` that they import is free of Flutter.

## Layering (phase 1 additions)

- **`core/` imports nothing else and `sim/` only `core/`,** so nothing the simulator depends on can depend on it, and it stays reusable from `tool/`. CLAUDE.md 6 does not say this; it follows from the simulator being pure Dart and first-class. `SimTransport` and `SimLocationSource` sit in `obd/transport/` and `location/`, one level up, where they belong.
- **The pure directories may not import `ui/`, `app/` or `platform/`,** and `ui/` may not import a transport or sqflite (CLAUDE.md 6, "it never touches transports or the database directly"). The architecture test resolves relative imports as well as package ones.

## Tooling (phase 1 additions)

- **`dart format` rewrites a `\u` escape in a Dart source file into the character itself, including inside a raw string,** which changes what the string means. The session log tests build such characters from code units instead.

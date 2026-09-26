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

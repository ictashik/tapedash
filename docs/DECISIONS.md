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

## Android

- **Launch window is `void`, in one theme only.** TapeDash is always dark (DESIGN.md 4.1), so there is no `values-night`. The launch drawable, `NormalTheme` and the Android 12+ splash background are all the `tapedash_void` colour, and `test/unit/platform/launch_theme_test.dart` fails if any of them drifts from `TapeColors.voidColor` or turns white. The default Flutter template used white and `?android:colorBackground`, which is what causes a white flash.
- **`android:allowBackup="false"`.** Android Auto Backup uploads app data to the user's Google account, and TapeDash is strictly offline. Trips leave the phone only through the CSV export.
- **Landscape comes from the manifest alone** (`sensorLandscape`, both directions). It works even with the phone's rotation lock on and avoids a portrait frame at launch, so there is no `SystemChrome` orientation call.
- **No permissions are declared yet.** Each one is added together with the feature that needs it, and must be on the allowed list in CLAUDE.md 4.
- **`uses-material-design: false`.** Material widgets and icons are banned (DESIGN.md 13.1), so the Material icon font is not bundled.

## Code

- **`TapeColors.voidColor`**, not `TapeColors.void`: `void` is a reserved word in Dart. Other tokens keep the DESIGN.md name with dots removed (`carbon900`, `etchStrong`) when they arrive in phase 3a.
- **`lib/main.dart` uses `WidgetsApp`**, not `MaterialApp`, so no Material code is linked in at all.

## Tooling

- **`tool/verify.sh` is the pre-commit gate:** `dart format` check, `flutter analyze`, `flutter test` and `tool/check_offline.sh`. On macOS and Windows golden tests are excluded (`--exclude-tags golden`), since they are generated on CI Linux only (CLAUDE.md 10). A format check is added to the three checks in CLAUDE.md 2 so diffs carry no formatting noise.
- **`tool/check_offline.sh` goes slightly beyond CLAUDE.md 4:**
  - `url_launcher` is banned outright, not just its web-opening use. The About page shows the project URL as text plus a QR code, so nothing needs it.
  - `Image.network`, `NetworkImage` and `NetworkAssetBundle` are treated like an HTTP client, because they use one internally.
  - Sockets are confined to `lib/obd/transport/wifi_transport.dart`, as CLAUDE.md 4 states, and the script enforces it.
  - Banned Gradle groups are `com.google.android.gms`, `com.google.firebase`, `com.google.android.play` and a few other proprietary SDKs. `com.google.guava` (small Guava stubs pulled in by androidx) is fine.
  - The Gradle step is skipped locally when nothing that changes the dependency tree has changed since the last pass, tracked by a stamp in `build/`. `--strict` (CI) never skips.
  - The script has its own fixture tests (`test/unit/tool/check_offline_test.dart`), so a broken check cannot pass silently.

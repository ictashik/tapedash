# Development setup

## What you need

- **Flutter 3.44.1, stable channel.** CI pins this version. Use the stable channel only (CLAUDE.md 3).
- **JDK 17.** The Android Gradle Plugin needs it.
- **The Android SDK**, with `adb` on your `PATH`. Gradle installs the platform and NDK it needs on first build.
- A shell with `bash`, `sed`, `grep` and `awk`. The scripts in `tool/` run on the bash 3.2 that ships with macOS as well as on Linux.

## Every day

```
flutter pub get
tool/verify.sh
```

`tool/verify.sh` is the gate before every commit: a `dart format` check, `flutter analyze`, `flutter test`, and `tool/check_offline.sh`. Never commit a red build (CLAUDE.md 2). On macOS and Windows it skips golden tests (`--exclude-tags golden`), since goldens are generated on CI Linux only.

`tool/check_offline.sh` fails if the app could reach the network outside the WiFi transport or pulls in Play Services or Firebase. Its Gradle step is skipped locally while nothing that changes the dependency tree has changed, and `--strict` never skips it.

## Building the APKs

```
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
tool/check_offline.sh --strict
tool/check_apk_size.sh
```

Only the two ABIs we ship are built, and both must stay under 20 MB. Release builds are signed with the debug key for now. Never commit a keystore or `key.properties`; both are git-ignored.

## Emulators and devices (layer 5)

Tests in `integration_test/` run the real app on an emulator or a phone (CLAUDE.md 10). They complement the headless tests and do not replace them.

### Two AVDs are useful

1. **A current Android**, for example the "Medium Phone" image from Android Studio.
2. **A stand-in for the target device class**: Android 7.0 (the minimum, API 24), a 720p screen and 2 GB of RAM. It is a good proxy for the OS, including the legacy code paths that newer Android never runs, and a poor proxy for CPU and GPU speed.

```
sdkmanager "system-images;android-24;default;arm64-v8a"
echo no | avdmanager create avd -n Reference_API24 \
  -k "system-images;android-24;default;arm64-v8a" -d pixel
```

Then set these in `~/.android/avd/Reference_API24.avd/config.ini`:

```
hw.lcd.width=720
hw.lcd.height=1280
hw.lcd.density=320
hw.ramSize=2048
```

Those commands are for an Apple silicon Mac. On an Intel machine use the `x86_64` image. Boot one headless with:

```
emulator -avd Reference_API24 -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect
```

### Running the tests

```
flutter test integration_test/device_channel_test.dart -d emulator-5554
flutter test integration_test/app_launch_test.dart -d emulator-5554
```

Run the files one at a time. Running the whole directory sometimes fails on the first file with a `WebSocketChannelException`, or hangs, while the tool connects to the app.

### Useful commands

```
adb emu rotate                                    # turn the emulated phone 90 degrees clockwise
adb emu sensor set light 5000                     # ambient light in lux
adb emu sensor set acceleration 0:9.81:0          # accelerometer in m/s2, in the phone's own axes
adb emu sensor get acceleration                   # read a sensor's current value
adb shell settings put secure immersive_mode_confirmations confirmed   # Android 10 or older
```

The last command stops Android's one-time "Viewing full screen" notice from covering the screen. Without it, the app is dimmed behind a teal box on first launch.

The emulator console wants a space between the sensor name and its value (`set light 5000`, not `set light:5000`). A wrong form is rejected with "KO: Usage", which is easy to miss if you discard the output.

### Things that will trip you up

- A test run **uninstalls the app** when it finishes, and the APK it leaves in `build/` uses the test file as its entrypoint. Installing that APK by hand shows the splash screen forever. To see the real app, build it with `flutter build apk`.
- `adb shell screenrecord` fails on the Android 7.0 image (`Encoder failed`). A loop of `screencap` calls works there.
- **A launch flash cannot be seen on an emulator.** Even a solid red launch colour never shows up in a recording (see `docs/DECISIONS.md`). Check on a real phone.
- `adb install` on Android 7.0 does not accept `-q`.

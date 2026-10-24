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

`tool/verify.sh` is the gate before every commit: a `dart format` check, `flutter analyze`, `flutter test`, `tool/check_offline.sh`, and `tool/check_android_api.sh` (Android's lint, limited to calls and constants newer than API 24, the minimum: the navigation listener once named `Bitmap.Config.HARDWARE`, which is Android 8's, and that is an `Error` on Android 7). Never commit a red build (CLAUDE.md 2). On macOS and Windows it skips golden tests (`--exclude-tags golden`), since goldens are generated on CI Linux only.

`tool/check_offline.sh` fails if the app could reach the network outside the WiFi transport or pulls in Play Services or Firebase. Its Gradle step is skipped locally while nothing that changes the dependency tree has changed, and `--strict` never skips it.

## Building the APKs

```
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
tool/check_offline.sh --strict
tool/check_apk_size.sh
```

Only the two ABIs we ship are built, and both must stay under 20 MB. Release builds are signed with the debug key for now. Never commit a keystore or `key.properties`; both are git-ignored.

## The simulator tools

The simulator is plain Dart, so these run under `dart` once `flutter pub get` has been run.

```
dart run tool/sim_server.dart --scenario city_stop_go --profile petrol_cvt_map
dart run tool/sim_server.dart --list           # scenarios, profiles and adapter quirks
dart run tool/record_sim.dart --scenario city_stop_go
dart run tool/record_sim.dart --all            # all ten, in about ten seconds
```

- **`tool/sim_server.dart`** is the simulated car and its ELM327 adapter over TCP, in real time, for trying the real WiFi transport without hardware. It serves one app at a time and starts the drive over when it ends.
  - From an **Android emulator** the host is `10.0.2.2:35000`.
  - From a **phone on USB**, run `adb reverse tcp:35000 tcp:35000` and connect to `127.0.0.1:35000`.
  - It listens on `127.0.0.1` only. `--host 0.0.0.0` serves your network, which you only want on a network you trust.
  - `--verbose` prints every command and reply, `--quirks flaky` turns on a misbehaving clone, and `--seed` fixes the noise.
- **`tool/record_sim.dart`** writes a scenario as a session log in `recordings/sim/`: the raw ELM327 text between the app's own OBD stack and the adapter, with the time of each piece. It runs on a fake clock, so a 30-minute drive takes a moment, and the same options give the same file. Nothing in `recordings/sim/` is kept in git. See [recordings/README.md](../recordings/README.md) for the format and for replaying.

Both take `--help`. `nc` is enough to talk to the server by hand, as long as each command ends in a carriage return (`\r`), which is what an adapter waits for, and the connection stays open long enough for the answers:

```
(printf 'ATZ\rATE0\r0100\r'; sleep 5) | nc 127.0.0.1 35000
```

### Cross-checking against a third-party ELM327

`tool/crosscheck_emulator.dart` runs the OBD stack in real time over TCP against [Ircama's ELM327-emulator](https://github.com/Ircama/ELM327-emulator), to see that what the stack reads is not only what our own simulator prints. It is a separate process, and needs Python 3:

```
python3 -m venv /tmp/emu && /tmp/emu/bin/pip install ELM327-emulator
sleep 3000 | /tmp/emu/bin/python -m elm -n 35100 -s car &
dart run tool/crosscheck_emulator.dart --port 35100
pkill -f "elm -n 35100"
```

- The `sleep` keeps the emulator's input open. It serves TCP on 127.0.0.1. `-s engineoff` starts it with the engine off, to see the session wait for the ignition and probe once a second.
- The tool runs for 20 seconds (`--seconds`) and prints the adapter, its protocol and PIDs, the polling and the last value of each sensor. It exits 0 if it connected and read RPM and speed, and 1 if not.
- **The emulator is CC BY-NC-SA 4.0,** which cannot be mixed into Apache-2.0 code. Run it, and never copy from it. Keep the virtual environment outside the project, and out of git.
- It is not part of `tool/verify.sh` or CI. It needs the emulator installed and takes real time.

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

# These two talk to the simulator on your Mac, which the emulator reaches at 10.0.2.2:
dart run tool/sim_server.dart --port 35000 --scenario city_stop_go &
flutter test integration_test/adapters_test.dart -d emulator-5554
flutter test integration_test/connect_wifi_flow_test.dart -d emulator-5554
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

## A watch emulator

The watch's screens (DESIGN.md 16) can be seen and driven without a watch, on a Wear OS emulator, with the simulated car on your laptop as the adapter. The watch is Android 11 (API 30) on a Galaxy Watch4 Classic, so that is the image to use.

```
sdkmanager --install "system-images;android-30;android-wear;arm64-v8a"     # x86_64 on an Intel Mac
echo no | avdmanager create avd -n tapedash_watch -d wearos_large_round \
    -k "system-images;android-30;android-wear;arm64-v8a"
emulator -avd tapedash_watch -gpu host &

flutter build apk --debug --target-platform android-arm64                  # android-x64 on Intel
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell pm grant io.github.ictashik.tapedash android.permission.ACCESS_FINE_LOCATION

dart run tool/sim_server.dart --port 35000 --profile petrol_cvt_map --scenario city_stop_go &
dart run tool/demo_exchange.dart /tmp/demo.tdx.gz               # a setup that points at 10.0.2.2:35000
adb shell am start -n io.github.ictashik.tapedash/.MainActivity
tool/adb_exchange.sh push /tmp/demo.tdx.gz
tool/adb_exchange.sh import --apply                            # the watch now drives from the simulator
adb exec-out screencap -p > shot.png                           # the emulator's round mask is in the picture
```

A tap anywhere is the next face; a vertical swipe turns the reel and the menu's wheels. The emulator has no bezel (the *Rotary input* page of its extended controls sends one, if you want to try it). Changing a setup while the car is moving is deferred by design ("It waits until the car has stopped"): import it while the simulated car is still at its first idle, or use `--scenario cold_start_idle`. `tool/adb_exchange.sh export` pulls what the watch has recorded, and `dart run tool/tdx.dart info|check|csv` reads it.

On a real watch, turn on developer options and *Wireless debugging*, `adb pair` and `adb connect <ip>:<port>`, and give `-s <ip>:<port>` to `tool/adb_exchange.sh` and `adb`.


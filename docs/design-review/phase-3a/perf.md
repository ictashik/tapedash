# Phase 3a: performance

DESIGN.md 9.4 and CLAUDE.md 10 (layer 5) ask for frame timings per fidelity tier over a 2-minute demo drive, on the reference device (2016–2018, 2 GB RAM, Snapdragon 4xx-class, Android 7–8, 720p). **That capture belongs to phase 3b**: there is no Drive page and no live-data screen yet to drive for 2 minutes, only the Design Lab's static gallery. Nothing below should be read as that measurement — it is what could honestly be checked this phase, on the hardware that was available.

## What ran, and where

- **Emulator:** `Reference_API24`, Android 7.0 (API 24), arm64-v8a, 720×1280 @ 320 dpi, 2 GB RAM, `-gpu swiftshader_indirect` (software GL). This matches CLAUDE.md 10's reference device on OS version, RAM and resolution; it does **not** match it on CPU or GPU — SwiftShader on the host Mac's CPU is not a Snapdragon 4xx, in either direction, and `DEV_SETUP.md` already says as much for this AVD. No physical low-end phone was available this session.
- Built and installed: debug (`flutter build apk --debug`) for the Lab's dev button, and both `--split-per-abi --release` APKs for the size and offline checks.
- `flutter test integration_test/app_launch_test.dart -d emulator-5554` passed (two tests: launches onto the void canvas in landscape; the dev button opens the Lab and its three tabs cycle without an exception).

## What was seen, not measured

Real screenshots and a real interaction pass are in `screenshots/` and `video/`, taken on the emulator above, debug build:

- The cold-open void canvas with the dev button (`01`).
- The Lab's three tabs (`02`–`04`), all rendering the real fonts, real halos, real grain.
- The aspect-frame switcher genuinely letterboxing to 20:9 (`05`) — the bug this caught is in the review README.
- The slow-motion and "overridden" state switchers live (`06`).
- A short frame sequence standing in for a screen recording (`video/lab-tour-frame-sequence.mp4`) — **not a real capture**: `adb shell screenrecord` fails on this AVD image with `Encoder failed (err=-38)`, a known limitation already noted in `DEV_SETUP.md`. The clip is `screencap` stills assembled with `ffmpeg`, at roughly 2 real actions a second; it shows what was tapped, not smooth motion. A real recording needs a newer AVD or a physical phone, same as `DEV_SETUP.md` already says for the launch-flash check.

None of this is a frame-timing number. `dumpsys gfxinfo` was tried against the running app and reported zero frames — Flutter's own engine does not feed the Android view system's per-frame counters the way a native view does, so that tool does not apply here. `FrameProbe` (built this phase, `lib/ui/design/fidelity/frame_probe.dart`) is wired into the Lab's "frame graph" toggle and was confirmed to draw a live sparkline on-device, but reading numbers off a screenshot of a sparkline is not a measurement worth recording as one.

## APK size (CLAUDE.md 3: under 20 MB per ABI)

Built with the full design system linked in (fonts, all of `lib/ui/design/`, the Lab):

```
armeabi-v7a: 12.0 MB
arm64-v8a:   14.8 MB
```

Both `tool/check_apk_size.sh` and `tool/check_offline.sh --strict` pass. No dependency was added this phase; the size increase over phase 2 is the 333 KB of subset fonts plus the Lab and design-system code.

## What phase 3b should measure for real

Once Drive exists: `TierDetector`'s cold-open capture, `TierGovernor` stepping under load, and the actual budget check of DESIGN.md 9.4 (UI thread < 5 ms, raster < 9 ms at p90 on Drive/Apex) — ideally on a physical low-end phone via the hardware-handoff-style capture CLAUDE.md 10 describes, or explicitly logged as unavailable if none can be borrowed before then.

# Phase 3b: performance

DESIGN.md 9.4 wants, on a 2016–2018 reference phone (2 GB RAM, Snapdragon 4xx-class, Android 7–8, 720p): UI thread under 5 ms and raster under 9 ms at p90 during a demo drive on Apex, and no frame above 32 ms in the ignition, swipes or Motion ↔ Parked transitions. **No such phone was available, so none of those budgets has been checked.** What follows is what could be measured, and how little it says.

## What ran

`integration_test/demo_drive_perf_test.dart`, on the `Reference_API24` emulator (Android 7.0, arm64-v8a, 720×1280, 2 GB, `-gpu swiftshader_indirect`: software GL on the host Mac's CPU), debug build, real time, about two minutes: the cold open, the demo path, 25 s on Apex, 20 s on each of Tape, Minimal, Telemetry and Road (vertical swipes between), 15 s on the HUD (a double-tap). It records `FrameTiming`s and prints the p50, p90 and p99 of each frame's cost, the longer of its build and raster time (`FrameProbe.costOf`). Raw output: `perf-raw.txt`.

| Screen | frames | p50 ms | p90 ms | p99 ms |
|---|---|---|---|---|
| Cold open | 24 | 10.5 | 16.9 | 87.7 |
| Apex | 217 | 10.6 | 12.7 | 63.7 |
| Tape | 175 | 9.5 | 10.8 | 13.1 |
| Minimal | 176 | 9.6 | 11.1 | 13.7 |
| Telemetry | 173 | 12.3 | 14.1 | 41.7 |
| Road | 175 | 9.7 | 11.6 | 16.7 |
| HUD | 132 | 12.1 | 14.3 | 27.5 |

The cold open chose **LITE** on this emulator (its own p90 of 16.9 ms, with the detector's 25% headroom, does not fit Balanced's 16.7 ms budget). The rest ran at that tier.

## How to read it

- **These are debug-build, software-GL numbers.** A debug build is slower than release, and SwiftShader is neither faster nor slower than a Snapdragon 4xx in any consistent way (`DEV_SETUP.md` already says so for this AVD). They are not the reference-device numbers, and **they do not show the 5 ms / 9 ms budgets met or missed**: the probe reports one cost per frame (build or raster, whichever is longer), not the two separately.
- **The frame counts are low (about 9 a second)** because the test driver pumps every 100 ms in real time; frames between are not being produced by the driver, so the counts show the driver's pacing, not the app's frame rate. The per-frame costs are real; the rate is not measured.
- **The p99s are the worrying part** (Apex 63.7 ms, Telemetry 41.7 ms, the cold open 87.7 ms), against DESIGN.md's "no frame above 32 ms" in the ignition and transitions. They may be first-frame costs (the glyph atlases and glow sprites are built on first use, in the first seconds of each screen) and the emulator's own hitches, or they may be real jank; a 100-frame sample cannot tell them apart. **This needs a release build on a real phone before anyone says the budgets are met.** The likely first place to look is atlas and sprite creation at the moment a cluster first appears.
- The tier decision itself (LITE) is the software renderer's, and says nothing about what a real 2016 phone would pick.

## Not measured

Release-build timings; a physical low-end phone; the ignition sequence, page swipe and Motion ↔ Parked transition frames separately (the run above averages 15–25 s of each screen, mostly steady state); memory (the 150 MB budget); the 60 → 30 fps fallback; the governor stepping down. The APK size was last measured in phase 3a (12.0 MB armeabi-v7a, 14.8 MB arm64-v8a) and not re-measured after the 3b work.

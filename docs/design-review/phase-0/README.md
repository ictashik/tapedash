# Design review: phase 0 (foundation)

This is the smallest review package there will be. Phase 0 touches the UI only at the edges: the launch window and one empty canvas. It is here because CLAUDE.md 13 asks for a package at the end of every phase that touches UI, and so that the one decision in it, the `void` colour, has a place to be looked at.

## What was built

- The launch window, the theme the app runs under, and the Android 12+ splash background are all `void`, #050607 (DESIGN.md 4.1).
- The app is a single `void` canvas in landscape, in both directions, with the system bars hidden.

There are no components, pages, fonts, liveries or motion yet. They start in phase 3a.

## Signature moments finished

None. The first are the ignition sequence and the detented numerals, in phase 3b.

## Screenshots

All are real captures from emulators. None is from a phone.

| File | What it shows |
|---|---|
| `canvas-android-16-api36.png` | The running app on an Android 16 emulator, 2400x1080. All 2,592,000 pixels are exactly (5, 6, 7), which is `void`. No status bar, no navigation bar. |
| `canvas-android-7-api24.png` | The same on an Android 7.0 emulator with a 720p phone screen, 1280x720 in landscape. Every pixel is `void`. |
| `first-launch-android-7-api24.png` | The first launch on Android 7.0. The OS shows its own one-time "Viewing full screen" notice over the dimmed canvas. This happens on Android 4.4 to 10 and cannot be suppressed. |
| `splash-android-16-api36.png` | The Android 12+ system splash: the `void` background with the template's default Flutter icon. The status bar is visible because Flutter has not started yet. |

## Deviations from DESIGN.md

- **The splash icon is Flutter's default, not ours.** DESIGN.md 12 wants the icon foreground on `void`. The `void` half is done. The adaptive icon is a phase 3b item, and until then the default launcher icon shows on the splash and on the home screen.

That is all. Everything else DESIGN.md asks of phase 0 is met.

## Not included, and why

- **No `video/`.** Nothing animates.
- **No `perf.md`.** There are no fidelity tiers and nothing animates, so there are no frame timings worth reporting. The first one is due with phase 3a.
- **No device captures.** No phone was available. That matters most for `void`: DESIGN.md 4.1 picks #050607 over pure black because pure black looks grey-blue on cheap LCDs, and an emulator cannot show how a real panel renders it.
- **The launch flash is not shown.** It could not be measured on an emulator. With the launch colour set to solid red, no red frame appears in a recording on either Android 7.0 or Android 16, so a recording cannot tell a white flash from none. It has to be checked on a real phone.

## Questions for you

1. **Is #050607 right?** Most of the product sits on it, so it is worth a look on your own phone once there is a build to install. `docs/DEV_SETUP.md` has the commands.
2. **Old Android's "Viewing full screen" notice.** It shows once, on Android 10 or older, over the first launch. Is a line in onboarding to tap "Got it" acceptable, or would you rather the first run avoid immersive mode until the user has passed onboarding?

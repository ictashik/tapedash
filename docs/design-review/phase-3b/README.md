# Design review: phase 3b — the cockpit and the HUD

Written 2026-09-29, at the end of phase 3b (CLAUDE.md 13). The human reviews the design only through this package (CLAUDE.md 1). Everything here was rendered from the real code: headless captures from the widget tests (`screenshots/matrix`, `screenshots/moments`) and real screenshots from the `Reference_API24` emulator (`screenshots/device`). **No physical phone, no windshield, and no screen recording** were available; see "What was not verified".

Phase 3a's package (`../phase-3a/`) is the component and token review; this one is the screens.

## What was built

- **The five Drive clusters** (`lib/ui/pages/drive/`): Apex, Tape, Minimal, Telemetry, Road, each on a real `DemoDrive` (the simulator through the real OBD stack), switched by a vertical swipe on `spring.page` with the hand's velocity.
- **The Strip** (`lib/ui/pages/strip/`): REVIEW · MONEY · DRIVE · COACH · HISTORY as one panel; swipe with parallax, the page tape, the motion lock (rubber-band and a lock glyph), the parked dock (Garage, Pit Stop, Diagnostics, HUD), the shared-element flight of the speed to Money's corner.
- **Motion ↔ Parked** (DESIGN.md 7.2) on one shared parked share: the arc thins and dims, the hero shrinks, the status captions appear, the dock rises; back in under 300 ms.
- **Ignition sequence** (7.13, Apex) and **connection states** (7.12: searching, waiting for ignition, lost, re-light).
- **The HUD** (DESIGN.md 8): three layouts, the flips, position and scale, four colours, the alignment pattern, the double-tap and the dock button.
- **Onboarding** (7.11): the cold open (a line of light, then the wordmark, 1.2 s), the choice, and the demo path, with the drive connecting behind the choice so the ignition plays within a second of the tap.
- **Brand** (12): the adaptive and monochrome icon, the Android 12 splash icon, the wordmark.
- **The app shell** now opens on all of it (`lib/app/`), in Demo Mode with the DEMO badge always on.

## Signature moments (DESIGN.md 3)

| # | Moment | Status |
|---|---|---|
| 1 | Ignition sequence | **Built in Apex only** (the arc wave, the needle to redline and back, numerals rolling up, the horizon drawing). The other four clusters get the needle and numerals (they are the shared signals) but not the arc wave, the horizon draw or the flank fade. Frames: `moments/ignition-*`, `device/d1-ignition`. |
| 2 | Light-blade needle, trail, phosphor | **Built** in the Apex tach arc. Not judged in motion by eye on a device: only stills. |
| 3 | Detented odometer numerals | **Built.** On the device they are visibly loud in Telemetry and Road (see open question 1). |
| 4 | Shift horizon | **Built** in every cluster's top strip. |
| 5 | The Money Tape | **Component built (3a/3b), no data yet:** it needs `money/` (phase 4). Not on any screen. |
| 6 | Stop and the cockpit opens | **Half.** The cluster refocuses (arc thins, hero shrinks, captions and dock appear) but the flanks' detail panels (trip stats, fuel, calibration) need phase 4's data and are absent. |
| 7 | Debrief | Phase 5. |
| 8 | Efficiency curve | Phase 5. |
| 9 | Road view | **Built, and it is the least finished screen** (see below). |
| 10 | VFD livery | Built in 3a; **not re-checked on the 3b screens**: every capture here is ION. |

## What the review captures found and fixed

The matrix (`screenshots/matrix`: five clusters × Motion and Parked × 640, 720 and 800 wide × 360, inside the real shell) was worth doing: it found real defects that the per-component tests had missed, all fixed with tests (`8d12e2e`, `5e56153`, `1bf94a8`, `be34138`):

- The hero speed sat ~28 lp right of the arc's centre in Apex and off-centre in Minimal and Road: `CenteredNumeral` centred on an estimate of the digit width. Now on the atlas's real advance.
- The status strip's clock and DEMO badge were drawn off the right edge of the screen in every cluster (only the clock's first digit showed).
- The parked dock never repainted its position as it rose, and overflowed a 640 lp screen.
- The dock covered Apex's unit label, Telemetry's bottom row and Minimal's RPM line; Telemetry's grid sat under the status captions; Apex's tach clipped its own top labels at 16:9; Tape's readout digits sat on their box's edge and its four-digit tick labels ran off the screen at 640.

## Deviations from DESIGN.md, and why

- **Apex's arc is centred 0.03H below the screen's centre** (6.2 says "centred on the hero"). At radius 0.44H the ticks and labels do not fit above the centre on a 16:9 screen, and the opening at the bottom leaves room. The hero moves with it.
- **Telemetry and Minimal stop at 0.20H from the bottom and Telemetry starts at 0.15H** (7.3: "share the horizon and floor", which are 0.16H and 0.10H), so the parked dock and the status captions never sit on their content. The same in Motion, so nothing moves with the mode.
- **The dock's four buttons are a compact variant across the screen's width**, not four full-size chamfer buttons (which are 824 lp wide with their labels; the screen is 640). Still 56 lp tall.
- **The right status flank reserves 240 lp** and right-aligns inside it.
- **The HUD's RPM bar has bold end caps and a taller red zone**, since a track is etch and etch is not on the glass (8) and colour alone is not allowed (11).
- **A stale HUD value is the HUD colour at 45%,** not the grey ink, since a grey would be a second colour.
- **CONNECT MY CAR is disabled** with a note; its scenes need phase 6.
- **The pre-Android-12 launch window is plain `void`,** not the logo, so the cold open does not have to line up with it.

## What is honestly absent (needs later phases)

Every money figure and the eco bar (phase 4: the Tape centre, Apex's driver flank and floor, Minimal's corner, the two money HUD layouts, which say MONEY UNAVAILABLE); the flanks' detail panels; Review, Coach and History (placeholders that say so); Garage, Pit Stop, Diagnostics (their dock buttons are disabled); the connect path of onboarding; persistence of any setting; the HUD's alert source; the accelerometer roll on the road view (drawn flat).

## What was not verified

- **No physical phone, so no reference-device numbers** (DESIGN.md 9.4 wants a 2016–2018 Snapdragon 4xx-class phone). Timings are from the emulator, software GL, and say little about a real phone; see `perf.md`.
- **No screen recording.** `adb shell screenrecord` fails on this AVD image (Encoder failed, err=-38; recorded in `DEV_SETUP.md` in phase 3a). So there is no `video/`, and **motion has been judged from stills and tests only**: nothing was reviewed in slow motion on a screen this phase. The springs, the swipe, the ignition and the parked transition are tested (2,300+ tests) but not watched.
- **Only the ION livery, only Normal mode.** No Daylight or Night, no EMBER, VFD or MONO on these screens; no goldens (DESIGN.md 14.1's matrix), only pixel assertions.
- **The HUD has never been on a windshield,** nor on a phone in a real reflection: brightness, the mirror's feel, the alignment pattern's usefulness are all unjudged. The brightness curve, wake lock and the 50 °C dim are not wired.
- **The icon at 48 px on a real launcher** and the Android 13 themed icon.
- A debug build was used on the emulator: its Design Lab dev button (bottom right) is in the screenshots, and on top of the HUD. It is not in a release build.

## Open questions for the human

1. **The detented numerals in Telemetry and Road look loud on the device** (`device/d-telemetry`, `d-road`): with a value changing every frame the neighbouring digits show at high alpha, above and below, and a fast-moving ones digit reads as two overlapping numerals ("28" with a large "9" under it in Road). DESIGN.md 5.6 asks for exactly this behaviour; should the neighbour digits' peak alpha come down, or is the mechanical look the point? (The hero speed in Apex hides it better because it changes less often.)
2. **The Road cluster** (`matrix/*road*`, `device/d-road`) reads as unfinished: the hero sits on the vanishing point and the road lines cross it, the car body is a stack of plain rounded rectangles, and there is no lateral roll. Is the hero meant to sit over the road like this, and how far should the car's silhouette go beyond a placeholder before phase 3b is called done?
3. **The tach's arc drop** (0.03H) and the unit label pulled up under the digits are my reading of a spec that says "centred" and puts the arc's box taller than the screen. Is a small drop right, or would you rather shrink the arc (radius 0.44H → ~0.38H) and keep it centred?
4. **Ignition in the other four clusters.** Apex has the full sequence; do Tape, Minimal, Telemetry and Road need their own arc-wave equivalents (a tape scroll-in, a tile-by-tile light-up), or is "needle and numerals only" enough outside Apex?
5. **The cold open every launch.** Today onboarding (cold open and choice) shows on every launch, since remembering the choice needs `shared_preferences`, a dependency I have not added. Fine to add it (BSD-3, no Play Services) in the Garage's piece?

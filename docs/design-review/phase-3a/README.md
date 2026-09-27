# Design review: phase 3a — the design system

Written 2026-09-27, at the end of phase 3a (CLAUDE.md 13). This is the first phase with anything to look at, and the human reviews it only through this package (CLAUDE.md 1, "Nothing is done until it's reviewed").

## What was built

Everything in `lib/ui/design/`, plus a working Design Lab to see it in (`lib/ui/lab/`), and the app now boots onto real pixels instead of a blank canvas.

- **Fonts** (`assets/fonts/`, `docs/DECISIONS.md`): Saira (variable, weight 300–800, width 100–125), Barlow and Barlow Semi Condensed (Regular/Medium/SemiBold), all SIL OFL 1.1, subset from a pinned `google/fonts` commit, verified by SHA-256, no Reserved Font Name. 333 KB total.
- **Tokens** (`lib/ui/design/tokens/`): every colour, the four liveries, the type scale and styles, spacing, strokes (with pixel snapping), shapes, glow strengths, opacity constants, the five springs, durations and curves — all from DESIGN.md 4–5, checked against the spec value by value.
- **Theme** (`lib/ui/design/theme/`): `TapeTheme`/`TapeThemeData` carry livery, mode, fidelity tier, driver side and reduce-motion. `TapePalette` resolves a livery in a mode once, so Daylight and Night's rules (halos off/halved, thicker strokes, `ink.dim`→`ink.mid`, an accent under 10:1 giving way to `ink.bright`) live in one place. `ModeController` follows ambient light with the spec's thresholds and 10 s dwell. `Contrast` computes WCAG ratios for the accessibility tests.
- **Motion core** (`lib/ui/design/motion/`): `MotionClock` is the one vsync ticker everything runs on — virtual time, a frame clamped to 50 ms, follows `timeDilation`, zero ticks when nothing is moving. `SpringValue` retargets an analytic `SpringSimulation` from the current position and velocity on every sample, so nothing jumps. `PhosphorBank` decays a whole bank of segments with one pair of exponentials a frame. `OdometerLayout` is the detented odometer of DESIGN.md 5.6, carries included, allocation-free. `SmoothedSignal` is the rest of the pipeline: capped lead compensation (off by default, off while noisy), the spring, the 1.5 s stale fade. `Timeline` is a choreographed span for the ignition sequence and the debrief, both still to come in 3b.
- **Render primitives** (`lib/ui/design/render/`): a glyph atlas (digits and symbols rasterised once per size/weight/density, drawn with `drawRawAtlas` from preallocated buffers), the same for the seven-segment renderer (chamfered hexagon segments, 8° lean, ghost segments), a glow-sprite cache (`MaskFilter.blur` baked into images, composited with `BlendMode.plus`), a seeded grain tile, a VFD hex-mesh tile, `Chamfer` path builders, pixel snapping, and `StaticLayer` for a picture that is recorded once and replayed.
- **Icon set** (`lib/ui/design/icons/icons.dart`): the 27 required glyphs (DESIGN.md 4.8), each a short path string on the 24-unit grid, parsed once; every line is along an axis or at 45°, circles are the only curve.
- **Fidelity** (`lib/ui/design/fidelity/`): `TierDetector` picks a tier from the cold open's frame cost with 25% headroom; `TierGovernor` steps a tier down after 5 s over budget, never up, and forces Lite/30 fps above 50 °C; `FrameProbe` reads the engine's own timings.
- **Components built and in the Lab**: `RollingNumerals` (Saira, detented, anchored on the ones column) and `SevenSegmentNumerals` (VFD), the chamfer button, toggle, segmented selector, slider, list row, `TouchBloom`, `TapeBackdrop` (the void, vignette, grain, VFD mesh, all cached).
- **Design Lab** (`lib/ui/lab/design_lab.dart`, DESIGN.md 13.2): three tabs (numerals, controls, icons) over the components above, with working switchers for livery, mode, fidelity tier, driving override, driver side, reduce motion, slow motion (`timeDilation` 1×/0.5×/0.25×/0.1×) and aspect frame (native/16:9/18:9/20:9, which now really letterboxes — see "What nearly shipped broken" below), a frame-timing graph on `FrameProbe`, and a capture-all that renders every tab × livery × mode to PNGs.
- **App shell**: `main()` awaits the fonts before the first frame. The Strip and its pages are phase 3b, so the shell is still the `void` canvas, now with one way in: a dev button that opens the Lab, shown in debug/profile builds or with `--dart-define=TAPEDASH_DEV=true` — until the real debug overlay exists (CLAUDE.md 9), which the button's visibility rule already matches.
- **`DemoDrive`** (`lib/app/demo_drive.dart`) and the `DataSource`/`DemoControl` interfaces (`lib/ui/dev/`): a looping simulated drive feeding a `VehicleState`, so phase 3b's pages can read live data without knowing whether it is Demo Mode or a real adapter. Not wired to any screen yet, since there is no screen to wire it to.

## Signature moments (DESIGN.md 3)

Of the ten, three are partly there — everything else is phase 3b or later, since it needs the tach arc, tapes, road view, ignition sequence or Money Tape, none of which exist yet.

| # | Moment | Status |
|---|---|---|
| 3 | Detented odometer numerals | **Built and tested.** `OdometerLayout` matches the spec's detent curve and carry rule exactly (`test/design/odometer_test.dart`, mutation-checked). Not yet seen rolling under a live OBD-paced signal, only under the Lab's slider and the scripted specimens. |
| 10 | VFD livery: glowing segments with ghost digits | **Built.** Seven-segment rendering, the lean, the gaps, ghost segments at 7%, per-segment phosphor so a digit change crossfades segment by segment. Seen on the API 24 emulator (screenshot 09). |
| 2 (half) | Phosphor afterglow | **Built and tested** (`PhosphorBank`, decay within 5% of its time constant). The other half of #2, the light-blade needle and its trail, is the tach arc — phase 3b. |

## What nearly shipped broken

Writing the Lab's own tests (`test/widget/design_lab_test.dart`) found two real bugs before this package was written, both now fixed and covered:

1. **The aspect-frame switcher did nothing.** Native/16:9/18:9/20:9 changed `DevSettings` but nothing read it. Fixed by letterboxing the capture area in a centred `AspectRatio`; screenshot 05 shows 20:9 for real on the emulator, narrower than the phone's own screen.
2. **`capture-all`'s renderer could hang under test** — `RenderRepaintBoundary.toImage()` never resolves if a `tester.pump()` ran earlier in the same `tester.runAsync` block, which is exactly what the sweep's `setState` → `endOfFrame` → `toImage` loop does. Not a bug in the app (it works fine on-device — the whole Lab, including a live capture-all run, was exercised on the emulator), but it meant the sweep's own logic was untested. Fixed by making the renderer injectable (`DesignLab.captureRenderer`, defaulting to the real one); the sweep's logic is tested with a fake renderer, and the real renderer is tested in isolation, on an already-settled tree, with no pump sharing its `runAsync` block. Recorded in the shell-quirks memory so it is not rediscovered.

Both are the kind of thing "build it, then write its tests" is supposed to catch, and did.

## Deviations from DESIGN.md, and why

- **Grain-compensated backdrop colour.** DESIGN.md 4.1 says the vignette runs from `carbon.900` to `void`. Grain (4.10) is white speckle at ~2.5% opacity laid over that, which on its own lifts the average colour above the token. `TapeBackdrop` darkens the base gradient by the grain's own average so the *result*, void plus grain, averages back to the token colours (`_beneathGrain` in `lib/ui/design/components/backdrop.dart`). Not written down in DESIGN.md, which does not say the two combine this way; recorded here and in the code comment rather than in DECISIONS.md, since it is an implementation detail of one component, not a design choice.
- **`RollingNumerals` is a `StatelessWidget` that picks `SairaNumerals` or `SevenSegmentNumerals`** by the theme's livery, rather than one render object switching its own drawing code. DESIGN.md 6.1 just says "VFD livery uses the seven-segment renderer"; the split keeps each renderer's state (an `OdometerLayout` vs a `PhosphorBank` per digit) from leaking into the other.
- **The capture-all sink writes to the system temp directory**, not real app storage. CLAUDE.md 5 has no device-feature decision for a storage path yet; `DesignLab.defaultCaptureSink` is a stand-in, swappable (`captureSink`), noted in `docs/DECISIONS.md`. It is not a phase-3a blocker since the Lab is dev-only, but phase 3b or later should add a proper path if store screenshots are to be captured this way (DESIGN.md 12 wants them from the Lab).
- **The design lint (`test/design/design_lint_test.dart`) covers `lib/ui` and `lib/app/app.dart` only**, not all of `lib/app`. DESIGN.md 13.1's rule is about the design system; `lib/app/demo_drive.dart` is service wiring with its own timing constants (a 2 s poll-loop interval) that has nothing to do with the token system. Widening the rule to all of `lib/app` in an earlier pass caught this file as a false positive; narrowed to the shell file, which does compose UI.
- **No golden-image tests yet** (DESIGN.md 14.1's matrix). Goldens compare real pages in every livery × mode at two widths; there are no pages until phase 3b. What exists instead: pixel-level assertions on rendered widgets (rolling numerals, seven-segment numerals, controls, icons, the backdrop) that check real colours and real layout, which is what a golden would otherwise be standing in for at this stage.

## Signal from what the tests weren't able to reach

- **Perf numbers are not from a demo drive**, because there is no Drive page to profile yet (Layer 5's "2-minute demo drive" in CLAUDE.md 10 needs phase 3b). `perf.md` says plainly what was and was not measured.
- **`DemoDrive` has never been exercised against a real screen.** It compiles, and `ObdSession`/`SimTransport`/`VehicleState` underneath it are the same phase-2 code already proven against the simulator's ground truth; the new part (the looping restart, the `DataSource` wrapper) has no test of its own yet, because nothing reads it. It gets one when phase 3b wires it to Demo Mode.
- **Two liveries' Daylight/Night captures** (screenshots 11–12) are EMBER only; ION, VFD and MONO were checked by the contrast test suite (`test/design/theme_test.dart`, every livery × every mode against DESIGN.md 11's ratios) but not by eye on a device. Worth a look before 3b's design review, cheap to add then since the Lab's livery switcher already reaches them.

## Open questions for the human

1. **The capture-all storage path.** Fine to leave as the temp-directory stand-in through 3b, or worth a small `DeviceChannel` addition now (an app-storage path, no new permission) so store screenshots (DESIGN.md 12) can be taken the way the spec describes?
2. **The dev button's reachability rule.** It currently shows in debug/profile builds or with an explicit dart-define, matching where CLAUDE.md 9's debug overlay will eventually live. When the real overlay and its long-press arrive (phase 3b or later), should the button move behind it, or is a visible button in debug/profile fine to keep alongside?
3. **VFD's ghost-8 leading zero**: DESIGN.md 5.6 says "no leading zeros (except VFD ghost 8s)" — implemented as a fully dark digit showing only its 7%-alpha ghost segments (screenshot 09, the leftmost digit of "087"). Is that the intended reading, or should a ghost 8 look identical to a lit 8 at 7%, which is what it does — asking because "ghost 8" as phrasing could also mean something between a blank and this.

## Not done, by design (later phases)

Everything else in DESIGN.md's component and screen sections: the tach arc, tapes, shift horizon, bar gauges, telemetry tiles, eco bar, money readout and Money Tape, status strip, alerts, road view, route trail, telemetry scrubber, efficiency curve, sheets, the Strip navigation, Motion↔Parked, the five Drive clusters, the HUD, onboarding, and the ignition/shutdown/debrief sequences. All of it is phase 3b in CLAUDE.md 13, and none of it was started.

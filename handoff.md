# Handoff

Updated 2026-09-28, at the end of a session that built the Motion <-> Parked choreography (DESIGN.md 7.2) on one shared parked share: the tach arc thinning and dimming to 60%, the hero shrunk to primary size in Apex and Minimal, and the status strip's captions fading in on the same share. Written 2026-09-28, at the end of the session before that, which built the Strip's navigation (the swipe with parallax, the page tape, the motion lock), the Drive page's reel, and the parked dock. Read this first, then `CLAUDE.md` and `DESIGN.md` in full (both are binding and are re-injected as system context every session, but re-reading them yourself, not trusting a summary of them, is the whole lesson this file exists to pass on -- see "The one lesson worth repeating" below).

## A bug found after the session ended

`the_strip.dart`'s `_settle()` had a leftover debug `print('settle: at $at, velocity $velocity')` behind `// ignore: avoid_print`, printing on every swipe release. It was introduced while developing the release/settle logic in the Strip's first commit (`99dbc81`) and never pulled out before commit -- the `ignore` comment let it slide past the analyzer instead of getting caught. Found by re-reading the strip's source end to end (not by a test; nothing exercised stdout), removed, `./tool/verify.sh` re-run green, committed separately as `7f04d1b` (`fix(strip): remove a leftover debug print from the settle path`). No other file in `lib/ui/pages/` had one -- checked with `grep -rn "print(\|debugPrint"`. **Grep for stray `print(`/`// ignore:` pairs before calling a phase's work done**; the design lint checks colour/text-style/duration/spring literals but not this, so it is on the workflow's own read-back, not a test, to catch it.

## Where things stand right now

- HEAD is `4cbba4f` on `main` (the choreography is `d177350`, the build frame `4cbba4f`). Tree is clean. Nothing has been pushed; there is no remote. No tags exist (`v0.1.0-sim` and `v0.2.0-design` are suggested but not placed -- see `docs/STATUS.md`).
- `./tool/verify.sh` is green: 2,218 tests, offline check clean (re-verified after the choreography landed).
- **The Motion <-> Parked choreography (DESIGN.md 7.2) is done** (`d177350`): one shared parked share (`DriveSignals.parkedShare`, a `ParkedShare` in `lib/ui/design/motion/parked_share.dart`), read by the tach arc (thinned and dimmed to 60%, stagger 0), the hero readouts in Apex and Minimal (shrunken to primary size through `ParkedScale`, a transition transform, not a re-layout), and the status strip's captions (fading in, the columns widening with them). The flanks' unfolded detail panels (trip stats, fuel, calibration) are the spec's remaining choreography item and are honestly absent (phase 4's data). The dock keeps its own spring; its fall is the same `spring.snap` inside the same budget. Per-piece details: `docs/STATUS.md`'s "Phase 3b: the Motion <-> Parked choreography".
- **All five Drive clusters exist** (`lib/ui/pages/drive/`: `apex_cluster.dart`, `road_cluster.dart`, `tape_cluster.dart`, `minimal_cluster.dart`, `telemetry_cluster.dart`), each rendering against a real `DemoDrive`, each with a capture test and a pixel-level widget test suite. Per-cluster details and the design decisions they recorded: `docs/STATUS.md`'s "Phase 3b: the ..." cluster sections.
- **The Strip exists** (`lib/ui/pages/strip/`): five pages, Drive at home in the centre, a horizontal swipe on spring.page with the spring chasing the finger and the hand's own velocity carrying into the settle, parallax in the tiers that allow it (the canvas drifts at 0.1x, wide enough to cover the whole drift range; the flow delegate loosens the canvas child's own constraints, which the viewport's tight ones would otherwise clamp back to one page wide), the page tape (the current page's tick lit, the rest etched, the locked pages carrying the lock in place of their dash), the motion lock (a swipe toward a locked page rubber-bands against the reachable edge and shows the lock glyph for 800 ms; a page left on when the car starts moving returns to the nearest reachable page on spring.snap inside the 300 ms), and honest placeholders for the four non-Drive pages. The strip does not rebuild for its own motion (one Flow, its delegate reading the spring fresh per frame, painting only the children whose own span meets the viewport), and a page inside the window builds once and never again while the strip moves within it.
- 31 build-video frames registered, one per piece of work, `docs/build-video/FRAMES.md`.
- The user has been getting periodic progress reports and wants build-video material as work lands. Keep registering frames with `tool/build_frame.sh` as each piece lands, the same as every commit so far.

## Done since: the shared-element transition (`e3f2e09`)

The speed flight is committed; the trip-rupees flight waits on phase 4. The section below is kept for the design notes.

## Done since: the ignition sequence (`DriveSignals.ignition`, Apex only; see STATUS.md)

## Done since: the connection states (DESIGN.md 7.12, see STATUS.md)

`ConnectionPresentation` + `ConnectionLayer` over the Drive reel; frame 34. Gaps recorded in STATUS.md. Still open from the ignition: the arc wave, horizon draw and flank fade are wired into Apex only.

## Done since: the HUD (`84db5c1`, dock repaint fix `5e56153`; see STATUS.md). Frame 35.

Also found: `CenteredNumeral` centres on an estimated digit width (54 lp off at 198 lp); the HUD works around it, the other clusters were not re-measured -- worth one measurement pass.

## Done since: Demo Mode in the app shell (`bd5696c`; `DriveShell`), plus two fixes it exposed (status strip right flank, dock at 640 lp). Frame 36.

## Done since: onboarding's cold open, choice and demo path (frame 37; see STATUS.md).

## Done since: the brand (icon, splash icon; frame 38).

## Done since: the phase 3b review package (`d1d0202`; `docs/design-review/phase-3b/`), plus the layout fixes its captures forced (`8d12e2e`) and the first emulator run of the whole app.

## Next step: wait for the human's review of the package (five open questions in its README), and act on the answers. If told to go on regardless: phase 4 (trips, fuel, money: CLAUDE.md 13), whose money data fills the slots every cluster leaves empty. Before that, worth doing whenever convenient: the Layer 4/4b page-level tests (goldens matrix, contrast, motion-lock, flash-rate: DESIGN.md 14.1-14.2), which the composed pages now make possible, and a release-build run on a real phone.

Useful now: `test/design/capture/review_matrix_capture_test.dart` renders every cluster in both modes at three widths inside the real shell (contact-sheet script was ad hoc: PIL); `integration_test/demo_drive_perf_test.dart` runs the demo drive on a device and prints frame costs (`flutter test integration_test/demo_drive_perf_test.dart -d emulator-5554`; the emulator was already running, see docs/DEV_SETUP.md). Don't trust a clean per-component test to mean a clean screen: five layout bugs hid until the shell existed.

(Original note on the shared-element transition follows.)

DESIGN.md 7.1's shared elements: moving from Drive to Money, the hero speed shrinks and flies to the Money page's status corner while the floor's ₹ grows and flies to Money's centre. Money's own centre value is phase 4, so the Money-side landing is the placeholder's slot for now, documented. The double-tap that toggles the HUD belongs with the HUD's own piece, not this.

Re-read DESIGN.md 7.1 and §5.7 (choreography) before starting: every transition is interruptible and reversible mid-flight, keeping its velocity, on `spring.page` -- the same chase-and-settle pattern the strip's swipe already uses; "the number you were watching never disappears; it travels" is the sentence to design against. The parked share's choreography (`ParkedShare` + `ParkedScale`) is the model for anything else that animates on a state change.

After that: ignition and shutdown sequences (DESIGN.md 7.13), then connection states (DESIGN.md 7.12) -- see the "Full remaining phase 3b scope" list below for the rest, in the order CLAUDE.md 13 names them.

The drags in the strip's own widget tests pace the hand's own moves in steps (`moveBy` in a few events with frames advanced between them), so the gesture's own velocity at the release is real -- a drag's single `moveBy` in one event leaves no velocity for the release to carry, and the settle then reads a hand that was still moving as one that had stopped. The same pacing pattern applies to any new gesture-driven test.

## The workflow every component, cluster and screen has followed

This produced a real, previously-unknown bug in *most* cases it was applied to -- not a formality. Don't skip steps to go faster.

1. **Re-read the exact DESIGN.md section** (and the relevant CLAUDE.md section, if it's data/architecture) before writing any code, every time, even for something that looks small. Don't rely on a memory of having read it earlier -- a summarised context window is exactly the failure mode that caused two components to be silently skipped earlier in phase 3b; see below.
2. **Build it**, reusing existing tokens/patterns rather than inventing new ones. Check for an existing helper before writing a new one (`SmoothedSignal.bind`, `ObservableListenable`, `CenteredNumeral`, `Chamfer`, `GlowSprite.drawCentered`, `TapeSpace`'s zone shares all already exist).
3. **Write a capture test** (`test/design/capture/*_capture_test.dart`, gated on `TAPEDASH_CAPTURE_DIR` being set, skipped otherwise) and actually render it:
   ```
   TAPEDASH_CAPTURE_DIR=<some scratch dir> flutter test test/design/capture/whatever_capture_test.dart
   ```
   then **read the resulting PNG with the Read tool and actually look at it.** But also see the lesson below: an eyeball can be *wrong*; when a capture looks off, measure before believing it.
4. **Fix what the capture really shows** (after measuring), re-capture, repeat until it looks right.
5. **Write a real widget test suite** against actual pixels (`Uint32List` from `renderImage`/`toByteData`, per the established pattern in every `test/widget/*_test.dart`), not just "does it throw." Expose pure math (a colour ramp, a share calculation, a threshold check) as a public static method for a direct test rather than trying to sample it back out of rendered pixels. **The pixel packing is `0xRRGGBBAA` on this platform** (`toByteData` reads back red in the top byte) -- `test/widget/pages/road_cluster_test.dart`'s comment writes the convention down; every later pixel test followed it.
6. Run the new test file alone first, fix failures (some will be real component bugs, some will be bugs in the test itself -- both happened repeatedly; **measure** which side is wrong before "fixing" either one).
7. Run `./tool/verify.sh` in full (it takes a few minutes) and only commit once it prints `verify: all green`. **Never trust a piped exit code** -- `./tool/verify.sh | tail -N` reports `tail`'s exit code, not the script's; redirect to a file and check `verify: all green` appears, or use `(./tool/verify.sh; echo "EXIT_CODE:$?") > log 2>&1`.
8. Commit with a detailed message: what was built, which DESIGN.md/CLAUDE.md section, and an honest account of every real bug the tests or captures found and how it was fixed -- including false alarms and what settled them. Every commit this session follows this shape; read a few (`git log`) for the exact voice/level of detail expected.
9. Register a build-video frame: `tool/build_frame.sh <path-to-a-capture-png> <slug> "<one-sentence caption>"`, then a small separate `docs(build-video):` commit.
10. Update `docs/STATUS.md` at natural checkpoints (after a meaningful unit of work, not every commit).

## Lessons this session added (in the order they cost something)

- **Measure, then believe.** An eyeball of the Minimal capture read the hero numeral as ~33 lp right of centre -- a measurement probe showed the ink centred to within a device pixel for 81, 88, 11 and 100 alike. A narrow digit's side bearing is what reads as offset. The same probe found where the RPM line actually lands (see next bullet). Eyeballing finds *suspicious* things; only measurement settles them. The choreography's own parked pixel test repeated the lesson: the "hero ink" a wide centre-zone band found was the tach needle's white core, not the numeral at all.
- **`RollingNumerals`' box is much taller than its ink.** `CenteredNumeral`/`RollingNumerals` reserve a box several times the ink's height (the detent/roll room, DESIGN.md 5.6), so anything laid out *below* a hero numeral (Minimal's RPM line, Apex's KM/H label) sits further down than the ink suggests. This is accepted behaviour, not a bug; when pixel-testing something below a hero, scan to the frame's bottom edge, not to where the ink ends.
- **A missing import can compile-error as something else.** Using `NumeralFormat` without importing `rolling_numerals.dart` produced `Not a constant expression` at the const constructor, not `isn't defined`. When a const constructor errors oddly, check the import list first. (`ValueListenable` without importing `package:flutter/foundation.dart` does the same: `flutter/widgets.dart` does not re-export it.)
- **The design lint only bans colour/text-style/duration/spring literals -- numeric layout values are fine inline** (ApexCluster's coolant gauge band, Minimal's 0.25W extent, the tapes' windows). Gauge config numbers belong at the call site; tokens are for look, not for a gauge's range.

## The one lesson worth repeating

Partway through an earlier session, a context-window summarisation happened, and the summary's own "pending tasks" list quietly dropped an item (the vertical tape, DESIGN.md 6.3 -- "tapes," the instrument the product is *named after*) that CLAUDE.md 13's actual phase-3b bullet still named explicitly. It was found only by running `ls lib/ui/design/components/` and diffing the filenames against CLAUDE.md 13's literal list, not by trusting the running notes. The same check, repeated afterwards on principle, found a second dropped item (the Money Tape, DESIGN.md 6.8).

**If you are reading this after your own context was summarised or compacted, or if you're starting fresh and only have this file plus a skim of `docs/STATUS.md`: before assuming something is "still to do" or "already done," check the filesystem against CLAUDE.md 13's literal bullet list yourself.** This file and `docs/STATUS.md` are both believed accurate as of `53b4935`, but they are still secondhand summaries, and CLAUDE.md is the source of truth on what phase 3b actually contains. This session's own check confirmed: all five clusters exist on disk; the remaining bullets below are the phase's remaining work.

## Standing rules (from CLAUDE.md, re-stated because they're easy to forget mid-task)

- **Never push, never create a tag**, without the user explicitly asking. Nothing has been pushed all session; keep it that way unless told otherwise.
- **Do not add attribution lines to commit messages or PR descriptions** -- this overrides CLAUDE.md's own git-workflow text if it says otherwise; a harness-level system reminder takes precedence.
- **Never commit a red build.** `flutter analyze`, `flutter test`, `tool/check_offline.sh` (all three run inside `tool/verify.sh`) must be clean first.
- Conventional Commits (`feat(design):`, `feat(drive):`, `fix(...)`, `test:`, `docs:`, `chore:`). Keep commits small and coherent; a cross-cutting fix found while building one thing gets folded into that thing's commit with an honest explanation, not hidden or split arbitrarily -- follow the precedent already in the git log.
- **Never invent data.** If a screen wants something from `fuel/`, `money/`, `trips/` or `coach/` (none of which exist before phase 4/5), the slot is simply absent, with a doc comment saying why and pointing at the phase that will fill it. Every cluster built so far follows this; don't be the first to fake a number.
- **Never guess PID formulas, ELM327 behaviour, or vehicle physics.** If something in `sim/`, `obd/`, `fuel/`, or `vehicle/` seems to need changing, check CLAUDE.md 8.3/8.4 or ask, rather than guess.
- Re-read the relevant DESIGN.md section before building any component or screen -- CLAUDE.md 12 says this explicitly, and skipping it is exactly how the same centring bug got built twice before `CenteredNumeral` fixed it at the source.
- The design lint (`test/design/design_lint_test.dart`, part of `tool/verify.sh`) enforces no Material widgets and no raw colour/text-style/duration/spring literal anywhere in `lib/ui/` outside `lib/ui/design/tokens/`. Don't be surprised by it; fix the token file, not the lint.
- `flutter analyze` also runs on `test/` -- an unused import there fails the gate too (this bit once this session; `dart format` before the gate, and fix lint infos, not just errors).

## Full remaining phase 3b scope (CLAUDE.md 13's own bullet, annotated)

- ~~Components~~ -- **done**, see `docs/STATUS.md`.
- ~~The five Drive clusters~~ -- **all done** (`lib/ui/pages/drive/`), each on a real `DemoDrive`.
- ~~The Strip navigation (DESIGN.md 7.1)~~ -- **done** (`99dbc81`): five pages, swipe, parallax, motion lock, page tape, honest placeholders for the four non-Drive pages.
- ~~The vertical cluster reel (DESIGN.md 7.3)~~ -- **done** (`addce3b`): a vertical swipe on Drive cycles the five clusters, the choice persists in the page's own state.
- ~~The parked dock (DESIGN.md 7.1)~~ -- **done** (`a505ef4`): rises into the floor zone when parked, Garage/Pit Stop/Diagnostics/HUD as disabled documented buttons, reacts to mode.
- ~~Motion <-> Parked (DESIGN.md 7.2)~~ -- **done** (`d177350`): one shared parked share; the arc thinned and dimmed to 60%, the heroes shrunken, the captions fading. The flanks' unfolded detail panels are phase 4's data and are honestly absent.
- ~~The shared-element transition (DESIGN.md 7.1)~~ -- **speed flight done** (`e3f2e09`); the ₹ flight is phase 4's.
- ~~Ignition and shutdown sequences (DESIGN.md 7.13)~~ -- **done in Apex** (the other four clusters lack the arc wave, horizon draw and flank fade).
- ~~Connection states (DESIGN.md 7.12)~~ -- **done** (see STATUS.md). Was: the full per-state cluster treatment (searching sweep beam, waiting-for-ignition dim breathing dot, lost freeze-and-fade). `DriveSignals.adapter`/`.connection` already expose the raw state; only the status strip's own small 3-state glyph currently reacts to it (see `_adapterStateFor` in `drive_signals.dart`) -- the fuller treatment is this bullet's job.
- HUD (DESIGN.md 8): layouts, the flips, the alignment pattern. Not started. **Next.**
- Demo Mode: `DemoDrive` (`lib/app/demo_drive.dart`, phase 3a) and the clusters' capture tests prove the wiring works, but nothing in `lib/app/app.dart` actually shows a real page yet -- `_Shell` in `app.dart` still only shows the void canvas and the Design Lab button. Wiring a real `DemoDrive` into the app shell, showing the DEMO badge (already built, `status_strip.dart`), belongs here.
- Onboarding (DESIGN.md 7.11): cold open, demo/connect choice, demo path. Not started.
- Brand: app icon, launch theme, wordmark. Not started -- launcher and splash icons are still Flutter's defaults (a known, flagged gap since phase 3a).
- Layer 4 and 4b tests (CLAUDE.md 10) once real pages exist to run them against -- widget tests today cover each component/cluster individually; page-level goldens and the full design-lint/contrast/motion-lock matrix from DESIGN.md 14.1-14.2 want real composed screens first.
- A design review package for phase 3b (CLAUDE.md 13, DESIGN.md 14.4), covering real driving screens, not just Lab components -- phase 3a's package (`docs/design-review/phase-3a/`) is the template for structure and honesty (it says plainly what wasn't verified, e.g. real frame timings, rather than skipping the question).

## Where things live

- `lib/ui/pages/drive/` -- the five cluster compositions and `DriveSignals`.
- `lib/ui/design/components/` -- the reusable component library (all built, see `docs/STATUS.md`).
- `lib/ui/design/tokens/` -- every colour/duration/spring/spacing constant. The design lint enforces that nothing outside this directory hardcodes one. Numeric gauge config (window sizes, extents, band ranges) is deliberately inline at the call sites.
- `test/design/capture/` -- capture-only tests, gated on `TAPEDASH_CAPTURE_DIR`.
- `test/widget/` and `test/widget/pages/` -- real pixel-level widget tests.
- `docs/STATUS.md` -- the canonical, CLAUDE.md-mandated running record. Update it at checkpoints.
- `docs/DECISIONS.md` -- short log of choices and reasons, including design decisions DESIGN.md was silent on. Check it before re-deciding something that might already be settled there.
- `docs/build-video/` -- `FRAMES.md` plus the frame images; `tool/build_frame.sh` appends to both.
- `/Users/ashikh/.claude/projects/-Volumes-Dev-Projects-TapeDash/memory/` -- persistent cross-session memory (not part of this repo). `shell-quirks-on-this-mac.md` there has real, previously-costly gotchas: zsh's `nomatch` on an empty glob aborting a `&&` chain, `dart format`'s `\uXXXX` rewriting, and the big one -- `RenderRepaintBoundary.toImage()` (and any sibling async image call like `toByteData()`) hanging forever inside `tester.runAsync` if a `tester.pump()` ran earlier in the *same* `runAsync` block, or if the async call isn't wrapped in `runAsync` at all. Read it before debugging a capture test that hangs rather than fails.

# Handoff

Written 2026-09-28, for whichever agent picks this up next. Read this first, then `CLAUDE.md` and `DESIGN.md` in full (both are binding and are re-injected as system context every session, but re-reading them yourself, not trusting a summary of them, is the whole lesson this file exists to pass on -- see "The one lesson worth repeating" below).

## Where things stand right now

- HEAD is `bdc742f` on `main`. Tree is clean. Nothing has been pushed; there is no remote. No tags exist (`v0.1.0-sim` and `v0.2.0-design` are suggested but not placed -- see `docs/STATUS.md`).
- `./tool/verify.sh` is green: 2,171 tests, offline check clean.
- **Every component DESIGN.md 6 and CLAUDE.md 13 name for phase 3b now exists**, built, tested and committed. Full inventory, real bugs found, and deliberate gaps: `docs/STATUS.md`'s "Phase 3b so far: every component" section.
- **The first real screen exists**: the Apex cluster (`lib/ui/pages/drive/apex_cluster.dart`), rendering against a real `DemoDrive` (the actual OBD stack from phases 1-2), not synthetic test-only signals. Detail: `docs/STATUS.md`'s "Phase 3b: the first real screen" section.
- The user has been getting periodic progress reports and wants build-video material as work lands (`docs/build-video/FRAMES.md`, 23 frames so far). Keep registering frames with `tool/build_frame.sh` as each piece of work lands, the same as every commit so far.

## Immediate next step: a `RoadCluster` wrapper

This is the cheapest remaining Drive cluster, and the natural next commit:

- `RoadView` (`lib/ui/design/components/road_view.dart`) is already complete, tested and committed -- DESIGN.md 6.11, "Road: the road view, full-bleed with its overlays" (DESIGN.md 7.3.5).
- `DriveSignals` (`lib/ui/pages/drive/drive_signals.dart`) already exposes `speed`, `rpm`, `longitudinalAcceleration` (really wired, from `VehicleState.motion`) and `lateralAcceleration` (deliberately never ingested into -- no accelerometer pipeline yet; `RoadView` already renders a valueless signal as 0/no-roll, a real working degradation, not a crash risk).
- So a `RoadCluster` is close to a pure composition: `RoadView(speed: signals.speed, rpm: signals.rpm, maxRpm: ..., longitudinalAcceleration: signals.longitudinalAcceleration, lateralAcceleration: signals.lateralAcceleration, width: ..., height: ...)`, likely with `moneySlot: null` (that overlay is phase 4, same reasoning as everywhere else).
- Follow the exact workflow below. Write a capture test against a real `DemoDrive` (copy `test/design/capture/apex_cluster_capture_test.dart`'s pattern) to see it actually moving, not just compiling.
- After Road, the other three clusters (Tape, Minimal, Telemetry -- DESIGN.md 7.3.2-7.3.4) are genuinely new layout work, not just wiring. **Read `lib/ui/design/components/centered_numeral.dart`'s doc comment before building any of them** -- all three want a hero-style centred readout, and that component exists specifically because the naive `Center(child: RollingNumerals(...))` approach is wrong and was hit twice already.

## The workflow every component and cluster so far has followed

This produced a real, previously-unknown bug in *every single case* it was applied to this session -- not a formality. Don't skip steps to go faster.

1. **Re-read the exact DESIGN.md section** (and the relevant CLAUDE.md section, if it's data/architecture) before writing any code, every time, even for something that looks small. Don't rely on a memory of having read it earlier -- a summarised context window is exactly the failure mode that caused two components (the vertical tape, the Money Tape) to be silently skipped earlier this session; see below.
2. **Build it**, reusing existing tokens/patterns rather than inventing new ones. Check for an existing helper before writing a new one (`SmoothedSignal.bind`, `ObservableListenable`, `CenteredNumeral`, `Chamfer`, `GlowSprite.drawCentered` all already exist and have all been rediscovered-the-hard-way once already).
3. **Write a capture test** (`test/design/capture/*_capture_test.dart`, gated on `TAPEDASH_CAPTURE_DIR` being set, skipped otherwise) and actually render it:
   ```
   TAPEDASH_CAPTURE_DIR=<some scratch dir> flutter test test/design/capture/whatever_capture_test.dart
   ```
   then **read the resulting PNG with the Read tool and actually look at it.** Every component this session had at least one real, visually-obvious bug that compiling and unit-testing alone would not have caught (a mispositioned halo, an invisible streak, a wrong colour token, a crash only reachable through a specific ambient layout constraint). `flutter test` commands reliably take longer than the tool's default timeout; run them with `run_in_background: true` and wait for the notification rather than polling.
4. **Fix what the capture shows**, re-capture, repeat until it looks right.
5. **Write a real widget test suite** against actual pixels (`Uint32List` from `renderImage`/`toByteData`, per the established pattern in every `test/widget/*_test.dart` this session), not just "does it throw." Expose pure math (a colour ramp, a phase calculation, a threshold check) as a public static method for a direct test rather than trying to sample it back out of rendered pixels -- this exact lesson was learned and re-applied at least five times this session.
6. Run the new test file alone first, fix failures (some will be real component bugs, some will be bugs in the test itself -- both happened repeatedly; verify visually which side is wrong before "fixing" either one).
7. Run `./tool/verify.sh` in full (`run_in_background: true`, it takes a few minutes) and only commit once it prints `verify: all green`. **Never trust a piped exit code** -- `./tool/verify.sh | tail -N` reports `tail`'s exit code, not the script's; redirect to a file and check `verify: all green` appears, or use `(./tool/verify.sh; echo "EXIT_CODE:$?") > log 2>&1`.
8. Commit with a detailed message: what was built, which DESIGN.md/CLAUDE.md section, and an honest account of every real bug the tests or captures found and how it was fixed. Every commit this session follows this shape; read a few (`git log`) for the exact voice/level of detail expected.
9. Register a build-video frame: `tool/build_frame.sh <path-to-a-capture-png> <slug> "<one-sentence caption>"`, then a small separate `docs(build-video):` commit.
10. Update `docs/STATUS.md` at natural checkpoints (not every single commit -- after a meaningful unit of work, the way this handoff's own STATUS.md commit just did).

## The one lesson worth repeating

Partway through this session, a context-window summarisation happened, and the summary's own "pending tasks" list quietly dropped an item (the vertical tape, DESIGN.md 6.3 -- "tapes," the instrument the product is *named after*) that CLAUDE.md 13's actual phase-3b bullet still named explicitly. It was found only by running `ls lib/ui/design/components/` and diffing the filenames against CLAUDE.md 13's literal list, not by trusting the running notes. The same check, repeated afterwards on principle, found a second dropped item (the Money Tape, DESIGN.md 6.8).

**If you are reading this after your own context was summarised or compacted, or if you're starting fresh and only have this file plus a skim of `docs/STATUS.md`: before assuming something is "still to do" or "already done," check the filesystem against CLAUDE.md 13's literal bullet list yourself.** This file and `docs/STATUS.md` are both believed accurate as of `bdc742f`, but they are still secondhand summaries, and CLAUDE.md is the source of truth on what phase 3b actually contains.

## Standing rules (from CLAUDE.md, re-stated because they're easy to forget mid-task)

- **Never push, never create a tag**, without the user explicitly asking. Nothing has been pushed all session; keep it that way unless told otherwise.
- **Do not add attribution lines to commit messages or PR descriptions** -- this overrides CLAUDE.md's own git-workflow text if it says otherwise; a harness-level system reminder takes precedence.
- **Never commit a red build.** `flutter analyze`, `flutter test`, `tool/check_offline.sh` (all three run inside `tool/verify.sh`) must be clean first.
- Conventional Commits (`feat(design):`, `feat(drive):`, `fix(...)`, `test:`, `docs:`, `chore:`). Keep commits small and coherent; a cross-cutting fix found while building one thing gets folded into that thing's commit with an honest explanation, not hidden or split arbitrarily -- follow the precedent already in the git log (e.g. the eco bar commit that also fixed `GlowSprite`, or this session's `CenteredNumeral` commit).
- **Never invent data.** If a screen wants something from `fuel/`, `money/`, `trips/` or `coach/` (none of which exist before phase 4/5), the slot is simply absent, with a doc comment saying why and pointing at the phase that will fill it. Every cluster built so far follows this; don't be the first to fake a number.
- **Never guess PID formulas, ELM327 behaviour, or vehicle physics.** If something in `sim/`, `obd/`, `fuel/`, or `vehicle/` seems to need changing, check CLAUDE.md 8.3/8.4 or ask, rather than guess.
- Re-read the relevant DESIGN.md section before building any component or screen -- CLAUDE.md 12 says this explicitly, and skipping it is exactly how the same centring bug got built twice before `CenteredNumeral` fixed it at the source.
- The design lint (`test/design/design_lint_test.dart`, part of `tool/verify.sh`) enforces no Material widgets and no raw colour/text-style/duration/spring literal anywhere in `lib/ui/` outside `lib/ui/design/tokens/`. It has caught a real violation at least twice this session (most recently a bare `Duration(seconds: 20)` in `WallClockTicker`). Don't be surprised by it; fix the token file, not the lint.

## Full remaining phase 3b scope (CLAUDE.md 13's own bullet, annotated)

- ~~Components~~ -- **done**, see `docs/STATUS.md`.
- The five Drive clusters: **Apex done**; **Road next** (see above); Tape, Minimal, Telemetry not started.
- The Strip navigation (DESIGN.md 7.1): horizontal swipe between `REVIEW · MONEY · [DRIVE] · COACH · HISTORY` with parallax, vertical swipe within Drive for cluster choice, the page tape, motion lock (only Money and Drive reachable while moving), the parked dock, the Drive-to-Money shared-element transition. Not started. Needs placeholder Money/Review/Coach/History pages to swipe to, since their real content is phase 4/5 -- an honest placeholder (not a fake data screen) is the right call, consistent with everything else.
- Motion <-> Parked (DESIGN.md 7.2): the transition choreography. The underlying state already exists and is already wired (`VehicleState.mode` -> `DriveSignals.mode`, DESIGN.md 7.2's exact rule was built in phase 2) -- what's missing is the UI reacting to it (thinning/dimming the tach arc, unfolding detail panels, the dock rising), not the state itself.
- Ignition and shutdown sequences (DESIGN.md 7.13).
- Connection states (DESIGN.md 7.12): the full per-state cluster treatment (searching sweep beam, waiting-for-ignition dim breathing dot, lost freeze-and-fade). `DriveSignals.adapter`/`.connection` already expose the raw state; only the status strip's own small 3-state glyph currently reacts to it (see `_adapterStateFor` in `drive_signals.dart`) -- the fuller treatment is this bullet's job.
- HUD (DESIGN.md 8): layouts, the flips, the alignment pattern. Not started.
- Demo Mode: `DemoDrive` (`lib/app/demo_drive.dart`, phase 3a) and `ApexCluster`'s own capture test prove the wiring works, but nothing in `lib/app/app.dart` actually shows a real page yet -- `_Shell` in `app.dart` still only shows the void canvas and the Design Lab button. Wiring a real `DemoDrive` into the app shell, showing the DEMO badge (already built, `status_strip.dart`), belongs here.
- Onboarding (DESIGN.md 7.11): cold open, demo/connect choice, demo path. Not started.
- Brand: app icon, launch theme, wordmark. Not started -- launcher and splash icons are still Flutter's defaults (a known, flagged gap since phase 3a).
- Layer 4 and 4b tests (CLAUDE.md 10) once real pages exist to run them against -- widget tests today cover each component/cluster individually; page-level goldens and the full design-lint/contrast/motion-lock matrix from DESIGN.md 14.1-14.2 want real composed screens first.
- A design review package for phase 3b (CLAUDE.md 13, DESIGN.md 14.4), covering real driving screens, not just Lab components -- phase 3a's package (`docs/design-review/phase-3a/`) is the template for structure and honesty (it says plainly what wasn't verified, e.g. real frame timings, rather than skipping the question).

## Where things live

- `lib/ui/pages/drive/` -- cluster compositions and `DriveSignals`. This is where `RoadCluster`, `TapeCluster`, etc. go.
- `lib/ui/design/components/` -- the reusable component library (all built, see `docs/STATUS.md`).
- `lib/ui/design/tokens/` -- every colour/duration/spring/spacing constant. The design lint enforces that nothing outside this directory hardcodes one.
- `test/design/capture/` -- capture-only tests, gated on `TAPEDASH_CAPTURE_DIR`.
- `test/widget/` and `test/widget/pages/` -- real pixel-level widget tests.
- `docs/STATUS.md` -- the canonical, CLAUDE.md-mandated running record. Update it at checkpoints.
- `docs/DECISIONS.md` -- short log of choices and reasons, including design decisions DESIGN.md was silent on (e.g. GPS's glyph treatment, the DEMO badge's colour). Check it before re-deciding something that might already be settled there.
- `docs/build-video/` -- `FRAMES.md` plus the frame images; `tool/build_frame.sh` appends to both.
- `/Users/ashikh/.claude/projects/-Volumes-Dev-Projects-TapeDash/memory/` -- persistent cross-session memory (not part of this repo). `shell-quirks-on-this-mac.md` there has real, previously-costly gotchas: zsh's `nomatch` on an empty glob aborting a `&&` chain, `dart format`'s `\uXXXX` rewriting, and the big one -- `RenderRepaintBoundary.toImage()` (and any sibling async image call like `toByteData()`) hanging forever inside `tester.runAsync` if a `tester.pump()` ran earlier in the *same* `runAsync` block, or if the async call isn't wrapped in `runAsync` at all. Read it before debugging a capture test that hangs rather than fails.

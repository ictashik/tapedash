# DESIGN.md — TapeDash

Companion to [CLAUDE.md](CLAUDE.md). CLAUDE.md defines what TapeDash does and how it's engineered. This file defines how it **looks, moves and feels**. Both are requirements; neither is optional.

---

## 0. How to use this document

- Read it fully before any UI work. Re-read the relevant section before building a component or screen.
- **Authority:** DESIGN.md is authoritative for look, layout, motion, interaction and copy. CLAUDE.md is authoritative for architecture, data, offline, safety rules and performance budgets. If an effect here breaks a budget there, don't silently drop the design: use the cheaper technique in §9.3, fall back a fidelity tier (§9.1), and if the look still suffers, ask the human.
- **Tokens only.** Every colour, size, stroke, duration and spring comes from `lib/ui/design/tokens/` (§13). No magic numbers in widgets.
- **Components first.** Build each component in the Design Lab (§13.2), tune its motion in slow motion, then compose screens from components.
- **Review gate.** Every UI phase ends with a design review package (§14.4). The human sees the design only through that package, so it must be complete and honest.
- When this document is silent, extrapolate from the principles in §2 and record the decision in `docs/DECISIONS.md`.

---

## 1. North star

**Who it's for:** car enthusiasts who follow the best instrument-cluster and HUD design in the world and wish their own car had it. They notice needle overshoot, digit jitter, font choices and 40 ms of lag. They will film it and post it.

**The feeling:** a precision instrument that happens to run on an old phone. Calm at a cruise, alive when you push, honest about the numbers.

**Three words:** Precise. Luminous. Alive.

**The bar**
- If a screenshot could be mistaken for a generic Flutter or Material app, it's wrong.
- If any number jitters, jumps sideways or reflows, it's wrong.
- If it only looks good on a flagship, it's wrong. It must look deliberate on a 2016 phone.
- If it looks like a sci-fi movie prop with no hierarchy, it's wrong. Futuristic means clear, not busy.

**Reference moods** (take the principles, never the trade dress):
- Aircraft glass cockpits: speed tapes, trend vectors, strict colour discipline.
- Motorsport steering-wheel displays and telemetry software: shift lights, dense but legible data.
- 1980s vacuum-fluorescent digital dashes: glowing segments, ghost digits, phosphor afterglow.
- Precision watch dials: tick hierarchy, restraint.
- Studio audio meters: ballistics, peak hold.

Never reproduce any manufacturer's cluster, logo, font or visual identity.

---

## 2. Principles

1. **Instrument, not app.** Full-bleed. No app bars, cards, floating buttons, drawers, snackbars or Material components. The screen is an instrument panel made of black glass.
2. **Light is information.** Only live data emits light. Structure (scales, ticks, frames) is etched: dim, thin, static. The brightest thing on screen is always the thing that matters most right now.
3. **Motion has mass.** Data moves like a physical instrument: springs, slight needle overshoot, phosphor afterglow. Nothing teleports. Nothing moves linearly.
4. **One continuous cockpit.** Pages are camera moves across one instrument panel, not separate screens. Numbers travel between pages instead of disappearing.
5. **Focus in motion, open when parked.** Moving: few values, huge, glanceable, no small text, no controls. Parked: the cockpit unfolds into detail, history and settings.
6. **Beautiful at Tier 1.** The look comes from composition, typography, light hierarchy and motion curves, not from expensive effects. Effects are garnish added by higher fidelity tiers.
7. **One-second glance.** Any driving screen answers its main question in under one second. At most three primary values per driving screen (the opt-in Telemetry cluster uses secondary-size values only).
8. **Honest and calm.** Estimates look like estimates. No false precision, no alarmism, no gamified nagging. Warnings are rare, so they matter.
9. **Details are the product.** Tabular numerals, anchored digits, pixel-snapped hairlines, a correct ₹ glyph, Indian digit grouping, no white flash at launch. Enthusiasts notice all of it.

---

## 3. Signature moments

These are what people will film. Each must be polished before its phase is called done.

| # | Moment | Spec |
|---|---|---|
| 1 | **Ignition sequence:** segments light in a wave, the needle sweeps to redline and back, digits resolve | §7.13 |
| 2 | **Light-blade needle** leaving a fading trail; segments with phosphor afterglow | §6.2, §5.5 |
| 3 | **Detented odometer numerals:** digits roll like a precision mechanism and never jitter | §5.6, §6.1 |
| 4 | **Shift horizon:** light converges from the screen edges as revs rise | §6.4 |
| 5 | **The Money Tape:** every rupee prints as a coloured block, building a barcode of where the money went | §6.8 |
| 6 | **Stop and the cockpit opens:** the cluster unfolds into detail when the car stops and refocuses when it moves | §7.2 |
| 7 | **Debrief:** the cluster powers down, the route draws itself in light, the receipt rolls up | §7.5 |
| 8 | **Your car's efficiency curve** with its glowing sweet spot | §6.13 |
| 9 | **Road view:** lane lines stream at your true speed, the car pitches under braking, tail lights glow | §6.11 |
| 10 | **VFD livery:** 80s-style glowing segments with ghost digits | §4.4, §6.17 |

---

## 4. Foundations

### 4.1 The canvas
- The app is **always dark**. There is no light theme; a bright screen reflects in the windshield at night.
- Background is `void` (#050607), not pure black. Pure black looks grey-blue on cheap LCDs; on OLED the difference is invisible.
- A static radial vignette from `carbon.900` at the centre to `void` at the edges gives depth. It's rendered once into a cached layer and dithered with grain (§4.10) to prevent banding on 6-bit panels.
- **Burn-in protection:** the whole cluster drifts by up to ±2 logical pixels on a slow 3×3 cycle, one step every 3 minutes, eased over 8 s. Imperceptible and mandatory.

### 4.2 Depth layers

| Layer | Name | Contents | Behaviour |
|---|---|---|---|
| L0 | Void | background, vignette, grain | never repaints |
| L1 | Etch | scales, ticks, labels, frames, grids | cached picture; repaints only on layout or livery change |
| L2 | Data | numerals, needles, bars, traces | repaints when values move |
| L3 | Light | halos, trails, phosphor, highlights | composited additively over L2 |
| L4 | Signal | alerts, touch bloom, overlays | on demand |

Page swipes use parallax across layers (§7.1). The HUD shows only L2–L4 (§8).

### 4.3 Colour
**Discipline:** a driving screen uses at most one accent hue plus champagne (money), plus amber or red only when something is actually wrong.

**Neutrals (all liveries)**

| Token | Value | Use |
|---|---|---|
| `void` | #050607 | background |
| `carbon.900` | #0B0D10 | vignette centre, overlay surface |
| `carbon.800` | #11141A | raised surfaces (parked) |
| `carbon.700` | #1A1F27 | tracks, unlit segments |
| `carbon.600` | #252B35 | disabled, inactive tracks |
| `etch.faint` | white 5% | grids, separators |
| `etch` | white 9% | ticks, frames |
| `etch.strong` | white 16% | major ticks, edges |
| `ink.dim` | #7A838F | labels, units (about 5:1 on `void`; the dimmest colour allowed for text) |
| `ink.mid` | #9AA3AF | secondary values |
| `ink.bright` | #E7ECF1 | primary non-accent values |
| `ink.hot` | #FFFFFF | needle cores and peak highlights only |

**Money (all liveries).** Champagne is the colour of money and is used for nothing else.

| Token | Value |
|---|---|
| `money.core` | #F3CF86 |
| `money.deep` | #D6A042 |
| `money.glow` | #FFC45C |

**State (all liveries)**

| Token | Value | Meaning |
|---|---|---|
| `caution` | #FFB020 | needs attention |
| `critical` | #FF3355 | act now, redline |
| `stale` | = `ink.dim` | data older than 1.5 s |

**Accent:** per livery (§4.4).

**Rules**
- `accent.core` for live primary data and needles; `accent.deep` for fills and tracks; glow colours only in L3.
- Unlit is not invisible: unlit segments are `carbon.700` (ghosts in VFD).
- Colour never carries meaning alone (§11).
- **Data ramps** (routes and traces):
  - Speed: `accent.deep` → `accent.core` → `ink.hot`
  - Cost per km: `ink.dim` → `money.core` → `caution` → `critical`
  - Throttle: `carbon.600` → `accent.core` → `caution`
- **Money buckets:**
  - Normal: solid `money.deep`
  - Idling: **hollow** `caution` outline (money burned for nothing looks empty)
  - Hard acceleration: solid `critical` with a notch
  - High speed: solid `accent.deep`

### 4.4 Liveries and modes
A livery swaps accent colours, numeral style and texture. Layout and motion never change.

| Livery | accent.core | accent.deep | accent.glow | Numerals | Texture | Character |
|---|---|---|---|---|---|---|
| **ION** (default) | #5CE1FF | #1296FF | #2EC8FF | Saira wide, Medium | grain | cool, electric, modern |
| **EMBER** | #FF7A3D | #E8461C | #FF6A2B | Saira wide, SemiBold | grain | warm, sporty |
| **VFD** | #6BF7DC | #1FC2A4 | #3DFFD5 | seven-segment renderer (§6.17), ghost segments at 7% | grain + fine mesh | 80s digital dash |
| **MONO** | #F2F3F4 | #A9AFB7 | #FFFFFF, halos at 40% | Saira wide, Light | grain | luxury, restrained, thin strokes |

**Modes** (automatic, applied on top of any livery; manual override in Garage):
- **Daylight:** ambient light above 5,000 lux for 10 s (back below 2,000). Halos off, all strokes +50%, `ink.dim` becomes `ink.mid`, labels become `ink.bright`, maximum brightness. Numerals in an accent below 10:1 against `void` (EMBER) switch to `ink.bright` while needles, segments and fills keep the accent; the ₹ glyph switches from `money.deep` to `money.core`. Contrast over atmosphere.
- **Night:** below 20 lux for 10 s (back above 60). Brightness follows a lux curve with a 12% floor, halos at 50%, L1 structure (ticks, frames, grids) at 70% while labels keep their full colour, no `ink.hot` except needle cores.
- **No light sensor:** use offline sunrise and sunset calculated from the last GPS fix and the clock; otherwise manual.

### 4.5 Typography
**Families** (bundled, OFL-licensed, subset with fonttools at dev time to keep the APK small):
- **Saira** (variable, width and weight axes): all numerals and the wordmark. Use width ≈ 112–125 (wide) for numerals. If the variable file can't be used, fall back to a static Saira cut and record it in `docs/DECISIONS.md`.
- **Barlow** and **Barlow Semi Condensed**: labels, units and all parked UI text. Its road-sign heritage suits a car.
- No other fonts. Never system fonts or Roboto.

**Glyph coverage:** verify ₹ (U+20B9), °, ×, ≈, − (U+2212) and · in the subset. If ₹ is missing or visually mismatched, draw it as a custom path matching the numeral stroke weight and put it in the glyph atlas.

**Numeral rules**
- Tabular figures only (`FontFeature.tabularFigures()`); live numerals are drawn from the glyph atlas (§9.3).
- **Digits are anchored by the ones column:** the ones digit never moves horizontally as a value goes 7 → 77 → 107. Readouts reserve a fixed box for their maximum digits.
- No leading zeros (except VFD ghost 8s).
- Units are small, `ink.dim`, and never the same size as the value.
- The minus sign is U+2212, not a hyphen.

**Type scale.** Driving screens scale with the screen; H = logical height in landscape.

| Token | Size | Clamp (lp) | Use |
|---|---|---|---|
| `hero` | 0.36H | 96–220 | speed |
| `display` | 0.20H | 56–128 | money on the Money page, big secondary values |
| `primary` | 0.12H | 34–72 | flank values |
| `secondary` | 0.075H | 22–44 | tertiary values, tape labels |
| `label` | 0.036H | 11–16 | instrument labels: UPPERCASE, Barlow Semi Condensed Medium, tracking +12% |

Parked UI uses fixed sizes and honours system font scale up to 1.3×: headline 30, title 22, body 16, small 13, caption 12 (Barlow; titles SemiBold, body Regular).

### 4.6 Shape language
- **The chamfer is the signature shape.** Panels, buttons, readout boxes and segments use 45° chamfers, not rounded corners. Buttons use an asymmetric chamfer: top-left and bottom-right cut at 8 lp, the other corners square.
- **Brackets instead of boxes.** Group things with L-shaped corner brackets (10–14 lp arms) rather than full outlines.
- Circles only for true dials, the position dot and the route start marker.
- **Strokes:** hairline = 1 physical pixel (pixel-snapped), fine 1.5 lp, regular 2 lp, bold 3 lp, HUD ≥ 5 lp.
- No drop shadows. Depth comes from light and layers.

### 4.7 Layout and grid
- Landscape only. Design at 640×360 lp (16:9); verify at 720×360 (18:9) and 800×360 (20:9).
- Respect display cutouts and rounded corners. Outer margin m = max(16, 0.045H).
- **Zones** (driving screens):
  - **Horizon:** top strip, 0.10H. Shift horizon and status.
  - **Floor:** bottom strip, 0.16H. Eco bar and trip values, with the page tape in its bottom 8 lp.
  - **Centre:** width min(0.5W, 1.25H). The hero.
  - **Flanks:** the remaining width, left and right. Secondary values.
- Wider screens widen the flanks only. Never stretch a gauge.
- **Driver side** (Garage setting, default Right for India): the flank nearer the driver holds the most important secondary value.
- **Spacing** (4 lp base): s1 4, s2 8, s3 12, s4 16, s6 24, s8 32, s12 48.
- Hairlines snap to physical pixels; odd stroke widths are offset by half a pixel.

### 4.8 Iconography
- Custom glyphs drawn in code on a 24-unit grid: stroke 1.75, square caps, 45° chamfers, no free curves except circles. One file, `icons.dart`. No icon fonts and no Material icons.
- Required set: adapter, bluetooth, wifi, gps, check-engine, coolant, voltage, fuel pump, clock, lock, back, close, chevron, garage, history, coach, review, rupee, idle (hollow square with a dot), hard accel (double chevron up), hard brake (double bar), speed, phone hot, HUD (windshield), flip, pit stop, end trip (a flag), zoom in, zoom out, fit, play, pause, stop, north (an N: the map is north up), heading (an arrow up: the map turns with the car), insights (bars on two axes) and share (an arrow out of a tray).

### 4.9 Light and glow
- Every luminous element has a crisp **core** (L2) and an optional **halo** (L3). A halo is a pre-rendered blurred sprite composited with `BlendMode.plus`. **Never blur at runtime.**
- **Halo budget:** at most three halos above 50% intensity on screen at once. Hero readout halo 25–35%; needles 60%; active alerts may exceed.
- Halos are the first thing removed in Daylight mode and the HUD, and are halved at Night.
- Parked overlays get a 1 px `etch.strong` line on their top edge as a glass edge. Nothing else pretends to be glass.

### 4.10 Texture
- **Grain:** a 128×128 monochrome noise tile generated procedurally at startup (seeded), tiled at 2–3% over L0 through an image shader inside the cached layer. It removes banding and adds material.
- **VFD mesh:** a fine hex mesh at 3% over data areas, VFD livery only, cached.
- No scanlines, glitch effects, chromatic aberration or "hacker" aesthetics. Futuristic does not mean broken.

---

## 5. Motion system

### 5.1 Two kinds of motion
- **Value-driven:** instrument positions are pure functions of a smoothed value: needle angle, tape offset, digit roll, road dash phase. No durations; they move as the data moves.
- **Time-driven:** UI transitions (pages, reveals, overlays) use spring tokens.

Never animate live data with a fixed-duration tween. Never make a UI transition linear.

### 5.2 The smoothing pipeline (live data to pixels)
1. **Timestamp** each PID sample at receipt minus half the measured round-trip latency, since the value was read mid-request.
2. **Reject outliers:** discard a sample implying a physically impossible change (RPM faster than 10,000 rpm/s; speed changing more than 15 km/h in 100 ms) unless the next sample confirms it.
3. **Play out (for the fast, low-rate signals: RPM, speed, throttle, load):** a cheap adapter gives these once or twice a second, at uneven times (`lib/core/dsp/playout.dart`). The target, every frame, is the **straight line between the two samples either side of a moment a little in the past**: the delay is two thirds of the usual gap between samples (about half a second at 0.8 s, next to nothing on a fast adapter), at most 0.6 s. The value therefore only ever moves between two readings the car has given, so it neither stands still between samples nor overshoots; when the next sample is late, the last segment's slope carries on for a moment, fading (0.2 s time constant), capped at 100 rpm, 1.5 km/h or 4 %, and never outside the signal's range (`TapePlayout` in the tokens). *Extrapolating the samples' velocity (a Kalman tracker) was tried and removed: on real drives it overshot at every gear change and swung back, a pendulum.* **Lead compensation (for a signal without a playout):** target = value + rate × lead. Default lead is 0 ms. It's tuned after the hardware handoff, capped at 150 ms, and disabled when the rate is noisy.
4. **Spring** the displayed value towards the target (§5.3). On every new sample, retarget by creating a new `SpringSimulation` from the current position and velocity. This preserves momentum and never jumps. A played-out signal's target moves every frame, so its spring is stepped in closed form (`SpringValue.track`: the same spring, exact for the frame, no allocation) instead of being restarted.
5. **Render** from the spring state, driven by the single `MotionClock` vsync ticker.

**Stale data** (no sample for 1.5 s, or for 2.5 times the signal's usual gap between samples if that is longer, at most 4 s, so a slow adapter is not called stale between two of its own samples): the value holds, fades to `stale` over 600 ms, and needles stop. Fresh data returns it to colour over 200 ms.

### 5.3 Spring tokens
Built with `SpringDescription.withDampingRatio`, mass 1.

| Token | Stiffness | Damping ratio | Feel | Use |
|---|---|---|---|---|
| `spring.needle` | 260 | 0.72 | ~4% overshoot, settles in ~0.35 s | tach needle, tapes, bar fills |
| `spring.gauge` | 380 | 1.0 | no overshoot | numerals' underlying value, eco puck |
| `spring.page` | 170 | 0.92 | confident, a tiny settle | page moves, shared elements |
| `spring.reveal` | 120 | 0.85 | soft | panels unfolding, sheets |
| `spring.snap` | 600 | 1.0 | instant but not abrupt | toggles, selection |

Tests assert overshoot and settle times (§14.2).

### 5.4 Durations and curves
For fades and draw-ons only; everything positional uses springs.

| Token | Value |
|---|---|
| `dur.micro` | 120 ms |
| `dur.quick` | 220 ms |
| `dur.scene` | 480 ms |
| `dur.cinematic` | 1,200 ms |

Enter curve: cubic(0.16, 1, 0.3, 1) (expo-out). Exit curve: cubic(0.7, 0, 0.84, 0).

### 5.5 Phosphor persistence
Luminous elements don't switch off instantly; they decay like a VFD or CRT phosphor.
- Rise τ = 30 ms; decay τ = 180 ms (exponential).
- Applies to tach segments, shift horizon segments, the newest Money Tape block and alert frames.
- Tier 1 applies it to segments only.

### 5.6 Detented odometer numerals
How all live numerals roll (value-driven):
- Each digit column is a vertical cylinder of glyphs 0–9.
- For the ones column with smoothed value v = n + f (n an integer, 0 ≤ f < 1), the column's position is n + detent(f):
  - detent(f) = 0 for f < 0.3
  - detent(f) = smoothstep((f − 0.3) / 0.4) for 0.3 ≤ f ≤ 0.7
  - detent(f) = 1 for f > 0.7

  The digit rests centred most of the time and rolls briskly through the transition: readable like a digital display, alive like a mechanical one.
- **Carries** work like a mechanical odometer: a higher column rolls only while the column below is rolling from 9 to 0, in sync with it.
- For decimals, the last displayed decimal acts as the ones column.
- Increasing values roll up; decreasing values roll down.
- Glyphs partly outside the digit window fade by their offset (alpha computed per glyph; no clip masks).
- Tier 3 adds velocity stretch: glyphs stretch vertically by up to 6% in proportion to roll speed.
- Static numbers in parked views are set normally, without rolling.

### 5.7 Choreography
- Every transition is interruptible and reversible mid-flight, keeping its velocity. No animation blocks input.
- Stagger groups by 30–50 ms, at most six items; beyond that, animate as one group.
- Things enter from where they conceptually come from: flank panels from the sides, sheets from below, the debrief receipt from the Money Tape.
- Exits run at about 0.7× the length of entrances.
- **Motion mode always wins:** when the car starts moving, the Motion layout returns within 300 ms, cancelling any parked animation.
- Only one hero animation at a time.

### 5.8 Reduce motion
Garage → Display → Reduce motion; also honour the system animation scale set to 0.
- Turned off: ignition sweep (replaced by a 200 ms fade), parallax, needle trails, road streaks, debrief draw-on (shown instantly), digit velocity stretch.
- Kept: springs, all switched to damping ratio 1.0 (no overshoot).

### 5.9 Frame pacing
- One `MotionClock` ticker drives all springs and value animations; painters repaint from it in the same frame.
- All motion is computed from vsync timestamps, never frame counts. After a stall, dt is clamped to 50 ms.
- Tier 3 follows the display refresh rate (60/90/120 Hz). Tier 2 locks to 60. Tier 1 targets 60 with a 30 fallback.
- A dropped frame must never make a needle jump. Springs are analytic, so they resume from the correct state.

### 5.10 Sound (the engine note)
A sound is not a signal. The engine sound is an optional extra that says what the tach already says, in a second sense, and it follows the same rules as the screen.
- **Off until turned on** (Garage, §7.8). No cue, alert, voice or chime: it carries no information beyond the revs and the load, so it cannot ask anything of the driver, and the coach's rule (CLAUDE.md 1.5) holds: nothing is said while driving.
- **It is the needle's sound.** It follows the same played-out revs and throttle the tach shows (§5.2), so what is heard is what is seen, and a cheap adapter's slow readings glide and never step or swing. The revs can rise at most 9000 a second and fall at most 6000 (a flywheel), so a late reading is a glide and never a click.
- **It goes quiet as the data does.** A stale signal, a lost link or the engine off fades it out (0.35 s), and it comes back in over 0.15 s. There is no drone on a dead link.
- **Where it plays.** On car audio only (Bluetooth, a wire, USB) unless the Garage allows the phone's own speaker: it does not start without car audio, and stops at once if the output changes to the speaker (the Bluetooth link dropped). It asks for no audio focus, so music carries on under it. It belongs to the screen that is showing: it stops when the app leaves the screen (there is no service, so no new permission).
- **Replay.** A Review replay (§6.12) has the engine too, from the trip's recorded revs, a little ahead of the picture (0.3 s at 1×, so that the sound arrives with it), on whatever output there is; it is silent while paused.
- **The engines** are made in code, not recorded: Inline-4, Three-cylinder, V6, V8, Flat-six, Turbo four and Electric. They are named for the layout, never a make. Each is a parameter set (cylinders and their firing, the exhaust pulse, the pipe, the body's resonances, the throttle's brightness, the intake, a turbo, pops on an overrun); every one is set to the same level at a reference load so that changing engine does not change the volume.
- **Latency is not the point.** The data arrives once or twice a second and the picture is already half a second behind it; Bluetooth audio adds about a fifth of a second more. The sound is honest about trends, not about blips, and next to a loud real engine it will drift out of step: it suits a quiet cabin best, and a replay.

---

## 6. Components

Each component lives in `lib/ui/design/components/`, has a Design Lab page with sliders for every input, has golden tests in every livery, and works in Tier 1.

### 6.1 Rolling numerals
- Inputs: smoothed value, format (digits and decimals), size token, colour role, prefix or suffix glyph (₹, %, °).
- Drawn from the glyph atlas with detented odometer behaviour (§5.6), in a fixed digit box anchored at the ones column.
- Hero variant carries a 25–35% halo (at half resolution in Tier 1, per §9.1).
- VFD livery uses the seven-segment renderer with ghost 8s.

### 6.2 Tach arc
- 240° sweep opening at the bottom: from lower-left (210°) over the top to lower-right (−30°), with angles in maths orientation (y up); negate them on Flutter's y-down canvas. Centred on the hero speed readout, radius ≈ 0.44H. In the Apex cluster the hero may scale down to 0.28H so it clears the arc's inner edge by at least 0.04H.
- Range 0 to the vehicle profile's maximum (default 7,000). One segment per 100 rpm (Tier 1: per 200).
- **Segments:** chamfered trapezoids filling 70% of their angular slot, radial depth 0.06H.
- **Scale:** major ticks every 1,000 rpm, drawn as longer etched ticks outside the arc with labels (secondary size, `ink.dim`, value ÷ 1000). Label "RPM ×1000" at the arc's opening.
- **Lit state:** segments at or below the needle glow `accent.core`; the segment under the needle lights fractionally; segments above decay with phosphor.
- **Redline zone:** segments from redline up carry a 20% `critical` tint even when unlit, and light fully `critical`.
- **Light-blade needle:** not a pointer from the centre. It's a tapered blade spanning the segment band (0.92R to 1.06R). Core `ink.hot` at 2 lp; halo sprite at 60%; driven by `spring.needle`.
- **Trail:** the last N needle angles sampled every 30 ms (Tier 1: 2, Tier 2: 6, Tier 3: 12), drawn as blades with alpha halving each step. The trail shows how hard the revs are moving.
- **Peak hold:** a thin tick at the highest RPM of the last 3 s, fading out over 1 s, like an audio meter.

### 6.3 Tapes (the brand instrument)
Aircraft-style vertical tapes for speed and RPM. The product is called TapeDash; tapes are its native instrument.
- Vertical strip 0.13W wide. The scale scrolls continuously with the smoothed value; the window shows ±30 km/h (speed) or ±2,000 rpm.
- Ticks every 5 km/h, with labelled majors every 10. RPM ticks every 250, labelled every 1,000.
- **Readout box:** a chamfered box straddling the tape's inner edge, holding rolling numerals. The box outline is accent; the tape is etch.
- **Trend vector:** an accent line from the readout box to the value predicted 5 s ahead (current rate × 5 s), springed. Pilots use this to anticipate; drivers will love it.
- The top and bottom 20% of the tape fade to void (alpha computed per element; no masks).
- Redline and the user's speed threshold appear as tinted bands on the tape.

### 6.4 Shift horizon
- A thin light band across the top edge, 0.018H tall, made of 24 segments per side converging towards the centre.
- It starts filling at shift RPM − 1,500 and is fully lit at shift RPM. Colours step from accent (first 60%) to `caution` (next 25%) to `critical` (last 15%).
- At or above shift RPM, all segments flash `critical` at 3 Hz. Never faster (photosensitivity).
- **CVT and automatic profiles:** shift light off by default. Instead, the horizon shows a faint accent glow whose width follows RPM, like the engine breathing.
- Phosphor decay on every segment.

### 6.5 Bar gauges
- Horizontal or vertical chamfered track (`carbon.700`) with a fill from `accent.deep` to `accent.core` at its leading edge.
- A normal band is etched on the track (e.g. coolant 80–100 °C). Fill outside the band turns `caution` or `critical`.
- A 2 lp `ink.bright` line marks the fill's leading edge, springed.
- Value at the track's end in secondary numerals, with a label.

### 6.6 Telemetry tiles (the enthusiast cluster)
- A bracket frame; label top-left; rolling value top-right; a sparkline filling the lower 55%.
- Sparkline: last 60 s at 2 Hz (ring buffer of 120 points), `accent.core` 1.5 lp line, fill beneath at 8% alpha, min and max as faint etch lines with tiny labels.
- Out-of-range values tint the tile's brackets `caution` or `critical`.

### 6.7 Eco bar
- In the floor zone, centred, 0.36W wide and 0.03H tall.
- A centre notch marks this car's average km/L (from its history).
- A glowing puck moves right (more efficient) or left (thirstier) on `spring.gauge`, over ±50% of the average.
- Puck colour samples a ramp: right `accent.core`, centre `ink.bright`, left `caution`, far left `critical`.
- No text in Motion mode. Hidden when fuel data is unavailable or the car is parked.
- In Tier 3 it may tint the hero halo slightly, never the digits themselves.

### 6.8 Money readout and the Money Tape
**Money readout**
- ₹ glyph at 55% of digit height, baseline-aligned, `money.deep`; digits in `money.core` with detented rolling.
- Whole rupees only in Motion mode. ₹/km with one decimal.
- **Confidence pips:** three small chamfered cells beside the value. One lit = uncalibrated, two = calibrating, three = calibrated. In parked detail views, estimates are prefixed with "≈".

**The Money Tape** (signature)
- A vertical strip on the Money page's driver-far flank, 0.06W wide; a thin horizontal variant can sit in the Drive floor.
- Each block is ₹1: 6 lp tall with 2 lp gaps. New blocks print at the bottom and push the stack up on `spring.gauge`; the newest block flashes with phosphor.
- Block style follows the bucket (§4.3): normal solid `money.deep`, idling hollow `caution`, hard acceleration solid `critical` with a notch, high speed solid `accent.deep`.
- When the strip fills, blocks compact: groups merge into ₹5 and then ₹10 blocks with a smooth merge animation, and a small scale label updates ("1 BLOCK = ₹5").
- Over a trip it builds a barcode of where the money went. The same barcode appears in Review and History.

### 6.9 Status strip
Inside the Horizon zone, on either side of the shift horizon.
- **Left:** adapter glyph (lit while data flows, pulsing at 0.5 Hz while searching, `caution` when lost) and GPS glyph.
- **Right:** clock (tabular, following the system's 12/24-hour setting), and the phone-hot glyph when warm. (There was a DEMO badge here for Demo Mode, which was removed on 2026-10-23.) The left flank is the adapter glyph and the GPS glyph; on a drive from the GPS alone it is the GPS glyph alone.
- Glyphs only in Motion mode; text labels appear in Parked mode.

### 6.10 Alerts

| Level | Examples | Presentation |
|---|---|---|
| Caution | coolant high, phone warm, low fuel | the affected value turns `caution`; a `caution` line on the horizon; a glyph in the alert slot (centre-bottom of the hero zone) |
| Critical | overheating, low voltage with the engine running, a check-engine code appearing this trip, adapter lost for more than 10 s | the affected value turns `critical`; a chamfered `critical` bracket frame around its component pulses at 1 Hz; a large glyph in the alert slot |
| Info | calibration improved, price missing | Parked only, as a line on the relevant page |

- Never modal, never a sound, never covering the hero in Motion mode.
- Alerts have hysteresis and minimum durations so they never flicker.

### 6.11 Road view ("car moving")
- The camera sits behind and above a generic car. The horizon line is at 38% of the height.
- Road: two edge lines converging (`etch.strong`), centre dashes (`accent.deep`) and a faint lane grid (`etch.faint`).
- **Truthful motion:** dash phase = distance travelled (integrated from smoothed speed) modulo the dash period. At 0 km/h the road is perfectly still.
- **Car:** a generic sedan silhouette seen from behind, drawn as vector paths. No brand and no real model. Body in `carbon.700` with an `etch.strong` outline and an accent rim-light line.
- Tail lights brighten with a `critical` halo when deceleration exceeds 1.5 m/s².
- Body pitch ±2° from longitudinal acceleration; roll ±3° from lateral acceleration (accelerometer, low-pass filtered); both on `spring.needle`.
- Speed streaks at the road edges above 60 km/h, density proportional to speed (Tier 2: up to 40; Tier 3: up to 120).
- Night mode adds a faint headlight cone on the road.
- Overlays: hero speed top-centre, a thin RPM bar along the horizon line, the money readout on the driver-side flank.

### 6.12 Route trail and telemetry scrubber
**Route trail**
- Equirectangular projection (x = lon × cos(lat₀), y = lat), fitted to the panel with 8% padding, north up.
- 3 lp line coloured by the selected metric's ramp. For performance, quantise colours into 16 bins and draw one path per bin.
- A faint 8 lp underlay at 10% gives glow without blur.
- **Markers:** start = hollow circle; end = filled chamfered square; hard acceleration = double chevron; hard braking = double bar; long idle = hollow square.
- **Draw-on:** the path reveals over 1.6 s with a bright comet head, using path metrics precomputed at load.
- **Metrics:** the selector offers SPEED, RPM, THROTTLE, LOAD, COOLANT, VOLTS and ₹/KM (the trip's own: LOAD, COOLANT and VOLTS only for a trip that recorded them). Seven do not fit 640 lp in equal cells, so the selector scrolls: cells as wide as their labels, the chosen one kept in view, a chevron at an edge with more. Coolant and volts are scaled over the range the trip covered (at least 10 °C and 1 V), the others from 0 or by their 95th percentile.
- **Interactive:** pinch to zoom (1 to 24 times the whole route, about the fingers), drag to pan (the route always fills the panel), double-tap to zoom in by 2.5 or, when well in, back out to the whole route, zoom in, zoom out and fit buttons at the top right. A tap on the route puts the scrubber's cursor on the nearest point (within 36 lp); a cursor the scrubber moves somewhere the view is not looking brings the view to it. The line, the markers and the cursor keep their size on screen at any zoom. Zoom changes from a button or a double-tap move on `spring.gauge`; a pinch or a drag follows the fingers.

**Replay (game mode)**
- **Transport.** Left of the scrubber, three 48 lp buttons: PLAY / PAUSE, the speed (1×, 2×, 3×, and round again; it can be chosen before playing) and STOP (dimmed until a replay is on). PLAY starts the replay from the scrubber's cursor if one was put, else from the start; at the end, PLAY starts over. A replay runs on the motion clock, so it slows with `timeDilation`; a gap of more than 3 s in the samples (the engine was off) is crossed in half a second, not waited out.
- **Instruments.** The receipt gives way (cross-fade on `spring.gauge`) to the replay's instruments: the speed large, a rev bar and a throttle bar with their numerals, the ₹ so far (litres with no price), the distance and the time, and the marked moment as it passes (a glyph and "Hard acceleration", "Hard braking" or "Long idle" in its marker's colour, held 2.5 s of the replay, more at 2× and 3× so that it is as long to the eye). Every numeral rests on whole digits (km/h, revs to 10, whole ₹, tenths of a km): a number that moves every frame would be part-way through a roll nearly all the time. The totals at the end are exactly the receipt's (the integrals are scaled to the trip's own distance and litres). The tip gives way too, and the map takes its room.
- **The car** is an arrow with a notch in its tail and a glow, placed on the route by the distance the trip's odometer says it had covered (so it stands still while the car did, and never creeps through a stop), facing the way the route runs over the next 35 m (so a corner turns it over a few points and a scatter of GPS does not jerk it). The route behind it is drawn at full strength, the route ahead at 40%. The route is drawn from up to 3000 points while a replay runs (1000 otherwise), so that the camera can go in close.
- **Chase camera.** It keeps the car in view, north up or heading up (the default: the map turns so that the car's way is up, and the car sits 20% below the middle so the road ahead has the room). It shows the ground the car will cover in the next 45 s across the panel's width (at least 260 m, at most 3 km): out as it speeds up, in as it slows, on slow critically damped springs (zoom ω 2.4, turn ω 3.2). The position is exact, so the car does not drift on the screen. A pinch, or the zoom buttons, moves the camera closer or further (0.3 to 3.5 times what it chose, a double-tap resets it); one finger dragging lets go of the car; FOLLOW (a crosshair) takes it back; a turn button (an arrow up, or an N) chooses heading up or north up; fit lets go and shows the whole route.
- **Ground.** With no map under the route, a replay draws what there is: a dark 14 lp road under the line, and a faint grid every 25 m to 5 km (the nearest spacing that is at least 44 lp apart on the screen), carried by the map, so that the ground is seen going by, at what speed, and turning.
- **Scrubbing** the band or tapping the route moves the play head (playing or not); the scrubber's line moves smoothly (by fractional sample), and its cursor follows the car by whole samples.

**Telemetry scrubber**
- A full-width band at the bottom of Review: speed trace (accent) above, throttle trace (`ink.mid`) below (or, with a channel chosen in the selector, that channel), a shared time axis, and event markers on the axis.
- Drag anywhere to scrub: a vertical cursor appears, the route shows a position dot, and readouts show speed, RPM, throttle and ₹/km at that moment (on another metric: the speed and that metric alone).
- Pinch to zoom time; double-tap to reset.

### 6.13 Efficiency curve
- X axis: speed bands 0–120 km/h in 10 km/h bins. Y axis: km/L.
- A smooth Catmull-Rom curve through bands that have enough data; bands without enough data are dotted ghost segments.
- The sweet spot (the best band plus neighbours within 3%) is a vertical accent glow column labelled, e.g., "SWEET SPOT 55–70 KM/H".
- The car's overall average as a dashed etch line.
- The curve draws on when the page opens (`dur.scene`).

### 6.14 Parked controls
Parked UI only. Minimum touch target 48 lp; at least 8 lp between targets.
- **Chamfer button:** 56 lp tall, asymmetric 8 lp chamfer, 1.5 lp accent outline, accent label (Barlow Semi Condensed SemiBold, uppercase, tracking +8%). Pressed: 12% accent fill plus touch bloom. The rare primary call to action is filled `accent.core` with a `void` label.
- **Light-switch toggle:** a 48×26 lp track whose "on" cell lights with a halo, moving on `spring.snap`.
- **Segmented selector:** a row of chamfered cells; the selected one lights.
- **List row:** 64 lp; label left (body), value right (`ink.mid`), chevron glyph; hairline separators inset by m.
- **Slide-to-confirm:** a 64 lp track; drag the chamfered thumb past 85% to confirm, otherwise it springs back. Used for clearing fault codes and deleting data. Destructive actions are never a single tap.
- **Numpad:** 3×4 keys, 72 lp, chamfer outlines, Saira digits, decimal and backspace; every press gets a touch bloom.
- **Text field** (car nickname only): no box. An etch underline, an accent caret, the label above.

### 6.15 Overlays and sheets
- "Smoked glass" without blur: `carbon.900` at 94%, a 1 px `etch.strong` top edge, and grain.
- Scrim: `void` at 60%.
- Sheets rise from the bottom on `spring.reveal`; dismiss by dragging down or tapping the scrim.
- Parked mode only.

### 6.16 Touch bloom
A cached radial glow sprite at the touch point: scale 0.6 → 1.4 and alpha 0.35 → 0 over `dur.quick`, expo-out. It replaces every ripple.

### 6.17 Seven-segment renderer (VFD livery)
- Segments are chamfered hexagons with an 8° italic skew and 10% gaps, drawn as paths and cached into the glyph atlas per size.
- Unlit segments show as ghosts at 7% accent.
- Covers 0–9, minus, decimal point, and a ₹ built from segments plus a bar.
- Each segment has its own phosphor decay, so digit changes crossfade segment by segment like a real VFD.

### 6.18 Insight charts
Drawn by `ChartKit` (`lib/ui/design/components/insights/`): text in the design's fonts, a line with its halo (a wider, fainter stroke under it; nothing is blurred at run time), dashes, hatching for "no data", L-shaped brackets. Each chart is a painter that takes an analysis result and a palette, and is exercised in the capture tests on made-up driving.
- **Voltage chart:** 11.5 to 15 V, grid at each volt, the charging band `accent.core` at 5%, the trace in `accent.core` with its halo, decimated to the lowest and highest of each pixel column so that a dip a second or two long survives; dip marks are `caution` diamonds with a `caution` label. **Rest trend:** a 28 lp sparkline of the battery at rest, at least a fifth of a volt tall so that a steady battery looks steady, the last point `ink.hot`.
- **Powerflow chart:** nodes 8 lp wide; ribbons are cubic bands the height of their node; `accent.deep` to the wheels, a `caution` outline for idling, `ink.dim` for heat, `accent.core` for the three sinks, the brakes strongest. The labels are Barlow Semi Condensed with Saira figures; the idling label sits below the sinks' ribbons, never across them.
- **Power chart:** 1,000 to 7,000 rpm (past the redline's thousand if the car went there) by 0 to the highest seen plus 15% in steps of 20 kW, dots 2.6 lp in three batches (no more than 6,000), the throttle key above the plot, the hatching at `etch`.
- **Gear chart:** 0 to 6,500 rpm by 0 to the fastest speed (80 km/h at least) in steps of 20, grid at 2,000 rpm, rays at `accent.core` 35%, dots 2.2 lp at 70% (45% for a fan).
- **Toll map:** scale from the extent of everything drawn with a 26 lp margin and the same scale on both axes; roads at `etch.strong`, each trip's line as faint as it must be for the road driven daily to read as a line (about 60% in all, however many trips); rings 6 to 24 lp by the square root of the share of the dearest place's money.
- **Ghost chart:** the two routes share one fit (a 18 lp margin, one scale on both axes); the earlier one is 5 lp dashes at 70% `ink.mid`; this one a 2.2 lp `accent.core` line with its halo. The tapes under it are the History barcode (§6.8) at 22 lp tall.
- **Year poster:** drawn on 640 × 360 poster units by one painter for the screen and the picture (the picture at 3 pixels a unit); bars from x 32 to 608 above a baseline at 252 and at most 150 tall; Saira 28 for the title, Saira 17 for the figures, labels at 9 to 12. Fonts are the bundled ones, so the picture is in the app's own typography wherever it is posted.
- **Tank gauge:** a chamfered column (bottom corners cut 10 lp), `carbon.700` track, a `money.deep` fill with a `money.core` surface line and a faint glow above it, ticks at every eighth (longer at the quarters), F, ½ and E labels. The reserve is hatched in `caution` at 14% under the fill.

---

## 7. Screens

### 7.1 The Strip (navigation)
The app is one continuous horizontal panel of five pages, with Drive at home in the centre:

`REVIEW · MONEY · [ DRIVE ] · COACH · HISTORY`

- **Horizontal swipe** moves between pages on `spring.page`, with parallax in Tiers 2 and 3: L0 0.1×, L1 0.6×, L2 1.0×, L3 1.05×.
- **Vertical swipe** on Drive changes the cluster layout (§7.3) with a reel-like transition.
- **Double-tap** on Drive or Money toggles the HUD (§8).
- **Page tape:** a thin row of five ticks in the bottom 8 lp of the floor; the current page is lit.
- **Motion lock:** while moving, only Money and Drive are reachable. Swiping towards a locked page rubber-bands back and shows a small lock glyph for 800 ms; locked ticks on the page tape show the lock too.
- **Parked dock:** in Parked mode, a dock rises into the floor zone with Garage, Pit Stop, Diagnostics, Insights and HUD (chamfer buttons, glyph plus label). The eco bar hides while parked.
- **Shared elements:** moving from Drive to Money, the hero speed shrinks and flies to the Money page's status corner while the floor's ₹ grows and flies to the Money page's centre. The number you were watching never disappears; it travels.

### 7.2 Motion ↔ Parked
- **Parked** = speed 0 for 5 s, or ignition off. **Motion** = speed above 3 km/h (immediate).
- **To Parked** (`dur.scene`, `spring.reveal`, staggered): the tach arc thins and dims to 60%, the hero shrinks to primary size, the flanks unfold detail panels (trip stats, fuel, calibration), the dock rises, and glyph labels become text.
- **To Motion:** the reverse in at most 300 ms, cancelling anything in flight. Safety beats beauty.

### 7.3 Drive page: cluster layouts
All clusters share the horizon and floor. Default is Apex. Vertical swipe cycles through them and the choice persists.

1. **Apex** (default)
   - Centre: hero speed with a "KM/H" label beneath, surrounded by the tach arc.
   - Driver-side flank: ₹ THIS TRIP (money readout, primary size) with ₹/KM (secondary) beneath.
   - Other flank: coolant bar gauge (vertical) and instant km/L (secondary).
   - Floor: eco bar centred; trip distance on the left, trip time on the right (secondary, `ink.mid`).
   - Horizon: shift horizon and status strip.
2. **Tape** (the brand layout): speed tape on the left, RPM tape on the right, both with trend vectors; instant km/L in the centre at display size with the eco bar beneath; ₹ this trip in the floor.
3. **Minimal:** hero speed only, with a thin RPM line under the digits whose length follows RPM; a small money readout in the driver-side corner. Best at night.
4. **Telemetry:** a 2×3 grid of telemetry tiles chosen from RPM, speed, throttle, load, MAP or MAF, coolant, intake air, voltage and instant km/L, with the shift horizon on top. It's the one dense layout: opt-in, never the default, with every tile value at secondary size.
5. **Road:** the road view (§6.11), full-bleed with its overlays.

### 7.4 Money page
- **Motion:** ₹ THIS TRIP in the centre at display size, with a champagne hero halo; ₹/KM and KM/L beneath (secondary); driver-side flank: idle cost with the hollow idle glyph (the counter pulses gently at 0.5 Hz, only while idling); other flank: the Money Tape; floor: fuel remaining as ₹ and km range, if fuel level is supported; horizon: confidence pips.
- **Parked:** the flanks unfold into the four-bucket breakdown (stacked bar plus legend rows with ₹ and %), the current price per litre with the date of the last fill-up, and a Pit Stop button.
- **No fuel price set:** litres are shown instead of ₹, with a single champagne outlined "SET FUEL PRICE" button (parked only).

### 7.5 Review and Debrief
**Layout** (parked only)
- Left 58%: the route trail, with a SPEED / THROTTLE / ₹/KM selector above it.
- Right: the receipt: ₹ total (display size), then distance, time, km/L, ₹/km and idle time; a WHERE IT WENT stacked bar with legend; one coach tip at the bottom in a bracket frame.
- Bottom 22%: the telemetry scrubber, with the replay's transport left of it (DESIGN.md 6.12).

**Debrief choreography** (runs automatically when a trip ends, meaning the engine is switched off; see CLAUDE.md §8.6 for the exact rule. Standing still with the engine running, in traffic or at a signal, never triggers it. If the engine restarts within 5 minutes, the trip resumes and the Debrief closes.)
1. The cluster powers down: the needle sweeps to 0, segments decay, halos fade (0.8 s).
2. The Money Tape compacts and rolls up into the WHERE IT WENT bar (0.6 s).
3. The route draws itself in light with a comet head (1.6 s).
4. Receipt figures roll up from 0, staggered (0.8 s).
5. The coach tip fades in last.

Total at most 4.5 s. Tapping anywhere skips to the end state. With reduce motion on, the end state shows immediately.

### 7.6 Coach
- Left 60%: the efficiency curve (§6.13).
- Right: the sweet-spot headline; THIS WEEK ₹ against LAST WEEK ₹ with a delta glyph; an 8-week ₹/km trend sparkline; the last three tips as bracketed panels (date, one sentence, ₹ impact).
- **Empty state:** the curve drawn as ghosts, with "Your curve fills in as you drive. Around 50 km of steady driving is enough."

### 7.7 History
- Header: THIS MONTH ₹, distance and average km/L. A week / month / all segmented selector.
- Rows (88 lp): date and time, a 48 lp mini route glyph, distance, ₹, km/L, and a thin mini Money Tape barcode. Tapping a row opens its Review.
- Trips flagged simulated (left by builds that had Demo Mode) are never listed and are excluded from totals.

### 7.8 Garage (settings)
Full-width list rows grouped under bracketed headers:
- **Car:** nickname, fuel type, engine displacement, tank size, max RPM and redline, shift light on/off and shift RPM, calibration status.
- **Adapter:** paired adapter, type, protocol, reconnect behaviour, compatibility mode.
- **Cluster:** default layout, livery, driver side. The livery picker shows live previews rendered by the real components, never screenshots.
- **HUD:** colour, flips, position and scale, alignment pattern (§8).
- **Navigation:** one switch, "Show Google Maps turns on the HUD", off to begin with; a line saying where it stands (off, Google Maps not on the phone, needs notification access, waiting for Google Maps, following Google Maps, Google Maps has gone quiet); a row that opens Android's notification-access screen when that is what is missing; and a plain note that Google Maps does the routing on its own connection, that TapeDash stays offline, sends it nothing and keeps nothing, that Android's access lets an app see every notification and TapeDash looks at Google Maps' only, and that the access can be taken away in Android's settings at any time. A second note says that Google Maps floats a small map over the screen when the person switches away from it during a route, and where in Android's settings to turn that off, because a bright window on the HUD's black is the one thing the glass cannot take. Parked only, like all of Garage.
- **Fuel price and currency.**
- **Coach:** speed threshold; hard acceleration and braking sensitivity as Gentle / Normal / Sporty presets mapping to `CoachThresholds`.
- **Engine sound:** on or off (off to begin with), the engine, the volume, whether the phone's speaker is allowed (no to begin with), a ten second test on whatever output there is, and a line saying where it stands (playing, no car audio, stopped because the output went away). §5.10.
- **Display:** automatic brightness, Daylight and Night automation, reduce motion, fidelity tier (Auto / Lite / Balanced / Full), ignition sequence (Off / Subtle / Full).
- **Units and format.**
- **Speed from:** the car's adapter or the GPS alone, the adapter (change, compatibility mode, record, survey drive, forget) and the connection log: what the app did to reach the adapter, newest first, for when it will not connect.
- **Data:** export trips as CSV to a user-chosen local file; delete all data (slide-to-confirm).
- **About:** version, open-source licences, and the project URL as text plus an offline-generated QR code.

### 7.9 Pit Stop (fill-up)
- Left: the numpad. Right: LITRES and AMOUNT ₹ fields (tap a field to point the numpad at it; the active field is lit), the live computed ₹/L, a FULL TANK light switch, and a SAVE primary button.
- **On save:** a vertical fuel column fills with champagne from the bottom (`spring.reveal`), then collapses into the new price chip. 900 ms total.
- Reachable only when parked.

### 7.10 Diagnostics
- **Adapter panel:** name and version (ATI), protocol, voltage, achieved poll rate as a live sparkline, and the fuel source in use (5E, MAF or MAP).
- **PID matrix:** a grid of small chamfered cells, one per Mode 01 PID from 01 to 60. Supported cells are lit in accent; polled cells pulse faintly on each response. It shows exactly what the car is talking about.
- **Fault codes:** rows with the code (Saira), its description and a stored/pending chip. CLEAR CODES uses slide-to-confirm and is parked only.

### 7.11 Onboarding and the first wow
- **Cold open** (at most 1.2 s): void, then a single horizontal line of light draws outwards from the centre (the tape), then the TAPEDASH wordmark resolves above it. This animation doubles as the fidelity benchmark (§9.2).
- **Choice:** two large chamfer buttons: CONNECT MY CAR (primary) and GPS SPEED ONLY.
- **GPS path:** straight to the GPS screen (§7.15), with no adapter. The app keeps asking until a source is chosen, and never picks one for the person.
- **Connect path:** full-screen scenes, each with a line-art illustration drawn in code in accent (adapter in the port, ignition on, phone on the dash): adapter type → scan and pair → car setup (fuel type, displacement) → fuel price (skippable) → cluster choice (live previews).
- Progress is shown as a thin tape at the top, not dots.

### 7.12 Connection states

| State | Presentation |
|---|---|
| Searching | cluster in standby; a sweep beam rotates around the tach arc (one revolution per 1.6 s); status line "Looking for your adapter" |
| Waiting for ignition | etch only at 15% brightness; one accent dot breathing at 0.25 Hz in the hero position; "Turn on the ignition" at full label colour |
| Connected | ignition sequence (§7.13) |
| Lost | values freeze and fade to `stale`; `caution` line on the horizon; adapter glyph `caution`; "Reconnecting…"; on reconnection, a quick 300 ms re-light instead of the full sweep |
| GPS only | the GPS screen (§7.15), with its own words for a missing location or no fix yet |

Never a blank screen. Never a spinner.

### 7.13 Ignition and shutdown sequences
**Ignition** (on the first valid RPM above 400 after connecting; setting Off / Subtle / Full):
1. 0–450 ms: tach segments light in a wave from 0 to maximum (expo-out), phosphor trailing.
2. 150–900 ms: the needle sweeps to redline and back to the live RPM (`spring.needle`, retargeted).
3. 300–900 ms: numerals roll up from 0 to the live value. In VFD, every segment first lights as 8s, then resolves.
4. 600–1,200 ms: the horizon line draws outwards from the centre; the flanks fade in, staggered.

Subtle runs steps 3 and 4 only. The sequence must never delay live data; values arriving mid-sequence simply retarget.

**Shutdown** (ignition off): the needle falls to 0 on `spring.needle`, segments decay, halos fade, and the Debrief begins (§7.5).

### 7.14 Insights
What the car and the trips add up to, one picture at a time (docs/DECISIONS.md, "Insights"). **Parked only**, from the dock's Insights button; it closes itself when the car moves, like Diagnostics.
- **Layout:** the scrolling selector (§6.14) across the top with CLOSE at its right; under it one panel, filling the screen. A panel is a chart on the left and, on the right, a bracketed column of facts (a label, a Saira figure, a line of plain words), about a third of the width.
- **Tabs:** CURRENT, POWERFLOW, POWER, GEARS, TANK, TOLLS, COLD START, GHOST, YEAR.
- **Every figure is an estimate and says so:** "≈" before it, the shares in whole percents, ₹ in whole rupees, a range to the nearest 5 km. A chart that has no data for part of its range hatches that part and says "no data yet"; it never draws a line across it.
- **Empty states** say the one thing that fills them in ("Fill the tank to the top, log it at Pit Stop with FULL TANK on, and the dash counts the litres from there.").
- **Current** (§6.18): the drive's steady voltage in Saira at 44 lp with CHARGING or ON THE BATTERY, the trace under it inside a tinted charging band (13.6 V and up) with a mark and "−1.5 V" under each of the five deepest dips (never two within 44 lp), the minutes along the bottom. In the facts: the share of the drive charging, the dips (count, typical depth and length), and the battery's resting voltage as a small trend with its last reading lit. What made a dip is not claimed: the car reports no battery current.
- **Powerflow** (§6.18): the energy in a trip's fuel as one river, thick as its share. Fuel on the left splits into WHEELS (top), IDLING (hollow, `caution`, like the Money Tape's idling) and ENGINE HEAT; the wheels split again, on the right, into TYRES, AIR and BRAKES, each with its share of the fuel and, when the trip was priced, its rupees ("BRAKES ≈ 1% · ₹4"). The facts say what reached the wheels and what the brakes took. The wheel share is capped at 40%, a physical limit, so a bad estimate cannot flatter the engine.
- **Power** (§6.18): wheel power against revs from ordinary driving. Dots by throttle (light, firm, full), the highest the dots reach as a white line with a ring on the peak, and everything past the revs the car has reached hatched and marked NO DATA YET. The facts give the highest power seen (the peak of the edge, never a single dot, so one wrong speed reading cannot make the headline) and the revs reached. The power axis is set from the edge with room over it; a dot above the axis is drawn on the top line.
- **Gears** (§6.18): "Gearbox, found". rpm against km/h, a dot for each moment above 12 km/h, and a faint ray from the origin through each crowd the driving has made, labelled with its ratio (rpm for each km/h). The facts list each gear by ratio with the speeds it was held between and its share of the driving. Gears are **not numbered**: one never driven in does not show, so a count from the shortest found could be wrong. A CVT has no crowds, only a fan, and the page says "None" and why; it is told from a gearbox by what the revs do while the speed is changing.
- **Tolls** (§6.18): "The Toll Map". The roads driven, north up and faint, and a hollow `caution` ring wherever the car stood with the engine running (stops of 15 s or more, grouped within 150 m, the twelve dearest), each as wide as what the standing cost, numbered from the dearest. A tap on a ring chooses it (the nearest within 30 lp); the facts give that place's ₹ (litres with no price), the time standing still and the stops, and the total since the first trip. No names: the app has no map, so a place is where the ring sits on the roads. Hollow, as the Money Tape's idling is.
- **Cold start** (§6.18): the cold-start bill. ₹ a kilometre against the minutes of a drive that began under 65 °C, the warm cost (the median of at least three minutes at 80 °C and over) as a dashed line, the cold running's extra between the curve and that line hatched in `caution`, the coolant as a thin line on its own scale, and the minute the engine was warm marked. A window dearer than 2.2 times the warm cost is drawn at the top, so a few seconds of stop-start cannot stretch the axis. The facts give this drive's extra ("≈ ₹3 over the warm cost, in 1.7 km") and the month's. If the chosen trip began warm, the latest that began cold is shown. Moving windows only.
- **Ghost** (§6.18): "Ghost commute". This drive's route in light with its start (hollow circle) and end (filled square), the earlier drive of the same route dashed behind it, both fitted together; under them the two Money Tapes, one above the other, each with its date and its ₹. The facts give the difference in rupees ("₹14 less", "₹9 more"), then, in plain words and only when there is one, the minutes standing still and the hard starts. **Rupees, never minutes**: it says nothing about being faster. A route counts as the same when both ends are within 400 m, its length within 1.3 times and 24 points along it within 180 m on average.
- **Year** (§6.18): "Year on Tape". A poster of the year, and one button. The poster is every trip as a bar of one barcode in the order of the calendar (two on a day share its slot), stacked by where the money went (normal `money.deep`, idling `caution` at 60%, hard acceleration `critical`, high speed `accent.deep`), the months along the foot, and the year's trips, kilometres, spend, idling (₹ and share) and sweet spot under it, marked "Estimates". The tallest bar is the 98th percentile of the trips, so that one trip to another city does not make the rest a hair. **SHARE** (the one primary button of the page, §6.14) draws the same poster at 1920 × 1080 in the current livery (never Daylight or Night), writes it to the app's cache and opens the phone's own share sheet; TapeDash sends nothing, and says so under the button. A year selector appears only when the trips span more than one year. No other control, no text field, no preview of the sheet.
- **Tank** (§6.18): a column that drains from the top, its surface a champagne line, the reserve (the last eighth) hatched in `caution`; beside it the litres left in Saira at display size and the range. The same count fills the Money page's fuel-left slot for a car that sends no level, marked "≈".

### 7.15 GPS only
A drive from the phone's GPS with no adapter: one screen, not the strip, because there is nothing for four of the five pages to say. Chosen at the cold open (GPS SPEED ONLY) or in Garage → Speed from, never by the app.
- **Layout:** the Minimal cluster's, without its RPM line. The hero speed in the centre zone (`bright`, `hero` size, shrinking to `primary` when parked like every cluster's), KM/H under it, and one row of five readouts at `secondary` size: DISTANCE (km, one decimal), MOVING (h:mm), AVERAGE, FASTEST (km/h) and HEADING (N, NE, E…). Each is a label over its number, in the numeral face. The status strip is the usual one with the GPS glyph alone on the left.
- **Honest numbers:** AVERAGE is a dash until there are ten seconds of moving, and HEADING a dash at a standstill. The speed is the receiver's own (the Doppler speed), zero below 1.5 km/h; the distance is that speed over time and never the sum of positions, which wander by metres at a red light.
- **Before there is a speed**, the centre says why in words and never shows a zero it does not have: STARTING GPS; LOCATION NEEDED with ALLOW LOCATION (the one button, parked or not, since there is no driving yet); NO GPS; LOOKING FOR GPS ("Give the phone a clear view of the sky; the first fix can take a minute. Check that location is on in the phone's settings."). After the first speed a lost fix (a tunnel) keeps the last number on screen, dimmed as any stale number is, and never swaps it for words.
- **Parked dock:** Garage, HUD and RESET TRIP (the distance, time and fastest back to nothing). No Pit Stop, Diagnostics or Insights: they are about the car.
- **HUD:** the Drive HUD's speed and its unit, and no RPM bar.
- **Garage** shows Speed from, Cluster (livery and driver side only), HUD, Display and About; the groups about the car (its fuel, the price, the coach, the layout, the trips) are left out.
- **Not here, and not invented:** a tach, money, a coach, trips, an engine sound. They need the car.

---

## 8. HUD

The HUD is one component of the product, not its design language. It inherits typography and motion, but windshield optics impose their own rules.

**Optics**
- A windshield reflects only a small fraction of the phone's light, and the two glass surfaces of a laminated windshield add a faint double image. Only bright, bold, simple shapes survive; thin or dim elements vanish.
- L0 and L1 are hidden entirely: pure black background, no etch. Halos off (they smear). No trails, no streaks.
- Strokes at least 5 lp. Labels at least 0.06H. Numerals SemiBold or heavier.
- **One colour, chosen by the user:** HUD Green #5CFF7A (default, the most visible), Ion #5CE1FF, Amber #FFB020 or White #FFFFFF. Critical alerts still use `critical`.
- No large filled bright areas at night (glare and double images). Numerals may be filled; panels never.

**Layouts:** Drive HUD (huge speed, thin RPM bar beneath, alert slot); Drive + Money HUD (speed left, ₹ this trip right); Money HUD (huge ₹ this trip, ₹/km beneath).

**Navigation layout** (docs/NAV.md). While Google Maps is navigating on the phone and the Garage switch is on, the HUD shows this layout in place of the chosen one, and puts the chosen one back when Maps stops. Nothing is asked of the driver.
- **Left half:** the speed, as in Drive + Money (0.34H), with KM/H under it.
- **Right half, the turn:** Google's own arrow, a one-colour mask painted in the HUD colour (0.34H square, its ink on the same edge as the words under it); the distance to the turn beside it, number in the numeral face at 0.17H and its unit as a label, shrunk to fit if long; and under it Google's instruction in UPPERCASE, up to three lines at 0.068H, cut at a word and ended with an ellipsis when it is too long. The instruction is Google's text in the phone's language, so it is not held to the six-word limit of §11; it is the one deliberate exception.
- **The approach line** (the "line map"): a bold line (at least 5 lp) from the car at the foot to a ring at the junction, leaning to the side the arrow turns (read from the arrow's own picture; straight when it is straight or cannot be read), with a filled dot on it that climbs as the distance to the turn falls (over the last 500 m, counting down on the car's own speed between Maps' updates). It is a sketch of the next junction. **It is not a map**: Google Maps does not give out its route, and the HUD does not pretend to draw one. At the turn the dot fills the ring.
- **Along the bottom:** the ETA (`9:25 PM`), the time left (`25 MIN`, or `1:05 H`) and the distance left (`5.4 KM`, or miles when Maps writes in them), numerals at 0.10H and units as labels. The time left is Google's when it gives it, and otherwise the ETA less the phone's clock.
- **States, told by words and shape, never by colour alone:** Maps' own words for `Starting navigation…` and `Rerouting...` (no arrow, no line, no figures); and when Maps has been silent for 15 s with the car moving (3 minutes standing), **NO UPDATE** and a dash in place of the turn, with no figures: an old turn is never shown as a live one. Everything else is the HUD's: one colour, pure black, no halo, no trail, nothing that fills an area.
- A distance in a unit the app has not seen is shown in Google's own text, never converted by guess; a figure Maps did not give is left out.

**Orientation:** Flip Horizontal (default on) and Flip Vertical toggles, plus vertical position and scale sliders, so it works however the phone is placed.

**Alignment pattern** (Garage → HUD, parked only): a full-screen test pattern with a crosshair grid, the wordmark, a large "F" and an "↑ UP" marker, rendered with the current flips so the user can confirm orientation and position in the windshield before driving.

**Brightness:** maximum in daylight; at night it follows the lux curve with a 20% floor.

**Motion:** detented numerals on `spring.gauge` only; nothing overshoots.

---

## 9. Fidelity tiers and performance craft

### 9.1 Tiers

| | Tier 1 · Lite | Tier 2 · Balanced | Tier 3 · Full |
|---|---|---|---|
| Frame rate | 60, 30 fallback | 60 | display maximum (90/120) |
| Halos | baked, half resolution, hero and needle only | baked, all luminous elements | baked, plus shader bloom |
| Needle trail | 2 | 6 | 12 |
| Phosphor | segments only | all luminous elements | all luminous elements |
| Parallax | off | on | on |
| Tach segments | one per 200 rpm | one per 100 rpm | one per 100 rpm |
| Road streaks | off | up to 40 | up to 120 |
| Digit velocity stretch | off | off | on |

Tier 1 must still look intentional and premium. Composition, typography, light hierarchy and springs are identical across tiers.

### 9.2 Detection and governor
- **First launch:** record frame timings (`SchedulerBinding.addTimingsCallback`, `FrameTiming`) during the cold-open animation, and pick the highest tier whose budget the p90 frame fits with 25% headroom.
- **Runtime governor:** if the p90 frame time exceeds the budget for 5 s, step down one tier with a 400 ms crossfade. Never step up during a trip; re-evaluate on the next launch.
- Phone temperature above 50 °C forces Tier 1 at 30 fps (CLAUDE.md §9).
- The user can override the tier in Garage → Display.

### 9.3 Craft techniques (mandatory)
- **Glyph atlas:** render digits 0–9 and the symbols `. − ₹ % ° ×` once per size, weight and colour role into an image atlas. Draw live numerals with `Canvas.drawAtlas` / `drawRawAtlas` using preallocated transform buffers. No `TextPainter` layout in the per-frame path.
- **Glow sprites:** generate halo sprites once with `MaskFilter.blur` into images (`PictureRecorder` → image) and composite them with `BlendMode.plus`. Rebuild only when size or livery changes.
- **Static layers:** L0 and L1 for each layout are recorded into a `Picture` (or image) inside a `RepaintBoundary` that never repaints while driving.
- **Batched segments:** tach and horizon segments are drawn with one `drawAtlas` call (or one path) per colour state, never one draw call per segment.
- **Zero allocation per frame:** reuse `Paint` and `Path` objects (`reset()`), `Float32List` and `Rect` buffers. No closures, lists or strings created while painting.
- **Banned in the per-frame path:** `saveLayer`, `ClipPath`, `Opacity` widgets, `ShaderMask`, `BackdropFilter`. Put alpha into colours; clip only with rectangles.
- **Repaint through `Listenable`s**, each component in its own `RepaintBoundary`. Widgets never rebuild for live data.
- **Precompute** route path metrics, downsampled traces and projected points when data loads (in an isolate if heavy), never while painting.
- **Fragment shaders** (`FragmentProgram`) only in Tier 3, behind a runtime compile check with a fallback.

### 9.4 Budgets
Tier 1 on the reference old device:
- UI thread under 5 ms and raster thread under 9 ms at p90 during a simulated drive on Drive / Apex.
- No frame above 32 ms during the ignition sequence, page swipes or Motion ↔ Parked transitions.
- **Reference device:** a phone from around 2016–2018 with 2 GB RAM, a Snapdragon 4xx-class or similar chip, Android 7–8 and a 720p screen. If none is available, say so in the review package and profile on the lowest-end device available.

---

## 10. Voice and copy

- Calm, precise, enthusiast-literate. Never cute, never shouty. No exclamation marks, no emoji.
- **Instrument labels** in UPPERCASE with tracking: SPEED, KM/H, RPM ×1000, COOLANT °C, THROTTLE %, ₹ THIS TRIP, ₹/KM, KM/L, IDLE.
- **Parked UI** in sentence case.
- **Numbers:** Indian digit grouping for money (₹1,23,456); ₹ directly before the number with no space; one decimal for ₹/km, km/L and distances under 100 km; whole numbers for speed and RPM.
- **Estimates:** "≈" in parked detail views; confidence pips beside money everywhere.
- **Status lines** are plain instructions: "Turn on the ignition", "Unplug the adapter and plug it back in".
- **Coach lines** state facts with money, without shaming: "₹24 of this trip went on idling — about 14 minutes with the engine on."

| Instead of | Write |
|---|---|
| Error: NO DATA | Your car isn't answering. Check the ignition is on. |
| Oops! Connection lost 😬 | Reconnecting… |
| You wasted ₹40! | ₹40 went on hard acceleration this trip. |
| Fuel efficiency: 14.6237 km/L | 14.6 KM/L |

---

## 11. Accessibility and safety

- **Contrast:** primary values at least 7:1 against `void`; labels and all other text at least 4.5:1; Daylight mode primary values at least 10:1. `critical` values and `stale` values are exempt from the 7:1 and 10:1 rules (a saturated red can't reach 7:1 on black, and stale values are dimmed on purpose), but they must still reach 4.5:1 and are always paired with a glyph, bracket or other non-colour cue.
- **Never colour alone:** every state also changes shape, position or glyph (hollow idle blocks, notched hard-acceleration blocks, alert brackets, glyphs in the alert slot).
- **Nothing flashes faster than 3 Hz.**
- **Motion mode:** no text longer than six words, no lists, no scrolling, and no controls other than the page swipe, cluster swipe and HUD double-tap. The only exception is the long-press that opens the developer debug overlay (CLAUDE.md §9).
- Driving screens use screen-relative sizes and ignore system font scale; parked UI honours it up to 1.3×.
- Reduce motion as specified in §5.8.
- No sounds and no vibration by default.

---

## 12. Brand

- **Wordmark:** TAPEDASH in wide Saira SemiBold, tracking +6%, with a single thin line of light (the tape) beneath, extending past both ends and fading out. Ion by default; inside the app it takes the livery's accent.
- **App icon** (adaptive): `void` background; foreground is a five-segment fragment of the tach arc with the last segment lit and glowing, above a short chamfered strip. It must read at 48 px. Include a monochrome layer for Android 13 themed icons.
- **Launch:** Android `LaunchTheme` window background is `void`; the Android 12+ splash shows the icon foreground on `void`; the first Flutter frame is `void`. **No white flash, ever.**
- **Store screenshots:** real renders from simulated drives in every livery, captured with the Design Lab. Never mockups.

---

## 13. Implementation map

### 13.1 Structure
```
lib/ui/design/
  tokens/       colors.dart, livery.dart, typography.dart, spacing.dart, strokes.dart, motion_tokens.dart
  theme/        tape_theme.dart   # InheritedWidget: livery, mode, tier, driver side, reduce motion
  fidelity/     tier_detector.dart, governor.dart
  motion/       motion_clock.dart, spring_value.dart, phosphor.dart, smoothing_pipeline.dart, odometer.dart
  render/       glyph_atlas.dart, glow_cache.dart, static_layer.dart, seven_segment.dart, chamfer.dart, grain.dart
  icons/        icons.dart
  components/   rolling_numerals, tach_arc, tape_gauge, shift_horizon, bar_gauge, telemetry_tile,
                eco_bar, money_readout, money_tape, status_strip, alert_frame, road_view,
                route_trail, telemetry_scrubber, efficiency_curve, sheet, touch_bloom,
                controls/ (button, toggle, segmented, list_row, slide_confirm, numpad, text_field)
lib/ui/lab/     design_lab.dart plus one page per component
```
- Use `WidgetsApp`, or `MaterialApp` purely as a shell with everything overridden.
- **Banned in `lib/ui/`:** AppBar, Card, ElevatedButton, TextButton, OutlinedButton, FloatingActionButton, Switch, Slider, Checkbox, Radio, ListTile, SnackBar, Dialog, AlertDialog, CircularProgressIndicator, LinearProgressIndicator, `Icon(Icons.…)`, InkWell and ink ripples, BottomNavigationBar, TabBar, Drawer, and Scaffold's default chrome.
- **No `Color(0x…)`, `TextStyle(`, `Duration(` or spring constants outside `tokens/`.**
- Both rules are enforced by the design-lint test (§14.2).

### 13.2 The Design Lab
A hidden developer screen, always shipped, opened from the debug overlay or a launch flag:
- A gallery of every component with a slider for each input, plus a "drive" button that feeds it a simulator scenario.
- Switchers for livery, mode (normal / Daylight / Night), fidelity tier, Motion / Parked, driver side, reduce motion, and aspect-ratio frames (16:9, 18:9, 20:9).
- Slow motion via `timeDilation`: 1×, 0.5×, 0.25×, 0.1×, for tuning springs.
- A live frame-timing graph (UI and raster, p50 and p90).
- **Capture all:** renders every page × livery × mode to PNGs in app storage, for the review package and store screenshots.

---

## 14. Design QA and the review gate

### 14.1 Golden tests
- Load the real bundled fonts in tests (`FontLoader`) so goldens show real typography.
- **Matrix:** every component in its key states; every page × {ION, VFD, EMBER, MONO} × {Motion, Parked} × {normal, Daylight, Night} at 640×360 and 800×360 in Tier 2 (Motion applies to Drive and Money only; the other pages are parked-only); every HUD layout in all four HUD colours, with flips.
- Drive a `FakeClock` and the simulator to fixed timestamps so frames are deterministic.
- Generate goldens on one platform only (CI Linux).

### 14.2 Design tests
- **Design lint:** fail on banned Material widgets, or colour, text style, duration or spring literals outside `tokens/`.
- **Springs:** needle overshoot ≤ 6% and settle ≤ 0.45 s; `spring.gauge` and `spring.snap` never overshoot; retargeting preserves velocity; no NaN on extreme inputs.
- **Odometer:** detent behaviour matches §5.6; carries happen only during 9 → 0; the ones column's x position is identical for 7, 77 and 107.
- **Phosphor:** decay matches τ within 5%.
- **Stale data:** the fade starts at 1.5 s.
- **Motion lock:** locked pages are unreachable above 3 km/h; the Motion layout is restored within 300 ms of moving.
- **Flashing:** every blinking element stays at or below 3 Hz.
- **Contrast:** every token pair used for text meets §11.

### 14.3 Visual checks
Done by the agent on renders and recordings:
- **Glance test:** each driving screen shown for one second — are speed and the page's main value unmistakable?
- **Squint test:** blur the screenshot — does the hierarchy survive (hero first, secondary second, etch last)?
- **Daylight test:** Daylight renders are legible at a glance.
- **Night test:** nothing dazzles; the brightness floor is respected.
- **Jitter test:** a slow-motion recording of a simulated drive shows no digit wobble, no reflow and no needle jumps.
- **Soak test:** 30 minutes of simulated driving on the oldest device holds the frame budget, with no memory growth; note the temperature.

### 14.4 The design review package
Required at the end of every UI phase, written to `docs/design-review/<phase>/`:
- `README.md`: what was built, which signature moments are finished, every deviation from this document and why, and open questions for the human.
- `screenshots/`: every page × livery × mode (from goldens, plus device captures when available) and the HUD alignment pattern.
- `video/`: a 60–90 s screen recording (`adb shell screenrecord`) of a simulated drive showing the ignition sequence, a swipe to Money, a cluster change, Motion → Parked and the Debrief, when a device or emulator is available.
- `perf.md`: frame timings per tier (p50, p90, p99), the device used, and the tier auto-selected.
- If anything couldn't be captured (no device, no emulator), say so plainly. Never present unverified visuals as done.

### 14.5 Definition of done for UI work
- Built only from tokens and components, and present in the Design Lab.
- Works and looks intentional in Tier 1, in every livery, in Daylight and Night, at 16:9 and 20:9.
- Golden and design tests pass.
- Motion reviewed in slow motion: nothing linear, nothing jumps.
- Copy follows §10.
- Design review package written.

---

## 15. Never do this

- Material look and feel: ripples, elevation shadows, cards, floating action buttons, default switches, app bars, snackbars, dialogs.
- System fonts or Roboto. Proportional digits. Digits that shift sideways.
- Linear tweens on data; fixed-duration animations of live values; animations that block input.
- Spinners, blank screens, raw error strings.
- Glassmorphism via runtime blur; more than three strong halos at once; rainbow gradients; chrome bezels; fake 3D metal; wood or leather textures.
- Glitch effects, scanlines, "hacker" aesthetics.
- Copying any manufacturer's cluster, logo, fonts or visual identity; real car models in the road view.
- Text-heavy driving screens; more than three primary values on a driving screen; tips or pop-ups while moving.
- Anything flashing faster than 3 Hz.
- A white frame anywhere, including at launch.
- Calling a screen done without its design review package.

---

## 16. The watch

TapeDash also runs on an Android watch (Wear OS on a Galaxy Watch4 Classic was the first, 2026-10-23). It is the same app and the same services on a much smaller, round screen, so it has **its own surface**, composed from the same components and tokens, and not the phone's layouts squeezed. Squeezing was tried by accident: on a 225 lp face the Apex cluster piles the speed, the tach labels, the money and the trip figures on one another, and the bezel cuts off the corners (the clock, the glyphs, the first and last tach numbers). Everything in §2 to §15 holds unless this section says otherwise.

### 16.1 What the watch is for

- **A glance.** On the wrist, or strapped to the vent or the column, the watch answers one question in under a second: *how fast, how hard, how much*. That is the speed, the revs and the ₹ of this trip. Nothing else is on the driving face.
- **Not a second phone.** Review, Coach, History, Insights, Diagnostics, Pit Stop's numpad, the survey drive, the HUD, the engine sound and the four other clusters are **phone only**. A watch has no room to draw them honestly, and a thumb-sized numpad on a 1.4 inch circle is the opposite of "no text entry". What the watch records goes to the phone to be looked at, and what the watch needs set up comes from the phone, as a file (`docs/EXCHANGE.md`).
- **Slow to set up, so little to set up.** The watch has defaults for everything, a short connect flow (type, find, test), and a few wheels for the things worth changing on the spot (the price, the livery, the source). The rest arrives by import.

### 16.2 Form factor

- A drive screen is the watch's when the platform says it is a watch (`FEATURE_WATCH`, or the UI mode type watch) or, where it cannot say (an emulator, a test), when the **shorter side is under 300 lp**. A watch is taken to be round unless the platform says it is not.
- **Orientation:** the landscape lock of CLAUDE.md 3 is for phones. On a watch the display keeps the orientation the system gives it (a wrist has an up, and it is 12 o'clock). Nothing here is drawn rotated.
- **Authored at 225 lp** (a 46 mm Galaxy Watch4 Classic: 450 px at 2x), checked at **192** (Pixel Watch), **198** (a 42 mm Galaxy Watch4), **240** and a stress size of **280**. Every dimension below is a share of the face's diameter **D**, never a pixel count, so one set of rules serves them all.

### 16.3 The round face

A screen that is a circle makes its corners invisible. **Nothing is drawn, and nothing that matters sits, outside the circle of diameter D** (a test renders every face and fails on any lit pixel in the corners). The face is made of five zones, named like the phone's:

| Zone | Where | Holds |
|---|---|---|
| **Rim** | the outer 7% of the radius | the instrument ring: the tach arc, the money ring |
| **Crown** | 11 to 1 o'clock, inside the rim | the link glyphs; the warm glyph |
| **Core** | the disc inside the rim | the hero |
| **Foot** | below the core's centre, between the ring's two ends | the ₹ readout |
| **Opening** | the gap in the ring at 6 o'clock | the eco arc; on parked faces, the page tape's ticks |

- Rim outer radius 0.485 D, depth 0.07 D; core radius 0.37 D. Text sits where the chord of the circle at its height is wide enough for it: a line of width *w* centred at height *y* needs `2·sqrt(r² − dy²) ≥ w`, and the layout asks `WatchFace.chordAt` and never guesses.
- **The Tape is a ring.** Tapes are TapeDash's native instrument and a straight tape does not fit a circle, so the speed tape became the **rim**: an arc of segments that lights to the revs (the tach arc, §6.2, on the rim) and a ring of ₹ blocks (the Money Tape, §6.8, wrapped round). The watch's bezel is a ring too, which is the point.

### 16.4 Type on the watch

The scale is `WatchType.forDiameter(D)`, clamped:

| Token | Share of D | At 225 | Use |
|---|---|---|---|
| `hero` | 0.34 | 76 | speed |
| `display` | 0.21 | 47 | ₹ this trip on the Money face |
| `primary` | 0.13 | 29 | the ₹ on the Drive face, a wheel's chosen row |
| `secondary` | 0.09 | 20 | ₹/km, the wheel's other rows |
| `label` | 0.062 | 14 | instrument labels; **never under 12 lp** |

- Numerals are **at least weight 500** on the watch: a Light face (MONO) at an angle, on a wrist that moves, disappears. MONO keeps its character in colour and in thin rings, not in a hairline numeral.
- Strokes on the rim are at least 2 lp. Daylight and Night apply as on the phone, from the watch's own light sensor.
- Parked text is Barlow at the watch's own sizes (`secondary` to `label`), at most two lines, never a paragraph. The system font size is ignored on the watch.

### 16.5 The faces

The watch has a **reel** of faces, one at a time, filling the circle. Motion has two; Parked has four.

1. **Drive** (home). *Rim:* the tach arc, 240°, opening at the bottom, one segment per 200 rpm, with the blade needle, the peak tick and the redline. *Core:* the speed, with KM/H beneath. *Foot:* ₹ THIS TRIP with its confidence pips. *Opening:* the **eco arc**, the eco bar (§6.7) bent into the ring's gap: a centre notch for this car's average and a puck that rides ±20° round the bottom, in the eco ramp's colours. *Crown:* the adapter and GPS glyphs, a warm glyph when the watch is hot, and an alert in the same place (§6.10). A drive on the GPS alone has no revs: the rim is a speed arc (0 to 140) and the Foot is the trip's distance.
2. **Money.** *Rim:* the **money ring**, every ₹ of the trip as a block printed clockwise from 12 o'clock (72 cells; past 72, a cell is ₹2, ₹5, ₹10 and so on, and the Opening says "1 BLOCK = ₹5"), in the buckets' styles of §4.3 (solid normal, **hollow** idling, notched hard acceleration, accent high speed). *Core:* ₹ THIS TRIP at display size. *Foot:* ₹/KM and the idle ₹ with the hollow idle glyph (pulsing at 0.5 Hz while idling).
3. **Where it went** (parked only). The four buckets as rows (swatch, name, ₹, share), the idling row first when it is the dearest, and the **estimates marked "≈"** as everywhere (§10). The ring is the trip's whole barcode.
4. **Menu** (parked only), the wheel of §16.7.

**Motion lock.** In Motion only Drive and Money are reachable. A swipe towards a locked face rubber-bands. A face left on when the car starts moving returns to Drive on `spring.snap`, inside 300 ms (§7.2). **To Parked:** the ring thins and dims to 60%, the hero shrinks to `primary`, the Opening's eco arc gives way to the page tape, and the reel opens to four faces. **No tips, no text longer than six words, no lists and no scrolling in Motion** (§11).

### 16.6 Input

A wrist cannot swipe precisely, and a driver's hand is on the wheel. The watch has three ways to turn the reel, and they are the only controls in Motion:
- **The bezel** (or a crown), where there is one: one detent, one face. A watch with no rotary input simply never sends one.
- **A vertical swipe** anywhere on the face.
- **A tap** anywhere on the face: the next face (and round again). It is the easiest gesture and the least harmful, since a stray tap only swaps Drive and Money.

Horizontal swipes are **not used** in Motion: on Wear OS a swipe right is the system's own back. In Parked, a swipe right closes an overlay, as Wear users expect, and so does the Back button (which does nothing in Motion, so that a knock on the wrist cannot close the dash). There is no long-press and no double-tap on the watch, and so no HUD; the debug overlay opens from a long-press on the About row of the menu.

Touch targets are at least 48 lp with 8 lp between (§6.14); on the watch a wheel's row is 56 lp.

### 16.7 The wheel (the watch's list, picker and dial)

One component serves every parked choice (its title, where it is, sits high in the circle at 0.12 D, above the row that comes over the chosen one). A column of rows with the chosen one at the centre, full size and in the accent; the rows above and below at 70% and fading; the bezel, a swipe, or a tap on a neighbouring row moves it, on `spring.gauge`, one detent per row, like the odometer's (§5.6). A tap on the centre row chooses it. It is a **menu** (rows with a chevron), a **choice** (livery, source: the row lights while chosen) and a **dial** (the price: the rows are values, the bezel steps ₹0.10 and a swipe ₹1). Entering a number on the watch is always a dial and never a keypad.

The menu's rows, for a drive from an adapter: CONNECT (the adapter and its state), SPEED FROM, PRICE ₹/L, LIVERY, DATA, END TRIP, RESET (hold to confirm), ABOUT. From the GPS alone: CONNECT, SPEED FROM, LIVERY, DATA, RESET, ABOUT. **RESET and any other destructive row is confirmed by holding the centre for 1.2 s while a ring fills**, never by a single tap (§6.14, for a screen on which a drag is not precise).

### 16.8 First run and connection

- **Cold open** (§7.11), on the face: the line of light draws across, the wordmark resolves above it.
- **Choice:** two chamfer buttons, CONNECT MY CAR and GPS SPEED ONLY, 48 lp tall (a touch target, §6.14) and as wide as their words, one above the other, the wordmark just over them, all as low in the circle as the lower button's corners allow (at 225 lp the first is at 0.37 D).
- **Connect:** TYPE (Bluetooth, which finds both radios, or WiFi, or Cancel) as a wheel, FIND as a wheel of the adapters the radios have seen (each with its radio and how close, nearest first), tried before it is taken. When one will not open the wheel becomes the way out: forget the pairing and pair again, try its other radio, use it anyway. A WiFi adapter is offered at its usual address (192.168.0.10, port 35000) and any other address arrives by import. A short arc of the rim shows how far through it is. The car's fuel type, displacement, tank, the price and the layout are **not asked**: they have the defaults of CLAUDE.md 8.4 and arrive by import or from the menu.
- **GPS only** (§7.15) on the watch is a reel of two faces: the speed as the hero inside a **speed arc** (0 to 140 km/h, one segment per 4, lit as the revs are on an adapter's face), the trip's distance in the Foot, the glyph of the GPS alone in the Crown, and, parked, the moving time and the fastest speed over the hero; and the menu's cover. Before there is a speed the centre says why in a few short lines, and a tap on "Location needed" asks again.
- **Connection states** (§7.12) are drawn on the face: SEARCHING sweeps a beam round the rim and says "Looking for your adapter" in two lines at the label size; WAITING FOR IGNITION breathes one dot in the hero's place and says "Turn on the ignition"; LOST dims the values, lights a `caution` arc and says "Reconnecting…". Never a spinner, never a blank face.

### 16.9 Power and heat

A watch has a 250 to 400 mAh battery and a skin to keep cool.
- **The canvas is plain `void`**: no vignette and no grain (§4.1, 4.10), so that on an AMOLED the dark pixels cost nothing and the corners are exactly black.
- **The fidelity tier starts at Lite** and is capped at Balanced (§9): the cold open's benchmark may raise it to Balanced and never to Full; one segment per 200 rpm, the cheapest halos, no parallax. The governor, and the heat rule of CLAUDE.md 9 (the warm glyph, and dimmed and held at Lite when too hot), apply to the watch's own battery temperature. A watch gets hot sooner than a phone, and the watch's thresholds are **41 °C and 45 °C** (a phone's are 45 and 50). *(Built.)*
- **Parked and untouched for 60 s the face dims to its Night floor** (12%), and a touch or a bezel turn brings it back. *(Specified, not built: it waits for a real watch to show how Wear OS treats the screen of an app that keeps it on.)*
- Reduce motion (§5.8) is on the menu's LOOK row on a watch with a system animation scale of 0.

### 16.10 The review gate for the watch

- The golden and capture matrix of §14.1 gains the watch: every face × {ION, VFD, EMBER, MONO} × {Motion, Parked} × {normal, Daylight, Night} at **198, 225 and 240 lp**, in Tier 1.
- **Round-safety test:** every face, every size: no pixel outside the circle is lit.
- **Text-fit test:** every line of text on every face fits the chord of the circle at its height.
- **Touch test:** every control is at least 48 lp.
- **Glance test:** each driving face shown for a second: are the speed, the revs and the ₹ unmistakable? **Wrist test** (only on a real watch): the same at arm's length, at an angle, in sunlight, on a moving wrist. Until then the watch is "unverified on hardware" (CLAUDE.md 11).

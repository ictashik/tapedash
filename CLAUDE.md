# CLAUDE.md — TapeDash

TapeDash is a free, open-source, **strictly offline** Flutter app. It turns an old Android phone into:

1. a smooth, world-class car dashboard, with a windshield HUD as one of its components,
2. a **trip computer that shows where the money goes** (₹ per trip, per km, idling cost), and
3. a gentle **driving coach**.

All of this runs off a cheap ELM327 OBD-II adapter. The whole user story: buy an ELM327, plug it into the OBD port, stick an old phone to the dash with double-sided tape, and drive. Optionally use a reflector film or a 3D-printed HUD holder.

**How this project is built:** everything is developed and tested against a **built-in vehicle simulator** first. Real OBD hardware (Bluetooth Classic, BLE, WiFi adapters on a real car) is connected by the human **only after every simulator test passes**. See section 11, "Hardware handoff".

**Design is half the product.** TapeDash is for car enthusiasts who know the world's best instrument clusters and want that on their own dash. The complete visual, motion and interaction spec is **[DESIGN.md](DESIGN.md)**, and it is as binding as this file. The HUD is one component of that design, not the design itself.

Read this file and DESIGN.md fully before starting. Re-read the relevant DESIGN.md section before building any component or screen. When something here conflicts with a request, ask before deviating.

**Which file wins:** CLAUDE.md is authoritative for architecture, data, offline guarantees, safety and performance budgets. DESIGN.md is authoritative for look, layout, motion, interaction and copy. If a design effect breaks a budget, don't silently drop it: use the cheaper technique in DESIGN.md §9.3, fall back a fidelity tier (DESIGN.md §9.1), and ask the human if the look still suffers.

---

## 1. Non-negotiable principles

1. **Strictly offline.** No cloud, accounts, analytics, crash reporting, ads, remote config, price APIs, or runtime downloads. Every asset is bundled or loaded from a file the user picks. Fuel prices are **entered by the user**, never fetched.
2. **Old devices first.** Everything must run smoothly on a 2GB-RAM, 32-bit ARM phone with an old GPU and a 720p screen, running Android 7.0.
3. **Simple to use.** Install to live gauges in under two minutes, with no manual needed. Sensible defaults over settings.
4. **Open source and F-Droid compatible.** No Google Play Services, Firebase, or proprietary SDKs, directly or transitively. Only OSI-approved licenses.
5. **Safety.** No interaction is required while driving. The coach **never nags during a drive**: live feedback is limited to subtle visual cues, and detailed tips appear only when the car is stopped or the trip has ended. No pop-ups, text entry, or small tap targets on driving screens. DESIGN.md §7.1–7.2 and DESIGN.md §11 define the Motion and Parked rules. The optional engine sound (DESIGN.md §5.10) is opt-in and passive: it says only what the tach says, and never carries a cue, an alert or a voice.
6. **Honest numbers.** Fuel and money figures are estimates. Label them as such, show calibration confidence, and never show false precision (round ₹ to whole rupees and km/L to one decimal).
7. **Simulator first.** Every feature must be exercisable end-to-end with the simulator, headlessly, in `flutter test`.
8. **World-class design on every device.** Every screen follows DESIGN.md: an instrument, not an app. No Material look, no jitter, no linear motion, and it must look deliberate on a 2016 phone, not just a flagship.
9. **Nothing is done until it's reviewed.** Every phase that touches UI ends with a design review package (DESIGN.md §14.4). The human reviews the design only through that package.

---

## 2. Git workflow (follow every session)

### Repository setup (first session only)
- Check whether the working directory is a git repo (`git status`).
- If it isn't, **stop and ask the user** before creating anything:
  - Confirm the repo name (default `tapedash`) and whether they've created a GitHub remote. If they have, ask for the URL.
  - Confirm the license. Recommend **Apache-2.0**. If they want GPL, note that it binds the whole app.
- Then run `git init -b main`, add `.gitignore` (the standard Flutter one plus `*.jks`, `key.properties`, `/recordings/private/`), `LICENSE`, `README.md`, this file and `DESIGN.md`, and make the first commit.
- Never create or push to a remote without the user's explicit approval.

### Commits
- **Commit after every meaningful step**, meaning any change that builds, passes tests and does one coherent thing. Examples: the simulator's engine model, the PID parser plus its tests, the glyph atlas, the tach arc component, the money engine, a new page.
- Before each commit, run `flutter analyze`, `flutter test` (including the design tests), and `tool/check_offline.sh`. Never commit a red build. If a step genuinely can't be green, say so and ask.
- Use Conventional Commits: `feat(sim): add city stop-go scenario`, `feat(design): detented odometer numerals`, `feat(money): idle cost attribution`, `fix(elm): handle SEARCHING... prefix`, `perf(tach): batch segments with drawAtlas`, `test:`, `docs:`, `chore:`, `refactor:`.
- Keep commits small. Don't mix refactors with features.
- Commit golden image updates separately (`test(golden): …`) with a one-line reason, so visual changes are easy to review.
- Never commit signing keys, keystores, `key.properties`, or recordings from someone else's car.
- Push only when the user asks, or if they've said "push after each commit".
- After each phase in section 13, update `docs/STATUS.md` and suggest a tag such as `v0.1.0-sim`.

---

## 3. Target platform and build

- **Android only** for v1. iOS is out of scope: Bluetooth Classic ELM327s, the cheap common ones in India, can't work on iOS.
- **minSdk:** as low as current Flutter stable allows (target API 24, Android 7.0). Never raise it for convenience.
- **targetSdk:** current Play requirement.
- **ABIs:** ship `armeabi-v7a` and `arm64-v8a`. Never drop v7a. Build with `flutter build apk --release --split-per-abi`.
- **APK budget:** under 20 MB per ABI, fonts included (subset them).
- **Orientation:** landscape only (both landscape orientations).
- **Launch:** the launch theme background is DESIGN.md's `void` colour. No white flash at any point (DESIGN.md §12).
- Use Flutter stable only.

---

## 4. Offline enforcement

### Permissions (AndroidManifest)
Allowed:
- `BLUETOOTH_CONNECT` and `BLUETOOTH_SCAN` (with `neverForLocation`) on Android 12+
- `BLUETOOTH` and `BLUETOOTH_ADMIN` (`maxSdkVersion="30"`)
- `ACCESS_FINE_LOCATION` for GPS and legacy BLE scanning
- `WAKE_LOCK` if needed
- `INTERNET`, **only** because Android requires it for any socket, including a local WiFi ELM327. See the guard below.

Anything else needs the user's approval. The ambient light sensor and accelerometer need no permission.

### Network guard
- All socket code lives in `lib/obd/transport/wifi_transport.dart`.
- It must refuse any host outside private ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8`, link-local). Unit-test this.
- No HTTP client anywhere. Banned packages: `http`, `dio`, `google_fonts`, any `firebase_*`, `*_analytics`, `sentry*`, and any `url_launcher` use that opens web pages.

### `tool/check_offline.sh` (build it in phase 0; run it before every commit and in CI)
Fail if:
- `pubspec.lock` contains a banned package
- any Dart file under `lib/` imports `package:http` or uses `HttpClient`
- the merged release manifest has permissions outside the allowed list
- `com.google.android.gms` or `com.google.firebase` appears in the Gradle dependency tree

### Assets
- Fonts are bundled, OFL-licensed, and subset at dev time (DESIGN.md §4.5). Never fetched at runtime.
- The fault-code description database is a bundled JSON asset. Its source must be permissively licensed or written from scratch; record the source in `assets/dtc/SOURCE.md`.
- Offline map tiles (optional, last phase) come from a `.pmtiles` or `.mbtiles` file the user picks. The app never downloads them.

---

## 5. Dependency policy

Before adding **any** package:
1. Its license and its transitive dependencies must be OSI-approved and compatible with the project license.
2. It must not pull in Play Services or Firebase.
3. It must support our minSdk and 32-bit ARM.
4. Prefer a small package or about 100 lines of our own code.
5. Record the license and the reason in the commit message and in `docs/DECISIONS.md`.

### Known decisions
- **GPS:** a thin Kotlin platform channel over `LocationManager` (GNSS provider). Don't use `geolocator` or `location`, which may pull in Play Services.
- **Bluetooth Classic (SPP):** a thin Kotlin channel using `BluetoothSocket` with the SPP UUID `00001101-0000-1000-8000-00805F9B34FB`.
- **BLE:** **verify the license first.** Don't assume `flutter_blue_plus` is acceptable; check its current terms. Alternatives are `flutter_reactive_ble` or a thin Kotlin channel. Ask the user if unsure.
- **WiFi adapters:** `dart:io` `Socket`, behind the network guard.
- **OBD protocol:** our own pure-Dart ELM327 layer. The `obd2` package (MPL-2.0) may be studied for design ideas; any copied file stays MPL-2.0 with its header, so prefer writing our own.
- **Engine sound:** synthesised in our own pure-Dart code (`lib/sound/`, no audio asset and so nothing to license), played through a thin Kotlin channel over `AudioTrack`. No audio library (Oboe, SoLoud) and no plugin. It runs in an isolate of its own. It plays on car audio only unless the user allows the speaker, asks for no audio focus, and stops with the screen (no foreground service, so no new permission). DESIGN.md §5.10.
- **Device features** (keep screen on, window brightness, battery temperature, immersive mode, ambient light, accelerometer): small native calls on a `DeviceChannel` rather than plugins. Ambient light drives Daylight and Night modes; the accelerometer drives the road view's body roll (DESIGN.md §4.4, §6.11).
- **Sharing a picture** (Year on Tape): a thin Kotlin `ShareChannel` that writes the PNG the app drew to its own cache and opens Android's share sheet through a `FileProvider` (`androidx.core`, Apache-2.0, already in the app through the Flutter embedding). No permission, no network code, no plugin; what the person picks in the sheet is their choice. Parked only, a button on the Year insight.
- **Storage:** `sqflite` for trips, samples, fill-ups and events. `shared_preferences` for settings.
- **State:** no heavy frameworks and no code generation. Use `ValueNotifier`/`ValueListenable` and streams, with constructor-injected services. Live data must never trigger widget rebuilds (DESIGN.md §9.3).
- **Time:** all time-dependent code takes an injected `Clock` (our own small interface, with `SystemClock` and `FakeClock`). Never call `DateTime.now()` or create `Timer`s directly in domain code; use the injected clock or scheduler. This is what makes the simulator tests deterministic and fast. UI animation runs on DESIGN.md's `MotionClock` (a vsync ticker), which tests drive through the fake clock.
- **Fonts:** Saira (variable) for numerals and the wordmark; Barlow and Barlow Semi Condensed for everything else. Nothing else (DESIGN.md §4.5).
- **UI framework:** `WidgetsApp` (or `MaterialApp` purely as a shell). Material widgets are banned in `lib/ui/` (DESIGN.md §13.1).
- **Dev-only tools:** fonttools for font subsetting and an icon generator such as `flutter_launcher_icons` are allowed at dev time only. They must not ship in the app.

---

## 6. Architecture

```
lib/
  main.dart
  app/                 # shell, routes, landscape/immersive, service wiring
  core/                # Clock, Scheduler, Result types, units, currency formatting (en_IN grouping)
  platform/            # Dart side of Kotlin channels (gps, bt_classic, device)
  sound/               # the engine sound: profiles, synth, voice host. Pure Dart, no Flutter imports
  sim/                 # vehicle simulator (section 7). Pure Dart, no Flutter imports
  obd/
    transport/         # Transport interface + sim, bt_classic, ble, wifi, replay
    elm327/            # command queue, init, framing, error mapping
    pids/              # PID definitions, decoders, supported-PID discovery
    dtc/               # Mode 03/04/07, decoding, description lookup
    poller.dart        # priority scheduler, multi-PID batching
    survey/            # the survey drive: a read-only sweep of every ECU into a log (docs/SURVEY.md)
  location/            # LocationSource interface + native GPS + sim GPS
  vehicle/             # VehicleState: derived values, smoothing, acceleration
  fuel/                # fuel-flow estimators (5E / MAF / MAP), calibration
  money/               # fuel price, fill-up log, live trip cost, attribution
  coach/               # event detection, sweet-spot learning, tips
  insights/            # what the trips add up to: powerflow, power curve, gearbox, voltage, toll map, cold start, ghost commute, year on tape
  trips/               # trip lifecycle, sample recording, sqflite repositories
  ui/
    design/            # the design system: tokens, theme, fidelity, motion, render caches, icons, components (DESIGN.md §13)
    lab/               # the Design Lab: component gallery, switchers, slow motion, capture-all (DESIGN.md §13.2)
    pages/             # Drive (clusters), Money, Review, Coach, History: composed only from design/ components
    hud/               # HUD layouts and the alignment pattern (DESIGN.md §8)
    onboarding/ garage/ pit_stop/ diagnostics/
android/app/src/main/kotlin/.../  # GpsChannel, BtClassicChannel, DeviceChannel, ShareChannel
assets/fonts/ assets/dtc/
tool/                  # check_offline.sh, sim_server.dart, record/replay helpers, font subsetting script
test/                  # unit/, e2e/, widget/, design/ (goldens + design lint)
integration_test/      # on-device/emulator tests: the app on tool/sim_server.dart over WiFi
recordings/            # replayable raw ELM sessions (sim-generated now, real later)
docs/                  # DECISIONS.md, STATUS.md, DEV_SETUP.md, HARDWARE_HANDOFF.md, RELEASE_CHECKLIST.md, design-review/
```

### Layering rules
- `sim/`, `obd/`, `vehicle/`, `fuel/`, `money/`, `coach/`, `insights/`, `sound/` and `trips/` (except the sqflite adapter) are **pure Dart with no Flutter imports**. They're tested headlessly.
- `ui/` only reads `ValueListenable`s and streams from services. It never touches transports or the database directly.
- Pages are composed only from `ui/design/` components and tokens. No Material widgets and no raw colours, text styles, durations or spring constants anywhere in `ui/` outside `ui/design/tokens/` (enforced by the design-lint test).
- `Transport` interface: `connect()`, `disconnect()`, `write(String)`, `Stream<String> incoming`, `Stream<TransportState> state`.
- `LocationSource` interface: `Stream<LocationFix>` (lat, lon, speed, heading, altitude, accuracy, time).
- Repositories have an in-memory implementation for tests and a sqflite implementation for the app.

---

## 7. The simulator (build this first)

The simulator is a first-class development feature. It powers every test, feeds the Design Lab, and serves the real WiFi transport on the dev machine (`tool/sim_server.dart`). **It is not in the app.** Demo Mode was removed on 2026-10-23 at the human's instruction (docs/DECISIONS.md): the app drives from the user's adapter or, by their choice, from the phone's GPS alone, and never shows simulated data as if it were the car's.

### 7.1 `VehicleModel`: a simple physical car
Deterministic given a seed and a stream of driver inputs (throttle 0–1, brake 0–1, ignition on or off). It updates at a fixed step (e.g. 50 ms) on the injected clock.
- **Longitudinal dynamics:** mass about 1150 kg, rolling resistance, aerodynamic drag, and engine force from throttle. Braking decelerates up to about 8 m/s². Speed is never negative.
- **CVT behaviour** (the default profile mimics a petrol CVT hatch or sedan): idle about 750 rpm; while moving, RPM follows throttle more than speed (roughly 1200–2200 when cruising gently, rising towards 5500–6000 at full throttle); red line 6500.
- **Air and fuel:**
  - MAP (kPa) from throttle and RPM, about 30 kPa at idle and about 98 kPa at wide-open throttle.
  - Air mass flow from speed-density with the profile's displacement and VE, so MAF, MAP and fuel rate are **physically consistent**.
  - Fuel rate = air mass / AFR (14.7) / density (740 g/L) for petrol. Fuel cut-off when coasting with throttle at 0 and RPM above 1500.
- **Lateral acceleration** from a synthetic route curvature, so the road view's roll and the accelerometer path can be exercised.
- **Warm-up:** coolant from ambient (about 30 °C) to about 90 °C over 8–10 minutes, then thermostat-held. Intake air temperature slightly above ambient.
- **Electrical:** 12.4 V with ignition on and engine off, about 14.1 V running.
- **Fuel level** falls as fuel is used (tank capacity from the profile).
- **Ground truth:** the model keeps exact cumulative fuel (L), distance (km), idle time and idle fuel, plus a log of every scripted hard-acceleration and hard-braking event. **Tests compare the app's estimates against this ground truth.**

### 7.2 Vehicle profiles (`sim/profiles/`)
- `petrol_cvt_maf`: supports 04, 05, 0B, 0C, 0D, 0F, 10, 11, 2F, 42 (MAF available).
- `petrol_cvt_map`: same, but **no 10 (MAF)**, so the app must use speed-density. Many Honda petrol cars behave like this.
- `petrol_cvt_fuelrate`: also supports 5E (engine fuel rate).
- `petrol_manual_sporty`: manual gearbox with gear ratios and a 7000 rpm redline, so the shift horizon and fast needle work can be exercised.
- `minimal_old_car`: only 04, 05, 0C, 0D, 11 (tests graceful degradation: money unavailable, clear messaging).
- `diesel_manual`: MAF available but diesel air-fuel ratio varies, so money estimates must be flagged low-confidence until fill-up calibration exists.

Profiles are **approximations, not real vehicle data**. Real recordings from the user's car replace or tune them after the hardware handoff.

### 7.3 `DriveScenario`: scripted drivers
Each scenario is a timeline of driver inputs, plus optional ignition events, DTC injections and adapter faults. Required scenarios:
- `cold_start_idle`: 5 minutes of idle from cold
- `city_stop_go`: 20 minutes with traffic signals, speeds 0–50 km/h, idling at signals
- `highway_cruise`: 30 minutes steady at 70–100 km/h with a few overtakes
- `aggressive_city`: frequent hard accelerations and hard braking
- `eco_city`: the same route as `aggressive_city`, driven gently. **Its cost must come out clearly lower**, which proves the coach's premise.
- `traffic_jam`: long idling with crawling
- `mixed_commute`: city, then highway, then city, with an ignition off and on midway
- `spirited_revs`: repeated high-RPM pulls and lifts on `petrol_manual_sporty`, for tuning needle, trail, peak hold and shift horizon motion
- `dtc_present`: any drive with P0420 and P0171 stored
- `adapter_flaky`: random `NO DATA`, dropped prompts and a disconnect-reconnect midway

### 7.4 `Elm327Simulator`: behaves like a real adapter
It takes raw command strings and produces **byte-accurate ELM327 text output**:
- Supports `ATZ` (with the reset banner `ELM327 v1.5` or a configurable one), `ATE0/1`, `ATL0/1`, `ATS0/1`, `ATH0/1`, `ATSP0-9`, `ATDPN`, `ATRV`, `ATI`, `ATAT0-2`, `ATST`.
- Echo, spaces, linefeeds and the `>` prompt all follow the current settings.
- `SEARCHING...` on the first request after `ATSP0`.
- Mode 01 single and **multi-PID** requests (up to 6), including ISO-TP multi-frame formatting when the response is longer than 7 bytes (`00A` / `0:` / `1:` lines).
- Supported-PID bitmasks (`0100`, `0120`, `0140`) generated from the profile.
- Modes 03, 04 and 07 with injected codes.
- `NO DATA` for unsupported PIDs, `?` for unknown commands, and ignition-off behaviour.
- **Quirk injection** via `AdapterQuirks`: per-command latency (fixed plus jitter, e.g. 40–120 ms for a Bluetooth Classic clone), drop-first-command, ignore `ATAT`, no multi-PID support, random `NO DATA` rate, missing prompt, garbage bytes, and disconnect at time t.

### 7.5 Transports and GPS for the simulator
- `SimTransport` implements `Transport` by wrapping `Elm327Simulator`, with latency on the injected scheduler.
- `SimLocationSource` implements `LocationSource`. It moves along a synthetic route (a polyline generated per scenario, starting from any fixed origin) at the vehicle model's speed, with a little GPS noise and occasional accuracy drops.
- `tool/sim_server.dart` serves the same simulator over TCP:
  ```
  dart run tool/sim_server.dart --port 35000 --profile petrol_cvt_map --scenario city_stop_go
  ```
  Run it on the dev machine and point the **real WiFi transport** at it. From an Android emulator the host is `10.0.2.2`, which is a private range and passes the guard. This tests the production WiFi code path end-to-end without hardware.
- Optional cross-check: the open-source Python ELM327-emulator over TCP, to make sure our parser also accepts another implementation's output.

### 7.6 No Demo Mode in the app
There is no demo drive, no DEMO badge and no demo setting. The widget tests run the whole app on a simulated car through the production path (`test/support/sim_shell.dart`: a chosen adapter whose transport is `SimTransport`), and `integration_test/` runs it on `tool/sim_server.dart` over WiFi. Trips flagged `is_demo` by older builds stay in the database file, are never listed or counted, and nothing makes one now.

**The source is chosen, never guessed.** The app asks (cold open: CONNECT MY CAR or GPS SPEED ONLY) until a source is chosen, then keeps it. An adapter that will not connect stays an adapter drive that is looking for its adapter; it never turns into another source. Garage → Speed from switches between the car's adapter and the GPS alone.

---

## 8. OBD, fuel, money and coach logic

### 8.1 ELM327 layer
- One command in flight at a time. Each response ends with `>`. Terminate commands with `\r`.
- Strip echoes, whitespace and `SEARCHING...`. Map errors to typed failures: `NO DATA`, `?`, `STOPPED`, `CAN ERROR`, `BUS INIT...ERROR`, `UNABLE TO CONNECT`, `BUFFER FULL`, timeout.
- **Init sequence:** `ATZ`, `ATE0`, `ATL0`, `ATS0`, `ATH0`, `ATAT1`, `ATSP0`, then `0100`. Remember the detected protocol per adapter (`ATDPN`) and set it directly next time. CAN 11-bit 500k is `ATSP6`.
- **Clone tolerance:** settle delay after connect, retry at most twice, a compatibility mode (slower pacing, no batching), and never depend on commands beyond ELM v1.4 without a fallback.
- Record each response's round-trip time; the UI's smoothing pipeline uses it to timestamp samples (DESIGN.md §5.2).

### 8.2 Polling
- Discover supported PIDs first, then only poll supported ones that are needed by the current page or by trip recording.
- **Tiers:** fast (every cycle) is RPM `0C`, speed `0D` and throttle `11`. Medium (about 1 Hz) is load `04`, MAF `10` or MAP `0B`, and fuel rate `5E`. Slow (every 3–5 s) is coolant `05`, intake air `0F`, fuel level `2F` and voltage `42`.
- The fuel source PID (`5E`, `10` or `0B`) moves to the fast tier while trip recording is active, because money accuracy depends on it.
- **Multi-PID batching** on CAN (up to 6), with automatic fallback.
- Expose the achieved cycle rate as a diagnostic value.

### 8.3 Decoders (A and B are data bytes)
| PID | Value | Formula |
|---|---|---|
| 04 | Engine load % | A·100/255 |
| 05 | Coolant °C | A − 40 |
| 0B | Intake MAP kPa | A |
| 0C | RPM | (256A + B)/4 |
| 0D | Speed km/h | A |
| 0F | Intake air °C | A − 40 |
| 10 | MAF g/s | (256A + B)/100 |
| 11 | Throttle % | A·100/255 |
| 2F | Fuel level % | A·100/255 |
| 42 | Module voltage V | (256A + B)/1000 |
| 5E | Engine fuel rate L/h | (256A + B)/20 |

### 8.4 Fuel-flow estimation (`fuel/`)
Pick the best available source automatically and show which one is in use on the Diagnostics page:
1. **PID 5E** (fuel rate): use it directly.
2. **MAF** (PID 10): L/h = MAF × 3600 / (AFR × ρ), with AFR 14.7 and ρ = 740 g/L for plain petrol (E0). **Ethanol changes both:** the vehicle setup has a petrol blend (E0, E10 or E20; E20 is what a new install starts with, since it is the petrol at Indian pumps), and the blend sets AFR and ρ from the two fuels (E20: 13.5 and 750 g/L, so about 7.5% more litres for the same air; E10: 14.1 and 745 g/L, about 3.6% more). PID 5E is the ECU's own figure and is never adjusted for the blend.
3. **Speed-density** (MAP, IAT, RPM plus vehicle profile):
   `MAF (g/s) = 1000 × MAP_kPa × displacement_L × (RPM / 120) × VE / (287.05 × IAT_K)`, then as in method 2.
   Displacement comes from the vehicle setup (e.g. 1.5 L). VE defaults to 0.85 and is adjusted by calibration.
4. None of these available: show fuel and money as unavailable, with a plain explanation.

Additional rules:
- Petrol with throttle at 0, RPM above 1500 and speed above 10 km/h is treated as possible fuel cut-off; use the reported value, don't invent fuel.
- Diesel: the MAF method isn't valid (variable air-fuel ratio). Use 5E if present; otherwise show money as low-confidence until fill-up calibration exists.
- All constants live in one `FuelConstants` class and are configurable per vehicle.

### 8.5 Fill-up log and calibration (`money/`)
- **Fill-up entry** on the Pit Stop page (DESIGN.md §7.9), only when the car is stopped: date, litres, amount paid, and a "tank filled full?" toggle. Price per litre = amount / litres, and this becomes the current price. The user can also set the price directly without logging a fill-up.
- **Currency** defaults to ₹ and is configurable. Money uses Indian digit grouping (₹1,23,456). Until a price is set, money views show litres only, with a prompt to add the price.
- **Calibration:** between two consecutive full-tank fill-ups, `factor = litres actually filled / litres estimated since the previous full fill`. Keep a rolling average of the last 3 factors, clamped to 0.7–1.3. Apply it to all fuel estimates.
- **Confidence levels:** "uncalibrated" (no factor yet), "calibrating" (1 factor), "calibrated" (2 or more), shown as confidence pips next to money figures (DESIGN.md §6.8).

### 8.6 Live trip computer
**Trip boundaries:** a trip starts when the engine starts (RPM above 400). It ends when the engine is switched off: RPM 0 or the ECU stops answering, with module voltage below about 13 V, for 10 s. If the engine restarts within 5 minutes, the same trip resumes. Standing still with the engine running (traffic, signals, jams) never ends a trip. The Debrief (DESIGN.md §7.5) follows the same rule.

Per trip, updated live:
- Distance, integrated from OBD speed (GPS is used as a sanity check and fallback)
- Fuel used (L), average km/L, instant km/L (shown as "—" below about 5 km/h)
- **Cost so far (₹)**, **₹ per km**, and fuel remaining in rupees and km if fuel level `2F` is supported
- Idle time and idle cost, updated live
- A per-rupee event stream (which bucket each ₹1 of spend fell into) that feeds the Money Tape (DESIGN.md §6.8)

### 8.7 Where the money went (attribution)
Each sample's fuel cost goes into **exactly one** bucket. Invariant: **the buckets sum to the trip total.**
- **Idling:** speed below 2 km/h with the engine running
- **Hard acceleration:** during a hard-acceleration event (below)
- **High speed:** above the user's speed threshold (default 100 km/h)
- **Normal driving:** everything else

Wording rules: idling is "avoidable". The other buckets say "spent during hard acceleration", **never "wasted"** (DESIGN.md §10). The eco-vs-aggressive simulator pair validates the premise; it isn't a per-trip claim.

### 8.8 Event detection (`coach/`)
- Smooth speed with an EMA over about 1 s before calculating acceleration. OBD speed is coarse (whole km/h) and noisy.
- **Hard acceleration:** smoothed acceleration above 2.5 m/s² for at least 1 s, or throttle above 70% for at least 2 s while speed is above 10 km/h.
- **Hard braking:** smoothed deceleration beyond 3.5 m/s² for at least 0.5 s.
- **Long idle:** idling for more than 60 s continuously.
- **High RPM:** above 3500 for more than 3 s (configurable).
- **Speeding:** above the user threshold for more than 10 s.
- Every threshold lives in `CoachThresholds`, is configurable (Gentle / Normal / Sporty presets in Garage), and is covered by tests.

### 8.9 Sweet spot and tips
- **Sweet spot:** from all real trips, collect steady-state samples (absolute acceleration below 0.3 m/s² and throttle change below 5% per second), bin them by 10 km/h speed band, and report km/L per band once a band has at least 3 km of data. This feeds the efficiency curve (DESIGN.md §6.13).
- **Tips** are rule-based templates, shown **only when stopped or after the trip**, at most 2 per trip, picked by rupee impact. For example: "₹24 of this trip went on idling — about 14 minutes with the engine on." Never shame; keep it factual.
- **Live cue while driving:** the eco bar (DESIGN.md §6.7), based on instant km/L relative to the car's own average. No text.

### 8.10 Diagnostics
- Mode `03` reads stored codes, `07` reads pending codes, and `04` clears them. Clearing uses slide-to-confirm and is only allowed at speed 0.
- Decode into P/C/B/U codes and look up descriptions in the bundled JSON.

---

## 9. UI

**DESIGN.md is the authoritative spec for everything visual and interactive: layout, motion, components, liveries, the HUD and copy.** This section lists the functional requirements only.

### Pages
The app is one continuous strip of pages: `REVIEW · MONEY · [DRIVE] · COACH · HISTORY` (DESIGN.md §7.1). While moving, only Drive and Money are reachable.
1. **Drive:** five cluster layouts (Apex, Tape, Minimal, Telemetry, Road), switched by vertical swipe (DESIGN.md §7.3). Has a HUD variant.
2. **Money:** live trip cost, ₹/km, km/L, idle cost, the Money Tape; the parked breakdown (DESIGN.md §7.4). Has a HUD variant.
3. **Review** (parked only): route trail, telemetry scrubber, receipt, where-it-went breakdown, one coach tip, and the Debrief when a trip ends (DESIGN.md §7.5).
4. **Coach** (parked only): efficiency curve and sweet spot, weekly spend, ₹/km trend, recent tips (DESIGN.md §7.6).
5. **History** (parked only): trip list with mini routes and mini Money Tapes (DESIGN.md §7.7).

**GPS only** (a source chosen at the cold open or in Garage → Speed from): one screen, not the strip. The speed as the hero, and what a GPS can honestly add up to (distance, moving time, average and fastest speed, heading); the parked dock with Garage, HUD and Reset trip; the HUD with the speed alone. No tach, money, coach, trips or engine sound, because nothing reads them, and none is invented. The speed is the receiver's Doppler speed (below about 1.5 km/h it is zero), the distance is that speed over time and never the positions, and a fix less accurate than 100 m is not used. Pure Dart in `lib/location/gps_drive.dart`, tested against the simulator's ground truth.

Also, from the parked dock: **Garage** (settings, DESIGN.md §7.8), **Pit Stop** (fill-up, DESIGN.md §7.9), **Diagnostics** (DESIGN.md §7.10), and the HUD toggle. Plus **Onboarding** (DESIGN.md §7.11).

### HUD
- One component of the app, specified in DESIGN.md §8: mirrored with `Transform.scale` (horizontal flip by default, vertical flip optional), pure black, one user-chosen colour, huge numerals, an alignment pattern for setup.
- Toggled with a double-tap on Drive or Money, or the dock button. The last mode is remembered.
- Screen kept on, maximum brightness in daylight, immersive mode.

### Motion and Parked
- Parked = speed 0 for 5 s, or ignition off. Motion = speed above 3 km/h. When the car starts moving, the Motion layout returns within 300 ms (DESIGN.md §7.2).
- Tips, fill-up entry, fault-code clearing and settings are only reachable when parked.

### Connection UX
- Auto-connect to the last adapter, with auto-reconnect and backoff.
- Connection states are presented as specified in DESIGN.md §7.12. Never show raw ELM errors in the main UI.

### Phone health
- Battery temperature above about 45 °C: warning glyph and a parked-only suggestion to unplug the charger and move the phone out of the sun. Above about 50 °C: dim automatically and force fidelity Tier 1 at 30 fps (DESIGN.md §9.2).

### Performance rules (old devices)
- Follow the fidelity tiers, governor and budgets in DESIGN.md §9. Tier 1 targets 60 fps with a 30 fps fallback, and the look must hold up in Tier 1.
- Follow the mandatory craft techniques in DESIGN.md §9.3: glyph atlas for live numerals, baked glow sprites, cached static layers, batched segments, zero allocation per frame, repaint through `Listenable`s.
- No per-frame `BackdropFilter`, runtime blur, `saveLayer`, `ClipPath`, `Opacity` widgets, `ShaderMask`, or gradients redrawn every frame. Fragment shaders only in Tier 3.
- Downsample route and timeline data before painting (at most about 1000 points on screen).
- Memory budget: about 150 MB.
- A debug overlay (FPS, poll rate, PIDs/sec, fuel source, fidelity tier, phone temperature) opens with a long-press and links to the Design Lab.

---

## 10. Testing strategy

Run all of this with `flutter test` (headless, no device), except layer 5.

### Layer 1: Unit tests (`test/unit/`)
- Every PID decoder, including edge values (0, max, and bytes that would overflow)
- ELM framing: echo on/off, spaces on/off, `SEARCHING...`, multi-PID single-frame and ISO-TP multi-frame, every error string, missing prompt, garbage bytes
- Supported-PID bitmask decoding
- DTC decoding
- Each fuel estimator, checked against hand-computed values
- Calibration maths: clamping, rolling average, confidence transitions
- Attribution: the buckets sum to the total, and each sample goes into exactly one bucket
- Event detectors: threshold edges and durations
- Sweet-spot binning and minimum-data rules
- Network guard: allows private, loopback and emulator-host addresses; refuses public addresses
- Currency and unit formatting, including Indian digit grouping

### Layer 2: Simulator self-tests (`test/unit/sim/`)
- The vehicle model is deterministic for a given seed
- MAF, MAP and fuel-rate outputs are mutually consistent
- The ELM simulator's output matches golden text fixtures for each AT-setting combination

### Layer 3: End-to-end simulated drives (`test/e2e/`)
Full stack: `SimTransport` → ELM layer → poller → vehicle → fuel → money → coach → trips (in-memory repository), on a `FakeClock`. A 30-minute drive must run in a few seconds.

**Required pass criteria** (compared against simulator ground truth):
- Trip distance within ±2% of the truth
- Fuel used within ±5% for the `5E` and `MAF` profiles, and ±10% for the `MAP` (speed-density) profile before calibration
- After two simulated full-tank fill-ups, the calibrated fuel estimate is within ±3% on all petrol profiles
- Idle time within ±5%, and idle cost within ±7%
- The detected hard-acceleration and hard-braking counts match the scripted events (allow ±1 for boundary effects in `aggressive_city`)
- `eco_city` total cost is at least 15% lower than `aggressive_city` over the same route, and the coach produces an idling or hard-acceleration tip for the aggressive run and none for the eco run
- `adapter_flaky`: no crash; reconnects; the trip continues as one trip; missing data doesn't create fuel spikes
- `mixed_commute`: an ignition off/on midway follows the trip boundaries in section 8.6 (resume if under 5 minutes, otherwise a new trip)
- `traffic_jam`: long stationary idling with the engine running never ends the trip or triggers the Debrief
- `minimal_old_car`: the gauges that can work do work; money shows as unavailable with the explanation
- `dtc_present`: codes are read and decoded, and clearing is refused while moving
- With a quirky Bluetooth Classic clone profile (80 ms ±40 ms latency), the fast tier achieves at least 3 Hz
- The Money Tape's per-rupee event stream adds up to the trip total and matches the bucket attribution

### Layer 4: Widget tests (`test/widget/`)
- Each page renders against a sim-driven service graph with no exceptions, at 640×360, 720×360 and 800×360 logical sizes
- HUD mode applies the chosen flips, and the Money HUD shows the ₹ figure
- Components don't rebuild their widgets on data updates (count rebuilds)
- The Pit Stop form validates input and is unreachable while moving
- Tips never appear while the vehicle is moving

### Layer 4b: Design tests (`test/design/`)
- The golden matrix, design lint, spring, odometer, phosphor, stale-data, motion-lock, flash-rate and contrast tests specified in DESIGN.md §14.1–14.2.
- Goldens load the real bundled fonts and are generated on CI Linux only. Tag golden tests `golden`. On Linux, run everything; on macOS or Windows, run `flutter test --exclude-tags golden` locally and rely on CI for the goldens, so the commit rule in section 2 stays achievable.

### Layer 5: Device and emulator (`integration_test/`, run when an emulator or device is available)
- The app connects to `tool/sim_server.dart` over WiFi and cycles all pages and clusters
- The WiFi transport connects to `tool/sim_server.dart` via `10.0.2.2:35000` and shows live values
- Profile-mode frame timings are logged per fidelity tier for a 2-minute simulated drive. **Document the results** in `docs/STATUS.md` and the design review package. If no emulator is available, say so explicitly rather than skipping silently.
- A 60–90 s screen recording of a simulated drive for the design review package (DESIGN.md §14.4).

### Recordings
- `tool/record_sim.dart` generates `recordings/sim/*.log` (timestamped raw ELM traffic) from scenarios.
- A `ReplayTransport` replays any recording. After the hardware handoff, real car logs go into `recordings/real/` and become regression tests.

---

## 11. Hardware handoff

The coding agent builds the Bluetooth Classic, BLE and native GPS code, but **can't verify them without hardware**. Those parts are unit-tested with mocked platform channels and marked "unverified on hardware" in `docs/STATUS.md`.

When **all of layers 1–4b pass** (and layer 5 where possible), the agent must:
1. Write `docs/HARDWARE_HANDOFF.md` containing:
   - How to build and install the debug APK on the phone
   - A step-by-step test script for the real car, in order: a WiFi adapter if the user has one, Bluetooth Classic, then BLE. For each: pair, connect, check the PID matrix, 10 minutes of driving, ignition off/on, and unplugging mid-drive.
   - A design check in the real car: each cluster by day and at night, Daylight and Night mode switching, and HUD setup with the alignment pattern
   - How to turn on **session recording** and where the log file is saved
   - What to report back: adapter name and version (`ATI`), detected protocol, supported PIDs, fuel source used, achieved poll rate, auto-selected fidelity tier, and any errors or visual problems
2. Stop and tell the user it's ready for real-hardware testing.

After the user's first real drives, the next session:
- Adds the real recordings to `recordings/real/` and replay tests for them
- Tunes the matching simulator profile to real behaviour (latency, supported PIDs, RPM behaviour)
- Tunes the smoothing pipeline's lead compensation against real latency (DESIGN.md §5.2)
- Fixes transport issues found, with a regression test for each
- Compares estimated fuel against the user's first full-tank fill-ups

---

## 12. Working style for Claude

- For non-trivial changes, state a short plan, then implement. Ask only for decisions that are expensive to reverse: dependencies, licensing, architecture, or anything touching the offline guarantees.
- After implementing: analyze, test, run the offline check, update `docs/STATUS.md` where relevant, and commit (section 2).
- When a test tolerance fails, **fix the estimator or the model, not the tolerance.** Loosen a tolerance only with the user's approval and a note in `docs/DECISIONS.md`.
- Build every visual component in the Design Lab first, tune its motion in slow motion, then compose screens. Never reach for a Material widget or a default style as a shortcut.
- A UI phase isn't done until DESIGN.md §14.5 is met and the design review package is written. Be candid in it about anything that doesn't meet the bar yet.
- Keep `docs/DECISIONS.md` as a short running log of choices and reasons, including design decisions where DESIGN.md was silent.
- Never add network features, telemetry, fuel price fetching or cloud sync. Suggest them as issues instead.
- Never guess PID formulas or ELM behaviour. If unsure, say so and check the SAE J1979 definitions or the ELM327 datasheet with the user.
- Say plainly when something couldn't be verified (no emulator, no hardware). Never report untested work as done.

---

## 13. Roadmap

**Plan as of 2026-09-29 (the human's instruction):** phases 4, 5 and 6 are built back to back, and the human tests on a real phone and car after phase 6 (the hardware handoff, section 11). Until then the app runs on Demo Mode only. The per-phase design review packages (screenshots, video) are waived for phases 4 and 5 and for phase 6's UI, at the human's request; the honest notes about what was not verified still go in `docs/STATUS.md`, and the phase 3b package stands as written (its open questions are unanswered and are carried in `docs/STATUS.md`). Everything else in this file still applies: tests, the offline check, the commit rules.

Each bullet is one or more commits. Don't start a phase until the previous phase's tests are green. **Every phase that touches UI ends with a design review package (DESIGN.md §14.4).**

### Phase 0: Foundation
- Flutter project, landscape and immersive setup, `void` launch theme, license, README
- `core/`: Clock, FakeClock, Scheduler, units, currency (en_IN grouping)
- `tool/check_offline.sh` plus CI (analyze, test, offline check, APK build)
- `DeviceChannel` (keep screen on, brightness, battery temperature, ambient light, accelerometer)

### Phase 1: Simulator
- VehicleModel with ground truth, profiles, scenarios
- Elm327Simulator with quirks, SimTransport, SimLocationSource
- `tool/sim_server.dart`, `tool/record_sim.dart`
- Layer 2 tests

### Phase 2: OBD stack on the simulator (tag `v0.1.0-sim`)
- ELM layer, PID decoders, supported-PID discovery, poller with batching
- VehicleState with smoothing
- Layer 1 and layer 3 connection tests (`adapter_flaky`, `minimal_old_car`, `dtc_present`)

### Phase 3a: Design system (tag `v0.2.0-design`)
- Fonts bundled and subset (with ₹ coverage checked), tokens, liveries, Daylight and Night modes, TapeTheme
- MotionClock, spring tokens, smoothing pipeline, phosphor, detented odometer
- Glyph atlas, glow cache, static layers, grain, seven-segment renderer, chamfer shapes, icon set
- Fidelity tier detection and governor
- Design Lab with capture-all, driven by the simulator
- Design lint, spring, odometer and phosphor tests
- Design review package: components and motion only

### Phase 3b: Cockpit and HUD (tag `v0.3.0-sim`)
- Components: rolling numerals, tach arc, tapes, shift horizon, bar gauges, telemetry tiles, eco bar, status strip, alerts, road view
- The Strip navigation, Motion ↔ Parked, all five Drive clusters, ignition and shutdown sequences, connection states
- HUD layouts, flips, alignment pattern
- Demo Mode (removed 2026-10-23, see 7.6), onboarding with the cold open, brand (icon, launch, wordmark)
- Layer 4 and 4b tests; design review package

### Phase 4: Trips, fuel and money (tag `v0.4.0-sim`)
- Trip lifecycle and recording (sqflite and in-memory repositories), native GPS channel (mock-tested)
- Fuel estimators, fill-up log, calibration
- Money page with the Money Tape, Money HUD, Pit Stop, live trip computer, attribution
- Layer 3 accuracy tests; design review package

### Phase 5: Coach and review (tag `v0.5.0-sim`)
- Event detection, sweet spot, tips
- Review with route trail, telemetry scrubber and the Debrief; Coach with the efficiency curve; History; Garage; Diagnostics with the PID matrix
- The `eco_city` vs `aggressive_city` tests, and the "no tips while moving" tests; design review package

### Phase 6: Real transports (tag `v0.6.0-handoff`)
- WiFi transport with network guard (verified against `sim_server`)
- Bluetooth Classic Kotlin channel, BLE transport after the license check, adapter pairing in onboarding, auto-reconnect
- Mocked-channel tests; `docs/HARDWARE_HANDOFF.md`
- **Stop for the hardware handoff (section 11).**

### Phase 7: After hardware (tag `v1.0.0`)
- Real recordings as regression tests, tuned profiles, tuned lead compensation, transport fixes
- Phone temperature protection verified, fidelity governor tuned on real devices, final polish of all signature moments (DESIGN.md §3)
- Optional offline map under the route (a user-supplied raster PMTiles or MBTiles file)
- F-Droid metadata, store screenshots from Design Lab captures, release checklist; final design review package

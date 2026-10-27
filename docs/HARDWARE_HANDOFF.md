# Hardware handoff

Everything in TapeDash has been built and tested against the built-in simulator. This is the first time it meets a real phone, a real adapter and a real car. **The Bluetooth Classic, BLE and GPS Kotlin code and the WiFi transport on a real network have never run on hardware** (CLAUDE.md 11); they compile, and their Dart sides are tested against mocked channels and a simulated adapter over a real socket.

Read this top to bottom once. The test script is in order; each part says what to do, what should happen, and what to write down.

## What to bring

- The phone (an old Android is the point) with **USB debugging on**, and a USB cable.
- The Mac with the project, `adb` on the `PATH`, and Flutter.
- An ELM327 adapter. In order of preference for a first try: a **WiFi** one if you have it (the simplest to debug), a **Bluetooth Classic** one (the common cheap kind), then a **BLE** one.
- Double-sided tape or a car mount, and, for the HUD, a reflector film or a 3D-printed holder.
- Optional: a friend to drive while you watch, or drive it yourself with the phone mounted. **Nothing on the driving screens needs a touch, and nothing should be tried while the car moves.**

## 1. Build and install

```
flutter pub get
tool/verify.sh                          # should be green before you start
flutter build apk --debug               # quickest, and fine for a first look
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

A **debug build is much slower** than the app really is (it runs unoptimised, with checks on), so do not judge smoothness by it. For that, build a release one for your phone's CPU:

```
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk    # or app-armeabi-v7a-release.apk for a 32-bit phone
```

(`adb shell getprop ro.product.cpu.abi` says which. Release builds are signed with the debug key for now.) The app's package is `io.github.ictashik.tapedash`. Launch it from the launcher; it runs in landscape only.

## 2. Before the car: check the phone at your desk

**a. GPS only.** First launch: the cold open, then GPS SPEED ONLY (there is no demo mode any more; the simulator is only reached over WiFI in step b). Allow the location when it asks. Outside, the speed should appear within a minute and follow the car or your walking pace; DISTANCE, MOVING, AVERAGE, FASTEST and HEADING fill in under it. Stood still for five seconds, the dock rises with GARAGE, HUD and RESET TRIP. Double-tap for the HUD (the speed alone). Nothing should be blank, jittery or off the screen. Write down anything that is.

**b. The WiFi path against the simulator, over USB.** This tests the production WiFi code on the phone with no car at all. On the Mac:

```
dart run tool/sim_server.dart --scenario city_stop_go --profile petrol_cvt_map --verbose
adb reverse tcp:35000 tcp:35000
```

In the app: **CONNECT MY CAR** (or Garage, then Adapter) -> **WiFi** -> address `127.0.0.1`, port `35000` -> **Test** (it should say "The adapter answered.") -> Next, and through the car, price and layout. `127.0.0.1` is allowed by the network guard; a public address is refused, so try `8.8.8.8` once and check that it says so. The drive screen should connect, and the values should follow the simulated car. Check Diagnostics: the adapter says `ELM327 v1.5`, the protocol is `ISO 15765-4 CAN, 11-bit, 500 kbaud`, the PID matrix is lit, the poll rate is a few a second. Stop the server (Ctrl-C) and see **Reconnecting** and the values going stale; start it again and see them come back.

Then go back to what you were using: Garage -> **Speed from** -> GPS only, or forget the simulator adapter (Garage -> Adapter -> Forget this adapter) and connect your own.

## 3. In the car

Do each adapter type in this order (skip the ones you do not have). For each:

### Pair and connect

- **WiFi:** plug the adapter in, turn the ignition on, join its WiFi network in Android's settings (often `WiFi_OBDII` or `V-LINK`; no internet, and Android may offer to leave it: keep it). In TapeDash: CONNECT MY CAR -> WiFi -> the address (most are `192.168.0.10`, port `35000`) -> **Test**. If nothing answers, the address is wrong: check the adapter's manual, and write it down.
- **Bluetooth:** plug the adapter in, ignition on. CONNECT MY CAR -> Bluetooth. Allow the permission when asked. The search runs **both** kinds of Bluetooth at once, and each adapter says which it is on (Classic or Low Energy) and how close it is. **One adapter often shows twice**, as `OBDII` (Classic) and `OBDBLE` (Low Energy): they are the same adapter on its two radios, and the nearer one is yours (an adapter in the next car shows as Far). Classic needs a pairing (the PIN is usually `1234` or `0000`); Low Energy has none. Whichever you tap is **tried before it is taken**; if it will not open, the screen says so and offers the other radio (**Try OBDBLE**) and, for Classic, **Forget and pair again**. Write down which of the two worked, how long it took, and whether it worked first time.
- **If it will not connect, or drops:** Garage -> Adapter -> **Connection log** has, newest first, what the app did (each attempt, the status code the radio gave, which kind of socket worked or failed, the services the adapter listed). **A screenshot of it is the most useful thing you can send.** The debug build also writes the same lines into the session recording as `@ link ...`. If it says the adapter has "no serial service TapeDash knows", the services line next to it is what is needed.

Then the car (fuel, engine size, tank), the price (or skip), and the layout, and START DRIVING.

### Check what the car says

Ignition on (engine off is fine for this), then the engine on. Open **Diagnostics** (parked only).

1. The **adapter** line, the **protocol**, and the **voltage**.
2. The **PID matrix**: how many cells are lit ("N of 96"). Take a screenshot.
3. **Fuel from:** `5E`, `MAF` or `MAP`. Money needs one of them; with `NONE` the money screens say it is unavailable.
4. **Fault codes:** does READ work? Do not clear codes you do not understand.
5. The **poll rate**: the number next to the sparkline.

### Drive for ten minutes

Drive normally (a real trip, not a parking lot). Afterwards, in Drive and Money and in Review (once parked): does the speed match the car's? Is the rev needle steady? Do the trip distance, litres and rupees look plausible against the trip meter and the tank? Does the trip end by itself, with the Debrief, ten seconds after the engine goes off?

### Ignition off and on, and unplugging

- **Ignition off, then on,** with the adapter left in. The screen should show **Turn on the ignition** and the values should come back within a few seconds of the ignition being on. Note how long, and what the adapter does in between (it may print `UNABLE TO CONNECT`, `NO DATA` or `CAN ERROR` where the app cannot see; the session recording has it).
- **Unplug the adapter mid-drive** (stopped, please) and plug it back in. The values should freeze and fade, say **Reconnecting…**, and come back by themselves, within about 10 seconds of the adapter being back. Note how long.

## 4. Session recording

**A debug build records by itself** (a release build does not, until you switch it on): Garage -> Adapter -> **Record what the adapter says** shows which. There has to be an adapter chosen. Each drive from that adapter writes one file, saved every 20 seconds and at the end, so a drive that ends with the phone dying still leaves a log.

The files are in the app's own folder on the phone, reachable over USB (no storage permission needed):

```
adb pull /sdcard/Android/data/io.github.ictashik.tapedash/files/recordings/ ./real-recordings
```

(A **survey drive**, Garage → Adapter → Survey drive, makes a `survey-<date>-<time>-<kind>.log` in the same folder: a thorough read of every ECU for a one-off drive. See [SURVEY.md](SURVEY.md).) They are named `session-<date>-<time>-<kind>.log` (`bluetoothClassic`, `ble` or `wifi`). A log is plain text (see `recordings/README.md`): the header has the adapter, the address and the app version, and the body has every command sent, every piece received and every link event, with the time of each, and the app's own notes (`@` lines: the car's setup, each change of the connection, the engine on and off, the trip starting and ending, and a `vitals` line every 5 s). **A log contains your adapter's address and where you drove only if you turn GPS on (it does not include GPS); it is safe to send, but check it before you do.** Put the ones you want kept in `recordings/real/`. Recordings from someone else's car are never committed.

Compatibility mode (Garage -> Adapter) forces a slower pace and no batching. If a cheap clone drops requests or the poll rate is very low, try it, and say whether it helped.

## 5. Design check in the real car

With the phone mounted where it will live (the tape, or the holder):

- **Each of the five layouts** (Apex, Tape, Minimal, Telemetry, Road), by day and at night: can you read the speed at a glance, from the seat, without leaning? Is any text too small? Does anything dazzle at night?
- **Daylight and Night.** The screen should go to Daylight (halos off, heavier strokes, maximum brightness) in direct sun, and to Night in the dark. Garage -> Display -> **Brightness mode** holds **Daylight** or **Night** by hand to look at each without waiting for the weather. Note the lux at which it switched if you can (a phone light-meter app), and whether it flickered.
- **The HUD.** Garage -> HUD -> **Alignment pattern** (parked; it closes Garage and shows the pattern). Set **Height on the glass** and **Size** to sit it in the reflector, and check the flips: a windshield reflection is a mirror, so **Flip left to right** is on by default; if the reflection reads backwards, turn it off. Check the HUD colours in daylight (green, ion, amber, white). Double-tap on the Drive or Money page (or the dock's HUD button) toggles it.
- **The ignition sequence** on connecting, and the shutdown; the connection states (searching, waiting for the ignition, lost).
- **Motion and Parked:** when the car starts moving the driving layout should come back within a third of a second, and the dock, Garage, Pit Stop and Review should be unreachable while it moves.
- **The phone's temperature.** In the sun on the dash the phone gets hot. Above 45 C the status strip shows a phone glyph, and Garage says to unplug the charger and move it; above 50 C the screen dims and the display eases to Lite at 30 fps. Note the battery temperature when the glyph appears (the debug overlay's BATTERY line shows it: long-press a driving screen), and whether the phone got hot enough to matter.

## 5b. The replay and the engine sound

**The replay, at your desk.** Review -> pick a trip with a route -> **play** (left of the scrubber). Watch: does the map turn smoothly? Does the camera sit too close or too far (try the zoom buttons while following; they move it from what the camera chose)? Do the speed, the rev and throttle bars and the ₹ tick up, and end on the receipt's own figures? Tap **1x** for 2x and 3x. Drag the scrubber: the car should jump there and carry on. Drag the map: the camera lets go of the car; the crosshair takes it back. Is the tip's room better spent on the map? Does anything overlap at your phone's size?

**The engine, at your desk.** Garage -> **Engine sound** -> pick an engine -> **Test the sound** (ten seconds, on whatever output there is: the phone's speaker is fine here). Try each. Or, to listen on the Mac first: `dart run tool/render_engine.dart --out build/engine` writes WAV files of every engine (idle, a sweep, a drive). **Say what sounds wrong** ("buzzy", "too thin", "the idle drones", "the turbo is too loud"): the engines are parameter sets (`EngineProfile`) and tuning them is rounds of this.

**The engine, in the car.** Turn **Engine sound** on in Garage and pair the phone to the car's Bluetooth stereo (for audio). Drive (or connect the adapter and sit with the engine running). Check:
- **It plays on the car stereo**, not the phone. With the Bluetooth off it should say "No car audio to play on" in Garage and stay silent. **Turn the car off:** when the link drops it must stop and not come out of the phone's speaker (the most important thing on this list).
- **Does the sound follow the tach?** It lags (the data is 1 to 2 Hz, and Bluetooth adds about 0.2 s): is that tolerable, or confusing next to the real engine? Does the pitch wobble or overshoot when you lift off?
- **Does it glitch or stutter**, and **does the OBD poll rate drop** when it is on? Compare the poll rate (Diagnostics) with the sound on and off: a Classic Bluetooth adapter and Bluetooth audio share the radio. The session recording notes say `sound on ...`, `sound lost ...` and `sound underruns N`.
- **Music** playing from the phone at the same time should carry on under the engine (the engine asks for no audio focus).
- **Leaving the app** (Home) should stop it; coming back should start it again.

## 5c. Insights (parked, from the dock)

Nine pictures from what the car and your trips already hold. Check each, parked, with the engine on, after a few real drives (some need trips, a full tank or a week of driving to show anything):

1. **Current:** the volts of the last drive, the dips marked with how deep. Before starting the engine, switch the ignition on and wait ten seconds: that is a resting-voltage reading, kept once a day. Do it on three mornings and look at the small trend.
2. **Powerflow:** the last drive's energy split. Check the wheel share is about 7 to 20%; a figure of 30% or more means the model has gone wrong, and the session log is what to send back.
3. **Power:** the dyno chart. The highest seen should be under about 60 kW for the City, and the hatched part should start where you have not taken the revs.
4. **Gears:** on the City (a CVT) it should say None and show a fan. If it finds lines, tell me.
5. **Tank:** log a full tank at Pit Stop with FULL TANK on. After a drive, the litres left and the range should follow what the pump takes at the next full tank (tell me the difference). The Money page's fuel-left line should show "≈ KM LEFT".
6. **Tolls:** after a week with the GPS on, the places you wait should be rings on your usual road. Tap one.
7. **Cold start:** needs the coolant under 65 °C at the start and a fuel price set.
8. **Ghost:** needs the same route twice with the GPS on.
9. **Year, and Share:** the poster. Tap SHARE: the phone's share sheet should open with the picture. **This is the one piece of Android code in this round that has never run on a phone**; say what the sheet does, and whether the picture is 1920 x 1080 and sharp.

## 5d. The watch (a Galaxy Watch4 Classic, or any Wear OS watch)

Nothing here has met a real watch. In order:

1. **Install and set up from the laptop** (the watch has no keyboard): `adb connect <ip>:<port>` over Wireless debugging, `adb -s <ip>:<port> install -r app-arm64-v8a-release.apk`, then, with `dart run tool/demo_exchange.dart` replaced by a file made from your phone's Garage → Data → Export (it holds your adapter, the car and the price), `tool/adb_exchange.sh -s <ip>:<port> push FILE` and `import --apply` (docs/EXCHANGE.md 5). Or do it on the watch: CONNECT MY CAR, Bluetooth, the adapter in the wheel, with the bezel.
2. **The face:** is the speed, the revs round the rim and the ₹ unmistakable at a glance, on the wrist and at an angle? In sunlight? Is anything cut off by the bezel's circle, or too small to read at arm's length? Do the numerals (never lighter than weight 500) hold up on a moving wrist?
3. **The bezel:** does a click turn one face, and the wheel one row? Which way is clockwise? (Only the direction is sent: if a fast turn skips or sticks, say how big a number the watch gives.) Does Back do nothing while moving, and does Home leave?
4. **Staying on:** with the screen kept awake, what does the watch do in a long drive (it dims, it drops to the watch face, the app is stopped)? How hot does it get, and how fast does the battery fall? (A hot watch shows a glyph at 41 °C and dims at 45 °C.)
5. **Links:** does the watch's own Bluetooth reach the adapter (Classic and BLE), and the watch's GPS (the GPS-only screen)?
6. **Data:** `tool/adb_exchange.sh -s <ip>:<port> export` after a drive, `tdx check` and `tdx info` on what comes back; push it into the phone's inbox and import it there.

## 5e. Google Maps' turns on the HUD (docs/NAV.md)

The one piece of this that has met real Google Maps is a **capture on an Android 16 emulator**; nothing has met your phone. Google Maps runs on the same phone as TapeDash (it navigates in the background; TapeDash is in front) and does all the routing and the internet; TapeDash stays offline and only reads Maps' notification.

**First, a capture of what Maps posts on *your* phone** (the format is Google's and differs by Android version, so this is the most useful thing you can do). It needs a **debug** build (a release build captures nothing); `adb install -r` keeps your trips, price and adapter:

```
flutter build apk --debug --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
tool/nav_spike.sh enable        # gives TapeDash notification access over adb
# Start navigation in Google Maps and drive a few minutes (or have someone drive you):
# a roundabout, a highway exit and a wrong turn that makes it reroute are the most useful. Then:
tool/nav_spike.sh status        # records so far
tool/nav_spike.sh pull          # into recordings/private/navspike-<time>/
tool/nav_spike.sh disable       # takes the access away again
```

The folder holds the street names along your route: it stays in `recordings/private/` (git-ignored). Send it, or a few lines of `nav.jsonl`; names can be changed before they become a test fixture. What is needed from it: **which fields Maps fills on your Android**, the language and units your Maps writes in (kilometres, miles, a language other than English), and how often it posts.

**Before you drive with it**, two things that are Android's and Google Maps', not TapeDash's, and that would put a bright window on the HUD's black: (a) turn off Google Maps' **floating window** (Settings, Apps, Special app access, Picture-in-picture, Maps; the wording differs by phone), which Maps shows by itself when you switch away from it during a route; (b) switch off the **pop-up card** Maps shows at turns: Garage → Navigation → "Open Google Maps' notification settings" → open its list of categories → **Navigation urgent updates** → turn off **Pop on screen** (the names may differ in your language). On the Android 16 emulator Maps moved to that channel at every turn and Android popped a card over the arrow and the distance in about a quarter of the frames; **Do Not Disturb did not stop it** there, and the one switch did. Whether your phone's Maps does it at all, please say. Other apps' pop-ups (a call, a message) are Android's: Do Not Disturb is the way for those. Garage → Navigation says both.

**Then the HUD itself:**

1. Garage → **Navigation** → turn on "Show Google Maps turns on the HUD". It says what stands in the way: *Needs notification access* (the row under it opens Android's own screen; turn TapeDash on there; on Android 13 and later an app installed outside a store may first need "Allow restricted settings" in its App info, in the three-dot menu: say if you had to), or *Google Maps is not on this phone*.
2. Start a route in Google Maps, then bring TapeDash to the front and put the HUD up. The HUD should change to the navigation layout by itself within a second or two, and back when you end the route.
3. **While driving (someone else driving, or parked at a standstill)**: does the arrow match Maps' own? Does the distance fall in steps as Maps' does? Is the ETA right? Does the dot on the line climb as the turn comes up, and does the line lean the way the arrow turns? On a roundabout or a U-turn, what does the line do (it is drawn straight when the arrow cannot be read, by design)?
4. **Rerouting** (take a wrong turn): the right half should say Maps' own words, show no figures, and come back when Maps has a route again.
5. **Quiet:** with the car moving, switch Maps' navigation off from Maps' own notification or kill Google Maps: the HUD should return to the layout you chose. If Maps freezes instead of stopping, after 15 seconds the HUD shows NO UPDATE and a dash, never an old turn.
6. **Both apps on the phone:** note whether Android keeps both alive for a whole drive, how warm the phone gets, and how the frame rate is (debug overlay). An old phone with 2 GB may not run today's Google Maps at all (it needs Android 9 or 12 and later, by version); say what yours does.
7. **Legibility on the glass:** the instruction is up to three lines of Google's own text at 0.068H, which is more than the six-word limit of DESIGN.md 11; say whether it is readable at a glance and whether it should be shorter.
8. **Cards over the HUD:** with Maps guiding, did a card from Maps (or from anything else) slide down over the arrow and the distance at a turn? Try it before and after switching off "Pop on screen" for Maps' "Navigation urgent updates" (Garage → Navigation opens the page). Say what you saw, and your Android version.
9. Take the access away in Android's settings: the HUD must go back to the chosen layout and Garage should say *Needs notification access*.

## 6. What to report back

For each adapter you tried:

- **The adapter's name and version** (Diagnostics -> Adapter; `ATI`), how it connects, and whether pairing or joining its network was easy.
- **The protocol** detected, and **how many PIDs** it supports (the matrix count) with a screenshot.
- **The fuel source** used (5E, MAF or MAP), and, after your first full-tank fill-up in Pit Stop, the app's litres against the pump's.
- **The achieved poll rate** (Diagnostics), with and without compatibility mode if you tried both, and how long connecting took.
- **The auto-selected fidelity tier** and the frame rate (the debug overlay: long-press on a driving screen, and read the FRAMES and TIER lines), and the phone model, Android version and RAM.
- **Every error and every visual problem**: a screenshot, what you were doing, and the log file if a recording was on.
- **The replay and the engine sound** (section 5b): what looked or sounded wrong, which engine is nearest, whether the sound stopped when the Bluetooth link dropped, and the poll rate with the sound on and off.
- What was **slow to connect**, what **dropped**, and what **came back by itself** and what did not.
- **The navigation HUD** (section 5e): the capture folder from your phone, whether it needed "Allow restricted settings", whether Maps and TapeDash stayed alive together, whether a card from Maps slid over the HUD at turns (and whether switching off "Pop on screen" for "Navigation urgent updates" stopped it), your Android version, and anything on the glass that was hard to read.

## 7. What happens next

The next session adds your recordings to `recordings/real/` with replay tests, tunes the simulator profile to the real car (latency, PIDs, RPM behaviour), tunes the smoothing's lead compensation against the real latency (DESIGN.md 5.2), fixes what the transports did wrong with a regression test for each, and compares the estimated fuel against your fill-ups (CLAUDE.md 11).

## Known gaps to keep in mind while testing

- **The petrol blend** is set in Garage (E0, E10, E20; E20 to begin with). It changes the fuel figures by up to 7.5%; check the app's litres against the pump's after a full tank.
- **A cheap BLE adapter gives about 1.3 poll cycles a second** (the first real drive). The screens are smoothed for it (DESIGN.md 5.2); the poll rate on Diagnostics and in the debug overlay is the honest number, and it is not a fault. Compatibility mode has not been tried on such an adapter: say whether it helps.

These are in `docs/STATUS.md`, repeated here so they are not mistaken for bugs:

- Garage has no currency or units choice (the money is ₹, km and litres), no shift-light settings, no CSV export, and no licences screen.
- The connect flow's last step lists the layouts by name; it does not show live previews.
- The PID matrix does not pulse on each response.
- The Money Tape does not yet compact into ₹5 and ₹10 blocks when full, and the ₹ figure does not fly from Drive to Money.
- The fault-code descriptions cover the common generic codes only; others are described by their system.
- **The navigation HUD has never met a phone.** The Kotlin listener, its channel and the Notification access flow ran on an Android 16 emulator against real Google Maps and a stand-in; the parser has read one capture (English, kilometres, Android 16). Maps' notification differs between Android versions, and a Maps update can change it: if the HUD does not take over, the capture in section 5e says why.
- The design review packages for phases 4 to 6 were waived at your request, so the screens were looked at in renders and never on a phone: expect polish problems.

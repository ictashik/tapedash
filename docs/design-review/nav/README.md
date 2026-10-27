# Design review: Google Maps' turns on the HUD (DESIGN.md 8, docs/NAV.md)

Written 2026-10-24. You asked for a simple way to see the next turn, the ETA and the speed on the HUD, with Google Maps doing the routing. This is that layout, how it looks, and what it cannot do. **Nothing here has met a real phone or a windshield**: the frames are renders (the design lint's own test harness) and screenshots from **an Android 16 emulator and an Android 7.0 emulator**, driven by the simulated car, by a stand-in for Maps' notification, and, in the frames marked *real Maps*, by **real Google Maps 25.33**, the last of them on the **release build** from the cold open.

The HUD takes this layout over by itself while Maps is guiding, and gives your chosen layout back when it stops. Each frame comes twice where it matters: **as designed**, and **as the glass shows it** (mirrored, which is what the windshield reflects).

## The layout

| As designed (720 x 360) | As the glass shows it |
|---|---|
| ![](screenshots/render-right.png) | ![](screenshots/render-right-glass.png) |

The speed on the left, as in Drive + Money. On the right: **Google's own arrow** (a one-colour mask Maps puts in its notification, painted in the HUD colour), **the distance to the turn**, **Google's instruction** (up to three lines, cut at a word), and along the bottom **the ETA, the time left and the distance left**. The bold line is the "line map": it climbs from the car to a ring at the junction, leans the way the arrow turns, and the dot on it climbs as the turn comes up (over the last 500 m, counting down on the car's own speed between Maps' updates; the figure in text is Maps' own, because that is the one its voice agrees with).

**It is not a map.** Google Maps gives no route to other apps, so TapeDash cannot draw the road ahead. The line is a sketch of the next junction and DESIGN.md says so.

## The states

| A turn, nearer | The last metres (Maps drops the distance) | Straight on, no turn in it |
|---|---|---|
| ![](screenshots/render-left-near.png) | ![](screenshots/render-turn-now.png) | ![](screenshots/render-straight-no-distance.png) |

| Rerouting (Maps' own words) | Starting | Maps has gone quiet |
|---|---|---|
| ![](screenshots/render-rerouting.png) | ![](screenshots/render-starting.png) | ![](screenshots/render-stale.png) |

- **The last metres:** real Maps counts `80 m`, `70 m`, `50 m` and then says only `Turn right onto Basappa Rd`. The dot then fills the ring: the turn is now.
- **Rerouting and starting** show Google's words and nothing else: no arrow, no line, no figures.
- **Maps gone quiet** (15 s with the car moving, 3 minutes standing): a dash and **NO UPDATE**, and no figures. An old turn is never shown as a live one.

## Other lengths and sizes

| A long instruction (cut at a word) | Miles (when Maps writes in them) | 640 wide, as the glass shows it |
|---|---|---|
| ![](screenshots/render-long-instruction.png) | ![](screenshots/render-miles.png) | ![](screenshots/render-right-640-glass.png) |

The same layout at 800 wide: [render-right-800.png](screenshots/render-right-800.png). Tested at 640, 720 and 800 wide for one colour on pure black, nothing under the 0.06H floor, and strokes of at least 5 lp.

## On the emulators

| Android 16, the simulated car, the stand-in (250 m) | Android 7.0, the same (200 m) |
|---|---|
| ![](screenshots/emulator-android16-stand-in-250m.png) | ![](screenshots/emulator-android7-stand-in-200m.png) |

| **Real Google Maps 25.33**, 350 m | **Real Google Maps**, 110 m, the car at a signal |
|---|---|
| ![](screenshots/emulator-android16-real-maps-350m.png) | ![](screenshots/emulator-android16-real-maps-110m.png) |

These are the real app, mirrored, through its real listener, parser and HUD. The two on the right are Google's own notification: its instruction, arrow, distance, ETA and distance left, read live while the emulator's position was stepped along a route in Bangalore (so Maps also reroutes now and then, and says so). The speed beside it comes from the simulated car, which is not in step with the emulator's position.

**The release build, real Google Maps, the phone's own GPS speed** (2026-10-27: the GPS-only source, the switch on, the emulator's position moving at 30 km/h; these are the frames as the glass shows them, mirrored):

| 450 m, a right turn (stopped at the start) | The turn with no distance (30 km/h) | Starting out, "Exit the parking lot" |
|---|---|---|
| ![](screenshots/release-android16-real-maps-450m.png) | ![](screenshots/release-android16-real-maps-no-distance.png) | ![](screenshots/release-android16-real-maps-exit-parking.png) |

| 350 m, 30 km/h, with the card switched off for Maps |
|---|
| ![](screenshots/release-android16-real-maps-popup-off-350m.png) |

Long real instructions are cut at a word with an ellipsis ("Turn right after Prithvi Exchange (India) Ltd (on the right) onto Convent Rd" shows as three lines ending "(ON THE..."). The second frame is Maps' last metres: it has dropped the distance and the dot sits in the ring.

## On your own phone (Motorola edge 60 stylus, Android 16, Google Maps 26.42)

Written 2026-10-27. The position was faked from the shell (a fixed Bangalore test route, 30 km/h); the HUD speed is blank because the shell can send no speed and the source is an adapter that was not there. These are the frames as the glass shows them (mirrored). Your Maps posts the **classic** notification shape (not the emulator's), and the first run found three bugs, now fixed:

| Before: "0 M" over a straight arrow, and Maps' floating window | After: no distance beside "Head north" |
|---|---|
| ![](screenshots/phone-maps26-before-0m-and-floating-window.png) | ![](screenshots/phone-maps26-head-north.png) |

| A turn left, 110 m | A turn right, 350 m (the card switched off) | "Sharp right": the line is drawn straight, not leaning left |
|---|---|---|
| ![](screenshots/phone-maps26-turn-left-110m.png) | ![](screenshots/phone-maps26-turn-right-350m-no-card.png) | ![](screenshots/phone-maps26-sharp-right-line-straight.png) |

- **"0 M"**: Maps writes the title `0 m` beside "Head east" and "towards ...". A zero distance is now no distance.
- **Sharp right**: Maps' hairpin arrow was read as a left bend, so the line would have leaned the wrong way. It is now left unread (drawn straight) and Google's own arrow says the rest.
- **Rerouting** was read as "starting" (Maps 26.42 leaves the sub text empty): both show Maps' own words, but the state is now right.

**The floating window and the card are one problem.** With Maps' floating window allowed (the phone's default) it covers the HUD's corner (first picture). With it denied, which is what you want, Maps moved to its "Navigation urgent updates" channel about ten times in 160 s and Android popped a dark-teal card over the HUD ([the picture](screenshots/phone-maps26-card-over-hud.png): 5 of 15 sampled frames). Garage's new row opened Android's page for Maps on the phone ([the categories](screenshots/phone-maps-notification-categories.png), [the channel](screenshots/phone-maps-urgent-channel-page.png)); with "Pop on screen" off for that channel there were **0 cards in 75 sampled frames**, although Maps went on posting to it. I put your Maps settings back as I found them, so the card is on again until you switch it off.

## Turning it on (release build, Android 16 emulator)

| Garage → Navigation, as it starts | Android's notification-access page | Android's confirmation | Garage after it |
|---|---|---|---|
| ![](screenshots/emulator-garage-navigation.png) | ![](screenshots/android-access-screen-granted.png) | ![](screenshots/android-access-dialog.png) | ![](screenshots/emulator-garage-navigation-granted.png) |

The switch is off to begin with; turning it on says "Needs notification access" and offers Android's own page, where the person turns TapeDash on and confirms Android's dialog. Android 16 did **not** block this with "restricted settings" for an app installed over adb; whether it does for an app installed some other way, and on Android 13 to 15, has not been seen. Android's own dialog says an app with this access can read notifications and "reply to messages" and "change settings"; TapeDash does neither, and Garage says what it does read.

## Two things seen that the app cannot fix, and what it does about them

| Maps' own floating window, over the HUD | Maps' card over the HUD, at a turn (real Maps, release build) |
|---|---|
| ![](screenshots/problem-maps-floating-window.png) | ![](screenshots/problem-maps-heads-up-over-hud-700m.png) |

1. **Google Maps shrinks to a small floating map when you switch away from it during a route.** On the glass that would be a bright window on the HUD's black. Android lets you turn it off for Maps (Settings, Apps, Special app access, Picture-in-picture); Garage says so under Navigation, and the hardware handoff says to do it first.
2. **Google Maps pops its notification over the screen as a card at turns, and I first got this wrong.** I had written that it happens the first time and that Do Not Disturb is the answer. With the release build and real Maps it happens at **every turn**: Maps moves its notification into a high-importance channel called "Navigation urgent updates" as a turn nears, and Android 16 shows it at the top for about 6 s, over the distance and the arrow (the second picture above; another at [280 m](screenshots/problem-maps-heads-up-over-hud-280m.png)), with the status bar showing. Measured over three 170 s drives: **25 of 85 frames had the card; with Do Not Disturb on, still 26 of 85; with "Pop on screen" switched off for that one channel, 0 of 85**, although Maps went on posting into it. So Garage now has a note and a row that opens Android's notification page for Google Maps; the switch is one level down, in the list of categories ([the page](screenshots/android-maps-notification-settings.png), [the channel](screenshots/android-maps-urgent-channel-settings.png), [Garage](screenshots/emulator-garage-card-note.png)). Maps goes on guiding. On your own phone it does the same (see above).

## What I am asking you

1. **The instruction.** It is Google's own text in the phone's language, up to three lines at 0.068H (24 lp at 360). That is more than DESIGN.md 11's six words for a Motion screen, and I made it the one exception on purpose, because the street you turn onto is what a driver wants. **Is it readable at a glance on the glass, or should it be shorter** (two lines, or only what follows "onto")?
2. **The line with the dot.** Is it useful beside the arrow, or clutter on the glass? It is the thing you called "line maps"; it is cheap to take out.
3. **Three figures along the bottom** (ETA, time left, distance left). Keep all three? The time left is Google's when it gives one, and otherwise the ETA less the phone's clock.
4. **The takeover.** The layout comes and goes by itself with Maps' notification. There is no "navigation HUD" to choose. Is that right, or should the HUD stay as you left it unless you pick this one? (Side note: I could not find a Garage control for choosing among the three older HUD layouts; the choice is only kept in the settings. Say if that is wrong.)
5. **The wording:** NO UPDATE for a Maps that has gone quiet.
6. **The arrow's size** (0.34H) against the speed (0.34H): equal weight is deliberate.

## What is not reviewable yet, said plainly

- The windshield. Brightness, the double image of a laminated screen, and whether three lines of text survive it.
- A real drive. On your phone the notification access was granted over adb (the Android 13+ "restricted settings" block was not met), Maps and TapeDash ran together at a desk for four runs of 2 to 3 minutes at 25 to 27 degrees, and nothing was tried in the sun or for a whole drive.
- **Other languages and units**: both captures read so far (Maps 25.33 on an emulator, 26.42 on your phone) are English and kilometres.
- Maneuvers that have not been seen: a roundabout, a U-turn, a highway exit. Where the arrow cannot be read the line is drawn straight, and Google's own arrow still says it.
- Frame rate on an old phone. On the emulators, with software drawing, the HUD cost p50 1.3 ms and p99 5 to 7 ms (Android 16), p50 11 ms and p99 21 to 29 ms (Android 7). That says nothing about a real low-end phone.

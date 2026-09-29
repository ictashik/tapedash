# Build video frames

Real renders of TapeDash, in the order it was built. Each is 1280 x 720 (a 640 x 360 lp
screen at 2x) unless it says otherwise. `tool/build_frame.sh` adds one.

| # | Frame | Taken at | What it shows |
|---|---|---|---|
| 1 | [001-numerals-ion.jpg](frames/001-numerals-ion.jpg) | `e5e107a` | First real pixels: Saira wide numerals drawn from a glyph atlas, a baked halo, on the vignette and grain void |
| 2 | [002-odometer-roll.jpg](frames/002-odometer-roll.jpg) | `e5e107a` | The detented odometer, frozen at seven values: 3 to 4 through the middle 40%, and 9 to 10 and 19 to 20 carrying in sync |
| 3 | [003-livery-vfd.jpg](frames/003-livery-vfd.jpg) | `e5e107a` | VFD livery: seven-segment digits with an 8 degree lean, ghost segments at 7%, the leading zero as a ghost 8, and the hex mesh |
| 4 | [004-livery-mono.jpg](frames/004-livery-mono.jpg) | `e5e107a` | MONO livery: Saira Light, thin strokes, halos at 40% |
| 5 | [005-livery-ember.jpg](frames/005-livery-ember.jpg) | `e5e107a` | EMBER livery: warm accent, Saira SemiBold |
| 6 | [006-mode-daylight.jpg](frames/006-mode-daylight.jpg) | `e5e107a` | Daylight mode on EMBER: halos off, and the numerals switch to ink.bright because the accent is under 10:1 |
| 7 | [007-mode-night.jpg](frames/007-mode-night.jpg) | `e5e107a` | Night mode on EMBER: halos halved |
| 8 | [008-icon-set.jpg](frames/008-icon-set.jpg) | `e5e107a` | The icon set: 27 glyphs drawn in code on a 24-unit grid, lines along an axis or at 45 degrees, circles the only curve |
| 9 | [009-app-shell-device.jpg](frames/009-app-shell-device.jpg) | `62fb1bb` | The app, for real: on the API 24 emulator, the void canvas with grain, and the one way in until phase 3b's Strip exists |
| 10 | [010-lab-numerals-device.jpg](frames/010-lab-numerals-device.jpg) | `62fb1bb` | The Design Lab, on device: numerals tab, real halos, real grain, the livery and mode switchers live |
| 11 | [011-lab-controls-device.jpg](frames/011-lab-controls-device.jpg) | `62fb1bb` | The Design Lab's controls tab on device: the chamfer button, the toggle mid-glow, the segmented selector |
| 12 | [012-lab-aspect-frame-device.jpg](frames/012-lab-aspect-frame-device.jpg) | `62fb1bb` | The aspect-frame switcher actually letterboxing to 20:9 on device, after a bug the Lab's own tests caught |
| 13 | [013-tach-arc.jpg](frames/013-tach-arc.jpg) | `d65614a` | The tach arc: chamfered segments, a light-blade needle, the redline zone in critical red past 6,500 rpm |
| 14 | [014-shift-horizon.jpg](frames/014-shift-horizon.jpg) | `21e2a7a` | The shift horizon: 24-segment-per-side light bar converging to the centre, accent to caution to critical by position |
| 15 | [015-bar-gauge.jpg](frames/015-bar-gauge.jpg) | `21e2a7a` | The vertical bar gauge: an accent.deep to accent.core fill, the etched normal band, a bright leading-edge line |
| 16 | [016-telemetry-tile.jpg](frames/016-telemetry-tile.jpg) | `1ace648` | The telemetry tile: bracket frame, rolling value, a 60 s sparkline at 2 Hz, brackets tinting caution live as rpm crosses the threshold |
| 17 | [017-eco-bar.jpg](frames/017-eco-bar.jpg) | `72b91b3` | The eco bar: a glowing puck centred on the car's own average km/L, moving right when more efficient, left when thirstier. |
| 18 | [018-status-strip.jpg](frames/018-status-strip.jpg) | `04a9cb7` | The status strip: the adapter glyph turns caution and gains a caption once parked -- SEARCHING pulses at 0.5 Hz while connecting. |
| 19 | [019-alerts.jpg](frames/019-alerts.jpg) | `944ff41` | A critical alert: the coolant gauge itself turns critical, and a chamfered bracket pulses at 1 Hz around it. |
| 20 | [020-road-view.jpg](frames/020-road-view.jpg) | `89dd1da` | The road view at 120 km/h: converging lane lines, truthful-motion dashes, speed streaks and the hero speed readout. |
| 21 | [021-vertical-tape.jpg](frames/021-vertical-tape.jpg) | `390010f` | The vertical tape: the aircraft-style RPM instrument, scrolling past a fixed readout, with a redline band and a trend vector -- the instrument TapeDash is named for. |
| 22 | [022-money-tape.jpg](frames/022-money-tape.jpg) | `56de0ba` | The Money Tape: each block is a rupee, styled by where it went -- normal, hollow for idling, notched for hard acceleration, solid for high speed. |
| 23 | [023-apex-cluster.jpg](frames/023-apex-cluster.jpg) | `74944ac` | The Apex cluster: the first real screen, reading a real DemoDrive through the actual OBD stack -- not synthetic capture data. |
| 24 | [024-road-cluster.jpg](frames/024-road-cluster.jpg) | `1714f59` | The Road cluster on a real demo drive at 81 km/h: the road view full-bleed with its hero speed and horizon RPM bar; night mode's headlight cone is subtle enough that a pixel test, not the eye, settled it. |
| 25 | [025-tape-cluster.jpg](frames/025-tape-cluster.jpg) | `6af6856` | The Tape cluster, the brand layout, on a real demo drive at 81 km/h: the speed and RPM tapes with their readout boxes straddling the inner edges, trend vectors, and the shared horizon above. |
| 26 | [026-minimal-cluster.jpg](frames/026-minimal-cluster.jpg) | `9d14916` | The Minimal cluster on a real demo drive at 81 km/h: the hero speed and a thin RPM line under its digits, nothing else; the numeral's centring is measured, not eyeballed. |
| 27 | [027-telemetry-cluster.jpg](frames/027-telemetry-cluster.jpg) | `49915fa` | The Telemetry cluster, the enthusiast layout, on a real demo drive: six tiles (RPM, speed, throttle, load, coolant, volts) with sparklines filled from 60 s of real history, numerals caught mid-roll. |
| 28 | [028-the-strip.jpg](frames/028-the-strip.jpg) | `99dbc81` | The Strip mid-swipe, on a real demo drive: the Money page half in with the parallax, the Drive page half out, and the page tape carrying the motion lock. |
| 29 | [029-drive-page.jpg](frames/029-drive-page.jpg) | `addce3b` | The Drive page's reel on a real demo drive: the five cluster layouts ride one vertical Flow, cycled by a vertical swipe, the choice held for the session. |
| 30 | [030-parked-dock.jpg](frames/030-parked-dock.jpg) | `a505ef4` | The parked dock on a real demo drive, cold-started: the dock rises into the floor zone with Garage, Pit Stop, Diagnostics and HUD, the buttons staggered after it; the destinations say what is coming. |
| 31 | [031-mode-parked.jpg](frames/031-mode-parked.jpg) | `d177350` | Parked: the tach arc thinned and dimmed to 60%, the hero shrunk to primary size, the status strip's captions under its glyphs -- the Motion <-> Parked choreography (DESIGN.md 7.2), all on one shared parked share |
| 32 | [032-shared-element-flight.jpg](frames/032-shared-element-flight.jpg) | `e3f2e09` | Swipe to Money and the speed you were watching travels to the status corner instead of vanishing. |

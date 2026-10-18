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
| 33 | [033-ignition-sequence.jpg](frames/033-ignition-sequence.jpg) | `69923ae` | The ignition: the needle swings back from redline as the numerals roll up and the horizon is about to draw. |
| 34 | [034-connection-states.jpg](frames/034-connection-states.jpg) | `e3983c8` | Connection states: the cluster in standby, a sweep beam circling the arc while it looks for the adapter. |
| 35 | [035-hud.jpg](frames/035-hud.jpg) | `84db5c1` | The HUD: pure black, one colour, Bold numerals, and the red zone stands taller as well as red. |
| 36 | [036-demo-shell.jpg](frames/036-demo-shell.jpg) | `bd5696c` | The app opens on a live simulated drive: the cluster, the clock and the DEMO badge, the page tape beneath. |
| 37 | [037-onboarding.jpg](frames/037-onboarding.jpg) | `09b7a6d` | First launch: the wordmark over its tape line, and the choice beneath it. |
| 38 | [038-brand.jpg](frames/038-brand.jpg) | `c98471c` | The app icon: a fragment of the tach arc with its last segment lit, above the tape. |
| 39 | [039-insights-tank.jpg](frames/039-insights-tank.jpg) | `5459bd9` | Insights, Tank without a gauge: the City sends no fuel level, so the dash counts the litres from the last full tank; the column drains, the reserve is hatched, the range is to the nearest 5 km. |
| 40 | [040-dock-insights.jpg](frames/040-dock-insights.jpg) | `5459bd9` | The parked dock at 640 lp with its new Insights button, End trip showing: six buttons still fit. |
| 41 | [041-insights-current.jpg](frames/041-insights-current.jpg) | `1c2d765` | Insights, Current: the volts of a drive inside the charging band, the deepest dips marked (a dip is a dent; the car reports no battery current), and the battery's resting voltage week by week. |
| 42 | [042-insights-powerflow.jpg](frames/042-insights-powerflow.jpg) | `3ce5eff` | Insights, Powerflow: where the energy in a trip's fuel went, from the fuel to the wheels, idling and engine heat, and from the wheels to tyres, air and brakes, with the rupees. |
| 43 | [043-insights-power.jpg](frames/043-insights-power.jpg) | `3ce5eff` | Insights, Power: a dyno chart built from ordinary driving, dots by throttle, the highest seen as a line, and the revs the car has never reached hatched as no data yet. |
| 44 | [044-insights-gears.jpg](frames/044-insights-gears.jpg) | `e72666c` | Insights, Gears: a gearbox found from the driving, each gear a ray of rpm against speed labelled by its ratio, with the speeds it was held between. |
| 45 | [045-insights-gears-cvt.jpg](frames/045-insights-gears-cvt.jpg) | `e72666c` | Insights, Gears on a CVT in the VFD livery: no rays, only a fan, and the page says so. |

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

# The exchange format (TDX)

How data gets **out of** and **into** TapeDash: trips and their samples, fill-ups, the car's setup, the price, the adapter, the look and the battery's resting readings. One file format, many ways to carry it:

| Way | Where it works | Needs |
|---|---|---|
| **adb pull / push** | any phone or watch with USB or Wi-Fi debugging | a computer |
| **In the app, to a file** (Garage → Data → Export) | phone and watch | nothing: it writes to the app's own folder (the same one adb reaches) |
| **In the app, share sheet** (Export) and **file picker** (Import) | phone | nothing; Wear OS has neither, so the watch uses the folder |
| **Beam** (phone ↔ watch over our own Bluetooth link) | designed, **not built** (see the end) | pairing |

The file is the unit. Nothing in the format knows how it travelled. Nothing is ever sent by TapeDash itself: no account, no server (CLAUDE.md 1).

Why this exists at all: the app keeps its trips in a private database and its settings in private preferences, which a release build does not let adb read, and a watch has no keyboard to set a price or an adapter on. A file in the app's own external folder is the one thing both a person and adb can reach.

## 1. The file

- **Name:** `tapedash-<scopes>-<yyyymmdd-hhmmss>-<device>.tdx`, or `.tdx.gz` when compressed. Any name is accepted on import; only the content matters.
- **Content:** UTF-8 text, **one JSON object per line** (newline-delimited JSON), LF line endings. Read it with `less`, `grep`, `jq -c .` or `zcat file.tdx.gz | jq -c .`.
- **Compression:** optional gzip. The reader tells them apart by the gzip magic bytes (`1f 8b`), never by the name. The app writes `.tdx.gz` when the file has trips in it (samples are the bulk: about 80 bytes a second of driving), and `.tdx` otherwise.
- **Limits:** a file over 256 MB, or one that expands past 512 MB, or a line over 4 MB, is refused.

### Lines

Every line is an object with a `"t"` (type). The first line is always the header and the last is always `end`.

```jsonc
{"t":"tdx","v":1,"app":"tapedash","appVersion":"0.9.0","createdMs":1793088900000,"created":"2026-10-24T08:15:00.000Z","device":{"id":"3f9c1a6e","kind":"watch","name":"Galaxy Watch4 Classic"},"scopes":["profile","trips","fillups","rest"]}
{"t":"profile","vehicle":{"fuelType":"petrol","displacementL":1.5,"tankL":40,"blend":"e20"},"money":{"pricePerLitre":115.0,"currency":"INR"},"adapter":{"kind":"ble","address":"66:1E:32:00:11:22","name":"OBDBLE"},"source":"obd","coach":{"preset":"normal","speedLimitKmh":100},"look":{"livery":"ion","driverSide":"right","cluster":0,"ignition":"full","reduceMotion":false}}
{"t":"trip","k":1793001234000,"startedMs":1793001234000,"endedMs":1793003034000,"distanceKm":14.2,"litres":0.93,"uncalibratedLitres":0.89,"cost":106.9,"pricePerLitre":115.0,"idleSeconds":142,"engineSeconds":1800,"bucketLitres":{"normal":0.71,"idling":0.08,"hardAcceleration":0.06,"highSpeed":0.08},"blocks":"nnnnnnniinnnhhnnss","fuelSource":"maf","lowConfidence":false,"calibrationFactor":1.04,"hardAccelerations":2,"hardBrakings":1,"longIdles":1,"longestIdleSeconds":96,"highRpmSeconds":4,"speedingSeconds":0}
{"t":"samples","trip":1793001234000,"cols":["s","kmh","rpm","thr","lph","lat","lon","load","clt","v"],"rows":[[0,0,812,0,0.74,12.9716,77.5946,null,null,null],[1,3,950,14,0.9,12.9716,77.5946,31.2,48,14.1]]}
{"t":"fillup","k":1792900000000,"atMs":1792900000000,"litres":31.2,"amount":3588,"full":true,"factor":1.02}
{"t":"rest","readings":[[1792950000000,12.61],[1793036400000,12.58]]}
{"t":"end","counts":{"profile":1,"trip":1,"samples":1,"fillup":1,"rest":1},"crc32":"9be3a2f0"}
```

| Line | Meaning |
|---|---|
| `tdx` | The header. `v` is the **major version** (1). `device` says where it was made (an install id, `phone` or `watch`, and a model name). `scopes` says what was asked for; a file with `trips` in its scopes and no trip lines means "no trips yet", not "not asked". |
| `profile` | The portable setup: **vehicle** (fuel type, displacement, tank, petrol blend), **money** (price a litre, currency), **adapter** (kind, address, name, port), **source** (`obd` or `gps`), **coach** (preset, speed threshold) and **look** (livery, driver side, cluster, ignition sequence, reduce motion). Any part may be missing; a missing part is left as it is. |
| `device` | *(scope `device`, never in a default export)* Settings that belong to one screen: HUD colour, flips, position and scale, the fidelity tier held by hand, the Daylight/Night setting, engine sound, compatibility mode, session recording. |
| `trip` | One finished trip (columns of `trips`, with names rather than indexes: `fuelSource` is `5e`, `maf`, `map`, `none`; the buckets are keyed by name). `blocks` is the Money Tape in one string, a letter per ₹: `n` normal, `i` idling, `h` hard acceleration, `s` high speed. |
| `samples` | The second-by-second record of the trip `trip` (its `k`). `cols` names the columns of each row: `s` seconds from the start, `kmh`, `rpm`, `thr` throttle %, `lph` litres an hour (calibrated), `lat`, `lon`, `load` %, `clt` coolant °C, `v` module volts. Unknown or null columns are `null`. A trip's samples may be split across several lines (the writer cuts at 2,000 rows), in order. |
| `fillup` | One visit to the pump. |
| `rest` | The battery's resting voltage log: `[ms, volts]` pairs, oldest first. |
| `end` | The footer. `counts` is how many of each line the writer wrote before it; `crc32` is the CRC-32 (IEEE 802.3, 8 lowercase hex digits) of **every byte before this line**, newlines included. |

Numbers are JSON numbers, the shortest that round-trips. Times are **milliseconds since 1970 UTC** everywhere, so a file means the same on a phone in Bangalore and a laptop in London; `created` is only for people.

### Never exported

- **Trips that are not finished** (`endedMs` null) and **simulated trips** (`is_demo`, from builds that had Demo Mode). They are left in the database as they are.
- The adapter's remembered protocol and the connection log (they describe a link, not the car), recordings and survey logs (they are files already: `files/recordings/`, reachable by adb as before).
- The running fuel count since the last full tank. It is only right with every trip since, on one device, so each device keeps its own; after an import the tank figure is re-counted from the fill-ups, and says "≈" as always.

## 2. Reading it

A reader **checks the whole file before it changes anything**: the header and its version, then every byte against the footer's CRC. A file with no footer (cut short by a dropped connection or a full disk) or a wrong CRC is refused whole, with a plain reason ("This file is not complete: it ends before its last line").

- **Versions.** A reader accepts any `v` up to its own. A bigger `v` is refused ("made by a newer TapeDash"). Adding a field or a line type is **not** a version change: a reader ignores fields and lines it does not know (and counts them in the report). A change that would make an old reader do the wrong thing bumps `v`.
- **Bad records.** A line that is not JSON, or has an impossible value (a negative distance, a latitude of 400, a trip that ends before it starts, a price of ₹0 or ₹10,000 a litre), is **rejected on its own**: it is counted, the first few reasons are kept for the report, and the rest of the file goes on.
- **Memory.** It reads line by line, twice (once to check, once to apply), and never holds the whole file. A year of daily drives is about 100 MB plain and 15 to 20 MB gzipped.

## 3. Merging

Importing **adds**, and never deletes. Two devices that have driven different trips end up with both.

| Thing | Same one when | If it is already here |
|---|---|---|
| Trip | same `k` (start time, ms) | skipped, and counted. A trip is never overwritten: a trip is a record. |
| Fill-up | same `k` and the same litres | skipped, and counted. |
| Rest voltage | same `ms` | skipped; the log is kept to its newest 120. |
| Profile | there is one only | **applied only when asked** (the import screen says what it would change), and only while parked. Applying it replaces the parts the file has. |

The same drive recorded on two devices at once (a phone and a watch both on the car) has two start times a second apart, so it comes in as two trips. Nothing guesses that they are one.

A trip that comes in has its own new id. The trips, the totals, the efficiency curve, the insights and the toll map are worked out from the trips on the device, so they fill in at once. After fill-ups come in, the calibration is rebuilt from them (the factors travel with the fill-ups).

**Each trip is saved whole or not at all** (the trip and its samples in one SQLite transaction), and everything that could be wrong with the file (its checksum, its version, every line's values) is found in a first pass **before the first trip is saved**. So a file that is damaged or cut short changes nothing; the only way to fail half way is the disk filling up, and then the trips already saved are whole trips.

## 4. Where the files are

On Android: the app's own external folder, which needs no permission and which adb can reach on any Android (the same place the session recordings go):

```
/sdcard/Android/data/io.github.ictashik.tapedash/files/exchange/
  outbox/     what Export wrote
  inbox/      what Import will read (drop files here)
  done/       what Import has read (moved here, never deleted)
  result.json what the last export or import did
```

The app makes these folders at its first start, so `adb push` has somewhere to go. `result.json` is written when an export or an import is done and says what it did (the counts, the sentence, the file), so a script can wait for it and read it; it is also how a script knows the app answered at all.

## 5. adb

```sh
PKG=io.github.ictashik.tapedash
DIR=/sdcard/Android/data/$PKG/files/exchange
ADB="adb"                       # or: adb -s <serial>  (a watch: adb connect <ip>:<port> first)

# Pull everything off the device (phone or watch) without touching its screen
$ADB shell am start -n $PKG/.MainActivity --es tapedash.exchange export
sleep 3
$ADB pull $DIR/outbox/ ./from-device/
$ADB shell cat $DIR/result.json

# Push a setup (or someone else's trips) in, and have the app read it. (Not
# `adb push` straight into $DIR: see below.)
$ADB push setup.tdx /data/local/tmp/ && $ADB shell "cp /data/local/tmp/setup.tdx $DIR/inbox/"
$ADB shell am start -n $PKG/.MainActivity --es tapedash.exchange import
$ADB shell cat $DIR/result.json
```

`tool/adb_exchange.sh` wraps these: `export [SCOPES]` (asks, waits, pulls), `pull`, `push FILE`, `import [--apply]` (asks, waits, prints the result) and `result`, each with `-s SERIAL` for a watch. The start intent's `tapedash.exchange` extra is `export` or `import`; `--es tapedash.scopes profile,trips,fillups,rest` narrows an export, and `--ez tapedash.apply_profile true` lets an import apply the file's profile (without it the profile is only counted and reported, never applied by a script by accident).

- **While the car is moving** nothing is imported (the app is a dashboard first): the request waits and is reported as skipped. An export is fine at any time.
- On Android 11 and later `/sdcard/Android/data` is closed to other **apps** but open to the `adb shell` user, so `pull` works as written. **`adb push` straight into the folder fails** ("remote fchown failed: Operation not permitted": the sync protocol tries to change the owner on scoped storage), found on a Wear OS 3 (Android 11) emulator on 2026-10-24. `tool/adb_exchange.sh push` therefore stages the file in `/data/local/tmp` and copies it as the shell user, which works; the copy is owned by `shell` with the group `ext_data_rw`, which the app is in, so the app reads it. Done the same by hand: `adb push f /data/local/tmp/ && adb shell cp /data/local/tmp/f $DIR/inbox/`. Checked on that emulator (export, pull, push, import, the setup applied, `result.json`); **not yet on a phone or a real watch** (CLAUDE.md 11).

### On a computer: `tool/tdx.dart`

The codec is pure Dart, so the same code reads files on the laptop:

```sh
dart run tool/tdx.dart info  from-device/*.tdx.gz        # header, counts, date range
dart run tool/tdx.dart check from-device/*.tdx.gz        # the CRC and every record
dart run tool/tdx.dart merge a.tdx b.tdx.gz -o all.tdx   # trips and fill-ups by key
dart run tool/tdx.dart csv   all.tdx > trips.csv         # one row a trip, for a spreadsheet
```

`merge` is how a phone and a watch's trips become one file. `csv` is the "export trips as CSV" that DESIGN.md 7.8 promised: the numbers are the stored ones, unrounded.

## 6. In the app

- **Garage → Data** (phone and watch; parked only): **Export** writes a file to `outbox/` and, on a phone, opens the share sheet for it (save it, mail it, send it to a friend: the app does none of that); **Import** lists what is in `inbox/` and, on a phone, offers **Choose a file** (Android's own picker, which grants the app that one file and no storage permission). Either way the result is a plain sentence: "Added 12 trips and 3 fill-ups. 2 were already here." and, if there was a profile, a button **Apply the setup from this file** with what it would change.
- **The watch** has no picker and no share sheet: its Data row shows how many files are waiting in `inbox/`, imports them on a tap, and exports to `outbox/`. Getting a file to or from a watch is adb, or Beam.

## 7. Beam (designed, not built)

A phone and a watch that are already paired can send each other a file over **Bluetooth Classic** (RFCOMM, a UUID of our own), with our own Kotlin channel and no Google Play Services (Wear's own phone link is the Play Services Data Layer, which CLAUDE.md 4 rules out). The receiver shows a four-digit code, the sender types or picks it, and the file goes across in length-prefixed frames with a CRC per frame; what arrives is a `.tdx` file in `inbox/`, to be imported like any other. The format needs nothing for this, which is why it is a transport and not a feature of the format. It is left out for now because it is a new native channel nobody can test without a phone and a watch side by side; it is the first thing to build once they are on the desk together.

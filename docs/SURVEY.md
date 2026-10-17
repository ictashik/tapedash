# Survey drive

A one-off drive that finds out what your car's computers will tell TapeDash. It
reads everything the car offers over the OBD socket, as fast as the adapter
allows, and writes the whole conversation to one file on the phone. Nothing is
shown on a dashboard while it runs: the file is the product.

Why: the first real drives showed that the car has **two ECUs** answering, with
different PIDs, that TapeDash read 9 of the 32 PIDs the car lists, and that the
dashboard got each value only 1.3 times a second. A survey asks for all of it,
properly, so the next pages (an electrical page, an engine page) are designed
from what the car really gives and not from what a car like it might.

## What it does, and what it never does

It **reads**. Mode 01 (live data), 03 / 07 / 0A (stored, pending and permanent
fault codes), 06 (the ECUs' own test results) and 09 (calibration ID, its
verification number, the ECU's name). It also asks the adapter itself what
voltage it sees at the OBD socket (`ATRV`), which it can answer with the car off.

It **never writes** and never asks for what is personal:

- it does not clear codes (Mode 04), change a setting, or send a request to
  change anything in the car;
- it does not ask for the **VIN** (Mode 09 PID 02), so the file does not have it;
- it uses no network and no location, and the file stays on the phone until you
  copy it off.

The file does name the adapter and its Bluetooth address, like any recording
(`recordings/real/` already has them).

## Before you go

- The phone on the dash and charging, as usual. The screen stays on.
- The adapter plugged in. Nothing else is needed: **no price, no trip, no
  setup**.
- It takes over the adapter, so **the dashboard is off while the survey runs.**
  It comes back when you finish.

## The drive

**The app leads.** Nothing has to be remembered or tapped except the big buttons.

1. **Parked, engine running, handbrake on.** Garage → Adapter → **Survey drive**
   → read the screen → **Start survey**. About 20 seconds of *Getting ready*
   while it sets up the adapter and asks the car what it has.
2. **Parked checks (about four minutes).** The screen offers them: **Begin
   checks**. Then, one step at a time, in big letters, it says what to do and
   counts down: everything off; headlights on, off; blower low, high, off; A/C
   on, off; rear defogger on, off; wipers on, off; the steering wheel lock to
   lock; and, last, an optional gentle rev (in P with the handbrake on, to about
   2,000 rpm, three times, not higher; **skip it if you are not comfortable**).
   As each step begins the app writes the switch into the log with its time, so
   you do not tap anything. **Next step** skips a step, **Stop checks** gives
   them up (anything it had said was on is written as off). This is what lets us
   see what each load does to the battery voltage.
3. **Drive as you normally do, twenty minutes or more.** City is fine. If there
   is a clear, legal stretch, a steady 60 to 100 km/h, a firm (not flat-out)
   acceleration and a lift-off coast show things a gentle drive never does.
   **Nothing is required**, and while the car moves the screen shows the time and
   a few numbers and has **nothing to touch**. The checks never start, and stop
   at once if they are running, when the car moves.
4. **Park.** After five seconds standing, the screen offers the checks again
   (**Repeat the checks**, with the engine warm) and **Finish survey**. Do the
   second run if you can, then finish. It says *Survey saved* and the file name;
   **Dashboard** goes back.
5. If the car is switched off during the survey it waits (*The car is off*) and
   carries on when you start it. If it is off for 30 minutes the survey ends by
   itself and saves what it has. The file is also written to the phone every 20
   seconds while it runs, so a phone that dies or an app that is closed still
   leaves the last copy.

If you skip the first checks, the screen offers them again as soon as you stop,
and at the end.

## Getting the file

The file is `survey-<date>-<time>-<ble|bluetoothClassic|wifi>.log`, in the same
folder as every recording:

```
adb pull /sdcard/Android/data/io.github.ictashik.tapedash/files/recordings/ ./pulled
```

When you tell whoever reads it about the drive, include: the car (model, year,
variant, petrol or hybrid), anything the checks asked for that you could not do
or that the car does not have (no rear defogger, say), whether the A/C was on
during the drive, and anything odd you saw on the phone. The file has what the
app asked for and when; it cannot know what you actually did.

## Reading it at a desk

```
dart run tool/survey_summary.dart pulled/recordings/survey-….log --csv survey.csv
```

prints the ECUs and their PIDs, how often each PID was read and the range it
covered, the answers to the other modes, your marks, and what the survey decided
along the way. `--csv` writes every reading as `t_s,ecu,pid,hex,value` (a value
only for the PIDs TapeDash has the formula of; the raw bytes are always there).

To try it without a car: `dart run tool/record_survey.dart` makes a survey of the
simulated twin-ECU car in `recordings/sim/survey.log`, and
`dart run tool/sim_server.dart --host 0.0.0.0 --profile petrol_cvt_twin_ecu`
serves that car over WiFi, so the app can be pointed at it (a WiFi adapter at the
computer's address, port 35000) and a whole survey run on the bench.

## What it does inside

1. Starts the adapter up the way the dashboard does.
2. Turns **headers on** and asks which PIDs exist (`0100`, `0120`...), so each
   ECU's reply carries its own ID and the two can be told apart.
3. Reads **every PID each ECU has, once**, then the other modes. With two ECUs it
   listens to one at a time (`ATCRA`), because when both answer with a long
   message, the adapter sends flow control to one only, and the other's answer is
   cut off. This is what the first recordings show.
4. **Drives**: PIDs round and round, six to a request, headers off. The ones that
   say what the engine is doing (revs, speed, throttle, load, air flow, battery
   voltage) about every 0.4 s, the sensors and the ECU's own commands about every
   2 s, temperatures every 10 s, status words every minute. A switch from one ECU
   to the other costs two commands, so it stays on one until the other is twice as
   late as it should be.

Every decision it makes is a line in the log that starts `@ survey`.

## What could go wrong, and what it does about it

| If the adapter... | the survey... |
|---|---|
| does not take `ATCRA` | says so, listens to every ECU at once, and lets the batch fall to what works |
| takes `ATCRA` and then nothing comes through | notices after three requests, drops it, and does not think the car is off |
| does not take several PIDs at once | falls to three, then to one, and still reads everything |
| prints headers in a form it cannot read | says so, and goes on without telling the ECUs apart (one ECU, `ALL`) |
| resets itself (`LV RESET`) | starts it up again and carries on |
| loses the link | opens it again (1, 2, 4, 8, then every 10 seconds) and carries on without starting over |
| the car is switched off | waits, asking every 2 seconds, and carries on |

## Not verified

It is tested against the simulator only: a car with two ECUs on 29-bit CAN, the
PID sets the first recordings listed, behind an adapter as slow as the one they
came from. **These are assumptions until a real survey runs**, and the log will
show which held:

- that the adapter takes `ATCRA`, and prints 29-bit headers as eight hex digits
  (`18DAF110`);
- that headers-on frames come as the ISO 15765-2 frames and not as numbered lines;
- that the car's ECUs allow six PIDs in a request when only one of them is
  listened to;
- how fast the real adapter runs the survey (the simulator says about 2.3 reads a
  second for the revs, against 1.3 for the dashboard);
- the *addresses* of the two ECUs (the simulator calls them `18DAF110` and
  `18DAF111`; the car's are what the survey finds).

## What it does not look for

**Honda's own extended data** (Mode 22, battery current, CVT temperature...)
is not asked for. No list for this car was found, and sending requests the
car's makers have not published to a car's computers is not something to do
blind. If the survey shows something that points to it, that is the next step,
and a separate decision.

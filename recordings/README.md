# Recordings

Raw ELM327 sessions: what passed between an app and an adapter, with the time of
each piece. The format is `lib/obd/transport/session_log.dart`; a file is text,
one line to an entry, and can be read and diffed.

```
# tapedash-session v1
# scenario: city_stop_go
1.270 > 0100\r
1.270 < SEARCHING...\r
3.690 < 4100983A8001\r
3.730 < \r>
```

A line's marker is `>` (sent), `<` (received), `!` (a link event) or `@` (a note
the app wrote about itself: its setup, connection status, engine, mode and trip,
and a `vitals` line every 5 s; replay ignores them). Only a recording of a real
drive has notes.

## `sim/`: made by the simulator

`dart run tool/record_sim.dart --scenario city_stop_go` records one drive, and
`--all` records all ten in about ten seconds. The same options give the same
file, byte for byte, so these are not kept in git (they are 0.3 to 5.3 MB each,
23 MB for the ten); make them when you want them.
`dart run tool/record_sim.dart --help` lists the options: profile, adapter
quirks, seed and length.

The traffic is the app's own. The recorder runs the real OBD stack, an
`ObdSession`, on the simulated car: it starts the adapter up, asks which PIDs the
car has, reads the fault codes once it is connected, and polls in fast, medium
and slow tiers with batching. So a recording shows what the app really sends.

## Replaying

`ReplayTransport` (`lib/obd/transport/replay_transport.dart`) plays a recording
back into the stack. It does not follow the clock: each command gets the next
recorded reply to the same command, with its pieces at the offsets they had. A
recording made by one build can therefore be played into another, even if the
commands go out in a different order or at different times. A command that is not
in the recording gets `?`, and an exchange that got no reply in the recording
gets none in the replay.

## `real/`: made in a real car (after the hardware handoff)

Logs recorded from the user's own car by the app's session recording. Each one
becomes a regression test: replayed through `ReplayTransport`, the app has to
read it the way it did on the day. Recordings from someone else's car are never
committed (CLAUDE.md 2).

## `private/`

Ignored by git. For anything that should stay on one machine.

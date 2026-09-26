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

## `sim/`: made by the simulator

`dart run tool/record_sim.dart --scenario city_stop_go` records one drive, and
`--all` records all ten in about two seconds. The same options give the same
file, byte for byte, so these are not kept in git (they are 0.2 to 2.6 MB each);
make them when you want them. `dart run tool/record_sim.dart --help` lists the
options: profile, adapter quirks, seed and length.

The client that makes the traffic is a small script that stands in for the app's
OBD stack, which does not exist yet. It starts the adapter up, asks which PIDs the
car has, reads the fault codes and polls in fast, medium and slow tiers. It does
not read the answers.

## `real/`: made in a real car (after the hardware handoff)

Logs recorded from the user's own car by the app's session recording. Each one
becomes a regression test: replayed through `ReplayTransport`, the app has to
read it the way it did on the day. Recordings from someone else's car are never
committed (CLAUDE.md 2).

## `private/`

Ignored by git. For anything that should stay on one machine.

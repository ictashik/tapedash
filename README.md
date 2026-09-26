# TapeDash

TapeDash turns an old Android phone into a car dashboard, a windshield HUD and a trip computer that shows where the money goes. It runs off a cheap ELM327 OBD-II adapter.

The whole idea: buy an ELM327, plug it into the OBD port, stick an old phone to the dash with double-sided tape, and drive.

- **A dashboard built like an instrument, not an app.** Tapes, a tach arc, detented numerals, a shift horizon. See [DESIGN.md](DESIGN.md).
- **A trip computer for your wallet.** ₹ per trip, per km, and what idling cost you.
- **A gentle driving coach.** It stays quiet while you drive and speaks only when the car is stopped.

## Status

Pre-alpha, **Phase 0 (foundation)**. Nothing has been tried on a real car yet. Everything is built and tested against a built-in vehicle simulator first, and real hardware comes only after every simulator test passes. The roadmap is in [CLAUDE.md](CLAUDE.md) section 13.

## Principles

- **Strictly offline.** No cloud, accounts, analytics, ads or price lookups. Fuel prices are entered by you. The only network use is a local WiFi ELM327 adapter, and that is limited to private addresses.
- **Old phones first.** Targets a 2 GB RAM, 32-bit ARM phone on Android 7.0 with a 720p screen.
- **Open source, F-Droid compatible.** No Google Play Services, Firebase or proprietary SDKs.
- **Honest numbers.** Fuel and money figures are estimates and are labelled as such.

## Safety

TapeDash is an aid, not a certified instrument. Set it up while parked. It is designed so that nothing needs your attention while you drive, but you remain responsible for driving safely.

## Documents

- [CLAUDE.md](CLAUDE.md): architecture, data, offline guarantees, safety, performance budgets and the roadmap.
- [DESIGN.md](DESIGN.md): the visual, motion and interaction spec.

## Building

Android only. You need the Flutter stable SDK and an Android SDK.

```
flutter pub get
flutter analyze
flutter test
```

## License

Apache License 2.0. See [LICENSE](LICENSE).

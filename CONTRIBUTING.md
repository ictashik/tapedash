# Contributing to TapeDash

Thanks for looking. TapeDash is a small project with strong opinions, written down in two binding documents. Reading them first saves everyone a round trip:

- [CLAUDE.md](CLAUDE.md): architecture, offline guarantees, safety, performance budgets.
- [DESIGN.md](DESIGN.md): look, layout, motion, interaction and copy.

## The most useful thing you can do: a real-car report

Everything is built and tested against a simulator, and the simulator is only as good as the real cars it has met. If you have an ELM327 adapter (WiFi, Bluetooth Classic or BLE) and a car, please try TapeDash and open an issue with:

- the adapter's name and version (`ATI`), and whether it is WiFi, Bluetooth Classic or BLE
- the car (make, model, year, fuel) and the protocol it detected
- which gauges worked and which did not
- the poll rate the debug overlay shows (long-press on a driving screen)
- a session recording, if you are happy to share it (see [docs/HARDWARE_HANDOFF.md](docs/HARDWARE_HANDOFF.md) for how to turn it on)

**Before you share a recording**, open it in a text editor. It is plain text: the commands the app sent and what the adapter replied, plus the app's own notes. It can contain the adapter's Bluetooth address and, if you asked for it, your VIN. Remove anything you don't want public.

## Ground rules

These are not negotiable, because they are what the project is:

1. **Strictly offline.** No network features, telemetry, analytics, price lookups or cloud sync. Suggest them in an issue if you must; they will not be merged. The one socket is the local WiFi ELM327 transport, guarded to private addresses.
2. **No Play Services, no Firebase, no proprietary SDKs.** Any new dependency needs an OSI-approved licence, support for Android 7.0 and 32-bit ARM, and a reason: prefer about 100 lines of your own code. See CLAUDE.md section 5.
3. **Old devices first.** Nothing may need more than the budgets in DESIGN.md section 9.
4. **Nothing needed while driving.** No pop-ups, text entry or small tap targets on driving screens, and the coach never speaks mid-drive.
5. **Simulator first.** A feature is not done until it runs end to end in `flutter test` against the simulator.
6. **No Material look.** Pages are composed only from `lib/ui/design/` components and tokens. The design-lint test fails the build on Material widgets and on raw colours, text styles, durations and spring constants outside `tokens/`.
7. **Honest numbers.** Fuel and money are estimates, labelled as such. Round rupees to whole numbers and km/L to one decimal.

## Setup

See [docs/DEV_SETUP.md](docs/DEV_SETUP.md). In short:

```sh
flutter pub get
tool/verify.sh
```

## Before you open a pull request

`tool/verify.sh` is the gate. It runs a `dart format` check, `flutter analyze`, `flutter test` and `tool/check_offline.sh`. All four must pass. CI runs the same, plus the golden-image tests, which are generated on Linux only. On macOS and Windows `verify.sh` skips them.

- **Fix the estimator or the model, not the tolerance.** If a test against simulator ground truth fails, do not loosen it without discussing it first.
- **Time goes through the injected `Clock`.** Domain code never calls `DateTime.now()` or creates a `Timer`. This is what keeps the simulated drives deterministic and fast.
- **Add a test with every fix.** A transport bug gets a regression test, ideally a replay of a recording.
- **Keep layering.** `sim/`, `obd/`, `vehicle/`, `fuel/`, `money/`, `coach/`, `sound/` and `trips/` are pure Dart with no Flutter imports. `lib/ui` never touches a transport. `test/unit/architecture_test.dart` checks it.
- Don't commit keystores, `key.properties`, or recordings from a car that is not yours.

## Commits

[Conventional Commits](https://www.conventionalcommits.org), kept small, one coherent change each:

```
feat(sim): add city stop-go scenario
fix(elm): handle SEARCHING... prefix
perf(tach): batch segments with drawAtlas
test(golden): update the apex matrix after the livery change
docs: ...
```

Don't mix refactors with features. Commit golden image updates separately, with a one-line reason, so a visual change is easy to review.

## Design changes

If your change alters how something looks or moves, say which section of DESIGN.md it follows, or argue for changing the section. Screenshots in the pull request help a lot. If a design effect breaks a performance budget, use the cheaper technique in DESIGN.md section 9.3 and fall back a fidelity tier before dropping the effect.

## Reporting a security problem

TapeDash holds no accounts and sends nothing anywhere, but it does talk to a car. If you find something that could affect a vehicle's safety, or a way to make the app reach the network, please open a GitHub security advisory on the repository rather than a public issue.

## Licence

By contributing you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), the same as the project.

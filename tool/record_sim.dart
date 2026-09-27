// Records a simulated drive as a session log (CLAUDE.md 10, Recordings): the
// raw ELM327 text between an app and the adapter, with the time of each piece.
//
//   dart run tool/record_sim.dart --scenario city_stop_go --profile petrol_cvt_map
//   dart run tool/record_sim.dart --all
//
// It runs on a fake clock, so a 30-minute drive takes a moment, and what it
// writes is the same every time for the same options.
//
// The traffic is the app's own: the recorder runs the real OBD stack, an
// ObdSession, against the simulated car. It starts the adapter up the way
// CLAUDE.md 8.1 says, asks which PIDs the car has, reads the fault codes once
// connected, and polls in tiers with batching, so a recording shows what the app
// really sends and can be played back into it to catch a change in how it
// reads a reply.
//
//   --scenario <name>   the drive (default city_stop_go)
//   --all               record every scenario, on its own profile
//   --profile <name>    the car (default: the one the scenario is written for)
//   --quirks <name>     none, bluetooth_clone or flaky (default: the scenario's)
//   --seed <n>          the noise (default 1)
//   --minutes <n>       stop after this long, if the drive is still going
//                       (default 40)
//   --out <path>        the file, or with --all the directory
//                       (default recordings/sim)
import 'dart:async';
import 'dart:io';

import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/transport/recording_transport.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/sim/vehicle_profile.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

/// What to record.
class RecordOptions {
  const RecordOptions({
    required this.scenario,
    this.profile,
    this.quirks,
    this.seed = 1,
    this.limit = const Duration(minutes: 40),
  });

  final DriveScenario scenario;

  /// Null for the profile the scenario is written for.
  final VehicleProfile? profile;

  /// Null for the scenario's own quirks.
  final AdapterQuirks? quirks;
  final int seed;

  /// The longest to record, if the drive does not end first.
  final Duration limit;
}

/// Runs [options] to the end of the drive and returns the session log, as text.
String recordSession(RecordOptions options) {
  final clock = FakeClock();
  final car = SimulatedCar(
    scenario: options.scenario,
    profile: options.profile,
    seed: options.seed,
    scheduler: clock,
  )..start();
  final quirks = options.quirks ?? options.scenario.quirks;
  final transport = SimTransport(
    car: car,
    scheduler: clock,
    quirks: quirks,
    seed: options.seed,
  );
  final recorder = RecordingTransport(
    transport,
    clock: clock,
    header: {
      'source': 'TapeDash simulator (tool/record_sim.dart)',
      'scenario': options.scenario.name,
      'profile': car.profile.name,
      'seed': '${options.seed}',
      'quirks': '$quirks',
    },
  );
  final vehicle = VehicleState(clock: clock, scheduler: clock);
  final session = ObdSession(
    transport: recorder,
    scheduler: clock,
    clock: clock,
    vehicle: vehicle,
  );
  // Read the fault codes once, a moment after the first connection, as the
  // Diagnostics page will.
  var codesRead = false;
  session.status.addListener(() {
    if (session.status.value == ConnectionStatus.connected && !codesRead) {
      codesRead = true;
      clock.runAfter(const Duration(seconds: 1), () {
        session.dtc?.read((_) {});
      });
    }
  });
  session.start();

  const step = Duration(seconds: 1);
  while (!car.isFinished && clock.monotonic() < options.limit) {
    clock.advance(step);
  }
  // Let the last answers come in.
  clock.advance(const Duration(seconds: 5));

  session.stop();
  final log = recorder.log.format();
  session.dispose();
  vehicle.dispose();
  car.stop();
  unawaited(recorder.dispose());
  unawaited(transport.dispose());
  return log;
}

Never _fail(String message) {
  stderr.writeln('record_sim: $message');
  exit(64);
}

void _write(String path, String content) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  stdout.writeln(
    'wrote $path (${(content.length / 1024).toStringAsFixed(0)} KB)',
  );
}

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  final flags = <String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) _fail('unexpected argument "$arg"');
    final name = arg.substring(2);
    if (const {'all', 'help'}.contains(name)) {
      flags.add(name);
    } else if (const {
      'scenario',
      'profile',
      'quirks',
      'seed',
      'minutes',
      'out',
    }.contains(name)) {
      if (i + 1 >= args.length) _fail('--$name needs a value');
      options[name] = args[++i];
    } else {
      _fail('unknown option "$arg"');
    }
  }
  if (flags.contains('help')) {
    final header = File(
      Platform.script.toFilePath(),
    ).readAsLinesSync().takeWhile((l) => l.startsWith('//'));
    stdout.writeln(
      header.map((l) => l.replaceFirst(RegExp(r'^// ?'), '')).join('\n'),
    );
    return;
  }

  final profileName = options['profile'];
  final profile = profileName == null
      ? null
      : (VehicleProfiles.byName(profileName) ??
            _fail('no profile "$profileName"'));
  final quirks = options.containsKey('quirks')
      ? (AdapterQuirks.presets[options['quirks']] ??
            _fail('no quirks "${options['quirks']}"'))
      : null;
  final seed = int.tryParse(options['seed'] ?? '1') ?? _fail('bad --seed');
  final minutes =
      int.tryParse(options['minutes'] ?? '40') ?? _fail('bad --minutes');
  final out = options['out'] ?? 'recordings/sim';

  if (flags.contains('all')) {
    for (final scenario in DriveScenarios.all) {
      final log = recordSession(
        RecordOptions(
          scenario: scenario,
          profile: profile,
          quirks: quirks,
          seed: seed,
          limit: Duration(minutes: minutes),
        ),
      );
      _write('$out/${scenario.name}.log', log);
    }
    return;
  }

  final name = options['scenario'] ?? 'city_stop_go';
  final scenario = DriveScenarios.byName(name);
  if (scenario == null) _fail('no scenario "$name"');
  final log = recordSession(
    RecordOptions(
      scenario: scenario,
      profile: profile,
      quirks: quirks,
      seed: seed,
      limit: Duration(minutes: minutes),
    ),
  );
  _write(options.containsKey('out') ? out : '$out/$name.log', log);
}

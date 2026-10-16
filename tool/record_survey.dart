// Makes a survey log from the simulator: what a survey drive writes, for trying
// the summary tool at a desk, and as a sample of the file format.
//
//   dart run tool/record_survey.dart [--profile petrol_cvt_twin_ecu]
//       [--scenario city_stop_go] [--quirks measured_ble] [--minutes 10]
//       [--seed 1] [--out recordings/sim/survey.log]
//
// The default car is the twin-ECU one, two ECUs on 29-bit CAN with the PID sets
// the first real recordings listed, behind an adapter as slow as the one they
// came from. Then:
//
//   dart run tool/survey_summary.dart recordings/sim/survey.log
import 'dart:async';
import 'dart:io';

import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/survey/survey_runner.dart';
import 'package:tapedash/obd/transport/recording_transport.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/sim/vehicle_profile.dart';

/// What to record.
class SurveyRecordOptions {
  const SurveyRecordOptions({
    this.profile = VehicleProfiles.surveyTwin,
    this.scenarioName = 'city_stop_go',
    this.quirks = AdapterQuirks.measuredBle,
    this.seed = 1,
    this.length = const Duration(minutes: 10),
  });

  final VehicleProfile profile;
  final String scenarioName;
  final AdapterQuirks quirks;
  final int seed;
  final Duration length;
}

/// Runs a survey on a simulated car for [SurveyRecordOptions.length] and returns
/// its log, as text.
String recordSurvey(SurveyRecordOptions options) {
  final clock = FakeClock();
  final car = SimulatedCar(
    scenario: DriveScenarios.byName(options.scenarioName)!,
    profile: options.profile,
    seed: options.seed,
    scheduler: clock,
  )..start();
  final transport = SimTransport(
    car: car,
    scheduler: clock,
    quirks: options.quirks,
    seed: options.seed,
  );
  final recorder = RecordingTransport(
    transport,
    clock: clock,
    header: {
      'source': 'TapeDash simulator (tool/record_survey.dart)',
      'survey': '1',
      'scenario': options.scenarioName,
      'profile': car.profile.name,
      'seed': '${options.seed}',
      'quirks': '${options.quirks}',
    },
  );
  final runner = SurveyRunner(
    transport: recorder,
    clock: clock,
    scheduler: clock,
    note: recorder.note,
  )..start();

  const step = Duration(seconds: 1);
  while (!car.isFinished && clock.monotonic() < options.length) {
    clock.advance(step);
  }
  clock.advance(const Duration(seconds: 3));
  runner.finish('end of the recording');
  final log = recorder.log.format();
  runner.dispose();
  car.stop();
  unawaited(recorder.dispose());
  unawaited(transport.dispose());
  return log;
}

Never _fail(String message) {
  stderr.writeln('record_survey: $message');
  exit(64);
}

void main(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help') {
      final header = File(
        Platform.script.toFilePath(),
      ).readAsLinesSync().takeWhile((l) => l.startsWith('//'));
      stdout.writeln(
        header.map((l) => l.replaceFirst(RegExp(r'^// ?'), '')).join('\n'),
      );
      return;
    }
    if (!arg.startsWith('--')) _fail('unexpected argument "$arg"');
    final name = arg.substring(2);
    if (!const {
      'profile',
      'scenario',
      'quirks',
      'minutes',
      'seed',
      'out',
    }.contains(name)) {
      _fail('unknown option "$arg"');
    }
    if (i + 1 >= args.length) _fail('--$name needs a value');
    options[name] = args[++i];
  }
  final profile = options.containsKey('profile')
      ? (VehicleProfiles.byName(options['profile']!) ??
            _fail('no profile "${options['profile']}"'))
      : VehicleProfiles.surveyTwin;
  final scenario = options['scenario'] ?? 'city_stop_go';
  if (DriveScenarios.byName(scenario) == null) {
    _fail('no scenario "$scenario"');
  }
  final quirks = options.containsKey('quirks')
      ? (AdapterQuirks.presets[options['quirks']] ??
            _fail('no quirks "${options['quirks']}"'))
      : AdapterQuirks.measuredBle;
  final minutes =
      int.tryParse(options['minutes'] ?? '10') ?? _fail('bad --minutes');
  final seed = int.tryParse(options['seed'] ?? '1') ?? _fail('bad --seed');
  final out = options['out'] ?? 'recordings/sim/survey.log';

  final log = recordSurvey(
    SurveyRecordOptions(
      profile: profile,
      scenarioName: scenario,
      quirks: quirks,
      seed: seed,
      length: Duration(minutes: minutes),
    ),
  );
  final file = File(out);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(log);
  stdout.writeln('wrote $out (${(log.length / 1024).toStringAsFixed(0)} KB)');
}

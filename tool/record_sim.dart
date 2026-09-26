// Records a simulated drive as a session log (CLAUDE.md 10, Recordings): the
// raw ELM327 text between an app and the adapter, with the time of each piece.
//
//   dart run tool/record_sim.dart --scenario city_stop_go --profile petrol_cvt_map
//   dart run tool/record_sim.dart --all
//
// It runs on a fake clock, so a 30-minute drive takes a moment, and what it
// writes is the same every time for the same options.
//
// The app's own OBD stack does not exist yet, so a small scripted client stands
// in for it: it starts the adapter up the way CLAUDE.md 8.1 says, asks which
// PIDs the car has, reads the fault codes, and then polls the PIDs it has in
// fast, medium and slow tiers, one command at a time. It does not read the answers. Once the app's
// stack is there it can replace this client.
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
import 'package:tapedash/core/scheduler.dart';
import 'package:tapedash/obd/transport/recording_transport.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/sim/vehicle_profile.dart';

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
  final client = ScriptedClient(
    transport: recorder,
    scheduler: clock,
    pids: car.profile.supportedPids,
  )..start();

  const step = Duration(seconds: 1);
  while (!car.isFinished && clock.monotonic() < options.limit) {
    clock.advance(step);
  }
  // Let the last answers come in.
  clock.advance(const Duration(seconds: 5));

  client.stop();
  final log = recorder.log.format();
  car.stop();
  unawaited(recorder.dispose());
  unawaited(transport.dispose());
  return log;
}

/// A stand-in for the app's OBD stack, which is written in a later phase: it
/// starts the adapter up, discovers the PIDs, and polls them, one command at a
/// time, waiting for each prompt. It never reads an answer.
///
/// It reacts to the transport's own streams and to the scheduler, and nothing
/// else, so a whole drive runs inside one `FakeClock.advance`.
class ScriptedClient {
  ScriptedClient({
    required this.transport,
    required this.scheduler,
    required this.pids,
  });

  final Transport transport;
  final Scheduler scheduler;

  /// The PIDs the car answers.
  final Set<int> pids;

  /// The gap between a prompt and the next command.
  static const Duration gap = Duration(milliseconds: 10);

  final StringBuffer _buffer = StringBuffer();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  ScheduledTask? _timeout;
  ScheduledTask? _next;
  ScheduledTask? _reconnect;

  late List<String> _init;
  int _initIndex = 0;
  bool _initialising = true;
  int _attempts = 0;
  int _cycle = 0;
  final List<String> _plan = [];
  bool _stopped = false;

  void start() {
    _subscriptions
      ..add(transport.incoming.listen(_onData))
      ..add(transport.state.listen(_onState));
    _connect();
  }

  void stop() {
    _stopped = true;
    _timeout?.cancel();
    _next?.cancel();
    _reconnect?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  bool _has(int pid) => pids.contains(pid);

  void _connect() {
    if (_stopped) return;
    transport.connect().catchError((Object _) {});
  }

  void _onState(TransportState state) {
    if (state.isConnected) {
      _startUp();
    } else if (state.status == TransportStatus.disconnected) {
      _timeout?.cancel();
      _next?.cancel();
      if (!_stopped && !(_reconnect?.isActive ?? false)) {
        // The way an app would: try again in a few seconds.
        _reconnect = scheduler.runAfter(const Duration(seconds: 3), _connect);
      }
    }
  }

  void _startUp() {
    _buffer.clear();
    _init = [
      'ATZ',
      'ATE0',
      'ATL0',
      'ATS0',
      'ATH0',
      'ATAT1',
      'ATSP0',
      '0100',
      if (pids.any((p) => p > 0x20)) '0120',
      if (pids.any((p) => p > 0x40)) '0140',
      // The stored and pending fault codes, read once at connect.
      '03',
      '07',
    ];
    _initIndex = 0;
    _initialising = true;
    _attempts = 0;
    _send();
  }

  String get _command {
    if (_initialising) return _init[_initIndex];
    if (_plan.isEmpty) _plan.addAll(_planFor(_cycle++));
    return _plan.first;
  }

  /// The commands of one poll cycle. The fast tier is asked every cycle, the
  /// medium every third and the slow every twelfth. The fuel source moves to
  /// the fast tier while a trip records, which this client does not model.
  List<String> _planFor(int cycle) {
    String ask(int pid) =>
        '01${pid.toRadixString(16).toUpperCase().padLeft(2, '0')}1';
    return [
      for (final pid in [0x0C, 0x0D, 0x11])
        if (_has(pid)) ask(pid),
      if (cycle % 3 == 0) ...[
        if (_has(0x04)) ask(0x04),
        if (_has(0x5E))
          ask(0x5E)
        else if (_has(0x10))
          ask(0x10)
        else if (_has(0x0B))
          ask(0x0B),
      ],
      if (cycle % 12 == 0)
        for (final pid in [0x05, 0x0F, 0x2F, 0x42])
          if (_has(pid)) ask(pid),
    ];
  }

  /// How long to wait for a prompt: the reset and the protocol search are slow.
  Duration _timeoutFor(String command) {
    if (command == 'ATZ') return const Duration(seconds: 3);
    if (_initialising && command == '0100') return const Duration(seconds: 10);
    return const Duration(seconds: 2);
  }

  void _send() {
    if (_stopped || !transport.currentState.isConnected) return;
    final command = _command;
    transport.write('$command\r').catchError((Object _) {});
    _timeout?.cancel();
    _timeout = scheduler.runAfter(_timeoutFor(command), _onTimeout);
  }

  void _onData(String text) {
    _buffer.write(text);
    if (_buffer.toString().endsWith('>')) {
      _buffer.clear();
      _timeout?.cancel();
      _advance();
    }
  }

  void _onTimeout() {
    _buffer.clear();
    // Start-up is retried, as CLAUDE.md 8.1 says: at most twice. Polling
    // just moves on.
    if (_initialising && ++_attempts <= 2) {
      _send();
    } else {
      _advance();
    }
  }

  void _advance() {
    _attempts = 0;
    if (_initialising) {
      if (++_initIndex >= _init.length) _initialising = false;
    } else if (_plan.isNotEmpty) {
      _plan.removeAt(0);
    }
    _next = scheduler.runAfter(gap, _send);
  }
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

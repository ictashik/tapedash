// The simulated car and its adapter over TCP (CLAUDE.md 7.5), so that the real
// WiFi transport can be tried without hardware:
//
//   dart run tool/sim_server.dart --port 35000 --profile petrol_cvt_map \
//       --scenario city_stop_go
//
// From an Android emulator the host is 10.0.2.2. It runs in real time, and one
// app at a time is served, as with a real WiFi adapter.
//
//   --port <n>          TCP port (default 35000)
//   --host <address>    interface to listen on (default 127.0.0.1, which is all
//                       an emulator needs; 0.0.0.0 to serve a phone on your
//                       network)
//   --scenario <name>   the drive (default city_stop_go)
//   --profile <name>    the car (default: the one the scenario is written for)
//   --quirks <name>     none, bluetooth_clone or flaky (default: the scenario's)
//   --seed <n>          for repeatable noise (default 1)
//   --no-loop           when the drive ends, stay parked instead of starting over
//   --verbose           print the traffic
//   --list              print the scenarios, profiles and quirks, and stop
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tapedash/core/scheduler.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/ecu.dart';
import 'package:tapedash/sim/elm327_simulator.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';

/// Bytes on the wire are Latin-1: an ELM327 speaks ASCII, and anything else is
/// noise that has to survive the trip.
const Latin1Codec _bytes = Latin1Codec(allowInvalid: true);

/// A car and an adapter, served over TCP to one app at a time.
class SimServer {
  SimServer({
    required this.car,
    required this.adapter,
    this.scheduler = const SystemScheduler(),
    this.host = '127.0.0.1',
    this.port = 35000,
    this.loop = true,
    this.log = _ignore,
    this.showTraffic = false,
  });

  final SimulatedCar car;
  final Elm327Simulator adapter;
  final Scheduler scheduler;
  final String host;
  final int port;

  /// Whether to start the drive again when it ends.
  final bool loop;

  /// Where messages go.
  final void Function(String message) log;
  final bool showTraffic;

  static void _ignore(String message) {}

  ServerSocket? _server;
  ScheduledTask? _looper;
  _Session? _session;

  /// The port actually bound, which differs from [port] when that was 0.
  int get boundPort => _server!.port;

  Future<void> start() async {
    car.start();
    if (loop) {
      _looper = scheduler.runEvery(const Duration(seconds: 1), () {
        if (car.isFinished) {
          log('the drive is over: starting again');
          car.restart();
        }
      });
    }
    final server = await ServerSocket.bind(host, port);
    _server = server;
    server.listen(_accept);
    log(
      '${car.scenario.name} on ${car.profile.name}, '
      'listening on $host:${server.port}',
    );
  }

  void _accept(Socket socket) {
    final peer = '${socket.remoteAddress.address}:${socket.remotePort}';
    final previous = _session;
    if (previous != null) {
      log('$peer takes over from ${previous.peer}');
      previous.close();
    }
    log('$peer connected');
    final session = _Session(this, socket, peer);
    _session = session;
    session.begin();
  }

  Future<void> close() async {
    _looper?.cancel();
    _looper = null;
    await _session?.close();
    await _server?.close();
    _server = null;
    car.stop();
  }
}

/// One connected app.
class _Session {
  _Session(this.server, this.socket, this.peer)
    : transport = SimTransport(
        car: server.car,
        scheduler: server.scheduler,
        adapter: server.adapter,
        connectDelay: Duration.zero,
      );

  final SimServer server;
  final Socket socket;
  final String peer;
  final SimTransport transport;
  bool _closed = false;
  StreamSubscription<List<int>>? _input;

  void begin() {
    transport.incoming.listen((text) {
      if (server.showTraffic) server.log('$peer <- ${SessionLog.escape(text)}');
      if (!_closed) socket.add(_bytes.encode(text));
    });

    _input = socket.listen(
      (data) {
        final text = _bytes.decode(data);
        if (server.showTraffic) {
          server.log('$peer -> ${SessionLog.escape(text)}');
        }
        transport.write(text).catchError((Object _) {});
      },
      onDone: () {
        server.log('$peer disconnected');
        close();
      },
      onError: (Object error) {
        server.log('$peer: $error');
        close();
      },
      cancelOnError: true,
    );
    // An app can start talking the moment it is connected, before the
    // transport is; whatever it sends waits in the socket until the link is up.
    _input?.pause();

    transport.state.listen((state) {
      if (state.isConnected) {
        _input?.resume();
      } else if (state.status == TransportStatus.disconnected) {
        if (state.failure != null) {
          server.log(
            '$peer: the adapter is out of reach (${state.failure!.name})',
          );
        }
        close();
      }
    });
    transport.connect().catchError((Object _) {});
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _input?.cancel();
    await transport.dispose();
    socket.destroy();
    if (identical(server._session, this)) server._session = null;
  }
}

void _printList() {
  stdout
    ..writeln('scenarios:')
    ..writeln(
      DriveScenarios.all
          .map((s) => '  ${s.name.padRight(18)} ${s.description}')
          .join('\n'),
    )
    ..writeln('profiles:')
    ..writeln(
      VehicleProfiles.all
          .map((p) => '  ${p.name.padRight(22)} ${p.description}')
          .join('\n'),
    )
    ..writeln('quirks:')
    ..writeln(
      AdapterQuirks.presets.entries
          .map((e) => '  ${e.key.padRight(16)} ${e.value}')
          .join('\n'),
    );
}

Never _fail(String message) {
  stderr.writeln('sim_server: $message');
  exit(64);
}

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  final flags = <String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) _fail('unexpected argument "$arg"');
    final name = arg.substring(2);
    if (const {'no-loop', 'verbose', 'list', 'help'}.contains(name)) {
      flags.add(name);
    } else if (const {
      'port',
      'host',
      'scenario',
      'profile',
      'quirks',
      'seed',
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
  if (flags.contains('list')) {
    _printList();
    return;
  }

  final scenario = DriveScenarios.byName(options['scenario'] ?? 'city_stop_go');
  if (scenario == null) {
    _fail('no scenario "${options['scenario']}" (see --list)');
  }
  final profile = options.containsKey('profile')
      ? VehicleProfiles.byName(options['profile']!)
      : scenario.profile;
  final quirks = options.containsKey('quirks')
      ? (AdapterQuirks.presets[options['quirks']] ??
            _fail('no quirks "${options['quirks']}" (see --list)'))
      : scenario.quirks;
  final port = int.tryParse(options['port'] ?? '35000') ?? _fail('bad --port');
  final seed = int.tryParse(options['seed'] ?? '1') ?? _fail('bad --seed');

  final car = SimulatedCar(
    scenario: scenario,
    profile: profile,
    seed: seed,
    scheduler: const SystemScheduler(),
  );
  final server = SimServer(
    car: car,
    adapter: Elm327Simulator(
      ecu: SimulatedEcu(car: car),
      quirks: quirks,
      seed: seed,
    ),
    host: options['host'] ?? '127.0.0.1',
    port: port,
    loop: !flags.contains('no-loop'),
    showTraffic: flags.contains('verbose'),
    log: (message) =>
        stdout.writeln('${DateTime.now().toIso8601String()}  $message'),
  );
  await server.start();
  stdout.writeln('quirks: $quirks. Ctrl-C to stop.');

  final stopped = Completer<void>();
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) {
      if (!stopped.isCompleted) stopped.complete();
    });
  }
  await stopped.future;
  await server.close();
}

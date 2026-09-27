// Runs the OBD stack against another implementation of an ELM327 (CLAUDE.md
// 7.5), to see that what it reads is not only what our own simulator prints.
//
// The other implementation is Ircama's ELM327-emulator, which is written in
// Python and is licensed CC BY-NC-SA 4.0. It is only ever run, as a separate
// process: nothing of it is in this repository, and it is not a dependency.
//
//   python3 -m venv /tmp/emu && /tmp/emu/bin/pip install ELM327-emulator
//   sleep 3000 | /tmp/emu/bin/python -m elm -n 35100 -s car &
//   dart run tool/crosscheck_emulator.dart --port 35100
//
// The `sleep` keeps the emulator's input open. It serves TCP on 127.0.0.1 only.
//
// This connects an ObdSession over a plain TCP socket, in real time, for 20
// seconds (--seconds), and prints what it found: the adapter, its protocol and
// PIDs, the polling, and the last value of each sensor. It exits 0 if it
// connected and read RPM and speed, and 1 if not.
//
//   --host <address>   default 127.0.0.1
//   --port <n>         default 35000
//   --seconds <n>      how long to run (default 20)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tapedash/core/clock.dart';
import 'package:tapedash/core/scheduler.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

const Latin1Codec _bytes = Latin1Codec(allowInvalid: true);

/// A [Transport] over a TCP socket, for this tool. It is not the app's WiFi
/// transport, which is phase 6 and has the network guard; this one is for a
/// developer's machine and does no checking of where it connects.
class TcpTransport implements Transport {
  TcpTransport(this.host, this.port);

  final String host;
  final int port;

  Socket? _socket;
  TransportState _current = const TransportState.disconnected();
  final StreamController<String> _incoming =
      StreamController<String>.broadcast();
  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast();

  @override
  TransportState get currentState => _current;

  @override
  Stream<TransportState> get state => _states.stream;

  @override
  Stream<String> get incoming => _incoming.stream;

  void _set(TransportState next) {
    if (next == _current) return;
    _current = next;
    _states.add(next);
  }

  @override
  Future<void> connect() async {
    if (_current.isConnected) return;
    _set(TransportState.connecting);
    try {
      // Kept in [_socket], and destroyed by [disconnect].
      // ignore: close_sinks
      final socket = await Socket.connect(host, port);
      _socket = socket;
      socket.listen(
        (data) => _incoming.add(_bytes.decode(data)),
        onDone: () => _lost(),
        onError: (Object _) => _lost(),
      );
      _set(TransportState.connected);
    } on SocketException catch (e) {
      _set(
        const TransportState.disconnected(
          failure: TransportFailure.unreachable,
        ),
      );
      throw TransportException(TransportFailure.unreachable, e.message);
    }
  }

  void _lost() {
    _socket = null;
    _set(const TransportState.disconnected(failure: TransportFailure.lost));
  }

  @override
  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    socket?.destroy();
    _set(const TransportState.disconnected());
  }

  /// Closes the streams.
  Future<void> close() async {
    await disconnect();
    await _incoming.close();
    await _states.close();
  }

  @override
  Future<void> write(String data) async {
    final socket = _socket;
    if (socket == null) {
      throw const TransportException(TransportFailure.notConnected);
    }
    socket.add(_bytes.encode(data));
  }
}

Never _fail(String message) {
  stderr.writeln('crosscheck_emulator: $message');
  exit(64);
}

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) _fail('unexpected argument "$arg"');
    final name = arg.substring(2);
    if (!const {'host', 'port', 'seconds'}.contains(name)) {
      _fail('unknown option "$arg"');
    }
    if (i + 1 >= args.length) _fail('--$name needs a value');
    options[name] = args[++i];
  }
  final host = options['host'] ?? '127.0.0.1';
  final port = int.tryParse(options['port'] ?? '35000') ?? _fail('bad --port');
  final seconds =
      int.tryParse(options['seconds'] ?? '20') ?? _fail('bad --seconds');

  const scheduler = SystemScheduler();
  const clock = SystemClock();
  final transport = TcpTransport(host, port);
  final vehicle = VehicleState(clock: clock, scheduler: scheduler);
  final session = ObdSession(
    transport: transport,
    scheduler: scheduler,
    clock: clock,
    vehicle: vehicle,
  );
  final started = clock.monotonic();
  String at() =>
      '${(clock.monotonic() - started).inMilliseconds} ms'.padLeft(9);
  session.status.addListener(
    () => stdout.writeln('${at()}  ${session.status.value.name}'),
  );
  session.start();

  await Future<void>.delayed(Duration(seconds: seconds));

  final info = session.adapterInfo.value;
  stdout.writeln('');
  if (info == null) {
    stdout.writeln(
      'The adapter was not started up. Problem: ${session.problem.value}.',
    );
  } else {
    stdout.writeln('Adapter:   ${info.banner}');
    stdout.writeln(
      'Protocol:  ${info.protocolNumber} (CAN: ${info.isCan}), ${info.ecuCount} ECU(s)',
    );
    stdout.writeln(
      'PIDs:      ${(info.supportedPids.toList()..sort()).map((p) => p.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ')}',
    );
    stdout.writeln(
      'Start-up:  ${info.retries} retries${info.warnings.isEmpty ? '' : ', ${info.warnings.join('; ')}'}',
    );
  }
  final poller = session.poller;
  stdout.writeln(
    'Polling:   ${poller == null ? 'not running' : '${session.pollRate.value.toStringAsFixed(1)} Hz, batching ${poller.isBatching}${poller.batchingRefused ? ' (the adapter refused it)' : ''}, ${poller.requestsSent} requests, ${poller.failedRequests} failed'}',
  );
  stdout.writeln(
    'Client:    ${session.client.commandsSent} commands, ${session.client.timeouts} timeouts, '
    '${session.client.garbledReplies} garbled, ${session.client.skippedReplies} skipped',
  );
  stdout.writeln('');
  for (final sensor in Sensor.values) {
    final r = vehicle.reading(sensor).value;
    stdout.writeln(
      '${sensor.name.padRight(18)} ${r == null ? '-' : '${r.value.toStringAsFixed(1)} ${sensor.unit}'}'
      '${r != null && vehicle.isStale(sensor) ? '  (stale)' : ''}',
    );
  }

  final ok =
      session.status.value == ConnectionStatus.connected &&
      vehicle.rpm.value != null &&
      vehicle.speed.value != null;
  session.dispose();
  vehicle.dispose();
  await transport.close();
  exit(ok ? 0 : 1);
}

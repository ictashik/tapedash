// The simulator over a real TCP socket, on real time. Every test that connects
// starts by writing to the socket at once, as an app on a fast link would.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/scheduler.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/ecu.dart';
import 'package:tapedash/sim/elm327_simulator.dart';
import 'package:tapedash/sim/scenario_events.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/simulated_car.dart';

import '../../../tool/sim_server.dart';

DriveScenario _scenario({
  List<AdapterFault> faults = const [],
  Duration? duration,
}) => DriveScenario(
  name: 'test',
  description: 'idles, warm and running',
  route: SimRoute.straight(100),
  adapterFaults: faults,
  duration: duration,
  startCoolantC: 90,
  engineRunningAtStart: true,
  driverBuilder: () => ScriptedDriver([IdleFor(100000)]),
);

/// A socket that collects what it is sent.
class _Client {
  _Client._(this._socket) {
    _socket.listen(
      (data) {
        _received.write(latin1.decode(data));
        _wake();
      },
      onDone: () {
        closed = true;
        _wake();
      },
      onError: (Object _) {
        closed = true;
        _wake();
      },
    );
  }

  static Future<_Client> connect(int port) async =>
      _Client._(await Socket.connect('127.0.0.1', port));

  final Socket _socket;
  final StringBuffer _received = StringBuffer();
  Completer<void>? _waiting;
  bool closed = false;

  void _wake() {
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  void write(String text) => _socket.add(latin1.encode(text));

  /// Everything received since the last [take].
  String take() {
    final text = _received.toString();
    _received.clear();
    return text;
  }

  /// Waits until what has been received satisfies [done], and returns it.
  Future<String> until(
    bool Function(String) done, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!done(_received.toString()) && !closed) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      _waiting = Completer<void>();
      await _waiting!.future.timeout(remaining, onTimeout: () {});
    }
    return take();
  }

  /// Sends a command and waits for its prompt.
  Future<String> send(String command) {
    write('$command\r');
    return until((text) => text.endsWith('>'));
  }

  Future<void> close() async {
    await _socket.close();
    _socket.destroy();
  }
}

class _Rig {
  _Rig({DriveScenario? scenario, bool loop = false}) {
    car = SimulatedCar(
      scenario: scenario ?? _scenario(),
      scheduler: const SystemScheduler(),
    );
    adapter = Elm327Simulator(ecu: SimulatedEcu(car: car));
    server = SimServer(
      car: car,
      adapter: adapter,
      port: 0,
      loop: loop,
      log: messages.add,
    );
  }

  late final SimulatedCar car;
  late final Elm327Simulator adapter;
  late final SimServer server;
  final List<String> messages = [];
  final List<_Client> clients = [];

  Future<_Client> connect() async {
    final client = await _Client.connect(server.boundPort);
    clients.add(client);
    return client;
  }

  Future<void> close() async {
    for (final client in clients) {
      await client.close();
    }
    await server.close();
  }
}

Future<_Rig> _started({DriveScenario? scenario, bool loop = false}) async {
  final rig = _Rig(scenario: scenario, loop: loop);
  await rig.server.start();
  addTearDown(rig.close);
  return rig;
}

void main() {
  test('an app that talks the moment it connects is answered', () async {
    final rig = await _started();
    final client = await rig.connect();

    client.write('ATZ\r');
    final reply = await client.until((t) => t.endsWith('>'));

    expect(reply, 'ATZ\r\r\rELM327 v1.5\r\n\r\n>');
  });

  test('it answers requests about the car', () async {
    final rig = await _started();
    final client = await rig.connect();
    for (final c in ['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6']) {
      await client.send(c);
    }

    final rpm = await client.send('010C1');
    final volts = await client.send('ATRV');

    expect(rpm, matches(RegExp(r'^410C[0-9A-F]{4}\r\r>$')));
    expect(volts, matches(RegExp(r'^1[34]\.\dV\r\r>$')));
  });

  test('a second app takes over, and the adapter keeps its settings', () async {
    final rig = await _started();
    final first = await rig.connect();
    await first.send('ATZ');
    await first.send('ATE0');

    final second = await rig.connect();
    final reply = await second.send('ATI');

    expect(reply, 'ELM327 v1.5\r\n\r\n>', reason: 'echo stayed off');
    await first.until((_) => first.closed, timeout: const Duration(seconds: 2));
    expect(first.closed, isTrue);
    expect(rig.messages.any((m) => m.contains('takes over')), isTrue);
  });

  test('when the app goes, the next one is served', () async {
    final rig = await _started();
    final first = await rig.connect();
    await first.send('ATI');
    await first.close();

    final second = await rig.connect();

    expect(await second.send('ATI'), contains('ELM327 v1.5'));
  });

  test('a link fault in the scenario closes the socket, and the outage refuses '
      'connections', () async {
    final rig = await _started(
      scenario: _scenario(
        faults: const [
          AdapterDisconnect(
            at: Duration(milliseconds: 700),
            outage: Duration(milliseconds: 1200),
          ),
        ],
      ),
    );
    final client = await rig.connect();
    expect(await client.send('ATI'), contains('ELM327'));

    await client.until(
      (_) => client.closed,
      timeout: const Duration(seconds: 3),
    );
    expect(client.closed, isTrue, reason: 'the link dropped');

    // Still out: a new connection is closed at once.
    final during = await rig.connect();
    await during.until(
      (_) => during.closed,
      timeout: const Duration(seconds: 2),
    );
    expect(during.closed, isTrue);
    expect(rig.messages.any((m) => m.contains('out of reach')), isTrue);

    // After the outage it works.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final after = await rig.connect();
    expect(await after.send('ATI'), contains('ELM327'));
  });

  test('with loop, the drive starts over when it ends', () async {
    final rig = await _started(
      scenario: _scenario(duration: const Duration(milliseconds: 1500)),
      loop: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 3200));

    expect(rig.messages.any((m) => m.contains('starting again')), isTrue);
    expect(rig.car.elapsedSeconds, lessThan(3));
  });

  test('without loop, the car stays where the drive ended', () async {
    final rig = await _started(
      scenario: _scenario(duration: const Duration(milliseconds: 500)),
    );

    await Future<void>.delayed(const Duration(milliseconds: 2500));

    expect(rig.messages.any((m) => m.contains('starting again')), isFalse);
    expect(rig.car.isFinished, isTrue);
  });

  test('after close nothing is listening and the car has stopped', () async {
    final rig = await _started();
    final port = rig.server.boundPort;

    await rig.server.close();

    await expectLater(
      Socket.connect('127.0.0.1', port),
      throwsA(isA<SocketException>()),
    );
    expect(rig.car.isRunning, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/elm327/elm327_client.dart';
import 'package:tapedash/obd/elm327/elm327_failure.dart';
import 'package:tapedash/obd/elm327/elm327_parser.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/pids/pid.dart';
import 'package:tapedash/obd/transport/replay_transport.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../../../tool/record_sim.dart';

Duration ms(int n) => Duration(milliseconds: n);

SessionEntry sent(int at, String text) =>
    SessionEntry(ms(at), SessionDirection.sent, text);
SessionEntry got(int at, String text) =>
    SessionEntry(ms(at), SessionDirection.received, text);
SessionEntry event(int at, String text) =>
    SessionEntry(ms(at), SessionDirection.event, text);

/// A replay of [entries] on a fake clock, connected, with what it delivers.
class _Rig {
  _Rig(
    List<SessionEntry> entries, {
    ReplayEnd end = ReplayEnd.loop,
    bool followLinkEvents = false,
    Duration connectDelay = const Duration(milliseconds: 400),
  }) {
    transport = ReplayTransport(
      log: SessionLog(entries: entries),
      scheduler: clock,
      clock: clock,
      end: end,
      followLinkEvents: followLinkEvents,
      connectDelay: connectDelay,
    );
    transport.incoming.listen((t) => received.add((clock.monotonic(), t)));
    transport.state.listen(states.add);
  }

  final clock = FakeClock();
  late final ReplayTransport transport;
  final List<(Duration, String)> received = [];
  final List<TransportState> states = [];

  Future<void> connect() async {
    final connected = transport.connect();
    clock.advance(ms(500));
    await connected;
  }

  void advance(int millis) => clock.advance(ms(millis));

  String get text => received.map((r) => r.$2).join();

  void close() => transport.dispose();
}

void main() {
  group('a command gets its recorded reply', () {
    test('at the recorded offset from the command', () async {
      final rig = _Rig([
        sent(1000, 'ATI\r'),
        got(1040, 'ELM327 v1.5\r\n\r\n>'),
      ]);
      addTearDown(rig.close);
      await rig.connect();
      final t0 = rig.clock.monotonic();

      await rig.transport.write('ATI\r');
      rig.advance(39);
      expect(rig.received, isEmpty);
      rig.advance(1);

      expect(rig.text, 'ELM327 v1.5\r\n\r\n>');
      expect(rig.received.single.$1 - t0, ms(40));
    });

    test('in every piece, each at its own offset', () async {
      final rig = _Rig([
        sent(0, '0100\r'),
        got(5, '0100\r'),
        got(15, 'SEARCHING...\r'),
        got(2400, '41 00 98 3B 80 01 \r'),
        got(2440, '\r>'),
      ]);
      addTearDown(rig.close);
      await rig.connect();
      final t0 = rig.clock.monotonic();

      await rig.transport.write('0100\r');
      rig.advance(3000);

      expect(rig.received.map((r) => (r.$1 - t0).inMilliseconds), [
        5,
        15,
        2400,
        2440,
      ]);
      expect(rig.text, '0100\rSEARCHING...\r41 00 98 3B 80 01 \r\r>');
    });

    test('whatever the case and the spacing of the command', () async {
      final rig = _Rig([sent(0, '010C1\r'), got(20, '41 0C 1A F8 \r\r>')]);
      addTearDown(rig.close);
      await rig.connect();

      await rig.transport.write('01 0c 1\r');
      rig.advance(30);

      expect(rig.text, '41 0C 1A F8 \r\r>');
    });

    test('several commands in one write are each answered', () async {
      final rig = _Rig([
        sent(0, 'ATE0\r'),
        got(10, 'OK\r\r>'),
        sent(100, 'ATL0\r'),
        got(110, 'OK\r\r>'),
      ]);
      addTearDown(rig.close);
      await rig.connect();

      await rig.transport.write('ATE0\rATL0\r');
      rig.advance(50);

      expect(rig.text, 'OK\r\r>OK\r\r>');
    });
  });

  group('the replies to one command, in order', () {
    List<SessionEntry> rpms() => [
      sent(0, '010C1\r'),
      got(20, '410C1AF8\r\r>'),
      sent(100, '010C1\r'),
      got(120, '410C1B00\r\r>'),
      sent(200, '010C1\r'),
      got(220, '410C1B10\r\r>'),
    ];

    test('are given one after the other', () async {
      final rig = _Rig(rpms());
      addTearDown(rig.close);
      await rig.connect();

      for (var i = 0; i < 3; i++) {
        await rig.transport.write('010C1\r');
        rig.advance(50);
      }

      expect(rig.received.map((r) => r.$2), [
        '410C1AF8\r\r>',
        '410C1B00\r\r>',
        '410C1B10\r\r>',
      ]);
    });

    test('and start again at the end, by default', () async {
      final rig = _Rig(rpms());
      addTearDown(rig.close);
      await rig.connect();

      for (var i = 0; i < 5; i++) {
        await rig.transport.write('010C1\r');
        rig.advance(50);
      }

      expect(rig.received.map((r) => r.$2).skip(3), [
        '410C1AF8\r\r>',
        '410C1B00\r\r>',
      ]);
    });

    test('or say ? at the end, if asked', () async {
      final rig = _Rig(rpms(), end: ReplayEnd.unknown);
      addTearDown(rig.close);
      await rig.connect();

      for (var i = 0; i < 4; i++) {
        await rig.transport.write('010C1\r');
        rig.advance(50);
      }

      expect(rig.received.last.$2, '?\r\r>');
      expect(rig.transport.unmatchedCommands, 1);
    });

    test('each command has its own place', () async {
      final rig = _Rig([
        sent(0, '010C1\r'),
        got(20, 'A\r>'),
        sent(50, '010D1\r'),
        got(70, 'B\r>'),
        sent(100, '010C1\r'),
        got(120, 'C\r>'),
      ]);
      addTearDown(rig.close);
      await rig.connect();

      for (final c in ['010D1\r', '010C1\r', '010C1\r']) {
        await rig.transport.write(c);
        rig.advance(50);
      }

      expect(rig.received.map((r) => r.$2), ['B\r>', 'A\r>', 'C\r>']);
    });
  });

  group('a command that was not recorded', () {
    test('gets a ? at once', () async {
      final rig = _Rig([sent(0, 'ATI\r'), got(10, 'ELM327 v1.5\r\r>')]);
      addTearDown(rig.close);
      await rig.connect();

      await rig.transport.write('0100\r');
      rig.advance(10);

      expect(rig.text, '?\r\r>');
      expect(rig.transport.unmatchedCommands, 1);
    });

    test('so a client that batches finds it is not understood', () async {
      final rig = _Rig([sent(0, '010C1\r'), got(20, '410C1AF8\r\r>')]);
      addTearDown(rig.close);
      await rig.connect();
      final client = Elm327Client(
        transport: rig.transport,
        scheduler: rig.clock,
        clock: rig.clock,
      );
      addTearDown(client.dispose);
      Elm327Reply? reply;

      client.request([0x01, 0x0C, 0x0D], (r) => reply = r);
      rig.advance(50);

      expect(reply!.failure, Elm327Failure.unknownCommand);
    });
  });

  group('a command that got no reply in the recording', () {
    test('gets none in the replay: the adapter that lost it is kept', () async {
      final rig = _Rig([
        sent(0, 'ATZ\r'),
        sent(3000, 'ATZ\r'),
        got(3800, '\r\rELM327 v1.5\r\n\r\n>'),
      ]);
      addTearDown(rig.close);
      await rig.connect();

      await rig.transport.write('ATZ\r');
      rig.advance(5000);
      expect(rig.received, isEmpty);
      await rig.transport.write('ATZ\r');
      rig.advance(1000);

      expect(rig.text, '\r\rELM327 v1.5\r\n\r\n>');
    });
  });

  group('the link', () {
    test('connects after the delay, and says so', () async {
      final rig = _Rig([]);
      addTearDown(rig.close);

      final connected = rig.transport.connect();
      expect(rig.transport.currentState, TransportState.connecting);
      rig.advance(399);
      expect(rig.transport.currentState, TransportState.connecting);
      rig.advance(1);
      await connected;

      expect(rig.states, [TransportState.connecting, TransportState.connected]);
    });

    test('writing with no link is an error', () async {
      final rig = _Rig([]);
      addTearDown(rig.close);

      await expectLater(
        rig.transport.write('ATI\r'),
        throwsA(isA<TransportException>()),
      );
    });

    test('nothing arrives after disconnecting', () async {
      final rig = _Rig([sent(0, 'ATI\r'), got(100, 'ELM327 v1.5\r\r>')]);
      addTearDown(rig.close);
      await rig.connect();
      await rig.transport.write('ATI\r');
      rig.advance(50);

      await rig.transport.disconnect();
      rig.advance(500);

      expect(rig.received, isEmpty);
      expect(rig.clock.pendingTasks, 0);
    });

    test('a long replay does not keep every task it ran', () async {
      final entries = <SessionEntry>[
        for (var i = 0; i < 200; i++) ...[
          sent(i * 100, '010C1\r'),
          got(i * 100 + 20, '410C1AF8\r\r>'),
        ],
      ];
      final rig = _Rig(entries);
      addTearDown(rig.close);
      await rig.connect();

      for (var i = 0; i < 200; i++) {
        await rig.transport.write('010C1\r');
        rig.advance(30);
      }

      expect(rig.clock.pendingTasks, 0);
    });
  });

  group('the recording\'s own link drops', () {
    List<SessionEntry> dropping() => [
      event(0, 'connecting'),
      event(400, 'connected'),
      sent(1000, 'ATI\r'),
      got(1010, 'ELM327 v1.5\r\r>'),
      event(10400, 'disconnected (lost)'),
      event(13400, 'connecting'),
      event(13800, 'disconnected (unreachable)'),
      event(16800, 'connecting'),
      event(20400, 'connected'),
    ];

    test(
      'are followed when asked: the link drops when it did, from the first connection',
      () async {
        final rig = _Rig(dropping(), followLinkEvents: true);
        addTearDown(rig.close);
        await rig.connect();
        final connectedAt = rig.clock.monotonic() - ms(100);
        rig.states.clear();

        rig.clock.advance(ms(9400));

        expect(rig.transport.currentState, TransportState.connected);
        rig.clock.advance(ms(600));
        expect(
          rig.transport.currentState,
          const TransportState.disconnected(failure: TransportFailure.lost),
        );
        expect(connectedAt, isNotNull);
      },
    );

    test(
      'and connecting fails until the recording\'s outage is over',
      () async {
        final rig = _Rig(dropping(), followLinkEvents: true);
        addTearDown(rig.close);
        await rig.connect();
        rig.clock.advance(ms(10000));
        expect(rig.transport.currentState.failure, TransportFailure.lost);

        final attempt = rig.transport.connect();
        final outcome = expectLater(
          attempt,
          throwsA(isA<TransportException>()),
        );
        rig.clock.advance(ms(500));
        await outcome;
        expect(
          rig.transport.currentState,
          const TransportState.disconnected(
            failure: TransportFailure.unreachable,
          ),
        );

        rig.clock.advance(ms(12000));
        final again = rig.transport.connect();
        rig.clock.advance(ms(500));
        await again;
        expect(rig.transport.currentState, TransportState.connected);
      },
    );

    test('are ignored by default', () async {
      final rig = _Rig(dropping());
      addTearDown(rig.close);
      await rig.connect();

      rig.clock.advance(const Duration(minutes: 1));

      expect(rig.transport.currentState, TransportState.connected);
    });
  });

  group('a recording of the simulator, played into the session', () {
    String record(String scenario, {AdapterQuirks? quirks, Duration? limit}) =>
        recordSession(
          RecordOptions(
            scenario: DriveScenarios.byName(scenario)!,
            quirks: quirks,
            limit: limit ?? const Duration(minutes: 4),
          ),
        );

    test('the session connects, with the recording\'s PIDs', () {
      final clock = FakeClock();
      final transport = ReplayTransport(
        log: SessionLog.parse(record('city_stop_go')),
        scheduler: clock,
        clock: clock,
      );
      final vehicle = VehicleState(clock: clock, scheduler: clock);
      final session = ObdSession(
        transport: transport,
        scheduler: clock,
        clock: clock,
        vehicle: vehicle,
      )..start();
      addTearDown(() {
        session.dispose();
        vehicle.dispose();
        transport.dispose();
      });

      clock.advance(const Duration(seconds: 30));

      expect(session.status.value, ConnectionStatus.connected);
      expect(session.adapterInfo.value!.supportedPids, {
        0x01,
        0x04,
        0x05,
        0x0B,
        0x0C,
        0x0D,
        0x0F,
        0x10,
        0x11,
        0x2F,
        0x42,
      });
    });

    test('what it reads is what the recording says, in order', () {
      final text = record('city_stop_go');
      final log = SessionLog.parse(text);
      // The RPM in each recorded answer to a request that asked for it,
      // decoded on its own with the same parser the session uses.
      final recorded = <double>[];
      final answer = StringBuffer();
      var asked = false;
      void finish() {
        if (!asked) return;
        asked = false;
        final parsed = Elm327Parser.parse(answer.toString());
        final messages = Elm327Parser.messages(parsed.lines);
        if (messages == null || messages.isEmpty) return;
        final v = Mode01Answer.parse(messages.first)?.valueOf(Pids.rpm);
        if (v != null) recorded.add(v.value);
      }

      for (final e in log.entries) {
        if (e.direction == SessionDirection.sent) {
          finish();
          answer.clear();
          final t = e.text.trim();
          asked = t.startsWith('01') && t.length > 4 && t.contains('0C');
        } else if (e.direction == SessionDirection.received) {
          answer.write(e.text);
        }
      }
      finish();

      final clock = FakeClock();
      final transport = ReplayTransport(
        log: log,
        scheduler: clock,
        clock: clock,
      );
      final vehicle = VehicleState(clock: clock, scheduler: clock);
      final session = ObdSession(
        transport: transport,
        scheduler: clock,
        clock: clock,
        vehicle: vehicle,
      )..start();
      addTearDown(() {
        session.dispose();
        vehicle.dispose();
        transport.dispose();
      });
      // The recorder read the fault codes a second after connecting; so does
      // this, to send the same commands at the same times.
      var codesRead = false;
      session.status.addListener(() {
        if (session.status.value == ConnectionStatus.connected && !codesRead) {
          codesRead = true;
          clock.runAfter(const Duration(seconds: 1), () {
            session.dtc?.read((_) {});
          });
        }
      });
      final read = <double>[];
      vehicle.rpm.addListener(() => read.add(vehicle.rpm.value!.value));

      clock.advance(const Duration(seconds: 60));

      // The session sends the very commands that were recorded, so it gets the
      // recorded answers in the order recorded.
      expect(read.length, greaterThan(500));
      for (var i = 0; i < 500; i++) {
        expect(read[i], recorded[i], reason: 'reading $i');
      }
      expect(transport.unmatchedCommands, 0);
    });

    test(
      'a recording from a clone that loses its first command loses it again',
      () {
        final log = SessionLog.parse(
          record('adapter_flaky', limit: const Duration(seconds: 60)),
        );
        final clock = FakeClock();
        final transport = ReplayTransport(
          log: log,
          scheduler: clock,
          clock: clock,
        );
        final vehicle = VehicleState(clock: clock, scheduler: clock);
        final session = ObdSession(
          transport: transport,
          scheduler: clock,
          clock: clock,
          vehicle: vehicle,
        )..start();
        addTearDown(() {
          session.dispose();
          vehicle.dispose();
          transport.dispose();
        });

        clock.advance(const Duration(seconds: 40));

        // The first ATZ of the recording got no reply, so the session's did not
        // either, and it went on after its retry.
        expect(session.client.timeouts, greaterThanOrEqualTo(1));
        expect(session.status.value, ConnectionStatus.connected);
        expect(session.adapterInfo.value!.retries, greaterThanOrEqualTo(1));
      },
    );
  });
}

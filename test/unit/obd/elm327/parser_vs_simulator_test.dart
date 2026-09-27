// The parser against the simulator's own output, for every setting of echo,
// linefeeds and spaces, and every length of message. The parser's unit tests
// use text written out by hand from the datasheet; this shows that it also
// reads what the simulator prints.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/elm327/elm327_failure.dart';
import 'package:tapedash/obd/elm327/elm327_parser.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/elm327_simulator.dart';

import '../../../support/scripted_ecu.dart';

List<int> _payload(int length) =>
    List.generate(length, (i) => (i * 37 + 11) & 0xFF);

/// An adapter on protocol 6, with the given settings, that answers 0902 with
/// [answer].
Elm327Simulator _adapter(
  List<int>? answer, {
  String settings = '',
  bool awake = true,
  AdapterQuirks quirks = AdapterQuirks.none,
  int seed = 1,
}) {
  final sim = Elm327Simulator(
    ecu: ScriptedEcu({'0902': ?answer}, awake: awake),
    quirks: quirks,
    seed: seed,
  )..execute('ATSP6');
  for (final s in settings.split(' ').where((s) => s.isNotEmpty)) {
    sim.execute('AT$s');
  }
  return sim;
}

void main() {
  const settings = [
    'E1 L1 S1',
    'E1 L1 S0',
    'E1 L0 S1',
    'E1 L0 S0',
    'E0 L1 S1',
    'E0 L1 S0',
    'E0 L0 S1',
    'E0 L0 S0',
  ];

  group('every message, at every setting', () {
    for (final setting in settings) {
      test(setting, () {
        for (final length in [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          13,
          14,
          15,
          20,
          21,
          50,
          200,
        ]) {
          final payload = _payload(length);
          final sim = _adapter(payload, settings: setting);

          final text = sim.execute('0902').text;
          final reply = Elm327Parser.parse(text, sentCommand: '0902');

          expect(reply.failure, isNull, reason: '$setting, $length bytes');
          expect(Elm327Parser.messages(reply.lines), [
            payload,
          ], reason: '$setting, $length bytes');
        }
      });
    }

    test('with SEARCHING... in front', () {
      final sim = Elm327Simulator(ecu: ScriptedEcu({'0902': _payload(20)}))
        ..execute('ATSP0');

      final reply = Elm327Parser.parse(
        sim.execute('0902').text,
        sentCommand: '0902',
      );

      expect(reply.searched, isTrue);
      expect(Elm327Parser.messages(reply.lines), [_payload(20)]);
    });

    test('a long message with the numbering wrapping past F', () {
      final payload = _payload(4000);
      final sim = _adapter(payload, settings: 'E0 L0 S0');

      final reply = Elm327Parser.parse(sim.execute('0902').text);

      expect(Elm327Parser.messages(reply.lines), [payload]);
    });
  });

  group('every error', () {
    Elm327Failure? failureOf(Elm327Simulator sim, String command) =>
        Elm327Parser.parse(
          sim.execute(command).text,
          sentCommand: command,
        ).failure;

    test('NO DATA, for a PID the car does not have', () {
      expect(failureOf(_adapter(null), '0902'), Elm327Failure.noData);
    });

    test('? for a command it does not know', () {
      expect(failureOf(_adapter(null), 'HELLO'), Elm327Failure.unknownCommand);
    });

    test('UNABLE TO CONNECT, searching with the ignition off', () {
      final sim = Elm327Simulator(ecu: ScriptedEcu({}, awake: false))
        ..execute('ATSP0');

      expect(failureOf(sim, '0100'), Elm327Failure.unableToConnect);
    });

    test('CAN ERROR, on a fixed protocol with the ignition off', () {
      expect(
        failureOf(_adapter(null, awake: false), '0100'),
        Elm327Failure.canError,
      );
    });

    test('BUS INIT: ...ERROR, on a K-line protocol', () {
      final sim = Elm327Simulator(ecu: ScriptedEcu({}))..execute('ATSP3');

      expect(failureOf(sim, '0100'), Elm327Failure.busInitError);
    });

    test('an AT command\'s reply is content', () {
      final sim = _adapter(null);

      final reply = Elm327Parser.parse(
        sim.execute('ATRV').text,
        sentCommand: 'ATRV',
      );

      expect(reply.failure, isNull);
      expect(reply.lines.single, matches(RegExp(r'^\d+\.\dV$')));
    });
  });

  group('noise', () {
    test('is never read as a different message', () {
      // With garbage in every reply, what comes out is the right message or
      // nothing at all: never a wrong one.
      var right = 0;
      var refused = 0;
      for (var seed = 1; seed <= 300; seed++) {
        final payload = _payload(seed % 3 == 0 ? 20 : 4);
        final sim = _adapter(
          payload,
          settings: 'E0 L0 S1',
          quirks: const AdapterQuirks(garbageRate: 1),
          seed: seed,
        );

        final reply = Elm327Parser.parse(
          sim.execute('0902').text,
          sentCommand: '0902',
        );
        final messages = Elm327Parser.messages(reply.lines);

        if (reply.failure == null && messages != null) {
          expect(messages, [payload], reason: 'seed $seed');
          right++;
        } else {
          refused++;
        }
      }

      expect(right, greaterThan(0), reason: 'a stray NUL is simply ignored');
      expect(refused, greaterThan(100), reason: 'most noise is caught');
    });

    test('a missing prompt does not change the content', () {
      final payload = _payload(20);
      final sim = _adapter(
        payload,
        settings: 'E0 L0 S1',
        quirks: const AdapterQuirks(missingPromptRate: 1),
      );

      final text = sim.execute('0902').text;

      expect(text.endsWith('>'), isFalse);
      expect(Elm327Parser.messages(Elm327Parser.parse(text).lines), [payload]);
    });
  });
}

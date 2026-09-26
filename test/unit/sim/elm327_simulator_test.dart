import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/ecu.dart';
import 'package:tapedash/sim/elm327_simulator.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';

import '../../support/scripted_ecu.dart';

/// An adapter with a scripted ECU, already on a fixed protocol 6 so that the
/// first request does not search.
Elm327Simulator _adapter({
  ObdEcu? ecu,
  AdapterQuirks quirks = AdapterQuirks.none,
  bool linefeeds = true,
  bool connect = true,
  int seed = 1,
}) {
  final sim = Elm327Simulator(
    ecu: ecu ?? ScriptedEcu(datasheetAnswers),
    quirks: quirks,
    linefeedsByDefault: linefeeds,
    seed: seed,
  );
  if (connect) {
    sim.execute('ATSP6');
    // Opens the session, so later requests are not delayed by it.
    sim.execute('0100');
  }
  return sim;
}

String _text(Elm327Simulator sim, String command) => sim.execute(command).text;

void main() {
  group('golden text: the settings, on a single-frame answer', () {
    // The reply to 010C, 41 0C 1A F8, with echo, linefeeds, spaces and
    // headers each on or off. Written out by hand from the datasheet: the
    // echo of what was typed, then each line ending in CR (or CR LF), then a
    // blank line, then the prompt. A CAN frame with headers on is the ID, the
    // length byte, the data, and zeros up to eight bytes.
    const fixtures = <String, String>{
      'E1 L1 S1 H0': '010C\r41 0C 1A F8 \r\n\r\n>',
      'E1 L1 S0 H0': '010C\r410C1AF8\r\n\r\n>',
      'E1 L0 S1 H0': '010C\r41 0C 1A F8 \r\r>',
      'E1 L0 S0 H0': '010C\r410C1AF8\r\r>',
      'E0 L1 S1 H0': '41 0C 1A F8 \r\n\r\n>',
      'E0 L1 S0 H0': '410C1AF8\r\n\r\n>',
      'E0 L0 S1 H0': '41 0C 1A F8 \r\r>',
      'E0 L0 S0 H0': '410C1AF8\r\r>',
      'E1 L1 S1 H1': '010C\r7E8 04 41 0C 1A F8 00 00 00 \r\n\r\n>',
      'E1 L1 S0 H1': '010C\r7E804410C1AF8000000\r\n\r\n>',
      'E1 L0 S1 H1': '010C\r7E8 04 41 0C 1A F8 00 00 00 \r\r>',
      'E1 L0 S0 H1': '010C\r7E804410C1AF8000000\r\r>',
      'E0 L1 S1 H1': '7E8 04 41 0C 1A F8 00 00 00 \r\n\r\n>',
      'E0 L1 S0 H1': '7E804410C1AF8000000\r\n\r\n>',
      'E0 L0 S1 H1': '7E8 04 41 0C 1A F8 00 00 00 \r\r>',
      'E0 L0 S0 H1': '7E804410C1AF8000000\r\r>',
    };

    for (final entry in fixtures.entries) {
      test(entry.key, () {
        final sim = _adapter();
        for (final setting in entry.key.split(' ')) {
          sim.execute('AT$setting');
        }

        expect(_text(sim, '010C'), entry.value);
      });
    }
  });

  group('golden text: the datasheet\'s own examples', () {
    test('01 00 on a CAN car, spaces on and headers off', () {
      final sim = _adapter();
      sim.execute('ATE0');

      expect(_text(sim, '0100'), '41 00 BE 1F B8 10 \r\n\r\n>');
    });

    test('01 05 is 41 05 7B', () {
      final sim = _adapter();
      sim
        ..execute('ATE0')
        ..execute('ATL0');

      expect(_text(sim, '0105'), '41 05 7B \r\r>');
    });

    test('09 02, the VIN, is 014 / 0: / 1: / 2:', () {
      final sim = _adapter();
      sim
        ..execute('ATE0')
        ..execute('ATL0');

      expect(
        _text(sim, '0902'),
        '014\r'
        '0: 49 02 01 31 44 34 \r'
        '1: 47 50 30 30 52 35 35 \r'
        '2: 42 31 32 33 34 35 36 \r'
        '\r>',
      );
    });

    test('01 04 05 0B 0C is 00A, and the last line is padded with zeros', () {
      final sim = _adapter();
      sim
        ..execute('ATE0')
        ..execute('ATL0');

      expect(
        _text(sim, '01 04 05 0B 0C'),
        '00A\r'
        '0: 41 04 3F 05 44 0B \r'
        '1: 21 0C 17 B8 00 00 00 \r'
        '\r>',
      );
    });

    test('the same PIDs in another order come back in that order', () {
      final sim = _adapter();
      sim
        ..execute('ATE0')
        ..execute('ATL0');

      expect(
        _text(sim, '01 0B 04 0C 05'),
        '00A\r'
        '0: 41 0B 21 04 3F 0C \r'
        '1: 17 B8 05 44 00 00 00 \r'
        '\r>',
      );
    });

    test('a request typed with spaces and lower case is echoed as typed', () {
      final sim = _adapter();
      sim.execute('ATL0');

      expect(_text(sim, '01 0c'), '01 0c\r41 0C 1A F8 \r\r>');
    });
  });

  group(
    'golden text: multi-frame answers with each spaces and headers setting',
    () {
      // The VIN: 20 bytes. With headers off the adapter prints its length and
      // numbered lines. With headers on it prints the CAN frames themselves: a
      // first frame (10 14, then six bytes) and consecutive frames (21, 22, then
      // seven bytes each).
      const fixtures = <String, List<String>>{
        'S1 H0': [
          '014',
          '0: 49 02 01 31 44 34 ',
          '1: 47 50 30 30 52 35 35 ',
          '2: 42 31 32 33 34 35 36 ',
        ],
        'S0 H0': [
          '014',
          '0:490201314434',
          '1:47503030523535',
          '2:42313233343536',
        ],
        'S1 H1': [
          '7E8 10 14 49 02 01 31 44 34 ',
          '7E8 21 47 50 30 30 52 35 35 ',
          '7E8 22 42 31 32 33 34 35 36 ',
        ],
        'S0 H1': [
          '7E81014490201314434',
          '7E82147503030523535',
          '7E82242313233343536',
        ],
      };

      for (final entry in fixtures.entries) {
        test(entry.key, () {
          final sim = _adapter();
          sim.execute('ATE0');
          for (final setting in entry.key.split(' ')) {
            sim.execute('AT$setting');
          }

          expect(
            _text(sim, '0902'),
            '${entry.value.map((l) => '$l\r\n').join()}\r\n>',
          );
        });
      }

      test('a message of eight bytes needs two frames: 008 / 0: / 1:', () {
        final sim = _adapter();
        sim
          ..execute('ATE0')
          ..execute('ATL0');

        // 43 03 04 20 01 71 | 03 00, the second line padded.
        expect(
          _text(sim, '03'),
          '008\r'
          '0: 43 03 04 20 01 71 \r'
          '1: 03 00 00 00 00 00 00 \r'
          '\r>',
        );
      });

      test(
        'with headers on, the sequence digit counts 1 to F and starts again',
        () {
          // 200 bytes: a first frame of 6, then 28 consecutive frames of 7 (the
          // last one short). The digits of the consecutive frames run 1 to F, then
          // 0, 1 and on.
          final ecu = ScriptedEcu({
            '0902': [0x49, ...List<int>.generate(199, (i) => i & 0xFF)],
          });
          final sim = _adapter(ecu: ecu, connect: false)
            ..execute('ATSP6')
            ..execute('ATE0')
            ..execute('ATL0')
            ..execute('ATH1');

          final lines = _text(
            sim,
            '0902',
          ).split('\r').where((l) => l.startsWith('7E8')).toList();
          // The digit of "7E8 2n" is the sixth character.
          final digits = lines.map((l) => l[5]).toList();

          expect(lines.first, startsWith('7E8 10 C8 49 '));
          expect(digits.skip(1).take(16).join(), '123456789ABCDEF0');
          expect(digits[17], '1');
          expect(lines.length, 1 + (200 - 6 + 6) ~/ 7);
        },
      );
    },
  );

  group('golden text: AT commands', () {
    test('a setting is answered OK, and the echo is of what was typed', () {
      final sim = _adapter(connect: false);

      expect(_text(sim, 'ATE0'), 'ATE0\rOK\r\n\r\n>');
      expect(_text(sim, 'ATL0'), 'OK\r\r>');
      expect(_text(sim, 'ATS0'), 'OK\r\r>');
      expect(_text(sim, 'ATH0'), 'OK\r\r>');
    });

    test('ATE1 turns echo back on, but is not itself echoed', () {
      final sim = _adapter(connect: false)..execute('ATE0');

      expect(_text(sim, 'ATE1'), 'OK\r\n\r\n>');
      expect(_text(sim, 'ATI'), 'ATI\rELM327 v1.5\r\n\r\n>');
    });

    test('ATL1 changes the very reply that says OK to it', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0');

      expect(_text(sim, 'ATL1'), 'OK\r\n\r\n>');
    });

    test('commands ignore case and spaces', () {
      final sim = _adapter(connect: false);

      expect(_text(sim, 'at e0'), 'at e0\rOK\r\n\r\n>');
      expect(_text(sim, 'A T L 0'), 'OK\r\r>');
    });

    test('ATI is the version and AT@1 the description', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0');

      expect(_text(sim, 'ATI'), 'ELM327 v1.5\r\r>');
      expect(_text(sim, 'AT@1'), 'OBDII to RS232 Interpreter\r\r>');
    });

    test('the version can be configured', () {
      final sim = Elm327Simulator(
        ecu: ScriptedEcu(datasheetAnswers),
        version: 'ELM327 v2.1',
      )..execute('ATE0');

      expect(_text(sim, 'ATI'), 'ELM327 v2.1\r\n\r\n>');
    });

    test('ATRV rounds to one decimal place, as the datasheet says', () {
      final ecu = ScriptedEcu(datasheetAnswers, volts: 12.47);
      final sim = _adapter(ecu: ecu, connect: false)
        ..execute('ATE0')
        ..execute('ATL0');

      expect(_text(sim, 'ATRV'), '12.5V\r\r>');

      ecu.volts = 14.1;
      expect(_text(sim, 'ATRV'), '14.1V\r\r>');
    });

    test('ATRV works with the ignition off: the battery is still there', () {
      final ecu = ScriptedEcu(datasheetAnswers, awake: false, volts: 12.4);
      final sim = _adapter(ecu: ecu, connect: false)
        ..execute('ATE0')
        ..execute('ATL0');

      expect(_text(sim, 'ATRV'), '12.4V\r\r>');
    });

    test('ATZ resets, and prints two carriage returns and the banner', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0')
        ..execute('ATS0');

      final reply = sim.execute('ATZ');

      // Echo was off when ATZ arrived, so ATZ itself is not echoed; the banner
      // is printed with the defaults that the reset has just put back.
      expect(reply.text, '\r\rELM327 v1.5\r\n\r\n>');
      // Afterwards echo, linefeeds and spaces are all back on.
      expect(
        _text(sim, '0100'),
        '0100\rSEARCHING...\r\n41 00 BE 1F B8 10 \r\n\r\n>',
      );
    });

    test(
      'ATZ with echo on echoes itself first, then the banner comes later',
      () {
        final sim = _adapter(connect: false);

        final reply = sim.execute('ATZ');

        expect(reply.chunks.length, 2);
        expect(reply.chunks[0].text, 'ATZ\r');
        expect(reply.chunks[0].after, Duration.zero);
        expect(reply.chunks[1].text, '\r\rELM327 v1.5\r\n\r\n>');
        expect(reply.chunks[1].after, const Duration(milliseconds: 800));
      },
    );

    test('ATWS is a quicker reset with the same banner', () {
      final sim = _adapter(connect: false);

      final reply = sim.execute('ATWS');

      expect(reply.chunks.last.text, '\r\rELM327 v1.5\r\n\r\n>');
      expect(reply.chunks.last.after, const Duration(milliseconds: 250));
    });

    test('an adapter that has linefeeds off by default says so after ATZ', () {
      final sim = _adapter(connect: false, linefeeds: false);

      expect(sim.execute('ATZ').chunks.last.text, '\r\rELM327 v1.5\r\r>');
      expect(_text(sim, 'ATI'), 'ATI\rELM327 v1.5\r\r>');
    });

    test('ATD puts the settings back but does not say who it is', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0')
        ..execute('ATS0')
        ..execute('ATH1');

      // Linefeeds are back on by the time it says OK.
      expect(_text(sim, 'ATD'), 'OK\r\n\r\n>');
      expect(_text(sim, 'ATI'), 'ATI\rELM327 v1.5\r\n\r\n>');
    });

    test('anything it does not know is ?', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0');

      for (final command in [
        'ATXYZ',
        'AT',
        'ATE2',
        'ATL',
        'HELLO',
        '01G0',
        'ATSP',
        'ATSPD',
        'ATSPZ',
        'ATST',
        'ATSTZZ',
        'ATSTABC',
        'ATSH',
        'ATSH12',
        'ATSHG12',
        'ATAT3',
      ]) {
        expect(_text(sim, command), '?\r\r>', reason: command);
      }
    });

    test('a lone carriage return repeats the last command', () {
      final sim = _adapter();
      sim
        ..execute('ATE0')
        ..execute('ATL0');
      expect(_text(sim, '010C'), '41 0C 1A F8 \r\r>');

      expect(_text(sim, ''), '41 0C 1A F8 \r\r>');
      expect(_text(sim, ''), '41 0C 1A F8 \r\r>');
    });

    test('a repeated command is echoed as the carriage return that asked', () {
      final sim = _adapter();
      sim.execute('ATL0');
      sim.execute('010C');

      expect(_text(sim, ''), '\r41 0C 1A F8 \r\r>');
    });

    test('a lone carriage return with nothing to repeat is just a prompt', () {
      final sim = Elm327Simulator(ecu: ScriptedEcu(datasheetAnswers));

      // Echo is on, so the carriage return comes back, and then the prompt.
      expect(_text(sim, ''), '\r>');
    });
  });

  group('protocols', () {
    test('a fresh adapter is on automatic, with nothing found yet', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0');

      expect(_text(sim, 'ATDPN'), 'A0\r\r>');
      expect(_text(sim, 'ATDP'), 'AUTO\r\r>');
    });

    test('ATSP6 selects protocol 6 on its own', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0');

      expect(_text(sim, 'ATSP6'), 'OK\r\r>');
      expect(_text(sim, 'ATDPN'), '6\r\r>');
      expect(_text(sim, 'ATDP'), 'ISO 15765-4 (CAN 11/500)\r\r>');
    });

    test('ATSPA6 and ATSP6A both mean: try 6, then search', () {
      for (final command in ['ATSPA6', 'ATSP6A', 'ATSP A6']) {
        final sim = _adapter(connect: false)
          ..execute('ATE0')
          ..execute('ATL0')
          ..execute(command);

        expect(_text(sim, 'ATDPN'), 'A6\r\r>', reason: command);
        expect(
          _text(sim, 'ATDP'),
          'AUTO, ISO 15765-4 (CAN 11/500)\r\r>',
          reason: command,
        );
      }
    });

    test('the letters A to C are protocols too', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0')
        ..execute('ATSPC');

      expect(_text(sim, 'ATDPN'), 'C\r\r>');
    });

    test('every protocol has a name', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0');

      for (var n = 1; n <= 12; n++) {
        sim.execute('ATSP${n.toRadixString(16)}');
        final reply = _text(sim, 'ATDP');
        expect(reply, '${Elm327Simulator.protocolNames[n]}\r\r>');
      }
    });

    test('ATSP0 goes back to searching', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0')
        ..execute('ATSP6')
        ..execute('ATSP0');

      expect(_text(sim, 'ATDPN'), 'A0\r\r>');
    });

    test('the first request after ATSP0 searches, and finds 6', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0')
        ..execute('ATSP0');

      final reply = sim.execute('0100');

      expect(
        reply.text,
        'SEARCHING...\r'
        '41 00 BE 1F B8 10 \r'
        '\r>',
      );
      expect(sim.isConnected, isTrue);
      expect(_text(sim, 'ATDPN'), 'A6\r\r>');
    });

    test('SEARCHING... is printed at once, and the answer takes seconds', () {
      final sim = _adapter(connect: false)..execute('ATSP0');

      final reply = sim.execute('0100');

      expect(reply.chunks[0].text, '0100\rSEARCHING...\r\n');
      expect(reply.chunks[0].after, Duration.zero);
      expect(reply.chunks[1].text, '41 00 BE 1F B8 10 \r\n');
      expect(reply.chunks[1].after, const Duration(milliseconds: 2420));
    });

    test('only the first request searches', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0')
        ..execute('ATSP0')
        ..execute('0100');

      expect(_text(sim, '010C'), '41 0C 1A F8 \r\r>');
    });

    test('changing the protocol closes the session, so it searches again', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0')
        ..execute('ATSP0')
        ..execute('0100');
      expect(sim.isConnected, isTrue);

      sim.execute('ATSP0');

      expect(sim.isConnected, isFalse);
      expect(_text(sim, '010C'), startsWith('SEARCHING...'));
    });

    test('a fixed protocol 6 connects without searching', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0')
        ..execute('ATSP6');

      final reply = sim.execute('0100');

      expect(reply.text, '41 00 BE 1F B8 10 \r\r>');
      expect(reply.chunks.first.after, const Duration(milliseconds: 20));
    });

    test('ATZ forgets the session, and remembers the protocol', () {
      final sim = _adapter(connect: false)
        ..execute('ATE0')
        ..execute('ATL0')
        ..execute('ATSP6')
        ..execute('0100');
      expect(sim.isConnected, isTrue);

      sim.execute('ATZ');

      expect(sim.isConnected, isFalse);
      // ATZ put echo and linefeeds back.
      expect(_text(sim, 'ATDPN'), 'ATDPN\r6\r\n\r\n>');
    });

    test('ATSP0 does not overwrite the stored protocol, ATSP00 erases it', () {
      final sim = _adapter(connect: false)
        ..execute('ATSP6')
        ..execute('ATSP0')
        ..execute('ATZ');
      expect(_text(sim, 'ATDPN'), 'ATDPN\r6\r\n\r\n>');

      sim
        ..execute('ATSP00')
        ..execute('ATZ');
      expect(_text(sim, 'ATDPN'), 'ATDPN\rA0\r\n\r\n>');
    });

    test('a protocol found by searching is remembered when memory is on', () {
      final sim = _adapter(connect: false)
        ..execute('ATSP0')
        ..execute('0100')
        ..execute('ATZ');

      expect(_text(sim, 'ATDPN'), 'ATDPN\rA6\r\n\r\n>');
      // Trying 6 first, the search is quick.
      final reply = sim.execute('0100');
      expect(
        reply.chunks.any((c) => c.after == const Duration(milliseconds: 420)),
        isTrue,
      );
    });

    test('with memory off it is not remembered', () {
      final sim = _adapter(connect: false)
        ..execute('ATM0')
        ..execute('ATSP0')
        ..execute('0100')
        ..execute('ATZ')
        ..execute('ATM0');

      expect(_text(sim, 'ATDPN'), 'ATDPN\rA0\r\n\r\n>');
    });

    test('ATTP tries a protocol without storing it', () {
      final sim = _adapter(connect: false)
        ..execute('ATTP6')
        ..execute('ATZ');

      expect(_text(sim, 'ATDPN'), 'ATDPN\rA0\r\n\r\n>');
    });
  });

  group('when the car cannot be reached', () {
    Elm327Simulator asleep(String protocol) {
      final sim =
          _adapter(
              ecu: ScriptedEcu(datasheetAnswers, awake: false),
              connect: false,
            )
            ..execute('ATE0')
            ..execute('ATL0')
            ..execute(protocol);
      return sim;
    }

    test('ignition off, searching: SEARCHING... then UNABLE TO CONNECT', () {
      final sim = asleep('ATSP0');

      final reply = sim.execute('0100');

      expect(reply.text, 'SEARCHING...\rUNABLE TO CONNECT\r\r>');
      expect(reply.duration, const Duration(seconds: 5));
      expect(sim.isConnected, isFalse);
    });

    test('it searches again on the next request', () {
      final sim = asleep('ATSP0')..execute('0100');

      expect(_text(sim, '0100'), startsWith('SEARCHING...'));
    });

    test('ignition off, protocol 6 fixed: CAN ERROR', () {
      final sim = asleep('ATSP6');

      expect(_text(sim, '0100'), 'CAN ERROR\r\r>');
    });

    test('a K-line protocol on a CAN car: BUS INIT: ...ERROR', () {
      final ecu = ScriptedEcu(datasheetAnswers);
      for (final protocol in ['ATSP3', 'ATSP4', 'ATSP5']) {
        final sim = _adapter(ecu: ecu, connect: false)
          ..execute('ATE0')
          ..execute('ATL0')
          ..execute(protocol);

        expect(_text(sim, '0100'), 'BUS INIT: ...ERROR\r\r>', reason: protocol);
      }
      expect(ecu.requests, isEmpty, reason: 'nothing was sent on the bus');
    });

    test('J1850 and 29-bit CAN on a CAN car: NO DATA', () {
      for (final protocol in ['ATSP1', 'ATSP2', 'ATSP7']) {
        final sim = _adapter(connect: false)
          ..execute('ATE0')
          ..execute('ATL0')
          ..execute(protocol);

        expect(_text(sim, '0100'), 'NO DATA\r\r>', reason: protocol);
      }
    });

    test('CAN at another bit rate: CAN ERROR', () {
      for (final protocol in ['ATSP8', 'ATSP9', 'ATSPA', 'ATSPB', 'ATSPC']) {
        final sim = _adapter(connect: false)
          ..execute('ATE0')
          ..execute('ATL0')
          ..execute(protocol);

        expect(_text(sim, '0100'), 'CAN ERROR\r\r>', reason: protocol);
      }
    });

    test('a connected adapter whose ECU falls asleep says NO DATA', () {
      final ecu = ScriptedEcu(datasheetAnswers);
      final sim = _adapter(ecu: ecu)
        ..execute('ATE0')
        ..execute('ATL0');
      expect(_text(sim, '010C'), '41 0C 1A F8 \r\r>');

      ecu.awake = false;

      expect(_text(sim, '010C'), 'NO DATA\r\r>');
      expect(sim.isConnected, isTrue);

      ecu.awake = true;

      expect(_text(sim, '010C'), '41 0C 1A F8 \r\r>');
    });
  });

  group('requests and their answers', () {
    Elm327Simulator ready() => _adapter()
      ..execute('ATE0')
      ..execute('ATL0');

    test('a PID the ECU does not answer is NO DATA', () {
      expect(_text(ready(), '0111'), 'NO DATA\r\r>');
    });

    test('a request for a mode with nothing is NO DATA', () {
      expect(_text(ready(), '0A'), 'NO DATA\r\r>');
    });

    test('hex that is not a request is ?', () {
      final sim = ready();

      // An odd digit count is a request and a response count, so 010 is 01
      // asking for no responses; that is a request the ECU has no answer to.
      expect(_text(sim, '0G'), '?\r\r>');
      expect(_text(sim, '0 1 0 C'), '41 0C 1A F8 \r\r>');
    });

    test(
      'a request of more than seven bytes is ? unless long messages are on',
      () {
        final sim = ready();
        const eight = '0102030405060708';

        expect(_text(sim, eight), '?\r\r>');

        sim.execute('ATAL');
        expect(_text(sim, eight), 'NO DATA\r\r>');

        sim.execute('ATNL');
        expect(_text(sim, eight), '?\r\r>');
      },
    );

    test(
      'the ECU is sent the bytes of the request, without the count digit',
      () {
        final ecu = ScriptedEcu(datasheetAnswers);
        final sim = _adapter(ecu: ecu)..execute('ATE0');
        ecu.requests.clear();

        sim.execute('010C1');

        expect(ecu.requests, [
          [0x01, 0x0C],
        ]);
      },
    );

    test('a request to another ECU address gets no answer', () {
      final ecu = ScriptedEcu(datasheetAnswers);
      final sim = _adapter(ecu: ecu)
        ..execute('ATE0')
        ..execute('ATL0');

      expect(_text(sim, 'ATSH7E5'), 'OK\r\r>');
      expect(_text(sim, '010C'), 'NO DATA\r\r>');
      expect(_text(sim, 'ATSH7E0'), 'OK\r\r>');
      expect(_text(sim, '010C'), '41 0C 1A F8 \r\r>');
      expect(_text(sim, 'ATSH7DF'), 'OK\r\r>');
      expect(_text(sim, '010C'), '41 0C 1A F8 \r\r>');
    });

    test('headers of three, six and eight digits are accepted', () {
      final sim = ready();

      expect(_text(sim, 'ATSH7E0'), 'OK\r\r>');
      expect(_text(sim, 'ATSH 24 F1 10'), 'OK\r\r>');
      expect(_text(sim, 'ATSH 18DB33F1'), 'OK\r\r>');
    });

    test('a negative response is passed on like any other answer', () {
      final ecu = ScriptedEcu({
        '04': [0x7F, 0x04, 0x22],
      });
      final sim = _adapter(ecu: ecu)
        ..execute('ATE0')
        ..execute('ATL0');

      expect(_text(sim, '04'), '7F 04 22 \r\r>');
    });
  });

  group('timing', () {
    Duration ofMs(int ms) => Duration(milliseconds: ms);

    List<int> at(Elm327Reply reply) =>
        reply.chunks.map((c) => c.after.inMilliseconds).toList();

    Elm327Simulator ready({AdapterQuirks quirks = AdapterQuirks.none}) =>
        _adapter(quirks: quirks)..execute('ATE0');

    test('an AT command is answered at once', () {
      final sim = ready();

      expect(sim.execute('ATL1').duration, Duration.zero);
    });

    test('an answer comes 20 ms after the request, and adaptive timing waits '
        '40 ms more', () {
      final reply = ready().execute('010C');

      expect(reply.chunks.length, 2);
      expect(reply.chunks[0].after, ofMs(20));
      expect(reply.chunks[1].after, ofMs(60));
      expect(reply.chunks[1].text, '\r\n>');
    });

    test('ATAT2 waits less', () {
      final sim = ready()..execute('ATAT2');

      expect(at(sim.execute('010C')), [20, 45]);
    });

    test('a count digit of 1 ends it as soon as the answer is in', () {
      final reply = ready().execute('010C1');

      expect(at(reply), [20]);
      expect(reply.text, '41 0C 1A F8 \r\n\r\n>');
    });

    test('a count digit of 2 waits for an ECU that never answers', () {
      final reply = ready().execute('010C2');

      // The whole timeout, ATST 32 hex x 4 ms = 200 ms.
      expect(at(reply), [20, 220]);
    });

    test('with adaptive timing off it waits the whole timeout', () {
      final sim = ready()..execute('ATAT0');

      expect(at(sim.execute('010C')), [20, 220]);
    });

    test('a clone that ignores adaptive timing waits the whole timeout', () {
      final sim = ready(
        quirks: const AdapterQuirks(ignoreAdaptiveTiming: true),
      );

      expect(at(sim.execute('010C')), [20, 220]);
    });

    test('...unless the request says how many answers to expect', () {
      final sim = ready(
        quirks: const AdapterQuirks(ignoreAdaptiveTiming: true),
      );

      expect(at(sim.execute('010C1')), [20]);
    });

    test('ATST sets the timeout in units of 4 ms', () {
      final sim = ready()
        ..execute('ATAT0')
        ..execute('ATST19');

      // 0x19 is 25, so 100 ms.
      expect(at(sim.execute('010C')), [20, 120]);
    });

    test('ATST 00 puts the default back', () {
      final sim = ready()
        ..execute('ATAT0')
        ..execute('ATSTFF')
        ..execute('ATST00');

      expect(at(sim.execute('010C')), [20, 220]);
    });

    test('NO DATA arrives after the whole timeout, digit or not', () {
      final sim = ready();

      expect(at(sim.execute('0111')), [200]);
      expect(at(sim.execute('01111')), [200]);
    });

    test('a long answer takes a little longer: 2 ms for each extra frame', () {
      final sim = ready();

      // The VIN is three frames.
      expect(at(sim.execute('0902')), [24, 64]);
    });

    test('the echo is not delayed, and the answer is a piece of its own', () {
      final sim = _adapter()..execute('ATL0');

      final reply = sim.execute('010C');

      expect(reply.chunks[0].text, '010C\r');
      expect(reply.chunks[0].after, Duration.zero);
      expect(reply.chunks[1].text, '41 0C 1A F8 \r');
      expect(reply.chunks[1].after, ofMs(20));
      expect(reply.chunks[2].text, '\r>');
    });
  });

  group('quirks', () {
    test('noMultiPid: several PIDs at once are not understood', () {
      final ecu = ScriptedEcu(datasheetAnswers);
      final sim =
          _adapter(ecu: ecu, quirks: const AdapterQuirks(noMultiPid: true))
            ..execute('ATE0')
            ..execute('ATL0');
      ecu.requests.clear();

      expect(_text(sim, '010C0D'), '?\r\r>');
      expect(ecu.requests, isEmpty);
      // One PID is fine, and so is another mode.
      expect(_text(sim, '010C'), '41 0C 1A F8 \r\r>');
      expect(_text(sim, '03'), startsWith('008'));
    });

    test('noDataRate 1: every answer is NO DATA', () {
      final sim = _adapter(quirks: const AdapterQuirks(noDataRate: 1))
        ..execute('ATE0')
        ..execute('ATL0');

      for (var i = 0; i < 5; i++) {
        expect(_text(sim, '010C'), 'NO DATA\r\r>');
      }
    });

    test('noDataRate 0: none is', () {
      final sim = _adapter()
        ..execute('ATE0')
        ..execute('ATL0');

      for (var i = 0; i < 200; i++) {
        expect(_text(sim, '010C'), '41 0C 1A F8 \r\r>');
      }
    });

    test('noDataRate 0.25: about a quarter, decided by the seed', () {
      final sim = _adapter(quirks: const AdapterQuirks(noDataRate: 0.25))
        ..execute('ATE0')
        ..execute('ATL0');
      var noData = 0;
      for (var i = 0; i < 2000; i++) {
        if (_text(sim, '010C').startsWith('NO DATA')) noData++;
      }

      expect(noData, inInclusiveRange(400, 600));
    });

    test('the same seed gives the same faults, another gives others', () {
      String run(int seed) {
        final sim = _adapter(quirks: AdapterQuirks.flaky, seed: seed)
          ..execute('ATE0')
          ..execute('ATL0');
        final out = StringBuffer();
        for (var i = 0; i < 500; i++) {
          out.write(_text(sim, '010C'));
        }
        return out.toString();
      }

      expect(run(4), run(4));
      expect(run(4), isNot(run(5)));
    });

    test('missingPromptRate 1: the answer ends without its >', () {
      final sim = _adapter(quirks: const AdapterQuirks(missingPromptRate: 1))
        ..execute('ATE0')
        ..execute('ATL0');

      final text = _text(sim, '010C');

      expect(text, '41 0C 1A F8 \r\r');
    });

    test('missingPromptRate applies to AT commands too', () {
      final sim = _adapter(
        quirks: const AdapterQuirks(missingPromptRate: 1),
        connect: false,
      );

      expect(_text(sim, 'ATE0'), 'ATE0\rOK\r\n\r\n');
    });

    test('garbageRate 1: stray bytes in the answer, and the rest intact', () {
      final sim = _adapter(quirks: const AdapterQuirks(garbageRate: 1))
        ..execute('ATE0')
        ..execute('ATL0');
      const clean = '41 0C 1A F8 \r\r>';
      const stray = [0x00, 0x1B, 0x7F, 0x80, 0xA0, 0xFF];

      for (var i = 0; i < 50; i++) {
        final text = _text(sim, '010C');
        final without = String.fromCharCodes(
          text.codeUnits.where((c) => !stray.contains(c)),
        );

        expect(text.length, greaterThan(clean.length));
        expect(text.length, lessThanOrEqualTo(clean.length + 3));
        expect(without, clean);
      }
    });

    test('garbage is in the answer, never in the echo', () {
      const stray = [0x00, 0x1B, 0x7F, 0x80, 0xA0, 0xFF];
      bool hasStray(String s) => s.codeUnits.any(stray.contains);

      for (var seed = 1; seed <= 30; seed++) {
        // A delayed answer: the echo is a piece of its own, and is clean.
        final delayed = _adapter(
          quirks: const AdapterQuirks(garbageRate: 1),
          seed: seed,
        ).execute('010C');
        expect(delayed.chunks[0].text, '010C\r', reason: 'seed $seed');
        expect(hasStray(delayed.chunks[1].text), isTrue, reason: 'seed $seed');

        // An instant answer is one piece with the echo at the front of it.
        final instant = _adapter(
          quirks: const AdapterQuirks(garbageRate: 1),
          connect: false,
          seed: seed,
        ).execute('ATE0');
        expect(instant.text, startsWith('ATE0\r'), reason: 'seed $seed');
        expect(hasStray(instant.text), isTrue, reason: 'seed $seed');
      }
    });

    test('no quirks: nothing is ever wrong', () {
      final sim = _adapter()
        ..execute('ATE0')
        ..execute('ATL0');

      for (var i = 0; i < 500; i++) {
        expect(_text(sim, '010C'), '41 0C 1A F8 \r\r>');
      }
    });
  });

  group('with the real ECU', () {
    Elm327Simulator adapterFor(String profileName, {double seconds = 60}) {
      final car = SimulatedCar(
        scenario: DriveScenarios.cityStopGo,
        profile: VehicleProfiles.byName(profileName),
      );
      while (car.elapsedSeconds < seconds) {
        car.tick();
      }
      return Elm327Simulator(ecu: SimulatedEcu(car: car))
        ..execute('ATE0')
        ..execute('ATL0')
        ..execute('ATSP6');
    }

    test('0100 gives the profile\'s bitmask', () {
      final sim = adapterFor('petrol_cvt_maf');

      expect(_text(sim, '0100'), '41 00 98 3B 80 01 \r\r>');
      expect(_text(sim, '0120'), '41 20 00 02 00 01 \r\r>');
      expect(_text(sim, '0140'), '41 40 40 00 00 00 \r\r>');
    });

    test('a minimal old car has nothing after 0100, so 0120 is NO DATA', () {
      final sim = adapterFor('minimal_old_car');

      expect(_text(sim, '0100'), '41 00 98 18 80 00 \r\r>');
      expect(_text(sim, '0120'), 'NO DATA\r\r>');
    });

    test('a request for six PIDs comes back as a two-frame message', () {
      final sim = adapterFor('petrol_cvt_maf');

      final lines = _text(
        sim,
        '01 04 05 0B 0C 0D 0F',
      ).split('\r').where((l) => l.isNotEmpty).toList();

      // 41, then 04+1, 05+1, 0B+1, 0C+2, 0D+1, 0F+1 = 1 + 2+2+2+3+2+2 = 14.
      expect(lines[0], '00E');
      expect(lines[1], startsWith('0: 41 04 '));
      expect(lines[2], startsWith('1: '));
      expect(lines.last, '>');
    });

    test('PID 0C decodes back to the car\'s rpm', () {
      final sim = adapterFor('petrol_cvt_maf');
      final text = _text(sim, '010C');
      final bytes = text
          .split('\r')
          .first
          .trim()
          .split(' ')
          .map((h) => int.parse(h, radix: 16))
          .toList();

      expect(bytes.take(2), [0x41, 0x0C]);
      expect((256 * bytes[2] + bytes[3]) / 4, greaterThanOrEqualTo(0));
    });
  });
}

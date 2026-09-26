import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/elm327_device.dart';
import 'package:tapedash/sim/elm327_simulator.dart';

import '../../support/scripted_ecu.dart';

/// A device on a fake clock that notes each piece of output and when it came.
class _Rig {
  _Rig({AdapterQuirks quirks = AdapterQuirks.none, int seed = 1}) {
    ecu = ScriptedEcu(
      datasheetAnswers,
      onRespond: (_) => asked.add(clock.monotonic()),
    );
    device = Elm327Device(
      simulator: Elm327Simulator(ecu: ecu, quirks: quirks, seed: seed),
      scheduler: clock,
      seed: seed,
      onOutput: (text) {
        output.add((clock.monotonic(), text));
        onOutput?.call(text);
      },
    );
  }

  final clock = FakeClock();
  late final ScriptedEcu ecu;
  late final Elm327Device device;

  /// Each piece of output, with the time it went out.
  final List<(Duration, String)> output = [];

  /// When the ECU was asked.
  final List<Duration> asked = [];

  void Function(String text)? onOutput;

  String get text => output.map((o) => o.$2).join();

  void advance(int ms) => clock.advance(Duration(milliseconds: ms));
}

void main() {
  group('lines', () {
    test('a command is run when its carriage return arrives', () {
      final rig = _Rig();

      rig.device.receive('ATE0');
      rig.advance(100);
      expect(rig.text, isEmpty);

      rig.device.receive('\r');
      rig.advance(100);

      expect(rig.text, 'ATE0\rOK\r\n\r\n>');
    });

    test('characters can arrive one at a time', () {
      final rig = _Rig();

      for (final c in 'ATI\r'.split('')) {
        rig.device.receive(c);
      }
      rig.advance(100);

      expect(rig.text, 'ATI\rELM327 v1.5\r\n\r\n>');
    });

    test('a line feed is ignored', () {
      final rig = _Rig();

      rig.device.receive('ATI\r\n');
      rig.advance(100);

      expect(rig.text, 'ATI\rELM327 v1.5\r\n\r\n>');
    });

    test('two commands in one write are answered one after the other', () {
      final rig = _Rig();

      rig.device.receive('ATE0\rATI\r');
      rig.advance(100);

      expect(rig.text, 'ATE0\rOK\r\n\r\n>ELM327 v1.5\r\n\r\n>');
    });

    test('a command that arrives while another is answered waits its turn', () {
      final rig = _Rig()..device.receive('ATE0\rATL0\rATSP6\r');
      rig.advance(10);
      rig.device.receive('0100\r');
      rig.advance(500);

      // The ATZ-free commands are all instant; the request is answered at
      // 20 ms and its prompt at 60 ms, after the others.
      expect(rig.text.endsWith('41 00 BE 1F B8 10 \r\r>'), isTrue);
      expect(rig.text.split('>').length - 1, 4, reason: 'four prompts');
    });

    test('an empty line repeats the last command', () {
      final rig = _Rig()..device.receive('ATI\r');
      rig.advance(10);
      rig.output.clear();

      rig.device.receive('\r');
      rig.advance(10);

      expect(rig.text, '\rELM327 v1.5\r\n\r\n>');
    });
  });

  group('timing', () {
    test('with a perfect link the echo is at once and the banner at 0.8 s', () {
      final rig = _Rig()..device.receive('ATZ\r');

      rig.advance(1000);

      expect(rig.output, [
        (Duration.zero, 'ATZ\r'),
        (const Duration(milliseconds: 800), '\r\rELM327 v1.5\r\n\r\n>'),
      ]);
    });

    test('nothing goes out synchronously inside receive', () {
      final rig = _Rig()..device.receive('ATI\r');

      expect(rig.output, isEmpty);
    });

    test('a link with 80 ms latency: 40 ms there, 40 ms back', () {
      final rig = _Rig(
        quirks: const AdapterQuirks(latency: Duration(milliseconds: 80)),
      )..device.receive('ATSP6\r');
      rig.advance(500);
      rig.output.clear();
      rig.asked.clear();

      rig.device.receive('010C\r');
      rig.advance(500);

      final t0 = const Duration(milliseconds: 500);
      // The ECU is asked half way through the round trip.
      expect(rig.asked.single - t0, const Duration(milliseconds: 40));
      // The echo comes back after the whole round trip, the answer 20 ms later
      // and the prompt 40 ms after that.
      expect(rig.output.map((o) => (o.$1 - t0).inMilliseconds), [80, 100, 140]);
    });

    test('the answer reflects the car at the middle of the round trip', () {
      // Whatever the ECU says is what it said when it was asked: check by
      // changing its answer between the request arriving and the answer.
      final rig = _Rig(
        quirks: const AdapterQuirks(latency: Duration(milliseconds: 100)),
      )..device.receive('ATSP6\r');
      rig.advance(500);
      rig.ecu.answers['010C'] = [0x41, 0x0C, 0x00, 0x04];
      rig.device.receive('010C\r');

      rig.advance(30);
      // Still before the request reaches the ECU at 50 ms: change the answer.
      rig.ecu.answers['010C'] = [0x41, 0x0C, 0x0F, 0xA0];
      rig.advance(500);

      expect(rig.text, contains('41 0C 0F A0'));
    });

    test('jitter: each command gets its own round trip, within the range', () {
      final rig = _Rig(
        quirks: const AdapterQuirks(
          latency: Duration(milliseconds: 80),
          jitter: Duration(milliseconds: 40),
        ),
      )..device.receive('ATSP6\r');
      rig.advance(1000);
      final trips = <int>[];

      for (var i = 0; i < 100; i++) {
        rig.output.clear();
        final start = rig.clock.monotonic();
        rig.device.receive('ATI\r');
        rig.advance(300);
        trips.add((rig.output.first.$1 - start).inMilliseconds);
      }

      expect(trips.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(40));
      expect(trips.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(120));
      expect(trips.toSet().length, greaterThan(20), reason: 'they vary');
      final mean = trips.reduce((a, b) => a + b) / trips.length;
      expect(mean, closeTo(80, 8));
    });

    test('the same seed gives the same round trips', () {
      List<int> run(int seed) {
        final rig = _Rig(
          quirks: const AdapterQuirks(
            latency: Duration(milliseconds: 80),
            jitter: Duration(milliseconds: 40),
          ),
          seed: seed,
        );
        final out = <int>[];
        for (var i = 0; i < 20; i++) {
          rig.output.clear();
          final start = rig.clock.monotonic();
          rig.device.receive('ATI\r');
          rig.advance(300);
          out.add((rig.output.first.$1 - start).inMilliseconds);
        }
        return out;
      }

      expect(run(3), run(3));
      expect(run(3), isNot(run(4)));
    });
  });

  group('one command at a time', () {
    test('a well-behaved app never overlaps', () {
      final rig = _Rig(
        quirks: const AdapterQuirks(latency: Duration(milliseconds: 60)),
      );
      var sent = 0;
      // Send the next command from inside the callback that delivers the
      // prompt, as fast as an app can.
      rig.onOutput = (text) {
        if (text.endsWith('>') && sent < 50) {
          sent++;
          rig.device.receive('010C\r');
        }
      };
      rig.device.receive('ATSP6\r');

      rig.advance(20000);

      expect(sent, 50);
      expect(rig.device.overlappedCommands, 0);
      expect(rig.text.split('>').length - 1, 51);
    });

    test('a command sent before the prompt counts as an overlap', () {
      final rig = _Rig()..device.receive('ATZ\r');
      rig.advance(100);

      rig.device.receive('ATI\r');

      expect(rig.device.overlappedCommands, 1);
      rig.advance(2000);
      expect(rig.text, endsWith('ELM327 v1.5\r\n\r\n>'));
      expect(rig.device.isBusy, isFalse);
    });

    test('nothing is left scheduled once everything is answered', () {
      final rig = _Rig(
        quirks: const AdapterQuirks(latency: Duration(milliseconds: 80)),
      )..device.receive('ATZ\rATI\r010C\r');

      rig.advance(5000);

      expect(rig.clock.pendingTasks, 0);
    });
  });

  group('a clone that loses the first command', () {
    const quirks = AdapterQuirks(dropFirstCommand: true);

    test('the first command is lost, echo and all', () {
      final rig = _Rig(quirks: quirks)..device.receive('ATZ\r');
      rig.advance(2000);

      expect(rig.output, isEmpty);
    });

    test('the second is answered', () {
      final rig = _Rig(quirks: quirks)..device.receive('ATZ\r');
      rig.advance(2000);

      rig.device.receive('ATZ\r');
      rig.advance(2000);

      expect(rig.text, 'ATZ\r\r\rELM327 v1.5\r\n\r\n>');
    });

    test('only the first is lost', () {
      final rig = _Rig(quirks: quirks)..device.receive('ATI\rATI\rATI\r');
      rig.advance(2000);

      expect(rig.text.split('>').length - 1, 2);
    });

    test('a new link loses one again', () {
      final rig = _Rig(quirks: quirks)..device.receive('ATI\rATI\r');
      rig.advance(500);
      rig.output.clear();

      rig.device
        ..linkOpened()
        ..receive('ATI\r');
      rig.advance(500);
      expect(rig.output, isEmpty);

      rig.device.receive('ATI\r');
      rig.advance(500);
      expect(rig.text, contains('ELM327'));
    });

    test('an adapter without the quirk loses nothing', () {
      final rig = _Rig()..device.receive('ATI\r');
      rig.advance(500);

      expect(rig.text, contains('ELM327'));
    });
  });

  group('when the link goes', () {
    test('what was on its way is never delivered', () {
      final rig = _Rig(
        quirks: const AdapterQuirks(latency: Duration(milliseconds: 100)),
      )..device.receive('ATI\r');
      rig.advance(60);

      rig.device.linkClosed();
      rig.advance(2000);

      expect(rig.output, isEmpty);
      expect(rig.clock.pendingTasks, 0);
    });

    test('what was waiting is forgotten', () {
      final rig = _Rig()..device.receive('ATZ\rATI\rATI\r');
      rig.advance(10);

      rig.device.linkClosed();
      rig.advance(5000);

      expect(rig.text, 'ATZ\r');
    });

    test('half a command that was typed is forgotten', () {
      final rig = _Rig()..device.receive('AT');
      rig.device.linkClosed();

      rig.device.receive('I\r');
      rig.advance(100);

      expect(rig.text, 'I\r?\r\n\r\n>');
    });

    test('the device works again afterwards', () {
      final rig = _Rig()..device.receive('ATZ\r');
      rig.advance(10);
      rig.device.linkClosed();
      rig.output.clear();

      rig.device
        ..linkOpened()
        ..receive('ATI\r');
      rig.advance(100);

      expect(rig.text, 'ATI\rELM327 v1.5\r\n\r\n>');
      expect(rig.device.isBusy, isFalse);
    });
  });
}

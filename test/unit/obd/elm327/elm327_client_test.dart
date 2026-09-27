import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/elm327/elm327_client.dart';
import 'package:tapedash/obd/elm327/elm327_failure.dart';
import 'package:tapedash/obd/transport/transport.dart';

import '../../../support/fake_transport.dart';

Duration ms(int n) => Duration(milliseconds: n);

/// A client on a fake clock and a hand-driven transport.
class _Rig {
  _Rig({Elm327Timing timing = const Elm327Timing(), bool connected = true}) {
    transport = FakeTransport(clock: clock, connected: connected);
    client = Elm327Client(
      transport: transport,
      scheduler: clock,
      clock: clock,
      timing: timing,
    );
  }

  final clock = FakeClock();
  late final FakeTransport transport;
  late final Elm327Client client;
  final List<Elm327Reply> replies = [];

  void advance(int millis) => clock.advance(ms(millis));

  void close() {
    client.dispose();
    transport.dispose();
  }

  /// Sends an AT command, and a reply of [text] arrives [after] ms later.
  void command(String text) => client.command(text, replies.add);

  Elm327Reply get last => replies.last;
}

void main() {
  group('sending', () {
    test('a command is written with a carriage return', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.command('ATE0');

      expect(rig.transport.writes, ['ATE0\r']);
    });

    test('a request is written as upper case hex', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.client.request([0x01, 0x0c], rig.replies.add);

      expect(rig.transport.writes, ['010C\r']);
    });

    test('a request can say how many answers to expect: one more digit', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.client.request([0x01, 0x0c], rig.replies.add, responses: 1);

      expect(rig.transport.writes, ['010C1\r']);
    });

    test('six PIDs in one request', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.client.request(
        [0x01, 0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F],
        rig.replies.add,
        responses: 1,
      );

      expect(rig.transport.writes, [
        '01 04 05 0B 0C 0D 0F1\r'.replaceAll(' ', ''),
      ]);
    });

    test(
      'nothing is written after the call returns, before the time is up',
      () {
        final rig = _Rig();
        addTearDown(rig.close);

        rig.command('ATI');

        // It is written at once: the transport is connected and idle.
        expect(rig.transport.writes.length, 1);
        expect(rig.client.isIdle, isFalse);
      },
    );

    test('one at a time: the second waits for the first', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.command('ATI');
      rig.command('ATRV');
      rig.command('ATE0');

      expect(rig.transport.writes, ['ATI\r']);
      expect(rig.client.queued, 2);

      rig.transport.receive('ELM327 v1.5\r\r>');
      expect(rig.transport.writes, ['ATI\r', 'ATRV\r']);

      rig.transport.receive('12.4V\r\r>');
      expect(rig.transport.writes, ['ATI\r', 'ATRV\r', 'ATE0\r']);
      expect(rig.client.queued, 0);
    });

    test('a command given from inside a callback goes after those waiting', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.command('A', (_) {
        rig.command('C');
      });
      rig.command('B');

      rig.transport.receive('x\r>');
      rig.transport.receive('y\r>');
      rig.transport.receive('z\r>');

      expect(rig.transport.writes, ['A\r', 'B\r', 'C\r']);
    });

    test('with no link, the call fails as disconnected, but not at once', () {
      final rig = _Rig(connected: false);
      addTearDown(rig.close);

      rig.command('ATI');
      expect(rig.replies, isEmpty, reason: 'never from inside the call');

      rig.advance(0);

      expect(rig.replies.single.failure, Elm327Failure.disconnected);
      expect(rig.transport.writes, isEmpty);
    });
  });

  group('reading a reply', () {
    test('the echo is dropped and the content is kept', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('ATI');

      rig.transport.receive('ATI\rELM327 v1.5\r\n\r\n>');

      expect(rig.last.ok, isTrue);
      expect(rig.last.lines, ['ELM327 v1.5']);
      expect(rig.last.messages, isEmpty);
      expect(rig.last.gotPrompt, isTrue);
    });

    test('a reply in many small pieces', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('ATI');

      for (final piece in [
        'A',
        'TI',
        '\r',
        'ELM',
        '327 v',
        '1.5\r',
        '\r',
        '>',
      ]) {
        expect(rig.replies, isEmpty);
        rig.transport.receive(piece);
      }

      expect(rig.last.lines, ['ELM327 v1.5']);
    });

    test('the prompt in a piece of its own', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('ATI');

      rig.transport.receive('ELM327 v1.5\r');
      expect(rig.replies, isEmpty);
      rig.transport.receive('\r>');

      expect(rig.last.lines, ['ELM327 v1.5']);
    });

    test('an OBD answer comes back as bytes', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add);

      rig.transport.receive('41 0C 1A F8 \r\r>');

      expect(rig.last.messages, [
        [0x41, 0x0C, 0x1A, 0xF8],
      ]);
      expect(rig.last.lines, ['41 0C 1A F8']);
    });

    test('a multi-frame answer comes back whole', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x04, 0x05, 0x0B, 0x0C], rig.replies.add);

      rig.transport.receive(
        '00A\r0: 41 04 3F 05 44 0B \r1: 21 0C 17 B8 00 00 00 \r\r>',
      );

      expect(rig.last.messages, [
        [0x41, 0x04, 0x3F, 0x05, 0x44, 0x0B, 0x21, 0x0C, 0x17, 0xB8],
      ]);
    });

    test('two ECUs give two messages', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x00], rig.replies.add);

      rig.transport.receive('41 00 BE 3E B8 11\r41 00 80 10 80 00\r>');

      expect(rig.last.messages.length, 2);
    });

    test('with an expected prefix, only the messages that start with it', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request(
        [0x01, 0x0C],
        rig.replies.add,
        expectPrefix: [0x41, 0x0C],
      );

      rig.transport.receive('41 0D 32\r41 0C 1A F8\r>');

      expect(rig.last.messages, [
        [0x41, 0x0C, 0x1A, 0xF8],
      ]);
    });

    test('SEARCHING... is noted', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x00], rig.replies.add);

      rig.transport.receive('SEARCHING...\r41 00 98 3B 80 01 \r\r>');

      expect(rig.last.searched, isTrue);
      expect(rig.last.messages.single.first, 0x41);
    });

    test('every error is a typed failure', () {
      const table = {
        'NO DATA': Elm327Failure.noData,
        '?': Elm327Failure.unknownCommand,
        'CAN ERROR': Elm327Failure.canError,
        'UNABLE TO CONNECT': Elm327Failure.unableToConnect,
        'BUS INIT: ...ERROR': Elm327Failure.busInitError,
        'BUFFER FULL': Elm327Failure.bufferFull,
        'STOPPED': Elm327Failure.stopped,
      };
      for (final entry in table.entries) {
        final rig = _Rig();
        rig.client.request([0x01, 0x0C], rig.replies.add);

        rig.transport.receive('${entry.key}\r\r>');

        expect(rig.last.failure, entry.value, reason: entry.key);
        expect(rig.last.messages, isEmpty);
        rig.close();
      }
    });

    test('a failed AT command carries the failure too', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('ATXYZ');

      rig.transport.receive('ATXYZ\r?\r\r>');

      expect(rig.last.failure, Elm327Failure.unknownCommand);
    });

    test('an answer that cannot be read is garbled', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add);

      rig.transport.receive('41 0C 1A F\x7F8\r\r>');

      expect(rig.last.failure, Elm327Failure.garbled);
      expect(rig.client.garbledReplies, 1);
    });

    test('a message that stops short is garbled', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x09, 0x02], rig.replies.add);

      rig.transport.receive('014\r0: 49 02 01 31 44 34\r1: 47 50\r>');

      expect(rig.last.failure, Elm327Failure.garbled);
    });

    test('the raw text is kept for diagnostics', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('ATE0');

      rig.transport.receive('ATE0\rOK\r\n\r\n>');

      expect(rig.last.raw, 'ATE0\rOK\r\n\r\n>');
    });

    test('an AT command with an empty reply is ok, with no lines', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('ATE0');

      rig.transport.receive('>');

      expect(rig.last.ok, isTrue);
      expect(rig.last.lines, isEmpty);
    });
  });

  group('the time of a reply', () {
    test('the latency is to the first line of data, not to the prompt', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add);

      rig.advance(100);
      rig.transport.receive('41 0C 1A F8 \r');
      rig.advance(200);
      rig.transport.receive('\r>');

      expect(rig.last.sentAt, Duration.zero);
      expect(rig.last.dataAt, ms(100));
      expect(rig.last.completedAt, ms(300));
      expect(rig.last.latency, ms(100));
      expect(rig.last.elapsed, ms(300));
    });

    test('the sample time is the middle of the trip to the data', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.advance(1000);
      rig.client.request([0x01, 0x0C], rig.replies.add);

      rig.advance(100);
      rig.transport.receive('41 0C 1A F8 \r\r>');

      expect(rig.last.sentAt, ms(1000));
      expect(rig.last.sampleTime, ms(1050));
    });

    test('the echo and SEARCHING... are not the data', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request(
        [0x01, 0x00],
        rig.replies.add,
        timeout: const Duration(seconds: 12),
      );

      rig.advance(10);
      rig.transport.receive('0100\r');
      rig.advance(20);
      rig.transport.receive('SEARCHING...\r');
      rig.advance(2400);
      rig.transport.receive('41 00 98 3B 80 01 \r');
      rig.advance(40);
      rig.transport.receive('\r>');

      expect(rig.last.dataAt, ms(2430));
      expect(rig.last.latency, ms(2430));
    });

    test('a line cut in two is data when its end arrives', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add);

      rig.advance(30);
      rig.transport.receive('41 0C ');
      rig.advance(20);
      rig.transport.receive('1A F8 \r\r>');

      expect(rig.last.dataAt, ms(50));
    });

    test('an error line counts as the data too', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add);

      rig.advance(200);
      rig.transport.receive('NO DATA\r\r>');

      expect(rig.last.dataAt, ms(200));
    });

    test('with no data the latency is unknown', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('ATE0');

      rig.advance(50);
      rig.transport.receive('>');

      expect(rig.last.latency, isNull);
      expect(rig.last.sampleTime, isNull);
    });
  });

  group('timeouts', () {
    test('nothing back: a timeout, at the time given', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add, timeout: ms(700));

      rig.advance(699);
      expect(rig.replies, isEmpty);
      rig.advance(1);

      expect(rig.last.failure, Elm327Failure.timeout);
      expect(rig.last.completedAt, ms(700));
      expect(rig.client.timeouts, 1);
    });

    test('the default for a command is 2 s', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('ATE0');

      rig.advance(1999);
      expect(rig.replies, isEmpty);
      rig.advance(1);

      expect(rig.last.completedAt, ms(2000));
    });

    test('the default for a request is 1.5 s', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add);

      rig.advance(1499);
      expect(rig.replies, isEmpty);
      rig.advance(1);

      expect(rig.last.completedAt, ms(1500));
    });

    test('what arrived before the timeout is in the raw text', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add);

      rig.transport.receive('41 0C 1A');
      rig.advance(1500);

      expect(rig.last.failure, Elm327Failure.timeout);
      expect(rig.last.raw, '41 0C 1A');
    });

    test('a timeout does not stop the next command', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('ATI');
      rig.command('ATRV');

      rig.advance(2000);
      // The timeout is followed by a short settle, then the next is written.
      rig.advance(100);

      expect(rig.transport.writes, ['ATI\r', 'ATRV\r']);
      rig.transport.receive('12.4V\r>');
      expect(rig.replies.last.lines, ['12.4V']);
    });

    test('the time is per command, from its own write', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('A');
      rig.command('B');
      rig.advance(1000);
      rig.transport.receive('x\r>');

      // B was written at 1000 ms and has until 3000 ms.
      rig.advance(1999);
      expect(rig.replies.length, 1);
      rig.advance(1);
      expect(rig.replies.length, 2);
      expect(rig.last.failure, Elm327Failure.timeout);
    });

    test('a late reply after the timeout is stray, and does no harm', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('ATI');
      rig.advance(2000);
      expect(rig.last.failure, Elm327Failure.timeout);

      rig.transport.receive('ELM327 v1.5\r>');

      expect(rig.client.strayCharacters, 'ELM327 v1.5\r>'.length);
      expect(rig.replies.length, 1);
    });
  });

  group('pacing', () {
    test('the next command waits for the minimum gap', () {
      final rig = _Rig(
        timing: const Elm327Timing(minGap: Duration(milliseconds: 40)),
      );
      addTearDown(rig.close);
      rig.command('A');
      rig.command('B');

      rig.advance(10);
      rig.transport.receive('x\r>');
      expect(rig.transport.writes, ['A\r'], reason: 'too soon');

      rig.advance(39);
      expect(rig.transport.writes, ['A\r']);
      rig.advance(1);

      expect(rig.transport.writes, ['A\r', 'B\r']);
      expect(rig.transport.writeTimes[1], ms(50));
    });

    test('no gap: the next is written the moment the prompt arrives', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('A');
      rig.command('B');

      rig.advance(10);
      rig.transport.receive('x\r>');

      expect(rig.transport.writeTimes, [Duration.zero, ms(10)]);
    });

    test('the gap can be changed while it runs', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.timing = rig.client.timing.copyWith(minGap: ms(100));
      rig.command('A');
      rig.command('B');

      rig.transport.receive('x\r>');
      rig.advance(99);
      expect(rig.transport.writes.length, 1);
      rig.advance(1);
      expect(rig.transport.writes.length, 2);
    });

    test('the settle after a timeout is at least 100 ms', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('A');
      rig.command('B');

      rig.advance(2000);
      expect(rig.transport.writes.length, 1);
      rig.advance(99);
      expect(rig.transport.writes.length, 1);
      rig.advance(1);
      expect(rig.transport.writes.length, 2);
    });
  });

  group('a reply that is not for this request', () {
    test('a bare prompt is skipped, and the real reply is waited for', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add);

      rig.transport.receive('\r\r>');
      expect(rig.replies, isEmpty);
      rig.advance(50);
      rig.transport.receive('41 0C 1A F8\r>');

      expect(rig.last.messages.single, [0x41, 0x0C, 0x1A, 0xF8]);
      expect(rig.client.skippedReplies, 1);
    });

    test('an answer to another PID is skipped when a prefix is expected', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request(
        [0x01, 0x0C],
        rig.replies.add,
        expectPrefix: [0x41, 0x0C],
      );

      rig.transport.receive('41 0D 32\r\r>');
      expect(rig.replies, isEmpty);
      rig.transport.receive('41 0C 1A F8\r\r>');

      expect(rig.last.messages.single, [0x41, 0x0C, 0x1A, 0xF8]);
      expect(rig.client.skippedReplies, 1);
    });

    test('without a prefix, any answer is taken', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add);

      rig.transport.receive('41 0D 32\r\r>');

      expect(rig.last.messages.single, [0x41, 0x0D, 0x32]);
    });

    test('the timeout still runs while replies are skipped', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request(
        [0x01, 0x0C],
        rig.replies.add,
        expectPrefix: [0x41, 0x0C],
      );

      rig.advance(500);
      rig.transport.receive('41 0D 32\r>');
      rig.advance(1000);

      expect(rig.last.failure, Elm327Failure.timeout);
    });

    test(
      'a late reply to a timed-out request does not answer the next one',
      () {
        // The request for 0C times out. The adapter was only slow, and its
        // answer to 0C arrives while 0D is being asked.
        final rig = _Rig();
        addTearDown(rig.close);
        rig.client.request(
          [0x01, 0x0C],
          rig.replies.add,
          expectPrefix: [0x41, 0x0C],
        );
        rig.client.request(
          [0x01, 0x0D],
          rig.replies.add,
          expectPrefix: [0x41, 0x0D],
        );
        rig.advance(1500);
        expect(rig.last.failure, Elm327Failure.timeout);
        rig.advance(100);
        expect(rig.transport.writes.last, '010D\r');

        rig.transport.receive('41 0C 1A F8\r\r>');
        expect(rig.replies.length, 1, reason: 'the late reply is not for 0D');
        rig.transport.receive('41 0D 32\r\r>');

        expect(rig.last.messages.single, [0x41, 0x0D, 0x32]);
      },
    );

    test(
      'several kinds of answer can be accepted, and the rest are skipped',
      () {
        final rig = _Rig();
        addTearDown(rig.close);
        rig.client.request(
          [0x04],
          rig.replies.add,
          acceptPrefixes: [
            [0x44],
            [0x7F, 0x04],
          ],
        );

        rig.transport.receive('41 0C 1A F8\r\r>');
        expect(rig.replies, isEmpty, reason: 'a poll reply is neither');
        rig.transport.receive('7F 04 22\r\r>');

        expect(rig.last.messages.single, [0x7F, 0x04, 0x22]);
        expect(rig.client.skippedReplies, 1);
      },
    );

    test('the positive kind is accepted too', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request(
        [0x04],
        rig.replies.add,
        acceptPrefixes: [
          [0x44],
          [0x7F, 0x04],
        ],
      );

      rig.transport.receive('44\r\r>');

      expect(rig.last.messages.single, [0x44]);
    });

    test('an expected prefix and accepted prefixes are both allowed', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request(
        [0x01, 0x0C],
        rig.replies.add,
        expectPrefix: [0x41, 0x0C],
        acceptPrefixes: [
          [0x7F, 0x01],
        ],
      );

      rig.transport.receive('7F 01 12\r\r>');

      expect(rig.last.messages.single, [0x7F, 0x01, 0x12]);
    });

    test('an error is for whichever request is waiting', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request(
        [0x01, 0x0C],
        rig.replies.add,
        expectPrefix: [0x41, 0x0C],
      );

      rig.transport.receive('NO DATA\r\r>');

      expect(rig.last.failure, Elm327Failure.noData);
    });
  });

  group('a prompt that does not come', () {
    test(
      'with the answers all in and a count expected, it is accepted after the grace',
      () {
        final rig = _Rig();
        addTearDown(rig.close);
        rig.client.request([0x01, 0x0C], rig.replies.add, responses: 1);

        rig.advance(40);
        rig.transport.receive('41 0C 1A F8 \r\r');
        rig.advance(249);
        expect(rig.replies, isEmpty);
        rig.advance(1);

        expect(rig.last.ok, isTrue);
        expect(rig.last.gotPrompt, isFalse);
        expect(rig.last.messages.single, [0x41, 0x0C, 0x1A, 0xF8]);
        expect(rig.last.completedAt, ms(290));
        expect(rig.client.missingPrompts, 1);
      },
    );

    test('the next command goes at once after that', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add, responses: 1);
      rig.command('ATI');

      rig.transport.receive('41 0C 1A F8 \r\r');
      rig.advance(250);

      expect(rig.transport.writes, ['010C1\r', 'ATI\r']);
    });

    test('a prompt that turns up in time is an ordinary reply', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add, responses: 1);

      rig.transport.receive('41 0C 1A F8 \r');
      rig.advance(100);
      rig.transport.receive('\r>');

      expect(rig.last.gotPrompt, isTrue);
      rig.advance(500);
      expect(rig.replies.length, 1, reason: 'the grace timer is cancelled');
    });

    test('without a count, the whole timeout is waited', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x0C], rig.replies.add);

      rig.transport.receive('41 0C 1A F8 \r\r');
      rig.advance(1499);
      expect(rig.replies, isEmpty);
      rig.advance(1);

      expect(rig.last.failure, Elm327Failure.timeout);
    });

    test('with fewer answers than expected, it is not accepted early', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request([0x01, 0x00], rig.replies.add, responses: 2);

      rig.transport.receive('41 00 BE 3E B8 11\r');
      rig.advance(1000);

      expect(rig.replies, isEmpty);
    });

    test('an answer for another request does not count', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.client.request(
        [0x01, 0x0C],
        rig.replies.add,
        responses: 1,
        expectPrefix: [0x41, 0x0C],
      );

      rig.transport.receive('41 0D 32\r');
      rig.advance(400);

      expect(rig.replies, isEmpty);
    });

    test(
      'an error with no prompt is accepted after the grace, if a count was given',
      () {
        final rig = _Rig();
        addTearDown(rig.close);
        rig.client.request([0x01, 0x0C], rig.replies.add, responses: 1);

        rig.transport.receive('NO DATA\r');
        rig.advance(250);

        expect(rig.last.failure, Elm327Failure.noData);
        expect(rig.last.gotPrompt, isFalse);
      },
    );
  });

  group('the link going', () {
    test('the command in flight and those waiting fail as disconnected', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('A');
      rig.command('B');
      rig.command('C');

      rig.transport.setState(
        const TransportState.disconnected(failure: TransportFailure.lost),
      );

      expect(rig.replies.map((r) => r.command), ['A', 'B', 'C']);
      expect(
        rig.replies.map((r) => r.failure),
        everyElement(Elm327Failure.disconnected),
      );
      expect(rig.client.isIdle, isTrue);
    });

    test('nothing is written for those that were waiting', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('A');
      rig.command('B');

      rig.transport.setState(const TransportState.disconnected());

      expect(rig.transport.writes, ['A\r']);
    });

    test('the timeout of the failed command does not fire later', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.command('A');
      rig.transport.setState(const TransportState.disconnected());
      expect(rig.replies.length, 1);

      rig.advance(10000);

      expect(rig.replies.length, 1);
      expect(rig.clock.pendingTasks, 0);
    });

    test(
      'after it comes back, commands work again, and pacing starts fresh',
      () {
        final rig = _Rig(
          timing: const Elm327Timing(minGap: Duration(milliseconds: 500)),
        );
        addTearDown(rig.close);
        rig.command('A');
        rig.transport.receive('x\r>');
        rig.transport.setState(const TransportState.disconnected());
        rig.transport.setState(TransportState.connected);

        rig.command('B');

        // No gap is owed to a command from before the link went.
        expect(rig.transport.writes, ['A\r', 'B\r']);
      },
    );

    test('data arriving while disconnected is stray', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.transport.setState(const TransportState.disconnected());

      rig.transport.receive('OK\r>');

      expect(rig.client.strayCharacters, 4);
    });

    test('a write that fails is not a crash, and the timeout follows', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.transport.failWrites = true;

      rig.command('A');
      rig.advance(2000);

      expect(rig.replies.single.failure, Elm327Failure.timeout);
      expect(rig.transport.writes, isEmpty);
    });
  });

  group('cleaning up', () {
    test('disposing fails what is waiting, and stops listening', () {
      final rig = _Rig();
      rig.command('A');
      rig.command('B');

      rig.client.dispose();

      expect(rig.replies.length, 2);
      expect(
        rig.replies.every((r) => r.failure == Elm327Failure.disconnected),
        isTrue,
      );
      rig.transport.receive('ELM327\r>');
      expect(rig.replies.length, 2);
      expect(rig.clock.pendingTasks, 0);
      rig.transport.dispose();
    });

    test('a command after disposing fails as disconnected', () {
      final rig = _Rig();
      rig.client.dispose();

      rig.command('A');
      rig.advance(0);

      expect(rig.last.failure, Elm327Failure.disconnected);
      expect(rig.transport.writes, isEmpty);
      rig.transport.dispose();
    });

    test('disposing twice is harmless', () {
      final rig = _Rig();

      rig.client.dispose();
      rig.client.dispose();
      rig.transport.dispose();
    });
  });

  group('counters', () {
    test(
      'commands sent, timeouts, garbled, skipped, stray and missing prompts',
      () {
        final rig = _Rig();
        addTearDown(rig.close);

        rig.client.request([0x01, 0x0C], rig.replies.add);
        rig.transport.receive('41 0C 1\x7F\r>'); // garbled
        rig.client.request([0x01, 0x0C], rig.replies.add);
        rig.advance(1500); // timeout
        rig.advance(100);
        rig.transport.receive('junk');
        rig.client.request([0x01, 0x0C], rig.replies.add, responses: 1);
        rig.transport.receive('\r>'); // skipped
        rig.transport.receive('41 0C 00 00\r');
        rig.advance(250); // accepted with no prompt

        expect(rig.client.commandsSent, 3);
        expect(rig.client.garbledReplies, 1);
        expect(rig.client.timeouts, 1);
        expect(rig.client.skippedReplies, 1);
        expect(rig.client.strayCharacters, 'junk'.length);
        expect(rig.client.missingPrompts, 1);
      },
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/elm327/elm327_failure.dart';
import 'package:tapedash/obd/elm327/elm327_parser.dart';

List<List<int>>? _messages(String raw, {String? command}) =>
    Elm327Parser.messages(Elm327Parser.parse(raw, sentCommand: command).lines);

void main() {
  group('taking a reply apart', () {
    test('a data line, with spaces, and the blank line and prompt after', () {
      final reply = Elm327Parser.parse('41 0C 1A F8 \r\r>');

      expect(reply.lines, ['41 0C 1A F8']);
      expect(reply.failure, isNull);
      expect(reply.searched, isFalse);
    });

    test('with linefeeds on', () {
      expect(Elm327Parser.parse('41 0C 1A F8 \r\n\r\n>').lines, [
        '41 0C 1A F8',
      ]);
    });

    test('with spaces off', () {
      expect(Elm327Parser.parse('410C1AF8\r\r>').lines, ['410C1AF8']);
    });

    test('with only line feeds', () {
      expect(Elm327Parser.parse('41 0C 1A F8 \n\n>').lines, ['41 0C 1A F8']);
    });

    test('the echo of the command is dropped', () {
      final reply = Elm327Parser.parse(
        '010C\r41 0C 1A F8 \r\r>',
        sentCommand: '010C',
      );

      expect(reply.lines, ['41 0C 1A F8']);
    });

    test('the echo matches whatever the spacing and case', () {
      expect(
        Elm327Parser.parse('01 0c\r41 0C 1A F8\r>', sentCommand: '010C').lines,
        ['41 0C 1A F8'],
      );
      expect(
        Elm327Parser.parse('010C\r41 0C 1A F8\r>', sentCommand: '01 0c').lines,
        ['41 0C 1A F8'],
      );
    });

    test('with no command given, an echo is just a line', () {
      expect(Elm327Parser.parse('010C\r41 0C 1A F8\r>').lines, [
        '010C',
        '41 0C 1A F8',
      ]);
    });

    test('only the first line can be the echo', () {
      final reply = Elm327Parser.parse('ATI\rATI\r>', sentCommand: 'ATI');

      expect(reply.lines, ['ATI']);
    });

    test('an AT reply', () {
      expect(
        Elm327Parser.parse('ATE0\rOK\r\n\r\n>', sentCommand: 'ATE0').lines,
        ['OK'],
      );
      expect(Elm327Parser.parse('12.5V\r\r>').lines, ['12.5V']);
      expect(Elm327Parser.parse('ELM327 v1.5\r\n\r\n>').lines, ['ELM327 v1.5']);
      expect(Elm327Parser.parse('ISO 15765-4 (CAN 11/500)\r\r>').lines, [
        'ISO 15765-4 (CAN 11/500)',
      ]);
    });

    test('the banner after a reset, with its two carriage returns', () {
      final reply = Elm327Parser.parse(
        'ATZ\r\r\rELM327 v1.5\r\n\r\n>',
        sentCommand: 'ATZ',
      );

      expect(reply.lines, ['ELM327 v1.5']);
    });

    test('a prompt at the end of a line, not on its own', () {
      expect(Elm327Parser.parse('41 0C 1A F8>').lines, ['41 0C 1A F8']);
      expect(Elm327Parser.parse('OK>').lines, ['OK']);
    });

    test('a reply with no prompt is read as far as it goes', () {
      expect(Elm327Parser.parse('41 0C 1A F8 \r').lines, ['41 0C 1A F8']);
      expect(Elm327Parser.parse('41 0C 1A F8').lines, ['41 0C 1A F8']);
    });

    test('NUL characters are ignored, as the datasheet says', () {
      expect(Elm327Parser.parse('41 0C\x00 1A F8\r\r>\x00').lines, [
        '41 0C 1A F8',
      ]);
      expect(_messages('4\x001 0C 1A F8\r\r>'), [
        [0x41, 0x0C, 0x1A, 0xF8],
      ]);
    });

    test('nothing but a prompt is an empty reply', () {
      expect(Elm327Parser.parse('>').isEmpty, isTrue);
      expect(Elm327Parser.parse('').isEmpty, isTrue);
      expect(Elm327Parser.parse('\r\r>').isEmpty, isTrue);
      expect(Elm327Parser.parse('ATI\r>', sentCommand: 'ATI').isEmpty, isTrue);
    });

    test('lines are trimmed, and blank ones dropped', () {
      expect(Elm327Parser.parse('  A  \r\r  \r B \r>').lines, ['A', 'B']);
    });

    test('a line keeps its spaces inside', () {
      expect(Elm327Parser.parse('OBDII to RS232 Interpreter\r>').lines, [
        'OBDII to RS232 Interpreter',
      ]);
    });
  });

  group('SEARCHING...', () {
    test('is noted, and is not content', () {
      final reply = Elm327Parser.parse('SEARCHING...\r41 00 BE 1F B8 10 \r\r>');

      expect(reply.searched, isTrue);
      expect(reply.lines, ['41 00 BE 1F B8 10']);
    });

    test('after the echo', () {
      final reply = Elm327Parser.parse(
        '0100\rSEARCHING...\r\n41 00 BE 1F B8 10 \r\n\r\n>',
        sentCommand: '0100',
      );

      expect(reply.searched, isTrue);
      expect(reply.lines, ['41 00 BE 1F B8 10']);
    });

    test('in any case, and with the dots or without', () {
      expect(Elm327Parser.parse('searching...\rOK\r>').searched, isTrue);
      expect(Elm327Parser.parse('SEARCHING\rOK\r>').searched, isTrue);
    });

    test('before an error, keeps the error', () {
      final reply = Elm327Parser.parse('SEARCHING...\rUNABLE TO CONNECT\r\r>');

      expect(reply.searched, isTrue);
      expect(reply.failure, Elm327Failure.unableToConnect);
      expect(reply.lines, isEmpty);
    });

    test('a reply without it says it did not search', () {
      expect(Elm327Parser.parse('OK\r>').searched, isFalse);
    });

    test('BUS INIT: OK is dropped, and is not an error', () {
      for (final line in [
        'BUS INIT: OK',
        'BUS INIT: ...OK',
        'bus init: ...ok',
      ]) {
        final reply = Elm327Parser.parse('SEARCHING...\r$line\r41 00 BE\r>');

        expect(reply.failure, isNull, reason: line);
        expect(reply.lines, ['41 00 BE'], reason: line);
      }
    });
  });

  group('errors', () {
    const table = <String, Elm327Failure>{
      '?': Elm327Failure.unknownCommand,
      'NO DATA': Elm327Failure.noData,
      'STOPPED': Elm327Failure.stopped,
      'CAN ERROR': Elm327Failure.canError,
      'BUS INIT: ...ERROR': Elm327Failure.busInitError,
      'BUS INIT: ERROR': Elm327Failure.busInitError,
      'BUS INIT:ERROR': Elm327Failure.busInitError,
      'UNABLE TO CONNECT': Elm327Failure.unableToConnect,
      'BUFFER FULL': Elm327Failure.bufferFull,
      'BUS BUSY': Elm327Failure.busBusy,
      'BUS ERROR': Elm327Failure.busError,
      'DATA ERROR': Elm327Failure.dataError,
      '<DATA ERROR': Elm327Failure.dataError,
      '<RX ERROR': Elm327Failure.rxError,
      'FB ERROR': Elm327Failure.feedbackError,
      'LV RESET': Elm327Failure.lowVoltageReset,
      'ERR94': Elm327Failure.internalError,
      'ERR01': Elm327Failure.internalError,
    };

    for (final entry in table.entries) {
      test('${entry.key} is ${entry.value.name}', () {
        expect(Elm327Parser.parse('${entry.key}\r\r>').failure, entry.value);
        // With the echo, and after SEARCHING...
        expect(
          Elm327Parser.parse(
            '0100\rSEARCHING...\r${entry.key}\r\r>',
            sentCommand: '0100',
          ).failure,
          entry.value,
        );
        // Whatever the case and the spacing.
        expect(
          Elm327Parser.parse('  ${entry.key.toLowerCase()}  \r>').failure,
          entry.value,
        );
      });
    }

    test('the error line is kept', () {
      final reply = Elm327Parser.parse('NO DATA\r\r>');

      expect(reply.failureLine, 'NO DATA');
      expect(reply.lines, isEmpty);
    });

    test('an error after data is still an error, and the data is kept', () {
      final reply = Elm327Parser.parse('41 0C 1A F8\r<DATA ERROR\r>');

      expect(reply.failure, Elm327Failure.dataError);
      expect(reply.lines, ['41 0C 1A F8']);
    });

    test('the first error is the one reported', () {
      final reply = Elm327Parser.parse('CAN ERROR\rBUS BUSY\r>');

      expect(reply.failure, Elm327Failure.canError);
    });

    test('text that only looks like an error is content', () {
      for (final text in [
        'NO DATA AVAILABLE',
        'ERROR',
        'ERR9',
        'ERR944',
        'ERRAB',
        'UNABLE',
        'BUS',
        'CAN',
      ]) {
        final reply = Elm327Parser.parse('$text\r>');

        expect(reply.failure, isNull, reason: text);
        expect(reply.lines, [text], reason: text);
      }
    });

    test('an error with noise in it is not recognised, and is not data', () {
      final reply = Elm327Parser.parse('N\x7FO DATA\r>');

      expect(reply.failure, isNull);
      expect(Elm327Parser.messages(reply.lines), isNull);
    });

    test('classify is the same table', () {
      expect(Elm327Parser.classify('no data'), Elm327Failure.noData);
      expect(Elm327Parser.classify('41 0C'), isNull);
    });
  });

  group('messages: one line of hex', () {
    test('a single answer', () {
      expect(_messages('41 0C 1A F8 \r\r>'), [
        [0x41, 0x0C, 0x1A, 0xF8],
      ]);
    });

    test('the same with the spaces off', () {
      expect(_messages('410C1AF8\r\r>'), [
        [0x41, 0x0C, 0x1A, 0xF8],
      ]);
    });

    test('the datasheet\'s 01 00', () {
      expect(_messages('41 00 BE 1F B8 10\r>'), [
        [0x41, 0x00, 0xBE, 0x1F, 0xB8, 0x10],
      ]);
    });

    test('lower case hex is accepted', () {
      expect(_messages('41 0c 1a f8\r>'), [
        [0x41, 0x0C, 0x1A, 0xF8],
      ]);
    });

    test('two ECUs answering give two messages, in order', () {
      // The datasheet's example of an 01 00 with two responders.
      expect(_messages('41 00 BE 3E B8 11\r41 00 80 10 80 00\r>'), [
        [0x41, 0x00, 0xBE, 0x3E, 0xB8, 0x11],
        [0x41, 0x00, 0x80, 0x10, 0x80, 0x00],
      ]);
    });

    test('no lines is no messages', () {
      expect(Elm327Parser.messages([]), isEmpty);
    });

    test('an odd number of hex digits is not a message', () {
      expect(_messages('41 0C 1A F\r>'), isNull);
      expect(_messages('410\r>'), isNull);
    });

    test('anything that is not hex is not a message', () {
      for (final line in [
        'OK',
        '41 0C 1A FG',
        '41 0C 1A F8\x7F',
        '\x1B41 0C 1A F8',
        '41-0C-1A-F8',
        'ELM327 v1.5',
        '12.5V',
      ]) {
        expect(_messages('$line\r>'), isNull, reason: line);
      }
    });

    test('one bad line spoils the lot', () {
      expect(_messages('41 0C 1A F8\rOK\r>'), isNull);
    });
  });

  group('messages: several frames', () {
    test('the datasheet\'s VIN, 014 and three numbered lines', () {
      final messages = _messages(
        '014\r'
        '0: 49 02 01 31 44 34 \r'
        '1: 47 50 30 30 52 35 35 \r'
        '2: 42 31 32 33 34 35 36 \r\r>',
      );

      expect(messages, [
        [
          0x49, 0x02, 0x01, 0x31, 0x44, 0x34, //
          0x47, 0x50, 0x30, 0x30, 0x52, 0x35, 0x35,
          0x42, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36,
        ],
      ]);
    });

    test('the datasheet\'s four PIDs, and the padding is cut off', () {
      final messages = _messages(
        '00A\r'
        '0: 41 04 3F 05 44 0B \r'
        '1: 21 0C 17 B8 00 00 00 \r\r>',
      );

      expect(messages, [
        [0x41, 0x04, 0x3F, 0x05, 0x44, 0x0B, 0x21, 0x0C, 0x17, 0xB8],
      ]);
    });

    test('with the spaces off', () {
      final messages = _messages('00A\r0:41043F05440B\r1:210C17B8000000\r>');

      expect(messages, [
        [0x41, 0x04, 0x3F, 0x05, 0x44, 0x0B, 0x21, 0x0C, 0x17, 0xB8],
      ]);
    });

    test(
      'with the spaces off and a space after the colon, as another adapter has it',
      () {
        // Ircama's ELM327-emulator prints '0: ' whatever the spaces setting.
        final messages = _messages(
          '00A\r0: 41043F05440B\r1: 210C17B8000000\r>',
        );

        expect(messages, [
          [0x41, 0x04, 0x3F, 0x05, 0x44, 0x0B, 0x21, 0x0C, 0x17, 0xB8],
        ]);
      },
    );

    test(
      'and a last line that stops at the length, unpadded, as that adapter does',
      () {
        final messages = _messages(
          '014\r0: 490201575030\r1: 5A5A5A39395A54\r2: 53333930303030\r>',
        );

        expect(messages!.single.length, 20);
        expect(messages.single.take(3), [0x49, 0x02, 0x01]);
      },
    );

    test('a last line that is not padded', () {
      final messages = _messages('008\r0:43030420 0171\r1:0300\r>');

      expect(messages, [
        [0x43, 0x03, 0x04, 0x20, 0x01, 0x71, 0x03, 0x00],
      ]);
    });

    test('eight bytes, the smallest that needs two frames', () {
      final messages = _messages(
        '008\r0: 43 03 04 20 01 71 \r1: 03 00 00 00 00 00 00 \r>',
      );

      expect(messages!.single.length, 8);
    });

    test('a message and then a single-line one', () {
      final messages = _messages(
        '00A\r0: 41 04 3F 05 44 0B\r1: 21 0C 17 B8 00 00 00\r41 00 BE 1F B8 10\r>',
      );

      expect(messages!.length, 2);
      expect(messages[1], [0x41, 0x00, 0xBE, 0x1F, 0xB8, 0x10]);
    });

    test('lines out of order are put right', () {
      final messages = _messages(
        '014\r'
        '0: 49 02 01 31 44 34\r'
        '2: 42 31 32 33 34 35 36\r'
        '1: 47 50 30 30 52 35 35\r>',
      );

      expect(messages!.single.sublist(0, 9), [
        0x49, 0x02, 0x01, 0x31, 0x44, 0x34, 0x47, 0x50, 0x30, //
      ]);
      expect(messages.single.length, 20);
      expect(messages.single.last, 0x36);
    });

    test('the numbering runs 0 to F and round again', () {
      // 1 + 20 numbered lines: 0..F, then 0..3.
      final lines = <String>[];
      for (var k = 0; k < 21; k++) {
        lines.add(
          '${(k % 16).toRadixString(16).toUpperCase()}: '
          '${(k * 7).toRadixString(16).padLeft(2, '0').toUpperCase()} '
          '00 00 00 00 00 00',
        );
      }
      final total = 6 + 20 * 7;
      final reply =
          '${total.toRadixString(16).padLeft(3, '0')}\r'
          '${lines.join('\r')}\r>';

      final messages = _messages(reply);

      expect(messages!.single.length, total);
    });

    test('a message that stops short is refused', () {
      // It says 20 bytes and has 19.
      expect(
        _messages(
          '014\r0: 49 02 01 31 44 34\r1: 47 50 30 30 52 35 35\r'
          '2: 42 31 32 33 34 35\r>',
        ),
        isNull,
      );
    });

    test('a count with no numbered lines is refused', () {
      expect(_messages('014\r>'), isNull);
      expect(_messages('014\r41 0C 1A F8\r>'), isNull);
    });

    test('numbered lines with no count are refused', () {
      expect(_messages('0: 41 04 3F 05 44 0B\r1: 21 0C 17 B8\r>'), isNull);
    });

    test('numbering that does not start at 0 is refused', () {
      expect(_messages('008\r1: 43 03 04 20 01 71\r2: 03 00\r>'), isNull);
    });

    test('a gap in the numbering is refused', () {
      expect(_messages('014\r0: 49 02 01 31 44 34\r2: 42 31\r>'), isNull);
    });

    test('a repeated line is refused', () {
      expect(
        _messages('014\r0: 49 02 01 31 44 34\r1: 47 50\r1: 47 50\r>'),
        isNull,
      );
    });

    test('noise in a numbered line is refused', () {
      expect(_messages('008\r0: 43 03 04 2\x7F 01 71\r1: 03 00\r>'), isNull);
    });

    test('an odd number of digits in a numbered line is refused', () {
      expect(_messages('008\r0: 43 03 04 20 01 7\r1: 03 00\r>'), isNull);
    });
  });
}

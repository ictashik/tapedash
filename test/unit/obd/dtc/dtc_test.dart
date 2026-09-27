import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/dtc/dtc.dart';
import 'package:tapedash/sim/ecu.dart';

void main() {
  group('a pair of bytes', () {
    // Each worked out by hand: the top two bits are the letter (P, C, B, U),
    // the next two the first digit, and the rest three hex digits.
    test('04 20 is P0420 and 01 71 is P0171', () {
      expect(DtcDecoder.decodePair(0x04, 0x20)!.code, 'P0420');
      expect(DtcDecoder.decodePair(0x01, 0x71)!.code, 'P0171');
    });

    test('the letter is the top two bits', () {
      expect(DtcDecoder.decodePair(0x00, 0x01)!.code, 'P0001');
      expect(DtcDecoder.decodePair(0x40, 0x01)!.code, 'C0001');
      expect(DtcDecoder.decodePair(0x80, 0x01)!.code, 'B0001');
      expect(DtcDecoder.decodePair(0xC0, 0x01)!.code, 'U0001');
    });

    test('the first digit is the next two bits', () {
      expect(DtcDecoder.decodePair(0x00, 0x01)!.code, 'P0001');
      expect(DtcDecoder.decodePair(0x10, 0x01)!.code, 'P1001');
      expect(DtcDecoder.decodePair(0x20, 0x01)!.code, 'P2001');
      expect(DtcDecoder.decodePair(0x30, 0x01)!.code, 'P3001');
    });

    test('the rest is three hex digits, in upper case, with leading zeros', () {
      expect(DtcDecoder.decodePair(0x0F, 0xFF)!.code, 'P0FFF');
      expect(DtcDecoder.decodePair(0x0A, 0xBC)!.code, 'P0ABC');
      expect(DtcDecoder.decodePair(0x00, 0x0A)!.code, 'P000A');
    });

    test('the corners', () {
      expect(DtcDecoder.decodePair(0x43, 0x00)!.code, 'C0300');
      expect(DtcDecoder.decodePair(0x90, 0x00)!.code, 'B1000');
      expect(DtcDecoder.decodePair(0xC1, 0x00)!.code, 'U0100');
      expect(DtcDecoder.decodePair(0x3F, 0xFF)!.code, 'P3FFF');
      expect(DtcDecoder.decodePair(0xFF, 0xFF)!.code, 'U3FFF');
      expect(DtcDecoder.decodePair(0x81, 0x23)!.code, 'B0123');
      expect(DtcDecoder.decodePair(0xA5, 0x67)!.code, 'B2567');
    });

    test('00 00 is padding, not a code', () {
      expect(DtcDecoder.decodePair(0, 0), isNull);
    });

    test('a value that is not a byte is refused', () {
      expect(() => DtcDecoder.decodePair(256, 0), throwsArgumentError);
      expect(() => DtcDecoder.decodePair(0, -1), throwsArgumentError);
    });

    test('it reads every code the simulator can write, back as it was', () {
      // The simulator encodes in its own code; this is a separate decoder.
      for (final letter in ['P', 'C', 'B', 'U']) {
        for (var digit = 0; digit <= 3; digit++) {
          for (var rest = 0; rest < 0x1000; rest++) {
            final code =
                '$letter$digit${rest.toRadixString(16).toUpperCase().padLeft(3, '0')}';
            final bytes = DtcCodec.encode(code)!;
            if (bytes[0] == 0 && bytes[1] == 0) continue;

            expect(DtcDecoder.decodePair(bytes[0], bytes[1])!.code, code);
          }
        }
      }
    });
  });

  group('a code', () {
    test('knows its system', () {
      expect(const Dtc('P0420').system, DtcSystem.powertrain);
      expect(const Dtc('C0300').system, DtcSystem.chassis);
      expect(const Dtc('B1000').system, DtcSystem.body);
      expect(const Dtc('U0100').system, DtcSystem.network);
    });

    test('is equal to another with the same text', () {
      expect(const Dtc('P0420'), const Dtc('P0420'));
      expect(const Dtc('P0420'), isNot(const Dtc('P0171')));
      expect(<Dtc>{const Dtc('P0420')}.length, 1);
    });

    test('prints as its code', () {
      expect(const Dtc('P0420').toString(), 'P0420');
    });
  });

  group('a Mode 03 message on CAN: 43, a count, then pairs', () {
    List<String>? codes(List<int> message, {int reply = 0x43}) =>
        DtcDecoder.decode(
          message,
          reply: reply,
          isCan: true,
        )?.map((c) => c.code).toList();

    test('two codes', () {
      expect(codes([0x43, 0x02, 0x04, 0x20, 0x01, 0x71]), ['P0420', 'P0171']);
    });

    test('none: 43 00', () {
      expect(codes([0x43, 0x00]), isEmpty);
    });

    test('43 alone, with no count, is none', () {
      expect(codes([0x43]), isEmpty);
    });

    test('three codes, in a message of eight bytes', () {
      expect(codes([0x43, 0x03, 0x04, 0x20, 0x01, 0x71, 0x03, 0x00]), [
        'P0420',
        'P0171',
        'P0300',
      ]);
    });

    test('a count that is too big is not believed: what is there is read', () {
      expect(codes([0x43, 0x03, 0x04, 0x20, 0x01, 0x71]), ['P0420', 'P0171']);
    });

    test('a count that is too small is believed, since ECUs pad', () {
      expect(codes([0x43, 0x01, 0x04, 0x20, 0x01, 0x71]), ['P0420']);
    });

    test('padding after the codes is not a code', () {
      expect(codes([0x43, 0x02, 0x04, 0x20, 0x01, 0x71, 0x00, 0x00]), [
        'P0420',
        'P0171',
      ]);
      expect(codes([0x43, 0x03, 0x04, 0x20, 0x01, 0x71, 0x00, 0x00]), [
        'P0420',
        'P0171',
      ]);
    });

    test('a byte left over is ignored', () {
      expect(codes([0x43, 0x02, 0x04, 0x20, 0x01]), ['P0420']);
    });

    test('Mode 07 is 47', () {
      expect(codes([0x47, 0x01, 0x03, 0x00], reply: 0x47), ['P0300']);
    });

    test(
      'a message of the other mode, a negative response, or nothing is null',
      () {
        expect(codes([0x47, 0x00]), isNull);
        expect(codes([0x7F, 0x03, 0x22]), isNull);
        expect(codes([]), isNull);
        expect(codes([0x41, 0x0C, 0x1A, 0xF8]), isNull);
      },
    );
  });

  group('a message on a protocol without a count', () {
    test('the codes follow the mode, three to a message', () {
      final codes = DtcDecoder.decode(
        [0x43, 0x04, 0x20, 0x01, 0x71, 0x00, 0x00],
        reply: 0x43,
        isCan: false,
      );

      expect(codes!.map((c) => c.code), ['P0420', 'P0171']);
    });

    test('43 alone is none', () {
      expect(DtcDecoder.decode([0x43], reply: 0x43, isCan: false), isEmpty);
    });
  });

  group('the messages of several ECUs', () {
    test('give every code once, in the order found', () {
      final codes = DtcDecoder.decodeAll(
        [
          [0x43, 0x02, 0x04, 0x20, 0x01, 0x71],
          [0x43, 0x02, 0x01, 0x71, 0x07, 0x00],
        ],
        reply: 0x43,
        isCan: true,
      );

      expect(codes!.map((c) => c.code), ['P0420', 'P0171', 'P0700']);
    });

    test('an ECU with none adds nothing', () {
      final codes = DtcDecoder.decodeAll(
        [
          [0x43, 0x00],
          [0x43, 0x01, 0x04, 0x20],
        ],
        reply: 0x43,
        isCan: true,
      );

      expect(codes!.map((c) => c.code), ['P0420']);
    });

    test('messages of another kind are left out', () {
      final codes = DtcDecoder.decodeAll(
        [
          [0x7F, 0x03, 0x22],
          [0x43, 0x01, 0x04, 0x20],
        ],
        reply: 0x43,
        isCan: true,
      );

      expect(codes!.map((c) => c.code), ['P0420']);
    });

    test('if none is the right kind, it is null', () {
      expect(
        DtcDecoder.decodeAll(
          [
            [0x7F, 0x03, 0x22],
          ],
          reply: 0x43,
          isCan: true,
        ),
        isNull,
      );
      expect(DtcDecoder.decodeAll([], reply: 0x43, isCan: true), isNull);
    });
  });
}

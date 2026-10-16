import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/survey/headed_reply.dart';

void main() {
  group('HeadedReply', () {
    test('a single frame on 29-bit CAN', () {
      final r = HeadedReply.parse(['18DAF110064100983A800100']);

      expect(r.unreadable, isEmpty);
      expect(r.messages, hasLength(1));
      final m = r.messages.single;
      expect(m.id, '18DAF110');
      expect(m.payload, [0x41, 0x00, 0x98, 0x3A, 0x80, 0x01]);
      expect(m.complete, isTrue);
    });

    test('a single frame on 11-bit CAN', () {
      final r = HeadedReply.parse(['7E8 03 41 05 7B 00 00 00 00']);

      expect(r.messages.single.id, '7E8');
      expect(r.messages.single.payload, [0x41, 0x05, 0x7B]);
    });

    test('spaces between the bytes make no difference', () {
      final r = HeadedReply.parse([
        '18 DA F1 10 06 41 00 98 3A 80 01 00 ',
        '7E8 03 41 05 7B 00 00 00 00 ',
      ]);

      expect(r.messages.map((m) => m.id), ['18DAF110', '7E8']);
      expect(r.messages.first.payload, [0x41, 0x00, 0x98, 0x3A, 0x80, 0x01]);
      expect(r.messages.last.payload, [0x41, 0x05, 0x7B]);
    });

    test('a message of several frames is put back together', () {
      // 12 bytes: 6 in the first frame, 6 in the next (padded).
      final r = HeadedReply.parse([
        '18DAF110 10 0C 41 0C 11 10 0D 00'.replaceAll(' ', ''),
        '18DAF110 21 11 02 0F 4B 00 00 00'.replaceAll(' ', ''),
      ]);

      expect(r.messages, hasLength(1));
      expect(r.messages.single.complete, isTrue);
      expect(r.messages.single.payload, [
        0x41,
        0x0C,
        0x11,
        0x10,
        0x0D,
        0x00,
        0x11,
        0x02,
        0x0F,
        0x4B,
        0x00,
        0x00, //
      ]);
    });

    test('two ECUs interleaved are told apart by their IDs', () {
      // The first ECU's long message is whole; the second's is cut after its
      // first frame (no flow control reached it).
      final r = HeadedReply.parse([
        '18DAF110 10 0C 41 0C 11 10 0D 00'.replaceAll(' ', ''),
        '18DAF111 10 0C 41 0C 11 11 0D 00'.replaceAll(' ', ''),
        '18DAF110 21 11 02 0F 4B 00 00 00'.replaceAll(' ', ''),
      ]);

      expect(r.messages, hasLength(2));
      final first = r.messages.first;
      final second = r.messages.last;
      expect(first.id, '18DAF110');
      expect(first.complete, isTrue);
      expect(first.payload, hasLength(0x0C));
      expect(second.id, '18DAF111');
      expect(second.complete, isFalse);
      expect(second.payload, [0x41, 0x0C, 0x11, 0x11, 0x0D, 0x00]);
    });

    test('a frame out of sequence marks the message incomplete', () {
      final r = HeadedReply.parse([
        '7E8 10 0C 41 0C 11 10 0D 00',
        '7E8 22 11 02 0F 4B 00 00 00',
      ]);

      expect(r.messages.single.complete, isFalse);
    });

    test('an ECU answering twice gives two messages', () {
      final r = HeadedReply.parse([
        '7E8 03 41 05 7B 00 00 00 00',
        '7E8 03 41 05 7C 00 00 00 00',
      ]);

      expect(r.messages, hasLength(2));
      expect(r.messages.map((m) => m.payload.last), [0x7B, 0x7C]);
    });

    test('text that is not a frame is kept apart, not guessed at', () {
      final r = HeadedReply.parse([
        '0: 41 04 3F 05 44 0B',
        'NOISE',
        '7E8 03 41 05 7B 00 00 00 00',
      ]);

      expect(r.messages, hasLength(1));
      expect(r.unreadable, ['0: 41 04 3F 05 44 0B', 'NOISE']);
    });

    test('a continuation with no first frame is unreadable', () {
      final r = HeadedReply.parse(['7E8 21 11 02 0F 4B 00 00 00']);

      expect(r.messages, isEmpty);
      expect(r.unreadable, hasLength(1));
    });

    test('flow control is not a message', () {
      final r = HeadedReply.parse(['7E0 30 00 00 00 00 00 00 00']);

      expect(r.messages, isEmpty);
      expect(r.unreadable, hasLength(1));
    });

    test('nothing in, nothing out', () {
      final r = HeadedReply.parse(const []);

      expect(r.messages, isEmpty);
      expect(r.unreadable, isEmpty);
    });
  });
}

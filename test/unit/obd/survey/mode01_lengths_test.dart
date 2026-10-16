import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/pids/pid.dart';
import 'package:tapedash/obd/survey/mode01_lengths.dart';

void main() {
  group('Mode01Lengths', () {
    test('agrees with every PID TapeDash reads', () {
      for (final pid in Pids.all) {
        expect(Mode01Lengths.of(pid.id), pid.length, reason: pid.name);
      }
    });

    test('has the lengths of PIDs the app does not read', () {
      expect(Mode01Lengths.of(0x01), 4);
      expect(Mode01Lengths.of(0x03), 2);
      expect(Mode01Lengths.of(0x0E), 1);
      expect(Mode01Lengths.of(0x15), 2);
      expect(Mode01Lengths.of(0x34), 4);
      expect(Mode01Lengths.of(0x44), 2);
      expect(Mode01Lengths.of(0x49), 1);
    });

    test('has none for what it is not sure of', () {
      expect(Mode01Lengths.of(0x64), isNull);
      expect(Mode01Lengths.of(0xA0), isNull);
      expect(Mode01Lengths.of(0xFF), isNull);
    });

    test('knows the mask PIDs', () {
      for (final pid in [0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0]) {
        expect(Mode01Lengths.isSupportMask(pid), isTrue);
      }
      expect(Mode01Lengths.isSupportMask(0x0C), isFalse);
    });
  });

  group('walk', () {
    test('reads PIDs one after another', () {
      // 41, rpm 0C (2), speed 0D (1), timing 0E (1), pedal 49 (1).
      final r = Mode01Lengths.walk([
        0x41, 0x0C, 0x11, 0x10, 0x0D, 0x00, 0x0E, 0x88, 0x49, 0x33, //
      ]);

      expect(r.complete, isTrue);
      expect(r.values.map((v) => v.$1), [0x0C, 0x0D, 0x0E, 0x49]);
      expect(r.values.map((v) => v.$2), [
        [0x11, 0x10],
        [0x00],
        [0x88],
        [0x33],
      ]);
    });

    test('is incomplete when the data is cut short', () {
      final r = Mode01Lengths.walk([0x41, 0x0D, 0x05, 0x0C, 0x11]);

      expect(r.complete, isFalse);
      expect(r.values.map((v) => v.$1), [0x0D]);
      expect(r.values.single.$2, [0x05]);
    });

    test('stops at a PID it does not know, and says so', () {
      final r = Mode01Lengths.walk([0x41, 0x0D, 0x05, 0xA4, 1, 2, 3, 4]);

      expect(r.complete, isFalse);
      expect(r.values, hasLength(1));
    });

    test('is not an answer if it does not begin with 41', () {
      expect(Mode01Lengths.walk([0x7F, 0x01, 0x12]).complete, isFalse);
      expect(Mode01Lengths.walk([0x41]).values, isEmpty);
      expect(Mode01Lengths.walk([]).complete, isFalse);
    });
  });
}

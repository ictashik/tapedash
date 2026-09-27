// The detented odometer numerals (DESIGN.md 5.6 and 14.2): the detent, the carries
// that happen only while a column rolls from 9 to 0, and digits that stay anchored
// on the ones column.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/motion/odometer.dart';

/// One sprite of a layout, for reading in a test.
class _Sprite {
  const _Sprite(this.column, this.digit, this.offset, this.alpha);

  final int column;
  final int digit;
  final double offset;
  final double alpha;

  @override
  String toString() => 'column $column digit $digit at $offset (alpha $alpha)';
}

List<_Sprite> _sprites(OdometerLayout layout) => [
  for (var i = 0; i < layout.count; i++)
    _Sprite(
      layout.column[i],
      layout.digit[i],
      layout.offset[i],
      layout.alpha[i],
    ),
];

/// The layout of [value], as sprites.
List<_Sprite> _at(double value, {int digits = 3, int decimals = 0}) {
  final layout = OdometerLayout(integerDigits: digits, decimals: decimals)
    ..layout(value);
  return _sprites(layout);
}

/// The digits showing at rest, left to right, as the number reads.
String _reads(double value, {int digits = 3, int decimals = 0}) {
  final sprites = _at(value, digits: digits, decimals: decimals)
    ..sort((a, b) => b.column.compareTo(a.column));
  return sprites
      .where((s) => s.alpha == 1 && s.offset == 0)
      .map((s) => s.digit)
      .join();
}

void main() {
  group('detent (DESIGN.md 5.6)', () {
    test('is 0 below 0.3 and 1 above 0.7', () {
      for (final f in [0.0, 0.1, 0.25, 0.2999]) {
        expect(Odometer.detent(f), 0, reason: '$f');
      }
      for (final f in [0.7001, 0.75, 0.9, 0.9999]) {
        expect(Odometer.detent(f), 1, reason: '$f');
      }
    });

    test('is a smoothstep through the middle 0.4', () {
      expect(Odometer.detent(0.3), 0);
      expect(Odometer.detent(0.5), closeTo(0.5, 1e-12));
      expect(Odometer.detent(0.7), 1);
      // smoothstep(0.25) = 0.15625
      expect(
        Odometer.detent(0.4),
        closeTo(0.25 * 0.25 * (3 - 2 * 0.25), 1e-12),
      );
    });

    test('is monotonic, and has no jump at the edges', () {
      var last = -1.0;
      for (var i = 0; i <= 1000; i++) {
        final d = Odometer.detent(i / 1000);
        expect(d, greaterThanOrEqualTo(last));
        last = d;
      }
      expect(
        (Odometer.detent(0.3001) - Odometer.detent(0.3)).abs(),
        lessThan(1e-5),
      );
      expect(
        (Odometer.detent(0.7) - Odometer.detent(0.6999)).abs(),
        lessThan(1e-5),
      );
    });

    test('is symmetric about the middle', () {
      for (final x in [0.05, 0.1, 0.2, 0.3, 0.45]) {
        expect(
          Odometer.detent(0.5 + x) + Odometer.detent(0.5 - x),
          closeTo(1, 1e-12),
        );
      }
    });

    test('a digit rests for the first and last 30% of its interval', () {
      var resting = 0;
      for (var i = 0; i < 1000; i++) {
        final d = Odometer.detent(i / 1000);
        if (d == 0 || d == 1) resting++;
      }

      expect(resting, closeTo(600, 5));
    });
  });

  group('the glyphs of a value', () {
    test('a whole number rests: one glyph per digit, centred and opaque', () {
      final sprites = _at(87);

      expect(sprites, hasLength(2));
      for (final s in sprites) {
        expect(s.offset, 0);
        expect(s.alpha, 1);
      }
      expect(_reads(87), '87');
    });

    test('reads as the number, for whole values across the range', () {
      for (final v in [
        0,
        1,
        7,
        9,
        10,
        19,
        20,
        99,
        100,
        101,
        107,
        199,
        200,
        555,
        999,
      ]) {
        expect(_reads(v.toDouble()), '$v', reason: '$v');
      }
    });

    test('no leading zeros, but the ones digit is always there', () {
      expect(_at(7), hasLength(1));
      expect(_at(77), hasLength(2));
      expect(_at(107), hasLength(3));
      expect(_reads(0), '0');
      expect(_at(0), hasLength(1));
    });

    test('a zero inside a number is drawn', () {
      expect(_reads(107), '107');
      expect(_reads(100), '100');
    });

    test(
      'decimals: the units digit is drawn even when it is a leading zero',
      () {
        expect(_reads(0.5, digits: 2, decimals: 1), '05');
        expect(_reads(12.3, digits: 2, decimals: 1), '123');
        expect(_at(0.5, digits: 2, decimals: 1), hasLength(2));
        expect(_at(0.0, digits: 2, decimals: 1), hasLength(2), reason: '0.0');
      },
    );

    test(
      'the value snaps to the digit it rests on: 3.2 reads 3, 3.8 reads 4',
      () {
        expect(_reads(3.2), '3');
        expect(_reads(3.29), '3');
        expect(_reads(3.71), '4');
        expect(_reads(3.8), '4');
      },
    );

    test(
      'through the middle it rolls: at 3.5 the 3 is half way up and the 4 half way in',
      () {
        final sprites = _at(3.5);

        expect(sprites, hasLength(2));
        final three = sprites.firstWhere((s) => s.digit == 3);
        final four = sprites.firstWhere((s) => s.digit == 4);
        expect(
          three.offset,
          closeTo(-0.5, 1e-9),
          reason: 'the old digit leaves upwards',
        );
        expect(
          four.offset,
          closeTo(0.5, 1e-9),
          reason: 'the new one comes in from below',
        );
        expect(three.alpha, closeTo(0.5, 1e-9));
        expect(four.alpha, closeTo(0.5, 1e-9));
      },
    );

    test(
      'a falling value rolls down: the same picture, with the lower digit leaving',
      () {
        // 4.5 falling to 3.5 is drawn as 3.5 is: the 4 is below, the 3 above,
        // and as the value falls further the 3 moves down to the centre.
        final atFour = _at(3.6).firstWhere((s) => s.digit == 3).offset;
        final atThree = _at(3.4).firstWhere((s) => s.digit == 3).offset;

        expect(
          atFour,
          lessThan(atThree),
          reason: 'the 3 is nearer the centre as it falls',
        );
        expect(
          atThree,
          lessThan(0),
          reason: 'the 3 is above the centre, waiting to come down',
        );
      },
    );

    test('a rising value moves its glyphs up', () {
      var lastOffset = 1.0;
      for (var i = 0; i <= 10; i++) {
        final v = 3 + 0.3 + 0.04 * i; // through the roll from 3 to 4
        final three = _at(v).where((s) => s.digit == 3);
        if (three.isEmpty) continue;
        expect(three.first.offset, lessThanOrEqualTo(lastOffset));
        lastOffset = three.first.offset;
      }
      expect(lastOffset, lessThan(0));
    });

    test('glyph alpha falls to 0 a whole cell from the centre', () {
      expect(Odometer.fade(0), 1);
      expect(Odometer.fade(0.5), 0.5);
      expect(Odometer.fade(-0.5), 0.5);
      expect(Odometer.fade(1), 0);
      expect(Odometer.fade(-3), 0);
    });

    test('there are never more than two glyphs in a column', () {
      final layout = OdometerLayout(integerDigits: 4);
      for (var v = 0.0; v < 2000; v += 0.37) {
        layout.layout(v);
        final perColumn = <int, int>{};
        for (var i = 0; i < layout.count; i++) {
          perColumn[layout.column[i]] = (perColumn[layout.column[i]] ?? 0) + 1;
        }
        for (final n in perColumn.values) {
          expect(n, lessThanOrEqualTo(2), reason: 'at $v');
        }
      }
    });
  });

  group('carries', () {
    test(
      'a higher column rolls only while the column below rolls from 9 to 0',
      () {
        final layout = OdometerLayout(integerDigits: 4);
        for (var v = 0.0; v < 1300; v += 0.013) {
          layout.layout(v);
          for (var k = 1; k < 4; k++) {
            final below = layout.positions[k - 1];
            final rolling = layout.positions[k] % 1 != 0;
            final belowRestOfTen = below % 10;
            final nineToZero = belowRestOfTen > 9;
            if (rolling) {
              expect(
                nineToZero,
                isTrue,
                reason:
                    'column $k rolls at $v while column ${k - 1} is at $belowRestOfTen',
              );
            }
          }
        }
      },
    );

    test('and in sync with it: the fractions match', () {
      final layout = OdometerLayout(integerDigits: 4);
      for (final v in [9.4, 9.5, 9.6, 99.5, 99.6, 999.5, 199.5, 1099.6]) {
        layout.layout(v);
        final ones = layout.positions[0] % 1;
        for (var k = 1; k < 4; k++) {
          final p = layout.positions[k];
          if (p % 1 != 0) {
            expect(p % 1, closeTo(ones, 1e-9), reason: 'column $k at $v');
          }
        }
      }
    });

    test('9 to 10 rolls both columns together', () {
      final sprites = _at(9.5);

      final ones = sprites.where((s) => s.column == 0);
      final tens = sprites.where((s) => s.column == 1);
      expect(ones.map((s) => s.digit).toSet(), {9, 0});
      expect(
        tens.length,
        1,
        reason: 'the blank above is not drawn, only the 1 rolling in',
      );
      expect(tens.single.digit, 1);
      expect(tens.single.alpha, closeTo(0.5, 1e-9));
      expect(tens.single.offset, closeTo(0.5, 1e-9));
    });

    test('a carry runs through several columns at once: 199 to 200', () {
      final layout = OdometerLayout(integerDigits: 3)..layout(199.5);

      for (var k = 0; k < 3; k++) {
        expect(
          layout.positions[k] % 1,
          closeTo(0.5, 1e-9),
          reason: 'column $k',
        );
      }
      final hundreds = _sprites(
        layout,
      ).where((s) => s.column == 2).map((s) => s.digit).toSet();
      expect(hundreds, {1, 2});
    });

    test('a column that is not carrying stays exactly where it was', () {
      final layout = OdometerLayout(integerDigits: 3);
      layout.layout(120.0);
      final tens = layout.positions[1];

      layout.layout(125.0);
      layout.layout(129.29);

      expect(
        layout.positions[1],
        tens,
        reason: 'the tens do not move while the ones go 0 to 9',
      );
    });

    test('the number never reads a wrong digit at rest, over a long climb', () {
      for (var v = 0; v <= 999; v++) {
        expect(_reads(v.toDouble()), '$v');
      }
    });

    test('positions never go backwards as the value rises', () {
      final layout = OdometerLayout(integerDigits: 3);
      final last = List<double>.filled(3, -1);
      for (var v = 0.0; v < 999; v += 0.07) {
        layout.layout(v);
        for (var k = 0; k < 3; k++) {
          expect(
            layout.positions[k],
            greaterThanOrEqualTo(last[k] - 1e-9),
            reason: 'column $k at $v',
          );
          last[k] = layout.positions[k];
        }
      }
    });
  });

  group('anchoring (DESIGN.md 4.5)', () {
    test('the ones digit is always in column 0, whatever the value', () {
      for (final v in [7.0, 77.0, 107.0, 0.0, 999.0]) {
        final ones = _at(v).where((s) => s.column == 0);
        expect(ones, hasLength(1), reason: '$v');
      }
    });

    test('7, 77 and 107 grow leftwards from the same column', () {
      final columnsOf = {
        for (final v in [7.0, 77.0, 107.0])
          v: (_at(v).map((s) => s.column).toList()..sort()),
      };

      expect(columnsOf[7.0], [0]);
      expect(columnsOf[77.0], [0, 1]);
      expect(columnsOf[107.0], [0, 1, 2]);
    });

    test('with decimals the last decimal is the ones column', () {
      final sprites = _at(107.3, digits: 3, decimals: 1);

      expect(sprites.where((s) => s.column == 0).single.digit, 3);
      expect(sprites.map((s) => s.column).toSet(), {0, 1, 2, 3});
    });
  });

  group('range', () {
    test('a value too big shows nines in every column', () {
      expect(_reads(1e9), '999');
      expect(_reads(1000), '999');
    });

    test('a negative value shows its size; the sign is the caller\'s', () {
      expect(_reads(-42), '42');
    });

    test('NaN counts as 0, and infinity as the largest', () {
      expect(_reads(double.nan), '0');
      expect(_reads(double.infinity), '999');
      expect(_reads(double.negativeInfinity), '999');
    });

    test('maxValue is nines, with decimals', () {
      expect(OdometerLayout(integerDigits: 3).maxValue, 999);
      expect(
        OdometerLayout(integerDigits: 2, decimals: 1).maxValue,
        closeTo(99.9, 1e-9),
      );
    });

    test(
      'a value between the top of the range and the next detent stays at the top',
      () {
        final layout = OdometerLayout(integerDigits: 2)..layout(99.8);

        expect(
          _sprites(layout).every((s) => s.digit == 9 || s.offset != 0),
          isTrue,
        );
        expect(layout.positions[0], lessThanOrEqualTo(99 + 1e-9));
      },
    );

    test(
      'presence is 0 for a leading zero, 1 for a digit, and rises as one rolls in',
      () {
        final layout = OdometerLayout(integerDigits: 3);

        layout.layout(7);
        expect(layout.presence(1), 0);
        layout.layout(77);
        expect(layout.presence(1), 1);
        layout.layout(9.5);
        expect(layout.presence(1), closeTo(0.5, 1e-9));
      },
    );
  });

  test('the layout allocates nothing per call', () {
    final layout = OdometerLayout(integerDigits: 3, decimals: 1);
    final lists = [
      layout.positions,
      layout.column,
      layout.digit,
      layout.offset,
      layout.alpha,
    ];

    for (var i = 0; i < 100; i++) {
      layout.layout(math.Random(i).nextDouble() * 999);
    }

    expect(
      [
        layout.positions,
        layout.column,
        layout.digit,
        layout.offset,
        layout.alpha,
      ],
      [for (final l in lists) same(l)],
    );
  });
}

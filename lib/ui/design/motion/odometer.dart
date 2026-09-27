import 'dart:math' as math;
import 'dart:typed_data';

import '../tokens/motion_tokens.dart';

/// How live numerals roll (DESIGN.md 5.6): a digit rests centred most of the
/// time and rolls briskly through the change, readable like a digital display and
/// alive like a mechanical one.
///
/// Each digit column is a vertical cylinder of glyphs 0 to 9. Everything here is
/// value-driven: a pure function of the smoothed value, with no time in it.
abstract final class Odometer {
  /// The detent of DESIGN.md 5.6, for the fraction [f] of the way from one whole
  /// number to the next: 0 for f below 0.3, a smoothstep through 0.3 to 0.7, and
  /// 1 above. The ones column sits at `n + detent(f)`.
  static double detent(double f) {
    if (f <= TapeMotion.detentStart) return 0;
    if (f >= TapeMotion.detentEnd) return 1;
    final x =
        (f - TapeMotion.detentStart) /
        (TapeMotion.detentEnd - TapeMotion.detentStart);
    return x * x * (3 - 2 * x);
  }

  /// How opaque a glyph [distance] cells from the centre of the window is: 1 at
  /// the centre, 0 a whole cell away. Alpha is set per glyph; there is no clip
  /// mask (DESIGN.md 5.6).
  static double fade(double distance) {
    final d = distance.abs() / TapeMotion.odometerFadeDistance;
    return d >= 1 ? 0 : 1 - d;
  }
}

/// The glyphs of a rolling number, and where each is, for one value.
///
/// It is the layout of DESIGN.md 5.6 with its carries: a column above the ones
/// rolls only while the column below it is rolling from 9 to 0, in sync with it,
/// like a mechanical odometer. It allocates nothing after it is made, so it can
/// be run every frame.
///
/// [layout] fills [count] sprites. Sprite `i` is the digit [digit]`[i]` in
/// column [column]`[i]` (0 is the ones column, or the last decimal), [offset]`[i]`
/// cells from the centre of its window (positive is below, so a rising value
/// moves its glyphs up), at opacity [alpha]`[i]`.
class OdometerLayout {
  OdometerLayout({required this.integerDigits, this.decimals = 0})
    : columns = integerDigits + decimals,
      _scale = math.pow(10, decimals).toDouble(),
      _maxScaled = math.pow(10, integerDigits + decimals).toDouble() - 1,
      positions = Float64List(integerDigits + decimals),
      column = Uint8List(2 * (integerDigits + decimals)),
      digit = Uint8List(2 * (integerDigits + decimals)),
      offset = Float32List(2 * (integerDigits + decimals)),
      alpha = Float32List(2 * (integerDigits + decimals)) {
    assert(integerDigits >= 1);
    assert(decimals >= 0);
  }

  /// The most integer digits it shows: the box a readout reserves.
  final int integerDigits;

  /// The digits after the decimal point.
  final int decimals;

  /// All the digit columns, decimals included.
  final int columns;

  final double _scale;
  final double _maxScaled;

  /// Where each column's cylinder is, in glyph units (0 is the ones column).
  /// After [layout], a column at rest holds a whole number.
  final Float64List positions;

  int count = 0;
  final Uint8List column;
  final Uint8List digit;
  final Float32List offset;
  final Float32List alpha;

  /// The largest value that fits: nines in every column.
  double get maxValue => _maxScaled / _scale;

  /// Lays out [value]. It is clamped to what fits, and NaN counts as 0. The sign
  /// is the caller's: this shows the size of the number.
  void layout(double value) {
    var scaled = value.isNaN ? 0.0 : value.abs() * _scale;
    if (scaled > _maxScaled) scaled = _maxScaled;

    final whole = scaled.floorToDouble();
    var p = whole + Odometer.detent(scaled - whole);
    var n = 0;
    for (var k = 0; k < columns; k++) {
      if (k > 0) {
        // Carry: the tens the column below has passed, and how far through its
        // 9 to 0 roll it is.
        final tens = (p / 10).floorToDouble();
        final rest = p - tens * 10;
        p = tens + (rest > 9 ? rest - 9 : 0);
      }
      positions[k] = p;

      final low = p.floorToDouble();
      for (var side = 0; side < 2; side++) {
        final glyph = low + side;
        final distance = glyph - p;
        final a = Odometer.fade(distance);
        if (a <= 0) continue;
        // A leading zero is not drawn. The ones digit of the number always is.
        if (glyph == 0 && k > decimals) continue;
        column[n] = k;
        digit[n] = (glyph % 10).toInt();
        offset[n] = distance;
        alpha[n] = a;
        n++;
      }
    }
    count = n;
  }

  /// How present the digit in [column] is, 0 to 1: 0 while it is a leading zero,
  /// and rising to 1 as a digit rolls in. A group separator to the left of the
  /// column shows only as far as this does.
  double presence(int column) {
    final p = positions[column];
    return p >= 1 ? 1 : p;
  }
}

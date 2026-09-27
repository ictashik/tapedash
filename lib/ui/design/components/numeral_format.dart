import 'package:flutter/widgets.dart';

import '../theme/palette.dart';
import '../tokens/typography.dart';

/// How digits are grouped in a number (DESIGN.md 10): Indian for money
/// (₹1,23,456), and the western thousands where the app shows counts.
enum DigitGrouping {
  none,
  indian,
  western;

  /// Whether a separator sits between digit [i] and the one to its right, where
  /// digit 0 is the units digit.
  bool separatorAfter(int i) => switch (this) {
    none => false,
    western => i > 0 && i % 3 == 0,
    indian => i >= 3 && (i - 3).isEven,
  };
}

/// The box a readout reserves for its number (DESIGN.md 4.5): how many integer
/// digits, how many decimals, how they are grouped.
@immutable
class NumeralFormat {
  const NumeralFormat({
    required this.integerDigits,
    this.decimals = 0,
    this.grouping = DigitGrouping.none,
    this.signed = false,
  });

  /// The most integer digits shown. A larger value shows nines.
  final int integerDigits;

  /// The digits after the decimal point. The last is the ones column of the roll.
  final int decimals;

  final DigitGrouping grouping;

  /// Whether a negative value is shown with a minus sign (U+2212).
  final bool signed;

  @override
  bool operator ==(Object other) =>
      other is NumeralFormat &&
      other.integerDigits == integerDigits &&
      other.decimals == decimals &&
      other.grouping == grouping &&
      other.signed == signed;

  @override
  int get hashCode => Object.hash(integerDigits, decimals, grouping, signed);
}

/// Which colour a numeral is drawn in: a role, resolved against the theme, so that
/// Daylight and Night can change it (DESIGN.md 4.3 and 4.4).
enum NumeralRole {
  /// Live primary data: the livery's accent.
  accent,

  /// Primary values that are not in the accent.
  bright,

  /// Secondary values.
  mid,

  /// Anything that should recede.
  dim,

  /// Money: champagne.
  money,

  /// Needs attention.
  caution,

  /// Act now.
  critical;

  Color colorIn(TapePalette palette) => switch (this) {
    accent => palette.numeral,
    bright => palette.inkBright,
    mid => palette.inkMid,
    dim => palette.inkDim,
    money => palette.money,
    caution => palette.caution,
    critical => palette.critical,
  };

  /// The colour of its halo.
  Color glowIn(TapePalette palette) => switch (this) {
    accent || bright || mid || dim => palette.accentGlow,
    money => palette.moneyGlow,
    caution => palette.caution,
    critical => palette.critical,
  };
}

/// The measurements of a rolling readout at a font size, for laying out what is
/// around it.
class NumeralMetrics {
  const NumeralMetrics(this.size);

  /// The font size, in logical pixels.
  final double size;

  /// How far apart the digits of a rolling column are.
  double get pitch => TapeType.digitPitchEm * size;

  /// The height of a digit's ink.
  double get inkHeight => TapeType.digitHeightEm * size;

  /// The height of the readout's box: two pitches, so that a digit rolling out
  /// of the window is still inside it, since nothing is clipped.
  double get boxHeight => 2 * pitch;

  /// The baseline, from the top of the box: digits are centred in it.
  double get baseline =>
      boxHeight / 2 + TapeType.digitAboveBaselineEm * size / 2;

  /// The distance from the top of the box to the top of the digits' ink.
  double get inkTop => baseline - TapeType.digitAboveBaselineEm * size;
}

import 'dart:math' as math;

/// Whether the drive screens are laid out for a phone or for a watch
/// (DESIGN.md 16.2).
enum FormFactor {
  phone,
  watch;

  /// A screen whose shorter side is under [TapeWatch.watchBelow] lp is a watch,
  /// where the platform cannot say so itself (an emulator, a test).
  static FormFactor ofSize(double width, double height) =>
      math.min(width, height) < TapeWatch.watchBelow ? watch : phone;
}

/// The watch's round face (DESIGN.md 16), as shares of its diameter **D**. One
/// set of shares serves every watch: no dimension here is a pixel count.
abstract final class TapeWatch {
  /// A shorter side under this many lp is a watch.
  static const double watchBelow = 300;

  /// The diameter the design is authored at (a 46 mm Galaxy Watch4 Classic) and
  /// the ones it is checked at (DESIGN.md 16.2).
  static const double authoredDiameter = 225;
  static const List<double> checkedDiameters = [192, 198, 225, 240, 280];

  /// The core: the disc inside the rim, kept a margin clear of its inner edge.
  static const double coreShare = 0.37;

  // Where things sit down the face, as the share of D from the top to their
  // centre (DESIGN.md 16.3).

  /// The link glyphs, in the crown.
  static const double crownY = 0.185;

  /// The hero speed's digits.
  static const double heroY = 0.455;

  /// The ₹ readout of the Drive face, in the foot.
  static const double footY = 0.725;

  /// The page tape's ticks, above the rim's opening.
  static const double tapeY = 0.855;

  /// The gap between the hero's ink and the unit under it, in lp of label size.
  static const double unitGap = 0.25;

  /// The money ring (DESIGN.md 16.5): this many cells round the rim, printed
  /// clockwise from 12 o'clock, each one ₹1 until they run out and then ₹2, ₹5,
  /// ₹10 and so on.
  static const int moneyCells = 72;
  static const List<int> moneyScales = [
    1,
    2,
    5,
    10,
    20,
    50,
    100,
    200,
    500,
    1000,
  ];

  /// A money cell fills this share of its angular slot.
  static const double moneyCellFill = 0.72;

  /// The eco arc in the rim's opening (DESIGN.md 16.5): the span either side of
  /// 6 o'clock the puck rides over, and the track's thickness as a share of D.
  static const double ecoSpanDegrees = 22;
  static const double ecoTrackShare = 0.014;
  static const double ecoPuckShare = 0.034;

  /// The lowest numeral weight on a watch (DESIGN.md 16.4): a Light face
  /// disappears at an angle on a moving wrist.
  static const double minNumeralWeight = 500;

  /// A wheel's row is this tall (DESIGN.md 16.7), and the rows either side of the
  /// chosen one are drawn at this share of its size.
  static const double wheelRow = 56;
  static const double wheelNeighbourScale = 0.7;

  /// Two bezel detents closer together than this are a quick turn, and a dial
  /// then steps its fast stride (DESIGN.md 16.7).
  static const Duration quickTurn = Duration(milliseconds: 90);

  /// A hold to confirm takes this long, in seconds (DESIGN.md 16.7).
  static const double holdSeconds = 1.2;

  /// A watch is called hot, and too hot, at these battery temperatures, in °C
  /// (DESIGN.md 16.9). A watch gets hot sooner than a phone.
  static const double hotAt = 41;
  static const double tooHotAt = 45;
}

/// The sizes of type on the watch (DESIGN.md 16.4).
class WatchType {
  const WatchType._({
    required this.hero,
    required this.display,
    required this.primary,
    required this.secondary,
    required this.label,
  });

  /// The scale for a face [diameter] lp across.
  factory WatchType.forDiameter(double diameter) => WatchType._(
    hero: _scaled(diameter, 0.32, 56, 104),
    display: _scaled(diameter, 0.21, 36, 68),
    primary: _scaled(diameter, 0.13, 24, 40),
    secondary: _scaled(diameter, 0.09, 17, 28),
    label: _scaled(diameter, 0.062, 12, 16),
  );

  /// Speed.
  final double hero;

  /// ₹ this trip on the Money face.
  final double display;

  /// The ₹ on the Drive face, and a wheel's chosen row.
  final double primary;

  /// ₹/km, and a wheel's other rows.
  final double secondary;

  /// Instrument labels. Never under 12 lp.
  final double label;

  static double _scaled(double d, double share, double min, double max) =>
      math.min(max, math.max(min, d * share));
}

/// The tach arc's geometry (DESIGN.md 6.2). Angles are in the maths convention
/// (0° east, 90° north, counter-clockwise positive); painters negate them for
/// Flutter's y-down canvas.
abstract final class TapeTach {
  /// The sweep: 240°, opening at the bottom. 0 rpm sits at the lower-left,
  /// maximum rpm at the lower-right, through the top.
  static const double startDegrees = 210;
  static const double sweepDegrees = 240;
  static const double endDegrees = startDegrees - sweepDegrees; // -30

  /// The arc's radius, as a share of the screen height. In the Apex cluster the
  /// hero may scale to 0.28H so it clears the arc's inner edge by 0.04H.
  static const double radiusShareOfHeight = 0.44;

  /// A segment's radial depth, as a share of H.
  static const double segmentDepthShareOfHeight = 0.06;

  /// The needle blade spans this band, as a multiple of the arc's radius.
  static const double needleInner = 0.92;
  static const double needleOuter = 1.06;

  /// The needle core's stroke, in logical pixels, and its halo strength.
  static const double needleCoreStroke = 2;
  static const double needleHaloStrength = 0.60;

  /// A major tick falls every this many rpm, and reaches this far past the
  /// segment band, as a share of H.
  static const double majorTickEveryRpm = 1000;
  static const double majorTickLengthShareOfHeight = 0.03;
  static const double minorTickLengthShareOfHeight = 0.015;

  /// Unlit segments at or above the redline still carry this much tint.
  static const double redlineGhostTint = 0.20;

  /// Default range, for a profile that has not set its own (DESIGN.md 7.7's
  /// simulator default): 0 to 7,000, shift/redline at 6,500.
  static const double defaultMaxRpm = 7000;
  static const double defaultRedlineRpm = 6500;
}

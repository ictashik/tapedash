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

  /// The Parked choreography (DESIGN.md 7.2): the arc dims to this share of
  /// its brightness, and its segments thin to this share of their depth --
  /// "thins and dims to 60%", both effects to the same 60%.
  static const double parkedBrightness = 0.60;
  static const double parkedDepthShare = 0.60;

  /// Default range, for a profile that has not set its own (DESIGN.md 7.7's
  /// simulator default): 0 to 7,000, shift/redline at 6,500.
  static const double defaultMaxRpm = 7000;
  static const double defaultRedlineRpm = 6500;
}

/// The shift horizon's geometry (DESIGN.md 6.4): a thin band across the top
/// edge, 24 segments per side converging towards the centre.
abstract final class TapeShiftHorizon {
  /// The band's height, as a share of H.
  static const double heightShareOfHeight = 0.018;

  static const int segmentsPerSide = 24;

  /// It starts filling this many rpm below the shift point, and is fully lit
  /// at the shift point itself.
  static const double fillsOverRpm = 1500;

  /// Segment position thresholds (as a share of the way from the outer edge to
  /// the centre): the first share is the accent colour, the next is caution,
  /// the rest is critical.
  static const double accentShare = 0.60;
  static const double cautionShare = 0.25;
  // The remaining 0.15 is critical.

  /// At or above the shift point every segment flashes critical, at the
  /// fastest rate DESIGN.md 11 allows.
  static const double flashHz = 3;

  /// The breathing glow of a CVT or automatic profile (shift light off): its
  /// width at idle and at the redline, as a share of the half-band's width.
  static const double breathingMinShare = 0.06;
  static const double breathingMaxShare = 1.0;
}

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

  /// How far the arc's centre sits below the screen's centre, as a share of the
  /// height, so the top labels clear the screen edge and the arc's lowest
  /// segments stay above the parked dock.
  static const double centreDropShare = 0.03;

  /// The gap between the hero digits' ink and the unit label under them, as a
  /// share of the height.
  static const double unitGapShare = 0.02;

  /// The watch's rim (DESIGN.md 16.3), as shares of the face's diameter: the
  /// band's outer edge, its depth, and the major ticks inside it.
  static const double rimOuterShare = 0.485;
  static const double rimDepthShare = 0.07;
  static const double rimTickShare = 0.02;
}

/// The sizes of one tach arc, in logical pixels: the phone's, which are shares of
/// the screen's height (DESIGN.md 6.2), or the watch's rim, which are shares of the
/// face's diameter (DESIGN.md 16.3).
class TachGeometry {
  const TachGeometry({
    required this.radius,
    required this.depth,
    required this.box,
    required this.tickLength,
    required this.glowHeight,
    required this.glowSigma,
    this.labels = true,
  });

  /// The phone's: radius 0.44H, segments 0.06H deep, with ticks and labels
  /// outside the arc, in a box that holds them all.
  factory TachGeometry.forHeight(double h) {
    final radius = TapeTach.radiusShareOfHeight * h;
    final depth = TapeTach.segmentDepthShareOfHeight * h;
    final tick = TapeTach.majorTickLengthShareOfHeight * h;
    return TachGeometry(
      radius: radius,
      depth: depth,
      box: 2 * (radius + depth / 2 + tick + 0.09 * h),
      tickLength: tick,
      glowHeight: h * 0.01,
      glowSigma: h * 0.015,
    );
  }

  /// The watch's rim: the arc is the outer band of a face of [diameter], its
  /// segments [TapeTach.rimDepthShare] deep, its ticks inside the band and no
  /// numbers (a round face has no room outside the ring).
  factory TachGeometry.rim(double diameter) {
    final depth = TapeTach.rimDepthShare * diameter;
    return TachGeometry(
      radius: TapeTach.rimOuterShare * diameter - depth / 2,
      depth: depth,
      box: diameter,
      tickLength: TapeTach.rimTickShare * diameter,
      glowHeight: diameter * 0.012,
      glowSigma: diameter * 0.018,
      labels: false,
    );
  }

  /// The radius of the middle of the segment band.
  final double radius;

  /// A segment's radial depth.
  final double depth;

  /// The side of the square the arc is drawn in.
  final double box;

  /// A major tick's length: outside the band with a label (the phone), inside
  /// the band without one (the watch).
  final double tickLength;

  /// The needle's halo sprite: its height and blur.
  final double glowHeight;
  final double glowSigma;

  /// Whether the major ticks carry their numbers and the arc its unit.
  final bool labels;
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

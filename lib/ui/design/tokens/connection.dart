/// The connection states' geometry and motion (DESIGN.md 7.12).
abstract final class TapeConnection {
  /// Standby (searching, waiting for ignition): the cluster is etch only,
  /// at this share of its brightness. The scrim over it is the rest.
  static const double standbyBrightness = 0.15;

  /// The status strip stays readable in standby: the adapter glyph is the
  /// one live thing on the screen, so the scrim leaves its two corners alone
  /// (the glyph columns on the left, the clock on the right).
  static const double stripBandHeight = 44;
  static const double stripLeftWidth = 160;
  static const double stripRightWidth = 100;

  /// The sweep beam turns once in this long, while searching.
  static const double sweepSeconds = 1.6;

  /// The beam's lit head and its fading trail, in degrees, and how many
  /// arcs the trail is batched into.
  static const double sweepTrailDegrees = 70;
  static const int sweepTrailSteps = 14;

  /// The beam's stroke, as a share of the arc's own depth.
  static const double sweepStrokeShareOfHeight = 0.012;

  /// The waiting dot breathes at this rate, between the two alphas, and its
  /// radius is a share of the height.
  static const double breathHz = 0.25;
  static const double breathAlphaMin = 0.25;
  static const double breathAlphaMax = 1.0;
  static const double dotRadiusShareOfHeight = 0.02;

  /// The status line sits this far below the centre, as a share of the
  /// height.
  static const double lineOffsetShareOfHeight = 0.16;
  static const double lineSize = 14;

  /// Lost: the caution line on the horizon (the shift horizon's own
  /// footprint, half the width, at the top), its thickness a share of the
  /// height.
  static const double cautionLineWidthShare = 0.5;
  static const double cautionLineShareOfHeight = 0.008;

  /// The re-light on reconnection (DESIGN.md 7.12): 300 ms, a ring at the
  /// arc's radius that rises to its peak by [relightPeak] of the way and
  /// falls away, in place of the full ignition sweep.
  static const double relightStrokeShareOfHeight = 0.005;
  static const Duration relight = Duration(milliseconds: 300);
  static const double relightPeak = 0.35;
}

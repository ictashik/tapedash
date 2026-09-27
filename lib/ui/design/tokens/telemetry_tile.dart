/// The telemetry tile's geometry (DESIGN.md 6.6).
abstract final class TapeTelemetryTile {
  /// The sparkline covers the lower share of the tile.
  static const double sparklineShare = 0.55;

  /// 60 s at 2 Hz: a ring buffer of 120 points.
  static const int sparklinePoints = 120;
  static const Duration sampleInterval = Duration(milliseconds: 500);

  static const double lineWidth = 1.5;
  static const double fillAlpha = 0.08;

  /// The corner bracket's arm length, matching DESIGN.md 4.6's 10-14 lp.
  static const double bracketArm = 12;
}

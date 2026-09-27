/// The bar gauge's geometry (DESIGN.md 6.5).
abstract final class TapeBarGauge {
  /// The track's thickness, in logical pixels, unless a caller asks for
  /// another.
  static const double defaultThickness = 14;

  /// The chamfer on the track and the fill, as a share of the thickness.
  static const double chamferShareOfThickness = 0.3;

  /// The leading-edge line's width.
  static const double edgeLineWidth = 2;

  /// The normal band is etched at this alpha over the track.
  static const double bandAlpha = 0.35;
}

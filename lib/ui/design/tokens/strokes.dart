/// Stroke widths, in logical pixels (DESIGN.md 4.6).
abstract final class TapeStroke {
  static const double fine = 1.5;
  static const double regular = 2;
  static const double bold = 3;

  /// The thinnest stroke on a windshield (DESIGN.md 8).
  static const double hud = 5;

  /// The width of an icon's stroke on its 24-unit grid (DESIGN.md 4.8).
  static const double icon = 1.75;

  /// Daylight mode draws every stroke 50% thicker (DESIGN.md 4.4).
  static const double daylightScale = 1.5;

  /// One physical pixel, in logical pixels, on a screen with [devicePixelRatio].
  static double hairline(double devicePixelRatio) => 1 / devicePixelRatio;

  /// Snaps a stroke's position so that it lands on whole physical pixels: a
  /// hairline drawn on a pixel boundary is one crisp line, and one drawn across
  /// two pixels is two grey ones (DESIGN.md 4.7).
  ///
  /// [coordinate] is the line's centre in logical pixels and [width] its width.
  /// A stroke an odd number of physical pixels wide is centred on a pixel, and
  /// one an even number wide on a boundary.
  static double snap(double coordinate, double width, double devicePixelRatio) {
    final physicalWidth = (width * devicePixelRatio).round();
    final physical = coordinate * devicePixelRatio;
    final snapped = physicalWidth.isOdd
        ? physical.floorToDouble() + 0.5
        : physical.roundToDouble();
    return snapped / devicePixelRatio;
  }
}

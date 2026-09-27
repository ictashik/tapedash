import 'dart:ui';

/// Snapping to the physical pixel grid (DESIGN.md 4.7): a hairline drawn across
/// two pixels is two grey lines, and a numeral drawn half a pixel off is soft.
abstract final class Pixel {
  /// [logical] moved to the nearest whole physical pixel.
  static double snap(double logical, double devicePixelRatio) =>
      (logical * devicePixelRatio).roundToDouble() / devicePixelRatio;

  /// [logical] moved down to a whole physical pixel.
  static double floor(double logical, double devicePixelRatio) =>
      (logical * devicePixelRatio).floorToDouble() / devicePixelRatio;

  /// [offset] with both coordinates snapped.
  static Offset snapOffset(Offset offset, double devicePixelRatio) => Offset(
    snap(offset.dx, devicePixelRatio),
    snap(offset.dy, devicePixelRatio),
  );

  /// [rect] with each edge snapped, so that its edges are crisp.
  static Rect snapRect(Rect rect, double devicePixelRatio) => Rect.fromLTRB(
    snap(rect.left, devicePixelRatio),
    snap(rect.top, devicePixelRatio),
    snap(rect.right, devicePixelRatio),
    snap(rect.bottom, devicePixelRatio),
  );
}

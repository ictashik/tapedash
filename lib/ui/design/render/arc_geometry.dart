import 'dart:math' as math;
import 'dart:ui';

/// Points on a circular arc, in the maths convention DESIGN.md 6.2 specifies
/// (0° east, 90° north, counter-clockwise positive), converted to Flutter's
/// y-down canvas.
abstract final class ArcGeometry {
  /// The point at [radius] from [center], at [degrees] (maths convention).
  static Offset pointAt(Offset center, double radius, double degrees) {
    final radians = degrees * math.pi / 180;
    return center +
        Offset(radius * math.cos(radians), -radius * math.sin(radians));
  }

  /// A trapezoid spanning [startDegrees] to [endDegrees] (either order), from
  /// [innerRadius] to [outerRadius], as four corners in order: inner-start,
  /// inner-end, outer-end, outer-start. Feed this to [Chamfer.polygon] for the
  /// chamfered segment shape DESIGN.md 6.2 asks for.
  static List<Offset> trapezoid(
    Offset center,
    double innerRadius,
    double outerRadius,
    double startDegrees,
    double endDegrees,
  ) => [
    pointAt(center, innerRadius, startDegrees),
    pointAt(center, innerRadius, endDegrees),
    pointAt(center, outerRadius, endDegrees),
    pointAt(center, outerRadius, startDegrees),
  ];
}

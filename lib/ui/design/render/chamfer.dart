import 'dart:math' as math;
import 'dart:ui';

/// Chamfered shapes: the signature of the design (DESIGN.md 4.6). Panels,
/// buttons, readout boxes and segments have 45 degree corners, not rounded ones.
///
/// Each builder has an `Into` form that fills a Path the caller owns, so a
/// painter can reuse one Path (`reset()`) and allocate nothing per frame
/// (DESIGN.md 9.3).
abstract final class Chamfer {
  /// [rect] with each corner cut at 45 degrees by the given size; 0 is square.
  /// A cut is limited to half of the shorter side, so opposite cuts never cross.
  static Path rect(
    Rect rect, {
    double topLeft = 0,
    double topRight = 0,
    double bottomRight = 0,
    double bottomLeft = 0,
  }) {
    final path = Path();
    rectInto(
      path,
      rect,
      topLeft: topLeft,
      topRight: topRight,
      bottomRight: bottomRight,
      bottomLeft: bottomLeft,
    );
    return path;
  }

  /// Like [rect], into [path], which is reset first.
  static void rectInto(
    Path path,
    Rect rect, {
    double topLeft = 0,
    double topRight = 0,
    double bottomRight = 0,
    double bottomLeft = 0,
  }) {
    final limit = math.min(rect.width, rect.height) / 2;
    final tl = topLeft.clamp(0, limit).toDouble();
    final tr = topRight.clamp(0, limit).toDouble();
    final br = bottomRight.clamp(0, limit).toDouble();
    final bl = bottomLeft.clamp(0, limit).toDouble();
    path
      ..reset()
      ..moveTo(rect.left + tl, rect.top)
      ..lineTo(rect.right - tr, rect.top)
      ..lineTo(rect.right, rect.top + tr)
      ..lineTo(rect.right, rect.bottom - br)
      ..lineTo(rect.right - br, rect.bottom)
      ..lineTo(rect.left + bl, rect.bottom)
      ..lineTo(rect.left, rect.bottom - bl)
      ..lineTo(rect.left, rect.top + tl)
      ..close();
  }

  /// [rect] with all four corners cut by [size].
  static Path all(Rect rect, double size) => Chamfer.rect(
    rect,
    topLeft: size,
    topRight: size,
    bottomRight: size,
    bottomLeft: size,
  );

  /// The button shape: top-left and bottom-right cut by [size], the other two
  /// corners square (DESIGN.md 4.6).
  static Path button(Rect rect, double size) =>
      Chamfer.rect(rect, topLeft: size, bottomRight: size);

  /// The same, into [path].
  static void buttonInto(Path path, Rect rect, double size) =>
      rectInto(path, rect, topLeft: size, bottomRight: size);

  /// L-shaped brackets at the four corners of [rect], with arms [arm] long. They
  /// are open paths, for stroking; they group things without boxing them in
  /// (DESIGN.md 4.6).
  static Path brackets(Rect rect, double arm) {
    final path = Path();
    bracketsInto(path, rect, arm);
    return path;
  }

  /// Like [brackets], into [path], which is reset first.
  static void bracketsInto(Path path, Rect rect, double arm) {
    final a = math.min(arm, math.min(rect.width, rect.height) / 2);
    path
      ..reset()
      ..moveTo(rect.left, rect.top + a)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.left + a, rect.top)
      ..moveTo(rect.right - a, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + a)
      ..moveTo(rect.right, rect.bottom - a)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right - a, rect.bottom)
      ..moveTo(rect.left + a, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.bottom - a);
  }

  /// A convex quadrilateral with each corner cut by [cut]: the shape of a tach
  /// segment, a trapezoid seen along an arc (DESIGN.md 6.2). [corners] are four
  /// points in order; the cut is taken along each edge, so it stays a 45 degree
  /// cut only for a right-angled corner, and is a bevel of the given length
  /// otherwise.
  static Path polygon(List<Offset> corners, double cut) {
    final path = Path();
    polygonInto(path, corners, cut);
    return path;
  }

  /// Like [polygon], into [path], which is reset first.
  static void polygonInto(Path path, List<Offset> corners, double cut) {
    path.reset();
    final n = corners.length;
    for (var i = 0; i < n; i++) {
      final previous = corners[(i + n - 1) % n];
      final corner = corners[i];
      final next = corners[(i + 1) % n];
      final toPrevious = previous - corner;
      final toNext = next - corner;
      final c = math.min(
        cut,
        math.min(toPrevious.distance, toNext.distance) / 2,
      );
      final start = corner + toPrevious / toPrevious.distance * c;
      final end = corner + toNext / toNext.distance * c;
      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      path.lineTo(end.dx, end.dy);
    }
    path.close();
  }
}

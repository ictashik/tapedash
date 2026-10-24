import 'dart:typed_data';

/// The picture of the next manoeuvre that Google Maps puts in its notification:
/// white on transparent, one picture for each kind of turn (docs/NAV.md).
///
/// Only the alpha channel is kept: it is a mask that the HUD paints in its own
/// colour, so the colour in the picture is of no use.
class NavArrow {
  const NavArrow({
    required this.id,
    required this.width,
    required this.height,
    required this.alpha,
  }) : assert(alpha.length == width * height);

  /// A name for these pixels, the same whenever the picture is the same, so that
  /// the native side can send each picture once and the UI can keep one image of
  /// it.
  final String id;
  final int width;
  final int height;

  /// [width] x [height] coverage, 0 (clear) to 255, row by row.
  final Uint8List alpha;

  @override
  bool operator ==(Object other) => other is NavArrow && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'NavArrow($id ${width}x$height)';
}

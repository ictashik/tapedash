import 'dart:math' as math;
import 'dart:ui' as ui;

import '../tokens/colors.dart';
import '../tokens/shapes.dart';
import 'chamfer.dart';

/// The seven segments of a digit, top to bottom and round the outside, with the
/// middle one last: `a` is the top bar, `b` the upper right, `c` the lower right,
/// `d` the bottom, `e` the lower left, `f` the upper left, and `g` the middle.
enum Segment { a, b, c, d, e, f, g }

/// What a seven-segment digit shows: which of its segments are lit (DESIGN.md
/// 6.17).
abstract final class SegmentMask {
  /// The mask of a digit 0 to 9, as a bit for each [Segment]: bit `a` is 1, `b`
  /// is 2, and so on.
  static int digit(int d) => _digits[d];

  /// The minus sign is the middle bar.
  static const int minus = 1 << 6;

  /// Nothing lit: a blank, showing only its ghost segments.
  static const int blank = 0;

  static bool lit(int mask, Segment segment) =>
      mask & (1 << segment.index) != 0;

  static const List<int> _digits = [
    0x3F, // 0: abcdef
    0x06, // 1: bc
    0x5B, // 2: abdeg
    0x4F, // 3: abcdg
    0x66, // 4: bcfg
    0x6D, // 5: acdfg
    0x7D, // 6: acdefg
    0x07, // 7: abc
    0x7F, // 8: all
    0x6F, // 9: abcdfg
  ];
}

/// The shapes of a seven-segment digit at one size (DESIGN.md 6.17): chamfered
/// hexagons with an 8 degree italic skew and a gap of 10% of their thickness
/// between them.
///
/// The paths are in a cell whose top-left is (0, 0). They are made once, drawn into
/// an atlas, and never built while a frame is painted.
class SevenSegmentGeometry {
  SevenSegmentGeometry._(
    this.height,
    this.width,
    this.thickness,
    this.skew,
    this.paths,
  );

  /// The height of a digit's segments, top edge to bottom edge, in logical pixels.
  final double height;

  /// The width of a digit, before the skew.
  final double width;

  final double thickness;

  /// How far the top of a digit leans to the right of its bottom.
  final double skew;

  /// The path of each [Segment], skewed.
  final Map<Segment, ui.Path> paths;

  /// The width of the cell a digit is drawn in: the digit and its lean.
  double get cellWidth => width + skew;

  /// How far the pen moves from one digit to the next: the digit, its lean and the
  /// space between digits.
  double get advance => cellWidth + TapeShape.sevenSegmentSpacing * height;

  factory SevenSegmentGeometry.forHeight(double height) {
    final width = TapeShape.sevenSegmentAspect * height;
    final t = TapeShape.sevenSegmentThickness * height;
    final tan = math.tan(TapeShape.sevenSegmentSkewDegrees * math.pi / 180);
    final skew = height * tan;
    // The gap between two segments is a share of the thickness, taken off the
    // ends of each.
    final gap = TapeShape.sevenSegmentGap * t;
    final half = t / 2;

    // Italic: each point moves right by its height above the bottom, times tan.
    ui.Offset lean(double x, double y) => ui.Offset(x + (height - y) * tan, y);

    ui.Path polygon(List<(double, double)> points) {
      final path = ui.Path();
      for (var i = 0; i < points.length; i++) {
        final p = lean(points[i].$1, points[i].$2);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      return path..close();
    }

    // A bar of the given tip-to-tip length, with 45 degree ends, centred on
    // (cx, cy). The tips are where the bar meets the ones at the corners.
    ui.Path horizontal(double cx, double cy, double length) {
      final l = length / 2;
      return polygon([
        (cx - l, cy),
        (cx - l + half, cy - half),
        (cx + l - half, cy - half),
        (cx + l, cy),
        (cx + l - half, cy + half),
        (cx - l + half, cy + half),
      ]);
    }

    ui.Path vertical(double cx, double cy, double length) {
      final l = length / 2;
      return polygon([
        (cx, cy - l),
        (cx + half, cy - l + half),
        (cx + half, cy + l - half),
        (cx, cy + l),
        (cx - half, cy + l - half),
        (cx - half, cy - l + half),
      ]);
    }

    final across = width - t - gap;
    final down = height / 2 - half - gap;
    final leftX = half;
    final rightX = width - half;
    final upperY = height / 4 + t / 4;
    final lowerY = 3 * height / 4 - t / 4;

    final paths = <Segment, ui.Path>{
      Segment.a: horizontal(width / 2, half, across),
      Segment.g: horizontal(width / 2, height / 2, across),
      Segment.d: horizontal(width / 2, height - half, across),
      Segment.f: vertical(leftX, upperY, down),
      Segment.b: vertical(rightX, upperY, down),
      Segment.e: vertical(leftX, lowerY, down),
      Segment.c: vertical(rightX, lowerY, down),
    };
    return SevenSegmentGeometry._(height, width, t, skew, paths);
  }
}

/// The segments of digits, rendered once into an image (DESIGN.md 9.3): seven
/// white sprites for a digit, and the extras that make a rupee sign.
///
/// A digit is drawn as seven sprites, each with its own alpha, so that a change of
/// digit can crossfade segment by segment like a real VFD (DESIGN.md 6.17).
class SevenSegmentAtlas {
  SevenSegmentAtlas._({
    required this.image,
    required this.scale,
    required this.geometry,
    required this.sprites,
    required this.padding,
  });

  final ui.Image image;

  /// Logical pixels per image pixel.
  final double scale;

  final SevenSegmentGeometry geometry;

  /// Where each sprite is in the image, in image pixels: the seven segments in
  /// [Segment] order, then the decimal point, then the comma.
  final List<ui.Rect> sprites;

  /// The index in [sprites] of the decimal point and of the comma.
  static const int pointSprite = 7;
  static const int commaSprite = 8;

  /// The transparent border round each sprite, in logical pixels.
  final double padding;

  /// The height of a digit in logical pixels.
  double get height => geometry.height;

  /// Renders the atlas for digits [heightLp] tall on a screen of
  /// [devicePixelRatio]. A [glowSigmaLp] above 0 blurs the segments into halos.
  static SevenSegmentAtlas build({
    required double heightLp,
    required double devicePixelRatio,
    double glowSigmaLp = 0,
    double resolution = 1,
  }) {
    final scale = 1 / (devicePixelRatio * resolution);
    final geometry = SevenSegmentGeometry.forHeight(heightLp / scale);
    final sigma = glowSigmaLp / scale;
    final pad = glowSigmaLp > 0 ? (3 * sigma).ceil() + 1 : 1;

    final cellW = geometry.cellWidth.ceil() + 2 * pad;
    final cellH = geometry.height.ceil() + 2 * pad;
    // One row of seven cells: every segment is drawn in its own place in a cell of
    // the whole digit, so a sprite is the size of a digit and sprites line up.
    final width = cellW * (Segment.values.length + 2);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..color = TapeColors.spriteWhite;
    if (sigma > 0) {
      paint.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
    }
    final sprites = <ui.Rect>[];
    for (final segment in Segment.values) {
      final x = segment.index * cellW;
      canvas.save();
      canvas.translate(x + pad.toDouble(), pad.toDouble());
      canvas.drawPath(geometry.paths[segment]!, paint);
      canvas.restore();
      sprites.add(
        ui.Rect.fromLTWH(x.toDouble(), 0, cellW.toDouble(), cellH.toDouble()),
      );
    }

    // The point and the comma sit at the foot of their own narrow cell: a square
    // as thick as a segment, and for the comma a tail.
    final t = geometry.thickness;
    final dotX = Segment.values.length * cellW + pad;
    final dotRect = ui.Rect.fromLTWH(
      dotX + t / 2,
      pad + geometry.height - t,
      t,
      t,
    );
    canvas.drawPath(Chamfer.all(dotRect, t * 0.25), paint);
    sprites.add(
      ui.Rect.fromLTWH(
        (Segment.values.length * cellW).toDouble(),
        0,
        cellW.toDouble(),
        cellH.toDouble(),
      ),
    );

    final commaX = (Segment.values.length + 1) * cellW + pad;
    final commaRect = ui.Rect.fromLTWH(
      commaX + t / 2,
      pad + geometry.height - t,
      t,
      t,
    );
    canvas.drawPath(Chamfer.all(commaRect, t * 0.25), paint);
    canvas.drawPath(
      ui.Path()
        ..moveTo(commaRect.left + t * 0.15, commaRect.bottom - t * 0.2)
        ..lineTo(commaRect.right - t * 0.05, commaRect.bottom - t * 0.2)
        ..lineTo(commaRect.left + t * 0.05, commaRect.bottom + t * 0.9)
        ..lineTo(commaRect.left - t * 0.15, commaRect.bottom + t * 0.9)
        ..close(),
      paint,
    );
    sprites.add(
      ui.Rect.fromLTWH(
        ((Segment.values.length + 1) * cellW).toDouble(),
        0,
        cellW.toDouble(),
        cellH.toDouble(),
      ),
    );

    final image = recorder.endRecording().toImageSync(width, cellH);
    return SevenSegmentAtlas._(
      image: image,
      scale: scale,
      geometry: SevenSegmentGeometry.forHeight(heightLp),
      sprites: sprites,
      padding: pad * scale,
    );
  }

  bool _disposed = false;
  bool get isDisposed => _disposed;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
  }
}

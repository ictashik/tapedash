import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../tokens/colors.dart';

/// The grain of DESIGN.md 4.10: a 128 by 128 monochrome noise tile, generated
/// procedurally from a seed, tiled over the void at 2 to 3%.
///
/// It removes the banding a vignette shows on a cheap 6-bit panel, and gives the
/// black glass some material. It is drawn once, into a cached layer, and never
/// again while driving.
///
/// The strength is in the tile itself: each pixel is white at a random alpha
/// whose average is [opacity]. So it does not depend on how a paint's alpha meets
/// a shader, and it is the same on every backend.
class GrainTile {
  GrainTile._(this.image, this.seed, this.opacity);

  /// The side of the tile, in pixels.
  static const int side = 128;

  /// The average strength of the grain over the canvas: 2.5% (DESIGN.md 4.10).
  static const double defaultOpacity = 0.025;

  final ui.Image image;
  final int seed;
  final double opacity;

  /// Makes the tile. The same seed and opacity always make the same tile.
  factory GrainTile.generate({int seed = 7, double opacity = defaultOpacity}) {
    final random = math.Random(seed);
    // Bucket the pixels by alpha, so each alpha is one draw call.
    final buckets = <int, List<double>>{};
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        // Twice the average, uniformly spread, so that the mean is [opacity].
        final alpha = (random.nextDouble() * 2 * opacity * 255).round();
        if (alpha == 0) continue;
        buckets.putIfAbsent(alpha, () => <double>[])
          ..add(x + 0.5)
          ..add(y + 0.5);
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..strokeWidth = 1
      ..strokeCap = ui.StrokeCap.square
      ..isAntiAlias = false;
    for (final entry in buckets.entries) {
      paint.color = TapeColors.spriteWhite.withAlpha(entry.key);
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(entry.value),
        paint,
      );
    }
    final image = recorder.endRecording().toImageSync(side, side);
    return GrainTile._(image, seed, opacity);
  }

  /// A paint that fills with the tile repeated. Fill a rect with it over the
  /// canvas colour.
  ui.Paint paint() {
    return ui.Paint()
      ..shader = ui.ImageShader(
        image,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
        filterQuality: ui.FilterQuality.none,
      );
  }

  void dispose() => image.dispose();
}

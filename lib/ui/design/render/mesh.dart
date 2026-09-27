import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../tokens/colors.dart';

/// The fine hex mesh of the VFD livery (DESIGN.md 4.10): a honeycomb of hairlines
/// over the data areas, at 3%, like the grid in front of a vacuum-fluorescent
/// display.
///
/// It is one small tile, made once and repeated by a shader, so covering the
/// screen with it is a single fill and not thousands of lines.
class MeshTile {
  MeshTile._(this.image, this.cell);

  /// The default strength: 3%.
  static const double defaultOpacity = 0.03;

  /// The side of one hexagon, in logical pixels.
  static const double defaultCell = 4;

  final ui.Image image;
  final double cell;

  /// Makes a tile of hexagons with sides [cell] logical pixels long, for a
  /// screen of [devicePixelRatio]. The tile is drawn at physical resolution so
  /// the hairlines are crisp.
  factory MeshTile.generate({
    double cell = defaultCell,
    double opacity = defaultOpacity,
    double devicePixelRatio = 1,
  }) {
    final s = cell * devicePixelRatio;
    // A flat-topped honeycomb repeats every 3s across and sqrt(3)s down.
    final w = (3 * s).round();
    final h = (math.sqrt(3) * s).round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = math.max(1, devicePixelRatio * 0.5)
      ..color = TapeColors.spriteWhite.withValues(alpha: opacity);

    void hexagon(double cx, double cy) {
      final path = ui.Path();
      for (var i = 0; i < 6; i++) {
        final angle = math.pi / 3 * i;
        final x = cx + s * math.cos(angle);
        final y = cy + s * math.sin(angle);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }

    // The five centres whose outlines reach into one tile.
    for (final (x, y) in [
      (0.0, 0.0),
      (3 * s, 0.0),
      (0.0, math.sqrt(3) * s),
      (3 * s, math.sqrt(3) * s),
      (1.5 * s, math.sqrt(3) / 2 * s),
    ]) {
      hexagon(x, y);
    }
    final image = recorder.endRecording().toImageSync(w, h);
    return MeshTile._(image, cell);
  }

  /// A paint that fills with the mesh repeated. [devicePixelRatio] scales the
  /// tile, drawn at physical resolution, back to logical pixels.
  ui.Paint paint(double devicePixelRatio) {
    final k = 1 / devicePixelRatio;
    return ui.Paint()
      ..shader = ui.ImageShader(
        image,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        Float64List.fromList([k, 0, 0, 0, 0, k, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
        filterQuality: ui.FilterQuality.low,
      );
  }

  void dispose() => image.dispose();
}

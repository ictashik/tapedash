import 'package:flutter/widgets.dart';

import '../../render/chamfer.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/strokes.dart';
import 'chart_kit.dart';

/// The counted tank (DESIGN.md 6.18): a column that drains from the top, its
/// surface a champagne line, the reserve hatched in `caution`, and ticks at every
/// eighth. With no count yet, an empty outline and a dashed line where the surface
/// will be.
class TankGauge extends StatelessWidget {
  const TankGauge({super.key, required this.level, required this.reserve});

  /// 0 to 1, or null with nothing counted.
  final double? level;

  /// The share of the tank that is reserve.
  final double reserve;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: TankGaugePainter(
      level: level,
      reserve: reserve,
      palette: TapeTheme.of(context).palette,
    ),
    size: Size.infinite,
  );
}

class TankGaugePainter extends CustomPainter {
  TankGaugePainter({
    required this.level,
    required this.reserve,
    required this.palette,
  });

  final double? level;
  final double reserve;
  final TapePalette palette;

  static const double _chamfer = 10;
  static const double _tickRoom = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - _tickRoom;
    final column = Rect.fromLTWH(0, 0, w, size.height);
    final shape = Chamfer.rect(
      column,
      bottomLeft: _chamfer,
      bottomRight: _chamfer,
    );
    canvas.drawPath(shape, Paint()..color = palette.track);

    // The reserve at the bottom.
    final reserveTop = column.bottom - column.height * reserve;
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawRect(
      Rect.fromLTRB(0, reserveTop, w, column.bottom),
      Paint()..color = palette.caution.withValues(alpha: 0.14),
    );
    ChartKit.hatch(
      canvas,
      Rect.fromLTRB(0, reserveTop, w, column.bottom),
      palette.caution.withValues(alpha: 0.35),
      gap: 6,
    );

    final l = level;
    if (l != null) {
      final top = column.bottom - column.height * l.clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTRB(0, top, w, column.bottom),
        Paint()..color = palette.moneyDeep.withValues(alpha: 0.88),
      );
      canvas.drawRect(
        Rect.fromLTRB(0, top - 4, w, top + 4),
        Paint()..color = palette.money.withValues(alpha: 0.18),
      );
      canvas.drawLine(
        Offset(0, top),
        Offset(w, top),
        Paint()
          ..color = palette.money
          ..strokeWidth = TapeStroke.regular,
      );
    } else {
      ChartKit.dashed(
        canvas,
        Offset(0, column.height * 0.4),
        Offset(w, column.height * 0.4),
        palette.etchStrong,
      );
    }
    canvas.restore();
    canvas.drawPath(
      shape,
      Paint()
        ..color = palette.etchStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Ticks at every eighth, longer at the quarters.
    for (var i = 0; i <= 8; i++) {
      final y = column.top + column.height * i / 8;
      final long = i % 4 == 0;
      canvas.drawLine(
        Offset(w + 4, y),
        Offset(w + (long ? 14 : 9), y),
        Paint()
          ..color = long ? palette.etchStrong : palette.etch
          ..strokeWidth = TapeStroke.fine,
      );
    }
    for (final (i, t) in [(0, 'F'), (4, '½'), (8, 'E')]) {
      ChartKit.label(
        canvas,
        t,
        Offset(w + 18, column.top + column.height * i / 8),
        palette.inkDim,
        size: 11,
      );
    }
  }

  @override
  bool shouldRepaint(TankGaugePainter old) =>
      old.level != level || old.reserve != reserve || old.palette != palette;
}

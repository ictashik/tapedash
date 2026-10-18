import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/palette.dart';
import '../../tokens/shapes.dart';
import '../../tokens/strokes.dart';
import '../../tokens/typography.dart';

/// Where a text sits against its anchor point.
enum ChartAlign { start, middle, end }

/// The small drawing helpers the insight charts share (DESIGN.md 6.18): text on
/// a canvas in the design's fonts, a line with its soft halo, a bracket, a dash.
///
/// Nothing here blurs: a halo is a wider, fainter stroke under the line, which is
/// all a parked chart needs (DESIGN.md 4.9 keeps runtime blur out).
abstract final class ChartKit {
  /// A label (UPPERCASE Barlow Semi Condensed) at [at], centred on it
  /// vertically. Returns its width.
  static double label(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    double size = 10,
    ChartAlign align = ChartAlign.start,
  }) => _draw(
    canvas,
    text.toUpperCase(),
    at,
    TapeType.label(size: size, color: color),
    align,
  );

  /// A numeral (Saira, wide, tabular) at [at].
  static double numeral(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    double size = 24,
    double weight = 500,
    ChartAlign align = ChartAlign.start,
  }) => _draw(
    canvas,
    text,
    at,
    TapeType.numeral(size: size, weight: weight, color: color),
    align,
  );

  /// Body text (Barlow) at [at].
  static double body(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    double size = 12,
    ChartAlign align = ChartAlign.start,
  }) => _draw(
    canvas,
    text,
    at,
    TapeType.small(color: color).copyWith(fontSize: size),
    align,
  );

  static double _draw(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle style,
    ChartAlign align,
  ) {
    final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final dx = switch (align) {
      ChartAlign.start => at.dx,
      ChartAlign.middle => at.dx - p.width / 2,
      ChartAlign.end => at.dx - p.width,
    };
    p.paint(canvas, Offset(dx, at.dy - p.height / 2));
    final w = p.width;
    p.dispose();
    return w;
  }

  /// [points] as a polyline, with a halo under it.
  static void glowLine(
    Canvas canvas,
    List<Offset> points,
    Color color, {
    double width = TapeStroke.fine,
    double halo = 0.14,
  }) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    glowPath(canvas, path, color, width: width, halo: halo);
  }

  static void glowPath(
    Canvas canvas,
    Path path,
    Color color, {
    double width = TapeStroke.fine,
    double halo = 0.14,
  }) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      path,
      stroke
        ..strokeWidth = width * 4
        ..color = color.withValues(alpha: halo),
    );
    canvas.drawPath(
      path,
      stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  /// A dashed horizontal or vertical line from [a] to [b].
  static void dashed(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color, {
    double dash = 4,
    double gap = 4,
    double width = 1,
  }) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width;
    for (var d = 0.0; d < total; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), paint);
    }
  }

  /// Diagonal hatching over [rect], for "no data here" (DESIGN.md 6.18).
  static void hatch(Canvas canvas, Rect rect, Color color, {double gap = 7}) {
    canvas.save();
    canvas.clipRect(rect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = rect.left - rect.height; x < rect.right; x += gap) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + rect.height, rect.top),
        paint,
      );
    }
    canvas.restore();
  }

  /// Horizontal grid lines and their labels down the left, for a chart in [area].
  static void yGrid(
    Canvas canvas,
    Rect area,
    TapePalette palette, {
    required double max,
    required double step,
    String Function(double v)? format,
  }) {
    final line = Paint()
      ..color = palette.etch
      ..strokeWidth = 1;
    for (var v = 0.0; v <= max + 1e-9; v += step) {
      final y = area.bottom - area.height * v / max;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), line);
      label(
        canvas,
        format == null ? v.round().toString() : format(v),
        Offset(area.left - 6, y),
        palette.inkDim,
        align: ChartAlign.end,
      );
    }
  }

  /// A chamfered hexagon-ish marker, for peaks: a small square turned 45°.
  static Path diamond(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy - r)
    ..lineTo(c.dx + r, c.dy)
    ..lineTo(c.dx, c.dy + r)
    ..lineTo(c.dx - r, c.dy)
    ..close();

  /// The L-shaped corner brackets of a panel (DESIGN.md 4.6).
  static void brackets(Canvas canvas, Rect rect, Color color) {
    final arm = TapeShape.bracketArm;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.fine;
    for (final (cx, cy, sx, sy) in [
      (rect.left, rect.top, 1.0, 1.0),
      (rect.right, rect.top, -1.0, 1.0),
      (rect.left, rect.bottom, 1.0, -1.0),
      (rect.right, rect.bottom, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx + sx * arm, cy)
          ..lineTo(cx, cy)
          ..lineTo(cx, cy + sy * arm),
        p,
      );
    }
  }
}

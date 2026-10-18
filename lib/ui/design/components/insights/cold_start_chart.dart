import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../insights/cold_start.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import 'chart_kit.dart';

/// The cold-start bill (DESIGN.md 6.18): rupees a kilometre falling as the coolant
/// climbs, against what a kilometre costs the warm engine. The cold running's
/// extra is hatched in `caution`, and the minute the engine was warm is marked.
class ColdStartChart extends StatelessWidget {
  const ColdStartChart({super.key, required this.cold});

  final ColdStart cold;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: ColdStartPainter(
      cold: cold,
      palette: TapeTheme.of(context).palette,
    ),
    size: Size.infinite,
  );
}

class ColdStartPainter extends CustomPainter {
  ColdStartPainter({required this.cold, required this.palette});

  final ColdStart cold;
  final TapePalette palette;

  static const double _left = 34;
  static const double _bottom = 22;
  static const double _top = 22;
  static const double _right = 8;

  /// A window dearer than this many times the warm cost is drawn at the top, not
  /// off it: a few seconds of a stop-start can cost a hundred rupees a kilometre.
  static const double clip = 2.2;

  /// The ₹/km axis: the dearest drawn window, to the next 5, and 15 at least.
  static double rupeesMax(ColdStart c) {
    var top = c.warmPerKm * 1.4;
    for (final w in c.windows) {
      top = math.max(top, math.min(w.perKm, c.warmPerKm * clip));
    }
    return math.max(15, (top / 5).ceil() * 5.0);
  }

  /// The minute axis: to the last window, to the next 5.
  static double minutesMax(ColdStart c) {
    final last = c.windows.isEmpty ? 10.0 : c.windows.last.minutes;
    return math.max(10, (last / 5).ceil() * 5.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );
    final yMax = rupeesMax(cold);
    final xMax = minutesMax(cold);
    double x(double m) => area.left + area.width * m / xMax;
    double y(double rs) => area.bottom - area.height * rs.clamp(0, yMax) / yMax;

    ChartKit.yGrid(canvas, area, palette, max: yMax, step: 5);
    ChartKit.label(
      canvas,
      '₹/km',
      Offset(area.left - 6, area.top - 10),
      palette.inkDim,
      align: ChartAlign.end,
    );
    for (var m = 0; m <= xMax; m += 5) {
      ChartKit.label(
        canvas,
        '$m',
        Offset(x(m.toDouble()), area.bottom + 13),
        palette.inkDim,
        align: ChartAlign.middle,
      );
    }
    ChartKit.label(
      canvas,
      'min',
      Offset(area.left - 6, area.bottom + 13),
      palette.inkDim,
      align: ChartAlign.end,
    );
    canvas.drawLine(
      Offset(area.left, area.bottom),
      Offset(area.right, area.bottom),
      Paint()
        ..color = palette.etchStrong
        ..strokeWidth = 1,
    );

    final base = y(cold.warmPerKm);
    final pts = [
      for (final w in cold.windows)
        Offset(x(w.minutes), y(math.min(w.perKm, cold.warmPerKm * clip))),
    ];

    // The extra: between the curve and the warm cost, until the engine was warm.
    final until = cold.windows.indexWhere(
      (w) => w.minutes >= cold.warmAtMinutes,
    );
    final cut = until < 0 ? pts.length : until + 1;
    if (cut >= 2) {
      final shape = Path()..moveTo(pts.first.dx, base);
      for (final p in pts.take(cut)) {
        shape.lineTo(p.dx, math.min(p.dy, base));
      }
      shape
        ..lineTo(pts[cut - 1].dx, base)
        ..close();
      canvas.save();
      canvas.clipPath(shape);
      canvas.drawRect(
        area,
        Paint()..color = palette.caution.withValues(alpha: 0.05),
      );
      ChartKit.hatch(
        canvas,
        area,
        palette.caution.withValues(alpha: 0.4),
        gap: 5,
      );
      canvas.restore();
    }

    ChartKit.dashed(
      canvas,
      Offset(area.left, base),
      Offset(area.right, base),
      palette.etchStrong,
    );
    ChartKit.label(
      canvas,
      'Warm · ₹${cold.warmPerKm.toStringAsFixed(1)}',
      Offset(area.right - 2, base + 9),
      palette.inkMid,
      size: 10,
      align: ChartAlign.end,
    );

    // The coolant, on its own scale, thin: it is why the cost falls.
    final temp = [
      for (final w in cold.windows)
        Offset(
          x(w.minutes),
          area.bottom - area.height * ((w.coolantC - 20) / 80).clamp(0.0, 1.0),
        ),
    ];
    if (temp.length >= 2) {
      final path = Path()..moveTo(temp.first.dx, temp.first.dy);
      for (final p in temp.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.inkMid.withValues(alpha: 0.7),
      );
      ChartKit.label(
        canvas,
        'Coolant',
        Offset(area.right - 2, temp.last.dy - 9),
        palette.inkMid,
        size: 10,
        align: ChartAlign.end,
      );
    }

    // The minute the engine was warm.
    if (cold.warmAtMinutes <= xMax) {
      ChartKit.dashed(
        canvas,
        Offset(x(cold.warmAtMinutes), area.top),
        Offset(x(cold.warmAtMinutes), area.bottom),
        palette.etchStrong,
        dash: 2,
        gap: 3,
      );
      ChartKit.label(
        canvas,
        'Warm at ${cold.warmAtMinutes.round()} min',
        Offset(x(cold.warmAtMinutes) + 6, area.bottom - 8),
        palette.inkDim,
        size: 10,
      );
    }

    ChartKit.glowLine(canvas, pts, palette.money, width: 1.8, halo: 0.12);
  }

  @override
  bool shouldRepaint(ColdStartPainter old) =>
      !identical(old.cold, cold) || old.palette != palette;
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../../insights/gearbox.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/strokes.dart';
import 'chart_kit.dart';

/// The gearbox found from the driving (DESIGN.md 6.18): rpm against km/h, a dot
/// for every moment, and each gear a straight ray from the origin through its
/// crowd, labelled with its ratio (rpm for each km/h). A CVT has no rays, only a fan of dots, and the chart says so.
class GearChart extends StatelessWidget {
  const GearChart({super.key, required this.gearbox});

  final Gearbox gearbox;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: GearChartPainter(
      gearbox: gearbox,
      palette: TapeTheme.of(context).palette,
    ),
    size: Size.infinite,
  );
}

class GearChartPainter extends CustomPainter {
  GearChartPainter({required this.gearbox, required this.palette});

  final Gearbox gearbox;
  final TapePalette palette;

  static const double maxRpm = 6500;
  static const int maxDots = 5000;

  static const double _left = 34;
  static const double _bottom = 22;
  static const double _top = 14;
  static const double _right = 22;

  /// The speed axis, to the next 20 km/h over the fastest moment, 80 at least.
  static double kmhMax(Gearbox g) {
    var top = 0.0;
    for (final p in g.points) {
      top = math.max(top, p.$1);
    }
    return math.max(80, (top / 20).ceil() * 20.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );
    final vMax = kmhMax(gearbox);
    double x(double kmh) => area.left + area.width * kmh / vMax;
    double y(double rpm) => area.bottom - area.height * rpm / maxRpm;

    final grid = Paint()
      ..color = palette.etch
      ..strokeWidth = 1;
    for (var r = 0; r <= 6000; r += 2000) {
      canvas.drawLine(
        Offset(area.left, y(r.toDouble())),
        Offset(area.right, y(r.toDouble())),
        grid,
      );
      ChartKit.label(
        canvas,
        '${r ~/ 1000}',
        Offset(area.left - 6, y(r.toDouble())),
        palette.inkDim,
        align: ChartAlign.end,
      );
    }
    for (var v = 20; v <= vMax; v += 20) {
      ChartKit.label(
        canvas,
        '$v',
        Offset(x(v.toDouble()), area.bottom + 13),
        palette.inkDim,
        align: ChartAlign.middle,
      );
    }
    ChartKit.label(
      canvas,
      '×1000',
      Offset(area.left - 6, area.top - 4),
      palette.inkDim,
      align: ChartAlign.end,
    );
    ChartKit.label(
      canvas,
      'KM/H',
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
    if (gearbox.isEmpty) return;

    // The rays first, under the dots.
    for (final r in gearbox.ratios) {
      final vEnd = math.min(vMax, maxRpm / r);
      canvas.drawLine(
        Offset(x(0), y(0)),
        Offset(x(vEnd), y(r * vEnd)),
        Paint()
          ..color = palette.accentCore.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      ChartKit.numeral(
        canvas,
        '${r.round()}',
        Offset(x(vEnd) + 6, y(r * vEnd)),
        palette.accentCore,
        size: 11,
      );
    }

    final stride = math.max(1, (gearbox.points.length / maxDots).ceil());
    final pts = <Offset>[
      for (var i = 0; i < gearbox.points.length; i += stride)
        Offset(x(gearbox.points[i].$1), y(gearbox.points[i].$2)),
    ];
    canvas.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..color = palette.accentCore.withValues(
          alpha: gearbox.isFan ? 0.45 : 0.7,
        )
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    if (gearbox.isFan) {
      ChartKit.label(
        canvas,
        'A fan, not lines',
        Offset(area.left + 10, area.top + 8),
        palette.inkMid,
        size: 11,
      );
    }
    canvas.drawLine(
      Offset(area.left, area.top),
      Offset(area.left, area.bottom),
      Paint()
        ..color = palette.etchStrong
        ..strokeWidth = TapeStroke.fine,
    );
  }

  @override
  bool shouldRepaint(GearChartPainter old) =>
      !identical(old.gearbox, gearbox) || old.palette != palette;
}

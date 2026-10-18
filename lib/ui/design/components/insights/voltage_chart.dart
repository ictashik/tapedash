import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../insights/rest_voltage_log.dart';
import '../../../../insights/voltage_trace.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/strokes.dart';
import 'chart_kit.dart';

/// The module voltage of a drive (DESIGN.md 6.18): the trace inside its charging
/// band, and a mark for each of the deepest dips, with how far it went.
class VoltageChart extends StatelessWidget {
  const VoltageChart({super.key, required this.trace});

  final VoltageTrace trace;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: VoltageChartPainter(
      trace: trace,
      palette: TapeTheme.of(context).palette,
    ),
    size: Size.infinite,
  );
}

class VoltageChartPainter extends CustomPainter {
  VoltageChartPainter({required this.trace, required this.palette});

  final VoltageTrace trace;
  final TapePalette palette;

  static const double minVolts = 11.5;
  static const double maxVolts = 15;

  /// The most dips given a label: the deepest, and never two on top of each other.
  static const int labelled = 5;
  static const double labelGap = 44;

  static const double _left = 34;
  static const double _bottom = 22;
  static const double _top = 8;
  static const double _right = 8;

  /// The points to draw: at most two a pixel column, the lowest and the highest of
  /// the stretch, so a dip a second or two long is not averaged away.
  static List<(double, double)> decimate(
    List<(double, double)> points,
    int columns,
  ) {
    if (points.length <= columns * 2) return points;
    final out = <(double, double)>[];
    final per = points.length / columns;
    for (var c = 0; c < columns; c++) {
      final from = (c * per).floor();
      final to = math.min(points.length, ((c + 1) * per).floor());
      if (to <= from) continue;
      var lo = points[from], hi = points[from];
      for (var i = from; i < to; i++) {
        if (points[i].$2 < lo.$2) lo = points[i];
        if (points[i].$2 > hi.$2) hi = points[i];
      }
      if (lo.$1 <= hi.$1) {
        out
          ..add(lo)
          ..add(hi);
      } else {
        out
          ..add(hi)
          ..add(lo);
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );
    double y(double v) =>
        area.bottom -
        area.height * ((v - minVolts) / (maxVolts - minVolts)).clamp(0.0, 1.0);

    // The charging band, and the grid.
    canvas.drawRect(
      Rect.fromLTRB(area.left, y(maxVolts), area.right, y(13.6)),
      Paint()..color = palette.accentCore.withValues(alpha: 0.05),
    );
    final grid = Paint()
      ..color = palette.etch
      ..strokeWidth = 1;
    for (final v in [12.0, 13.0, 14.0, 15.0]) {
      canvas.drawLine(Offset(area.left, y(v)), Offset(area.right, y(v)), grid);
      ChartKit.label(
        canvas,
        '${v.round()}',
        Offset(area.left - 6, y(v)),
        palette.inkDim,
        align: ChartAlign.end,
      );
    }
    ChartKit.label(
      canvas,
      'Charging band · ${VoltageTrace.chargingVolts} V and up',
      Offset(area.left + 6, y(14.55)),
      palette.accentCore.withValues(alpha: 0.8),
    );

    if (trace.isEmpty) {
      ChartKit.label(
        canvas,
        'No voltage in this drive',
        area.center,
        palette.inkMid,
        size: 11,
        align: ChartAlign.middle,
      );
      return;
    }

    final t0 = trace.points.first.$1;
    final t1 = trace.points.last.$1;
    final span = math.max(1.0, t1 - t0);
    double x(double t) => area.left + area.width * (t - t0) / span;

    // The minutes along the bottom.
    final minutes = span / 60;
    final step = minutes > 40
        ? 10
        : minutes > 16
        ? 5
        : minutes > 6
        ? 2
        : 1;
    for (var m = 0; m <= minutes; m += step) {
      final px = x(t0 + m * 60);
      canvas.drawLine(
        Offset(px, area.bottom),
        Offset(px, area.bottom + 4),
        Paint()
          ..color = palette.etchStrong
          ..strokeWidth = TapeStroke.fine,
      );
      ChartKit.label(
        canvas,
        '$m',
        Offset(px, area.bottom + 13),
        palette.inkDim,
        align: ChartAlign.middle,
      );
    }
    ChartKit.label(
      canvas,
      'MIN',
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

    final line = [
      for (final p in decimate(trace.points, area.width.floor()))
        Offset(x(p.$1), y(p.$2)),
    ];
    ChartKit.glowLine(canvas, line, palette.accentCore, width: 1.5);

    // The deepest dips, labelled with how far they went.
    final deepest = [...trace.dips]..sort((a, b) => b.depth.compareTo(a.depth));
    final placed = <double>[];
    for (final d in deepest.take(labelled * 2)) {
      if (placed.length >= labelled) break;
      final px = x(d.startSeconds + d.seconds / 2);
      if (placed.any((o) => (o - px).abs() < labelGap)) continue;
      placed.add(px);
      final py = y(d.lowest);
      canvas.drawPath(
        ChartKit.diamond(Offset(px, py), 3),
        Paint()..color = palette.caution,
      );
      ChartKit.label(
        canvas,
        '−${d.depth.toStringAsFixed(1)} V',
        Offset(px, math.min(area.bottom - 8, py + 11)),
        palette.caution,
        align: ChartAlign.middle,
      );
    }
  }

  @override
  bool shouldRepaint(VoltageChartPainter old) =>
      !identical(old.trace, trace) || old.palette != palette;
}

/// The battery at rest, reading by reading: a small trend with its last point lit.
class RestTrend extends StatelessWidget {
  const RestTrend({super.key, required this.readings});

  final List<RestReading> readings;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: RestTrendPainter(
      readings: readings,
      palette: TapeTheme.of(context).palette,
    ),
    size: Size.infinite,
  );
}

class RestTrendPainter extends CustomPainter {
  RestTrendPainter({required this.readings, required this.palette});

  final List<RestReading> readings;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = palette.etch
        ..strokeWidth = TapeStroke.fine,
    );
    if (readings.length < 2) {
      if (readings.length == 1) {
        canvas.drawCircle(
          Offset(size.width - 3, size.height / 2),
          2.6,
          Paint()..color = palette.accentCore,
        );
      }
      return;
    }
    var lo = readings.first.volts, hi = lo;
    for (final r in readings) {
      lo = math.min(lo, r.volts);
      hi = math.max(hi, r.volts);
    }
    // At least a fifth of a volt tall, so that a steady battery looks steady.
    final mid = (lo + hi) / 2;
    final half = math.max(0.1, (hi - lo) / 2);
    Offset at(int i) => Offset(
      size.width * i / (readings.length - 1),
      size.height / 2 -
          (readings[i].volts - mid) / half * (size.height / 2 - 4),
    );
    final pts = [for (var i = 0; i < readings.length; i++) at(i)];
    final fill = Path()..moveTo(pts.first.dx, size.height);
    for (final p in pts) {
      fill.lineTo(p.dx, p.dy);
    }
    fill
      ..lineTo(pts.last.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = palette.accentCore.withValues(alpha: 0.08),
    );
    ChartKit.glowLine(canvas, pts, palette.accentCore, width: 1.5, halo: 0.1);
    canvas.drawCircle(pts.last, 2.8, Paint()..color = palette.inkHot);
  }

  @override
  bool shouldRepaint(RestTrendPainter old) =>
      !identical(old.readings, readings) || old.palette != palette;
}

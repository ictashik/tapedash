import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../../insights/power_curve.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/strokes.dart';
import 'chart_kit.dart';

/// A dyno chart from ordinary driving (DESIGN.md 6.18): a dot of wheel power for
/// every moment the engine pulled, coloured by the throttle, the highest the dots
/// reach drawn in light, and the revs the car has never been taken to hatched.
class PowerCurveChart extends StatelessWidget {
  const PowerCurveChart({super.key, required this.curve});

  final PowerCurve curve;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: PowerCurvePainter(
      curve: curve,
      palette: TapeTheme.of(context).palette,
    ),
    size: Size.infinite,
  );
}

class PowerCurvePainter extends CustomPainter {
  PowerCurvePainter({required this.curve, required this.palette});

  final PowerCurve curve;
  final TapePalette palette;

  /// The most dots drawn; more only blur into a block.
  static const int maxDots = 6000;

  /// The throttle (percent) above which a dot is a firm pull, and a full one.
  static const double firmThrottle = 45;
  static const double fullThrottle = 86;

  static const double _left = 34;
  static const double _bottom = 22;
  static const double _top = 22;
  static const double _right = 8;

  /// The rev axis: to the redline's thousand at least, and past the revs reached.
  static double rpmMax(PowerCurve curve) =>
      math.max(7000, ((curve.coveredRpm + 500) / 1000).ceil() * 1000.0);

  /// The power axis, in steps of 20 kW above the highest seen, 40 at least.
  static double kwMax(PowerCurve curve) {
    final top = curve.highest?.kw ?? 0;
    return math.max(40, ((top * 1.15) / 20).ceil() * 20.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );
    final rMax = rpmMax(curve);
    final kMax = kwMax(curve);
    double x(double rpm) =>
        area.left + area.width * (rpm - 1000) / (rMax - 1000);
    double y(double kw) => area.bottom - area.height * kw / kMax;

    ChartKit.yGrid(canvas, area, palette, max: kMax, step: 20);
    ChartKit.label(
      canvas,
      'kW',
      Offset(area.left - 6, area.top - 10),
      palette.inkDim,
      align: ChartAlign.end,
    );
    for (var r = 1000; r <= rMax; r += 1000) {
      canvas.drawLine(
        Offset(x(r.toDouble()), area.bottom),
        Offset(x(r.toDouble()), area.bottom + 4),
        Paint()
          ..color = palette.etchStrong
          ..strokeWidth = TapeStroke.fine,
      );
      ChartKit.label(
        canvas,
        '${r ~/ 1000}',
        Offset(x(r.toDouble()), area.bottom + 13),
        palette.inkDim,
        align: ChartAlign.middle,
      );
    }
    ChartKit.label(
      canvas,
      'Along: rpm ×1000',
      Offset(area.right, area.top - 10),
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

    // The throttle key.
    var kx = area.left + 4;
    for (final (label, color) in [
      ('Light', palette.trackInactive),
      ('Firm', palette.accentCore),
      ('Full', palette.caution),
    ]) {
      canvas.drawCircle(
        Offset(kx + 3, area.top - 10),
        2.6,
        Paint()..color = color,
      );
      kx +=
          10 +
          ChartKit.label(
            canvas,
            label,
            Offset(kx + 10, area.top - 10),
            palette.inkDim,
            size: 10,
          ) +
          12;
    }

    if (curve.isEmpty) return;

    // What the car has never been taken to.
    final covered =
        ((curve.coveredRpm / PowerCurve.binRpm).ceil() + 1) *
        PowerCurve.binRpm.toDouble();
    if (covered < rMax) {
      final unseen = Rect.fromLTRB(
        x(covered),
        area.top,
        area.right,
        area.bottom,
      );
      ChartKit.hatch(canvas, unseen, palette.etch);
      ChartKit.dashed(
        canvas,
        Offset(unseen.left, area.top),
        Offset(unseen.left, area.bottom),
        palette.etchStrong,
        dash: 3,
        gap: 3,
      );
      // The words, as many as the room holds.
      final mid = unseen.center;
      if (unseen.width >= 50) {
        ChartKit.label(
          canvas,
          unseen.width >= 120 ? 'No data yet' : 'No data',
          Offset(mid.dx, mid.dy - 8),
          palette.inkMid,
          size: 11,
          align: ChartAlign.middle,
        );
      }
      if (unseen.width >= 120) {
        for (final (i, line) in [
          'fills in as you use more',
          'of the rev range',
        ].indexed) {
          ChartKit.body(
            canvas,
            line,
            Offset(mid.dx, mid.dy + 8 + 14.0 * i),
            palette.inkDim,
            size: 11,
            align: ChartAlign.middle,
          );
        }
      }
    }

    // The dots, three colours in three batches.
    final stride = math.max(1, (curve.dots.length / maxDots).ceil());
    final light = <Offset>[], firm = <Offset>[], full = <Offset>[];
    for (var i = 0; i < curve.dots.length; i += stride) {
      final d = curve.dots[i];
      final p = Offset(x(d.rpm), y(math.min(d.kw, kMax)));
      (d.throttle >= fullThrottle
              ? full
              : d.throttle >= firmThrottle
              ? firm
              : light)
          .add(p);
    }
    void dots(List<Offset> pts, Color color) => canvas.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..color = color
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    dots(light, palette.trackInactive);
    dots(firm, palette.accentCore.withValues(alpha: 0.85));
    dots(full, palette.caution);

    // The highest the dots reach, and where.
    final edge = [for (final (r, k) in curve.edge) Offset(x(r), y(k))];
    ChartKit.glowLine(canvas, edge, palette.inkHot, width: 1.4, halo: 0.12);
    final top = curve.highest;
    if (top != null) {
      canvas.drawCircle(
        Offset(x(top.rpm), y(math.min(top.kw, kMax))),
        3.6,
        Paint()
          ..color = palette.inkHot
          ..style = PaintingStyle.stroke
          ..strokeWidth = TapeStroke.fine,
      );
    }
  }

  @override
  bool shouldRepaint(PowerCurvePainter old) =>
      !identical(old.curve, curve) || old.palette != palette;
}

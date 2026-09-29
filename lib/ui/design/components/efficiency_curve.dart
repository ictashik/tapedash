import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../coach/efficiency_curve.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/strokes.dart';
import '../tokens/typography.dart';

/// The car's own efficiency curve (DESIGN.md 6.13): speed bands from 0 to
/// 120 km/h across, km/L up. A smooth Catmull-Rom curve runs through the bands
/// that have enough data; bands that do not are a dotted ghost joining the
/// reported ones. The sweet spot is a vertical accent glow column with its range
/// written on it; the car's overall average is a dashed etch line. The curve
/// draws on as [draw] goes from 0 to 1.
///
/// With no band reported, the ghost of a curve is drawn, and the page says what
/// fills it in.
class EfficiencyCurveView extends StatelessWidget {
  const EfficiencyCurveView({
    super.key,
    required this.curve,
    required this.draw,
  });

  final SweetSpot curve;

  /// How much of the curve is drawn, 0 to 1.
  final ValueListenable<double> draw;

  static const int maxKmh = 120;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: EfficiencyCurvePainter(
        curve: curve,
        draw: draw,
        palette: TapeTheme.of(context).palette,
      ),
      size: Size.infinite,
    );
  }
}

class EfficiencyCurvePainter extends CustomPainter {
  EfficiencyCurvePainter({
    required this.curve,
    required this.draw,
    required this.palette,
  }) : super(repaint: draw);

  final SweetSpot curve;
  final ValueListenable<double> draw;
  final TapePalette palette;

  static const double _left = 34;
  static const double _bottom = 22;
  static const double _top = 8;
  static const double _right = 8;

  Size? _size;
  Path? _path;
  ui.PathMetric? _metric;

  /// The km/L the y axis tops out at: the best reported, with room, and at
  /// least 15 so that an empty curve has a scale.
  double yMax() {
    var m = 15.0;
    for (final b in curve.reported) {
      if (b.kmPerLitre! * 1.2 > m) m = b.kmPerLitre! * 1.2;
    }
    return (m / 5).ceil() * 5.0;
  }

  Offset _point(SpeedBand b, Size size, double yMax) {
    final w = size.width - _left - _right;
    final h = size.height - _top - _bottom;
    final x =
        _left +
        w *
            (b.fromKmh + SweetSpot.bandWidthKmh / 2) /
            EfficiencyCurveView.maxKmh;
    final y = _top + h * (1 - (b.kmPerLitre! / yMax).clamp(0.0, 1.0));
    return Offset(x, y);
  }

  /// The smooth path through consecutive reported bands (Catmull-Rom), one
  /// sub-path for each unbroken run. Exposed for a direct test.
  static Path smooth(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[math.max(0, i - 1)];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[math.min(pts.length - 1, i + 2)];
      // Catmull-Rom as a cubic Bezier.
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  void _build(Size size) {
    if (_size == size) return;
    _size = size;
    final ym = yMax();
    final pts = [for (final b in curve.reported) _point(b, size, ym)];
    // Runs of bands next to each other are smoothed; a gap is joined by a dotted
    // ghost (drawn separately).
    final path = Path();
    var run = <Offset>[];
    final reported = curve.reported;
    for (var i = 0; i < reported.length; i++) {
      run.add(pts[i]);
      final endOfRun =
          i == reported.length - 1 ||
          reported[i + 1].fromKmh - reported[i].fromKmh >
              SweetSpot.bandWidthKmh;
      if (endOfRun) {
        path.addPath(smooth(run), Offset.zero);
        run = [];
      }
    }
    _path = path;
    final metrics = path.computeMetrics().toList();
    _metric = metrics.isEmpty ? null : metrics.first;
    _ghost = [
      for (var i = 0; i < reported.length - 1; i++)
        if (reported[i + 1].fromKmh - reported[i].fromKmh >
            SweetSpot.bandWidthKmh)
          (pts[i], pts[i + 1]),
    ];
  }

  List<(Offset, Offset)> _ghost = const [];

  @override
  void paint(Canvas canvas, Size size) {
    _build(size);
    final w = size.width - _left - _right;
    final h = size.height - _top - _bottom;
    final ym = yMax();
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.fine;

    // The axes: km/L up the left, speeds along the bottom.
    line.color = palette.etch;
    for (var v = 0; v <= ym; v += 5) {
      final y = _top + h * (1 - v / ym);
      canvas.drawLine(Offset(_left, y), Offset(size.width - _right, y), line);
      _text(
        canvas,
        '$v',
        Offset(_left - 6, y),
        palette.inkDim,
        alignRight: true,
      );
    }
    for (var k = 0; k <= EfficiencyCurveView.maxKmh; k += 20) {
      final x = _left + w * k / EfficiencyCurveView.maxKmh;
      _text(
        canvas,
        '$k',
        Offset(x, size.height - _bottom + 12),
        palette.inkDim,
        centre: true,
      );
    }

    // The sweet spot: a glow column, and its range.
    final range = curve.range;
    if (range != null) {
      final x0 = _left + w * range.from / EfficiencyCurveView.maxKmh;
      final x1 = _left + w * range.to / EfficiencyCurveView.maxKmh;
      canvas.drawRect(
        Rect.fromLTRB(x0, _top, x1, _top + h),
        Paint()..color = palette.accentCore.withValues(alpha: 0.14),
      );
      canvas.drawRect(
        Rect.fromLTRB(x0, _top, x1, _top + h),
        Paint()
          ..color = palette.accentCore.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = TapeStroke.fine,
      );
      _text(
        canvas,
        'SWEET SPOT ${range.from}–${range.to} KM/H',
        Offset((x0 + x1) / 2, _top + 10),
        palette.accentCore,
        centre: true,
      );
    }

    // The car's overall average, dashed.
    final avg = curve.average;
    if (avg != null) {
      final y = _top + h * (1 - (avg / ym).clamp(0.0, 1.0));
      line.color = palette.etchStrong;
      for (var x = _left; x < size.width - _right; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width - _right), y),
          line,
        );
      }
    }

    // The ghost of a curve with nothing in it yet.
    if (curve.reported.isEmpty) {
      line.color = palette.etchStrong;
      final ghost = Path()
        ..moveTo(_left, _top + h * 0.8)
        ..cubicTo(
          _left + w * 0.3,
          _top + h * 0.2,
          _left + w * 0.55,
          _top + h * 0.1,
          _left + w,
          _top + h * 0.6,
        );
      _dotted(canvas, ghost, line);
      return;
    }

    // Ghost segments across the gaps.
    line.color = palette.etchStrong;
    for (final (a, b) in _ghost) {
      _dotted(
        canvas,
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy),
        line,
      );
    }

    // The curve, drawn on.
    final metric = _metric;
    final t = draw.value.clamp(0.0, 1.0);
    if (_path != null && t > 0) {
      line
        ..strokeWidth = TapeStroke.bold
        ..color = palette.accentCore;
      if (t >= 1) {
        canvas.drawPath(_path!, line);
      } else if (metric != null) {
        // (Only the first run is trimmed while drawing on; a curve of several
        // runs is whole once the draw-on ends.)
        canvas.drawPath(metric.extractPath(0, metric.length * t), line);
      }
    }
    if (t >= 1) {
      final dot = Paint()..color = palette.inkBright;
      for (final b in curve.reported) {
        canvas.drawCircle(_point(b, size, ym), 3, dot);
      }
    }
  }

  void _dotted(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 8) {
        canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), paint);
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    bool alignRight = false,
    bool centre = false,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TapeType.label(size: 10, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight
        ? at.dx - p.width
        : centre
        ? at.dx - p.width / 2
        : at.dx;
    p.paint(canvas, Offset(dx, at.dy - p.height / 2));
    p.dispose();
  }

  @override
  bool shouldRepaint(EfficiencyCurvePainter old) =>
      !identical(old.curve, curve) || old.palette != palette;
}

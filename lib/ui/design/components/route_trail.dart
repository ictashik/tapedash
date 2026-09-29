import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../coach/sample_events.dart';
import '../../../trips/route_geometry.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/strokes.dart';

/// The route trail (DESIGN.md 6.12): a trip's route on a dark panel, north up,
/// coloured by a metric, with markers where things happened and a draw-on with a
/// bright comet head.
///
/// The colours are quantised into [bins] and one set of segments is kept per
/// bin, so the trail is drawn in [bins] calls however long the route. Everything
/// heavy is worked out once, when the geometry or the metric changes; a frame
/// only draws (and repaints only for [reveal] and [cursor], never a rebuild).
class RouteTrail extends StatefulWidget {
  const RouteTrail({
    super.key,
    required this.geometry,
    required this.metric,
    required this.ramp,
    required this.reveal,
    this.cursor,
    this.markers = const [],
  });

  /// The route, already fitted to this widget's size (`RouteGeometry.build` with
  /// the size the widget is given).
  final RouteGeometry geometry;

  /// The metric at each of the geometry's points, 0 to 1.
  final List<double> metric;

  /// The ramp from the metric's low to its high.
  final List<Color> ramp;

  /// How much of the route is drawn, 0 to 1 (the draw-on; 1 is all of it).
  final ValueListenable<double> reveal;

  /// The point (index into the geometry) to put a position dot on, while
  /// scrubbing.
  final ValueListenable<int?>? cursor;

  final List<RouteMarker> markers;

  /// Sixteen colours (DESIGN.md 6.12).
  static const int bins = 16;

  /// The bin a metric value falls in.
  static int binOf(double v) => (v.clamp(0.0, 1.0) * (bins - 1)).round();

  /// The colour of [bin] on [ramp]: a straight blend along its stops.
  static Color colourOf(int bin, List<Color> ramp) {
    final t = bin / (bins - 1) * (ramp.length - 1);
    final i = t.floor().clamp(0, ramp.length - 2);
    return Color.lerp(ramp[i], ramp[i + 1], t - i)!;
  }

  @override
  State<RouteTrail> createState() => _RouteTrailState();
}

/// A marker on the route: a moment at a point.
class RouteMarker {
  const RouteMarker(this.type, this.point);

  final SampleEventType? type;

  /// Index into the geometry's points. A null [type] with the first point is the
  /// start, and with the last the end.
  final int point;
}

class _RouteTrailState extends State<RouteTrail> {
  // Per bin, the segments' endpoints as x1, y1, x2, y2, and the index of the
  // segment's first point, in route order.
  late List<Float32List> _lines;
  late List<Int32List> _indices;
  late List<double> _progress;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(RouteTrail old) {
    super.didUpdateWidget(old);
    if (!identical(old.geometry, widget.geometry) ||
        !identical(old.metric, widget.metric)) {
      _prepare();
    }
  }

  void _prepare() {
    final g = widget.geometry;
    final lines = List.generate(RouteTrail.bins, (_) => <double>[]);
    final indices = List.generate(RouteTrail.bins, (_) => <int>[]);
    for (var n = 1; n < g.length; n++) {
      final m = (widget.metric[n - 1] + widget.metric[n]) / 2;
      final bin = RouteTrail.binOf(m);
      lines[bin].addAll([g.xs[n - 1], g.ys[n - 1], g.xs[n], g.ys[n]]);
      indices[bin].add(n - 1);
    }
    _lines = [for (final l in lines) Float32List.fromList(l)];
    _indices = [for (final i in indices) Int32List.fromList(i)];
    _progress = g.progress;
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return CustomPaint(
      painter: _TrailPainter(
        state: this,
        palette: palette,
        listenable: Listenable.merge([
          widget.reveal,
          if (widget.cursor != null) widget.cursor!,
        ]),
      ),
    );
  }
}

class _TrailPainter extends CustomPainter {
  _TrailPainter({
    required this.state,
    required this.palette,
    required Listenable listenable,
  }) : super(repaint: listenable);

  final _RouteTrailState state;
  final TapePalette palette;

  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _fill = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final w = state.widget;
    final g = w.geometry;
    if (g.length < 2) return;
    final reveal = w.reveal.value.clamp(0.0, 1.0);
    // The last point drawn: the route is revealed by distance along it.
    var last = g.length - 1;
    if (reveal < 1) {
      last = 0;
      for (var n = 0; n < g.length; n++) {
        if (state._progress[n] <= reveal) last = n;
      }
    }

    // The faint underlay (DESIGN.md 6.12), 8 lp at 10%, for a glow with no blur.
    _line
      ..strokeWidth = 8
      ..color = palette.accentCore.withValues(alpha: 0.10);
    for (var b = 0; b < RouteTrail.bins; b++) {
      _drawBin(canvas, b, last);
    }
    _line.strokeWidth = TapeStroke.bold;
    for (var b = 0; b < RouteTrail.bins; b++) {
      _line.color = RouteTrail.colourOf(b, w.ramp);
      _drawBin(canvas, b, last);
    }

    if (reveal < 1 && last > 0) {
      // The comet head: a bright dot at the front of the line.
      _fill.color = palette.inkHot;
      canvas.drawCircle(Offset(g.xs[last], g.ys[last]), 4, _fill);
      _fill.color = palette.accentCore.withValues(alpha: 0.35);
      canvas.drawCircle(Offset(g.xs[last], g.ys[last]), 8, _fill);
    }

    if (reveal >= 1) _drawMarkers(canvas, g);

    final c = w.cursor?.value;
    if (c != null && c >= 0 && c < g.length) {
      _fill.color = palette.inkHot;
      canvas.drawCircle(Offset(g.xs[c], g.ys[c]), 5, _fill);
      _line
        ..strokeWidth = TapeStroke.regular
        ..color = palette.accentCore;
      canvas.drawCircle(
        Offset(g.xs[c], g.ys[c]),
        8,
        _line..style = PaintingStyle.stroke,
      );
    }
  }

  /// Draws the segments of [bin] whose first point is at or before [last].
  void _drawBin(Canvas canvas, int bin, int last) {
    final lines = state._lines[bin];
    if (lines.isEmpty) return;
    final indices = state._indices[bin];
    var count = indices.length;
    if (last < state.widget.geometry.length - 1) {
      // Segments are in route order, so the count is a search.
      var lo = 0, hi = indices.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (indices[mid] < last) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      count = lo;
    }
    if (count == 0) return;
    canvas.drawRawPoints(
      ui.PointMode.lines,
      Float32List.sublistView(lines, 0, count * 4),
      _line,
    );
  }

  void _drawMarkers(Canvas canvas, RouteGeometry g) {
    final ink = palette.inkBright;
    for (final m in state.widget.markers) {
      if (m.point < 0 || m.point >= g.length) continue;
      final p = Offset(g.xs[m.point], g.ys[m.point]);
      _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = TapeStroke.regular
        ..color = ink;
      _fill.color = ink;
      switch (m.type) {
        case null:
          if (m.point == 0) {
            // The start: a hollow circle.
            canvas.drawCircle(p, 6, _line);
          } else {
            // The end: a filled chamfered square.
            const r = 6.0;
            canvas.drawPath(
              Path()
                ..moveTo(p.dx - r + 3, p.dy - r)
                ..lineTo(p.dx + r, p.dy - r)
                ..lineTo(p.dx + r, p.dy + r - 3)
                ..lineTo(p.dx + r - 3, p.dy + r)
                ..lineTo(p.dx - r, p.dy + r)
                ..lineTo(p.dx - r, p.dy - r + 3)
                ..close(),
              _fill,
            );
          }
        case SampleEventType.hardAcceleration:
          // A double chevron up.
          _chevron(canvas, p, -3, palette.critical);
          _chevron(canvas, p, 3, palette.critical);
        case SampleEventType.hardBraking:
          // A double bar.
          _line.color = palette.critical;
          canvas.drawLine(
            p + const Offset(-3, -5),
            p + const Offset(-3, 5),
            _line,
          );
          canvas.drawLine(
            p + const Offset(3, -5),
            p + const Offset(3, 5),
            _line,
          );
        case SampleEventType.longIdle:
          // A hollow square.
          _line.color = palette.caution;
          canvas.drawRect(
            Rect.fromCenter(center: p, width: 10, height: 10),
            _line,
          );
      }
    }
    _line.style = PaintingStyle.stroke;
  }

  void _chevron(Canvas canvas, Offset p, double dy, Color color) {
    _line
      ..strokeWidth = TapeStroke.regular
      ..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(p.dx - 5, p.dy + dy + 3)
        ..lineTo(p.dx, p.dy + dy - 2)
        ..lineTo(p.dx + 5, p.dy + dy + 3),
      _line,
    );
  }

  @override
  bool shouldRepaint(_TrailPainter old) => old.palette != palette;
}

/// Normalises [values] to 0 to 1 for the metric ramp, by their 95th percentile so
/// that one spike does not flatten the rest.
List<double> normalise(List<double> values, {double? fixedMax}) {
  if (values.isEmpty) return const [];
  double max;
  if (fixedMax != null) {
    max = fixedMax;
  } else {
    final sorted = List.of(values)..sort();
    max = sorted[math.min(sorted.length - 1, (sorted.length * 0.95).floor())];
  }
  if (max <= 0) return List.filled(values.length, 0);
  return [for (final v in values) (v / max).clamp(0.0, 1.0)];
}

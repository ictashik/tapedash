import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../coach/sample_events.dart';
import '../../../trips/route_geometry.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/strokes.dart';
import 'route_view.dart';

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
    this.view,
    this.onPick,
    this.onTouch,
    this.car,
  });

  /// The replay's car (DESIGN.md 6.12): where it is on the route, and which way it
  /// faces. While it is visible the route behind it is drawn at full strength and
  /// the route ahead dimmed, and the scrubber's cursor dot gives way to it.
  final RouteCar? car;

  /// Any touch on the panel, at the moment of touching (the page's own tap, which
  /// the panel's gestures would otherwise swallow: a tap skips the Debrief, and
  /// waiting out the double-tap to know it was a tap would make that slow).
  final VoidCallback? onTouch;

  /// Where the panel is looking. With one, the trail can be pinched, dragged and
  /// double-tapped (DESIGN.md 6.12); without, it is a picture.
  final RouteViewController? view;

  /// A tap on the route: the geometry's point nearest to it. Only with a [view].
  final ValueChanged<int>? onPick;

  /// How near, in panel points, a tap must be to the route to pick a point.
  static const double pickRadius = 36;

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
    // The scrubber moved the cursor: if the view is zoomed in somewhere else,
    // it goes to the cursor.
    final c = widget.cursor?.value;
    if (widget.view != null &&
        c != null &&
        c != old.cursor?.value &&
        !widget.view!.isChasing) {
      final g = widget.geometry;
      if (c >= 0 && c < g.length) {
        widget.view!.follow(Offset(g.xs[c], g.ys[c]));
      }
    }
  }

  double _lastScale = 1;

  void _onTapUp(TapUpDetails d) {
    final view = widget.view;
    final pick = widget.onPick;
    if (view == null || pick == null) return;
    final at = view.toRoute(d.localPosition);
    final hit = widget.geometry.nearestTo(at.dx, at.dy);
    // The distance in panel points is the route's, scaled.
    if (hit.distance * view.scale <= RouteTrail.pickRadius) pick(hit.point);
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
    final view = widget.view;
    final trail = CustomPaint(
      painter: _TrailPainter(
        state: this,
        palette: palette,
        listenable: Listenable.merge([
          widget.reveal,
          if (widget.cursor != null) widget.cursor!,
          ?view,
          ?widget.car,
        ]),
      ),
    );
    if (view == null) return trail;
    return LayoutBuilder(
      builder: (context, box) {
        view.size = box.biggest;
        return ClipRect(
          child: Listener(
            onPointerDown: (_) => widget.onTouch?.call(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (d) => _lastScale = 1,
              onScaleUpdate: (d) {
                final factor = d.scale / _lastScale;
                _lastScale = d.scale;
                if (factor != 1) view.zoomAt(d.localFocalPoint, factor);
                // Following the car, a pinch must not let go of it: only one
                // finger dragging does.
                if (d.pointerCount == 1 || !view.isChasing) {
                  view.panBy(d.focalPointDelta);
                }
              },
              onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
              onDoubleTap: () {
                final at = _doubleTapAt;
                if (at != null) view.doubleTap(at);
              },
              onTapUp: _onTapUp,
              child: trail,
            ),
          ),
        );
      },
    );
  }

  Offset? _doubleTapAt;
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

  // The ramp's sixteen colours, and the same dimmed for the route ahead of the car:
  // made once per painter (a painter is made when the ramp changes), not per frame.
  late final List<Color> _colours = [
    for (var b = 0; b < RouteTrail.bins; b++)
      RouteTrail.colourOf(b, state.widget.ramp),
  ];
  late final List<Color> _dimColours = [
    for (final c in _colours) c.withValues(alpha: TapeReplay.aheadAlpha),
  ];

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

    // Zoomed, the lines are drawn through the view's transform with their widths
    // divided by its scale, so they stay as thick on screen as at 1; everything
    // that is a mark (the head, the markers, the cursor, the car) is placed through
    // it and drawn at its own size. A heading-up map is turned about the middle of
    // the panel.
    final view = w.view;
    final sc = view?.scale ?? 1.0;
    final off = view?.offset ?? Offset.zero;
    final turn = view?.rotation ?? 0.0;
    Offset screen(double x, double y) =>
        view == null ? Offset(x, y) : view.toScreen(Offset(x, y));
    Offset pos(int i) => screen(g.xs[i], g.ys[i]);

    final car = w.car;
    final replaying = car != null && car.visible;
    // In a replay the route behind the car is bright and the rest is dim.
    final driven = replaying
        ? car.point.floor().clamp(0, g.length - 1)
        : g.length - 1;

    canvas.save();
    if (turn != 0) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(turn);
      canvas.translate(-size.width / 2, -size.height / 2);
    }
    canvas.translate(off.dx, off.dy);
    canvas.scale(sc);

    // The faint underlay (DESIGN.md 6.12), 8 lp at 10%, for a glow with no blur.
    _line
      ..strokeWidth = 8 / sc
      ..color = palette.accentCore.withValues(alpha: 0.10);
    for (var b = 0; b < RouteTrail.bins; b++) {
      _drawBin(canvas, b, last);
    }
    _line.strokeWidth = TapeStroke.bold / sc;
    if (replaying) {
      for (var b = 0; b < RouteTrail.bins; b++) {
        _line.color = _dimColours[b];
        _drawBin(canvas, b, last);
      }
      for (var b = 0; b < RouteTrail.bins; b++) {
        _line.color = _colours[b];
        _drawBin(canvas, b, driven);
      }
      // The segment the car is on, up to the car.
      if (driven < g.length - 1) {
        final m = (w.metric[driven] + w.metric[driven + 1]) / 2;
        _line.color = _colours[RouteTrail.binOf(m)];
        canvas.drawLine(
          Offset(g.xs[driven], g.ys[driven]),
          Offset(car.x, car.y),
          _line,
        );
      }
    } else {
      for (var b = 0; b < RouteTrail.bins; b++) {
        _line.color = _colours[b];
        _drawBin(canvas, b, last);
      }
    }
    canvas.restore();

    if (reveal < 1 && last > 0) {
      // The comet head: a bright dot at the front of the line.
      _fill.color = palette.inkHot;
      canvas.drawCircle(pos(last), 4, _fill);
      _fill.color = palette.accentCore.withValues(alpha: 0.35);
      canvas.drawCircle(pos(last), 8, _fill);
    }

    if (reveal >= 1) _drawMarkers(canvas, g, pos, size);

    final c = w.cursor?.value;
    if (c != null && c >= 0 && c < g.length && !replaying) {
      _fill.color = palette.inkHot;
      canvas.drawCircle(pos(c), 5, _fill);
      _line
        ..strokeWidth = TapeStroke.regular
        ..color = palette.accentCore;
      canvas.drawCircle(pos(c), 8, _line..style = PaintingStyle.stroke);
    }

    if (replaying) _drawCar(canvas, screen(car.x, car.y), car.heading + turn);
  }

  // The car: an arrow with a notch in its tail, pointing up at rest.
  static final Path _carShape = Path()
    ..moveTo(0, -1)
    ..lineTo(0.75, 0.8)
    ..lineTo(0, 0.4)
    ..lineTo(-0.75, 0.8)
    ..close();

  /// The car at [at] on the panel, facing [heading] (radians on the screen, 0 to
  /// the right): a glow, then the arrow.
  void _drawCar(Canvas canvas, Offset at, double heading) {
    const r = TapeReplay.carSize;
    _fill.color = palette.accentCore.withValues(alpha: 0.25);
    canvas.drawCircle(at, r * 1.9, _fill);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(heading + math.pi / 2);
    canvas.scale(r);
    _fill.color = palette.inkHot;
    canvas.drawPath(_carShape, _fill);
    _line
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.regular / r
      ..strokeJoin = StrokeJoin.miter
      ..color = palette.accentCore;
    canvas.drawPath(_carShape, _line);
    canvas.restore();
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

  void _drawMarkers(
    Canvas canvas,
    RouteGeometry g,
    Offset Function(int) pos,
    Size size,
  ) {
    final ink = palette.inkBright;
    final visible = (Offset.zero & size).inflate(12);
    for (final m in state.widget.markers) {
      if (m.point < 0 || m.point >= g.length) continue;
      final p = pos(m.point);
      // Zoomed in, most of the markers are somewhere else.
      if (!visible.contains(p)) continue;
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

  // A new painter means the geometry, the metric or the palette changed (the
  // frames in between repaint through the listenable): draw it.
  @override
  bool shouldRepaint(_TrailPainter old) => true;
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

/// Normalises [values] to 0 to 1 over the range they cover, but over at least
/// [minSpan]: a coolant that stayed within a degree of 90 sits mid-ramp, not at
/// one end of it, since a wide scale is what makes a change look like a change.
List<double> normaliseSpread(List<double> values, {required double minSpan}) {
  if (values.isEmpty) return const [];
  var lo = values.first, hi = values.first;
  for (final v in values) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  if (hi - lo < minSpan) {
    final mid = (lo + hi) / 2;
    lo = mid - minSpan / 2;
    hi = mid + minSpan / 2;
  }
  final span = hi - lo;
  return [for (final v in values) ((v - lo) / span).clamp(0.0, 1.0)];
}

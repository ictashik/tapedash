import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../motion/motion_clock.dart';
import '../motion/spring_value.dart';
import '../tokens/motion_tokens.dart';

/// Where the route panel is looking (DESIGN.md 6.12): a scale and an offset on
/// the route as `RouteGeometry` fitted it, so 1 is the whole route. Pinch, drag,
/// double-tap and the buttons change it; [RouteTrail] draws through it.
///
/// A screen point is `route * scale + offset`. The view is kept so that the route's
/// panel is always full: zoomed in, you cannot drag it off the edge and lose it.
///
/// Gestures set it directly ([zoomAt], [panBy]); the buttons, a double-tap and a
/// jump to the cursor move it on `spring.gauge` (critically damped, so it never
/// overshoots the edge it is clamped to).
class RouteViewController extends ChangeNotifier {
  RouteViewController({required MotionClock clock})
    : _scale = SpringValue(clock: clock, spec: TapeSprings.gauge, initial: 1),
      _x = SpringValue(clock: clock, spec: TapeSprings.gauge),
      _y = SpringValue(clock: clock, spec: TapeSprings.gauge) {
    for (final s in [_scale, _x, _y]) {
      s.addListener(notifyListeners);
    }
  }

  /// The furthest in: 24 times the whole route.
  static const double maxScale = 24;

  final SpringValue _scale;
  final SpringValue _x;
  final SpringValue _y;
  Size _size = Size.zero;

  /// The panel's size, set by [RouteTrail] when it lays out. Zero until then.
  Size get size => _size;

  set size(Size value) {
    if (value == _size) return;
    _size = value;
    _settle();
  }

  double get scale => _scale.value;
  Offset get offset => Offset(_x.value, _y.value);

  /// Whether the view is zoomed in at all.
  bool get isZoomed => scale > 1.001;

  /// Where the view is heading, when it is on a spring.
  double get targetScale => _scale.target;

  /// The panel point [local] as a point of the route (as fitted).
  Offset toRoute(Offset local) => (local - offset) / scale;

  /// The route point [route] as a panel point.
  Offset toScreen(Offset route) => route * scale + offset;

  /// The offset that keeps a panel of the size full at [scale]: the route's
  /// extent, `size * scale`, must cover the panel.
  Offset _clamped(double scale, Offset offset) => Offset(
    offset.dx.clamp(_size.width * (1 - scale), 0.0),
    offset.dy.clamp(_size.height * (1 - scale), 0.0),
  );

  void _settle() {
    final o = _clamped(scale, offset);
    if (o == offset) return;
    _x.jumpTo(o.dx);
    _y.jumpTo(o.dy);
  }

  /// Zooms by [factor] about the panel point [focal], now (a pinch).
  void zoomAt(Offset focal, double factor) {
    final s = (scale * factor).clamp(1.0, maxScale);
    final o = _clamped(s, focal - (focal - offset) * (s / scale));
    _set(s, o);
  }

  /// Drags the view by [delta] panel points, now.
  void panBy(Offset delta) => _set(scale, _clamped(scale, offset + delta));

  void _set(double scale, Offset offset) {
    _scale.jumpTo(scale);
    _x.jumpTo(offset.dx);
    _y.jumpTo(offset.dy);
  }

  /// Moves to zoom [scale] about the panel point [focal], on a spring.
  void animateZoomAt(Offset focal, double scale) {
    final s = scale.clamp(1.0, maxScale);
    final o = _clamped(s, focal - (focal - offset) * (s / this.scale));
    _scale.retarget(s);
    _x.retarget(o.dx);
    _y.retarget(o.dy);
  }

  /// Zooms in by [factor] about the middle of the panel, on a spring.
  void zoomIn([double factor = 2]) => animateZoomAt(
    Offset(_size.width / 2, _size.height / 2),
    math.min(maxScale, _scale.target * factor),
  );

  void zoomOut([double factor = 2]) {
    final s = math.max(1.0, _scale.target / factor);
    animateZoomAt(Offset(_size.width / 2, _size.height / 2), s);
  }

  /// A double-tap at [at]: in by 2.5, or, if already well in, back to the whole
  /// route.
  void doubleTap(Offset at) {
    if (_scale.target > 4) {
      reset();
    } else {
      animateZoomAt(at, _scale.target * 2.5);
    }
  }

  /// The whole route again at once (another trip was chosen).
  void resetNow() => _set(1, Offset.zero);

  /// The whole route again, on a spring.
  void reset() {
    _scale.retarget(1);
    _x.retarget(0);
    _y.retarget(0);
  }

  /// Brings the route point [route] into the middle third of the panel if it is
  /// off it (or near an edge), keeping the zoom: the scrubber moved the cursor
  /// somewhere the view is not looking.
  void follow(Offset route) {
    if (!isZoomed) return;
    final p = toScreen(route);
    final inner = Rect.fromLTWH(
      _size.width * 0.15,
      _size.height * 0.15,
      _size.width * 0.7,
      _size.height * 0.7,
    );
    if (inner.contains(p)) return;
    final centre = Offset(_size.width / 2, _size.height / 2);
    final o = _clamped(scale, centre - route * scale);
    _x.retarget(o.dx);
    _y.retarget(o.dy);
    _scale.retarget(scale);
  }

  @override
  void dispose() {
    for (final s in [_scale, _x, _y]) {
      s.removeListener(notifyListeners);
      s.dispose();
    }
    super.dispose();
  }
}

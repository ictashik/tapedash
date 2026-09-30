import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../motion/motion_clock.dart';
import '../motion/spring_value.dart';
import '../tokens/motion_tokens.dart';

/// Where the route panel is looking (DESIGN.md 6.12): a scale and an offset on
/// the route as `RouteGeometry` fitted it, so 1 is the whole route. Pinch, drag,
/// double-tap and the buttons change it; [RouteTrail] draws through it.
///
/// A screen point is the route point times the scale, plus the offset, turned by
/// [rotation] about the middle of the panel. The view is kept so that the route's
/// panel is always full: zoomed in, you cannot drag it off the edge and lose it.
///
/// Gestures set it directly ([zoomAt], [panBy]); the buttons, a double-tap and a
/// jump to the cursor move it on `spring.gauge` (critically damped, so it never
/// overshoots the edge it is clamped to).
///
/// **The chase camera** (a trip replay): [chaseTo] keeps a point of the route in the
/// middle of the panel, at a zoom and a rotation the replay chooses. The position
/// is exact (the car does not drift on the screen), and the zoom and the turn
/// follow on slow springs. While chasing, the view is not held to the route's panel
/// (the car is never lost), a pinch changes how close the camera sits, and a drag
/// lets go of the car.
class RouteViewController extends ChangeNotifier implements MotionDriven {
  RouteViewController({required this.clock})
    : _scale = SpringValue(clock: clock, spec: TapeSprings.gauge, initial: 1),
      _x = SpringValue(clock: clock, spec: TapeSprings.gauge),
      _y = SpringValue(clock: clock, spec: TapeSprings.gauge),
      _turn = SpringValue(clock: clock, spec: TapeReplay.turn) {
    for (final s in [_scale, _x, _y, _turn]) {
      s.addListener(notifyListeners);
    }
  }

  final MotionClock clock;

  /// The furthest in a pinch goes: 24 times the whole route.
  static const double maxScale = 24;

  final SpringValue _scale;
  final SpringValue _x;
  final SpringValue _y;
  final SpringValue _turn;
  Size _size = Size.zero;

  bool _chasing = false;
  Offset _chasePoint = Offset.zero;
  double _scaleGoal = 1;
  double _turnGoal = 0;
  double _bias = 1;

  /// Bumped when what the buttons show changes (not on every frame of a move).
  final ValueNotifier<int> flags = ValueNotifier(0);
  int _flags = 0;

  /// The panel's size, set by [RouteTrail] when it lays out. Zero until then.
  Size get size => _size;

  set size(Size value) {
    if (value == _size) return;
    _size = value;
    _settle();
  }

  double get scale => _scale.value;
  Offset get offset => Offset(_x.value, _y.value);

  /// How far the map is turned, in radians (0 is north up): what a heading-up map
  /// is. The route is turned about the middle of the panel.
  double get rotation => _turn.value;

  /// Whether the view is zoomed in at all.
  bool get isZoomed => scale > 1.001;

  /// Whether the camera is following a point (the replay's car).
  bool get isChasing => _chasing;

  /// How much closer (above 1) or further (below) than the camera chose it sits,
  /// for a pinch or the buttons.
  double get chaseBias => _bias;

  /// Where the view is heading, when it is on a spring.
  double get targetScale => _scale.target;

  Offset get _centre => Offset(_size.width / 2, _size.height / 2);

  /// The panel point [local] as a point of the route (as fitted).
  Offset toRoute(Offset local) {
    final v = local - _centre;
    final c = math.cos(-rotation), s = math.sin(-rotation);
    final unturned = Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c) + _centre;
    return (unturned - offset) / scale;
  }

  /// The route point [route] as a panel point.
  Offset toScreen(Offset route) {
    final p = route * scale + offset;
    final theta = rotation;
    if (theta == 0) return p;
    final v = p - _centre;
    final c = math.cos(theta), s = math.sin(theta);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c) + _centre;
  }

  /// The offset that keeps a panel of the size full at [scale]: the route's
  /// extent, `size * scale`, must cover the panel.
  Offset _clamped(double scale, Offset offset) => Offset(
    offset.dx.clamp(_size.width * (1 - scale), 0.0),
    offset.dy.clamp(_size.height * (1 - scale), 0.0),
  );

  /// Whether the view is held to the route's panel: not while chasing, and not
  /// while the map is turned.
  bool get _held => !_chasing && rotation.abs() < 1e-6;

  void _settle() {
    if (!_held) return;
    final o = _clamped(scale, offset);
    if (o == offset) return;
    _x.jumpTo(o.dx);
    _y.jumpTo(o.dy);
    _updateFlags();
  }

  /// Zooms by [factor] about the panel point [focal], now (a pinch). Chasing, it
  /// moves the camera closer or further instead, and the car stays in the middle.
  void zoomAt(Offset focal, double factor) {
    if (_chasing) {
      _setBias(_bias * factor);
      return;
    }
    // A chase can have gone further in than a pinch can: never snap back out.
    final s = (scale * factor).clamp(1.0, math.max(maxScale, scale)).toDouble();
    final o = _clamped(s, focal - (focal - offset) * (s / scale));
    _set(s, o);
  }

  /// Drags the view by [delta] panel points, now. Chasing, a drag lets go of the
  /// car instead, and the view stays where it is.
  void panBy(Offset delta) {
    if (_chasing) {
      endChase();
      return;
    }
    _set(scale, _clamped(scale, offset + delta));
  }

  void _set(double scale, Offset offset) {
    _scale.jumpTo(scale);
    _x.jumpTo(offset.dx);
    _y.jumpTo(offset.dy);
    _updateFlags();
  }

  /// Moves to zoom [scale] about the panel point [focal], on a spring.
  void animateZoomAt(Offset focal, double scale) {
    final s = scale.clamp(1.0, maxScale).toDouble();
    final o = _clamped(s, focal - (focal - offset) * (s / this.scale));
    _scale.retarget(s);
    _x.retarget(o.dx);
    _y.retarget(o.dy);
    _updateFlags();
  }

  /// Zooms in by [factor] about the middle of the panel, on a spring (while
  /// chasing, the camera sits closer).
  void zoomIn([double factor = 2]) {
    if (_chasing) return _setBias(_bias * TapeReplay.biasStep);
    animateZoomAt(_centre, math.min(maxScale, _scale.target * factor));
  }

  void zoomOut([double factor = 2]) {
    if (_chasing) return _setBias(_bias / TapeReplay.biasStep);
    final s = math.max(1.0, _scale.target / factor);
    animateZoomAt(_centre, s);
  }

  /// A double-tap at [at]: in by 2.5 or, if already well in, back to the whole
  /// route. Chasing, it puts the camera back where it chose to be.
  void doubleTap(Offset at) {
    if (_chasing) return _setBias(1);
    if (_scale.target > 4) {
      reset();
    } else {
      animateZoomAt(at, _scale.target * 2.5);
    }
  }

  /// The whole route again at once (another trip was chosen).
  void resetNow() {
    _chasing = false;
    _bias = 1;
    _scale.setSpec(TapeSprings.gauge);
    _set(1, Offset.zero);
    _turn.jumpTo(0);
    _updateFlags();
  }

  /// The whole route again, on a spring (and north up).
  void reset() {
    _chasing = false;
    _bias = 1;
    _scale.setSpec(TapeSprings.gauge);
    _scale.retarget(1);
    _x.retarget(0);
    _y.retarget(0);
    _turn.retarget(_unwrapped(0));
    _updateFlags();
  }

  /// Brings the route point [route] into the middle third of the panel if it is
  /// off it (or near an edge), keeping the zoom: the scrubber moved the cursor
  /// somewhere the view is not looking.
  void follow(Offset route) {
    if (!isZoomed || _chasing || !_held) return;
    final p = toScreen(route);
    final inner = Rect.fromLTWH(
      _size.width * 0.15,
      _size.height * 0.15,
      _size.width * 0.7,
      _size.height * 0.7,
    );
    if (inner.contains(p)) return;
    final centre = _centre;
    final o = _clamped(scale, centre - route * scale);
    _x.retarget(o.dx);
    _y.retarget(o.dy);
    _scale.retarget(scale);
    _updateFlags();
  }

  // ---- The chase camera ----

  /// Keeps the route point [route] in the middle of the panel, at zoom [scale]
  /// (before the pinch's [chaseBias]) and turned by [rotation] radians (null keeps
  /// the map as it is): call it whenever the car has moved. It starts the chase.
  void chaseTo(Offset route, {required double scale, double? rotation}) {
    final wasChasing = _chasing;
    _chasing = true;
    _chasePoint = route;
    _scaleGoal = scale;
    if (rotation != null) _turnGoal = _unwrapped(rotation);
    if (!wasChasing) {
      // Begin from where the view is, and let the slow springs take it from there.
      _scale.setSpec(TapeReplay.zoom);
      _updateFlags();
    }
    // The car is in the middle now, not a frame from now.
    _centreOnCar();
    clock.attach(this);
  }

  /// Lets go of the car: the view stays where it is, turned back to north up, and
  /// held to the route's panel again.
  void endChase() {
    if (!_chasing) return;
    _chasing = false;
    _bias = 1;
    _scale.setSpec(TapeSprings.gauge);
    final s = _scale.value;
    _scale.retarget(s);
    _turn.retarget(_unwrapped(0));
    final o = _clamped(s, offset);
    _x.retarget(o.dx);
    _y.retarget(o.dy);
    _updateFlags();
  }

  void _setBias(double bias) {
    _bias = bias.clamp(TapeReplay.biasMin, TapeReplay.biasMax).toDouble();
    clock.attach(this);
    _updateFlags();
  }

  /// [angle] as the same direction at the turn nearest to where the map is now, so
  /// that it takes the short way round.
  double _unwrapped(double angle) {
    final d = angle - _turn.value;
    return _turn.value + math.atan2(math.sin(d), math.cos(d));
  }

  @override
  bool advance(double dt, Duration time) {
    if (!_chasing) return false;
    final goal = (_scaleGoal * _bias).clamp(1.0, TapeReplay.chaseMaxScale);
    _scale.track(goal.toDouble(), dt);
    _turn.track(_turnGoal, dt);
    _centreOnCar();
    final settled =
        (_scale.value - goal).abs() < 1e-3 &&
        (_turn.value - _turnGoal).abs() < 1e-4 &&
        _scale.velocity.abs() < 1e-3 &&
        _turn.velocity.abs() < 1e-4;
    return !settled;
  }

  /// The offset that puts the followed point in the middle of the panel at the
  /// zoom the view has now.
  void _centreOnCar() {
    final s = _scale.value;
    _x.place(_size.width / 2 - _chasePoint.dx * s);
    _y.place(_size.height / 2 - _chasePoint.dy * s);
  }

  void _updateFlags() {
    final next =
        (_scale.target > 1.001 ? 1 : 0) |
        (_scale.target >= maxScale - 0.01 ? 2 : 0) |
        (_chasing ? 4 : 0) |
        (_bias >= TapeReplay.biasMax - 0.01 ? 8 : 0) |
        (_bias <= TapeReplay.biasMin + 0.01 ? 16 : 0);
    if (next == _flags) return;
    _flags = next;
    flags.value = next;
  }

  @override
  void dispose() {
    clock.detach(this);
    for (final s in [_scale, _x, _y, _turn]) {
      s.removeListener(notifyListeners);
      s.dispose();
    }
    flags.dispose();
    super.dispose();
  }
}

/// Where the replay's car is on the route, for [RouteTrail] to draw and the camera
/// to follow: updated in place on every frame, so that a replay allocates nothing.
class RouteCar extends ChangeNotifier {
  /// The fractional index into the geometry's points.
  double point = 0;

  /// The position on the route, in the geometry's panel units.
  double x = 0;
  double y = 0;

  /// The direction of travel on the route, in radians (0 is right, y is down).
  double heading = 0;

  bool visible = false;

  void place(double point, double x, double y, double heading) {
    this.point = point;
    this.x = x;
    this.y = y;
    this.heading = heading;
    visible = true;
    notifyListeners();
  }

  void hide() {
    if (!visible) return;
    visible = false;
    notifyListeners();
  }
}

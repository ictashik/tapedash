import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';

import '../tokens/motion_tokens.dart';
import 'motion_clock.dart';

/// A number that moves by a spring (DESIGN.md 5.3), on the [MotionClock].
///
/// Give it a new [target] whenever the data changes. Each time it starts a fresh
/// `SpringSimulation` from where it is and how fast it is going, so momentum is
/// kept and the value never jumps (DESIGN.md 5.2). The simulation is analytic, so
/// a dropped frame cannot make it jump either.
///
/// It is a [Listenable]: painters repaint from it, and it tells them nothing
/// once it has come to rest.
class SpringValue extends ChangeNotifier implements MotionDriven {
  SpringValue({
    required this.clock,
    required this._spec,
    double initial = 0,
    this.precision = 0.001,
  }) : _value = initial,
       _target = initial;

  final MotionClock clock;

  /// How close to the target, in the value's own units, counts as arrived, and
  /// how slow, per second, counts as still.
  final double precision;

  SpringSpec _spec;
  SpringSimulation? _simulation;
  Duration _startedAt = Duration.zero;
  double _value;
  double _velocity = 0;
  double _target;
  bool _disposed = false;

  /// Where the value is now.
  double get value => _value;

  /// How fast it is moving, in units per second.
  double get velocity => _velocity;

  /// Where it is heading.
  double get target => _target;

  SpringSpec get spec => _spec;

  /// Whether it has come to rest.
  bool get isSettled => _simulation == null;

  /// Sends the value towards [target] from where it is now, keeping its
  /// velocity. A target that is not a finite number is ignored, so a bad sample
  /// can never put a NaN on screen.
  void retarget(double target) {
    if (_disposed || !target.isFinite) return;
    _target = target;
    _simulation = SpringSimulation(
      _spec.description,
      _value,
      target,
      _velocity,
    );
    _startedAt = clock.now;
    clock.attach(this);
  }

  /// Puts the value at [value] at once, at rest. For the first reading of a
  /// signal, and for anything that must not animate.
  void jumpTo(double value) {
    if (_disposed || !value.isFinite) return;
    _simulation = null;
    _value = value;
    _target = value;
    _velocity = 0;
    clock.detach(this);
    notifyListeners();
  }

  /// Changes the spring, for reduce motion. It takes effect from the next
  /// retarget, and the one in flight is restarted with it so it does not finish
  /// on the old one.
  void setSpec(SpringSpec spec) {
    if (spec.stiffness == _spec.stiffness &&
        spec.dampingRatio == _spec.dampingRatio) {
      return;
    }
    _spec = spec;
    if (_simulation != null) retarget(_target);
  }

  @override
  bool advance(double dt, Duration time) {
    final simulation = _simulation;
    if (simulation == null) return false;
    final t = (time - _startedAt).inMicroseconds / 1e6;
    final x = simulation.x(t);
    final v = simulation.dx(t);
    if (!x.isFinite || !v.isFinite) {
      // It cannot happen with finite inputs; if it ever does, land on the target.
      _finish();
      return false;
    }
    if ((x - _target).abs() <= precision && v.abs() <= precision) {
      _finish();
      return false;
    }
    _value = x;
    _velocity = v;
    notifyListeners();
    return true;
  }

  void _finish() {
    _simulation = null;
    _value = _target;
    _velocity = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    clock.detach(this);
    super.dispose();
  }
}

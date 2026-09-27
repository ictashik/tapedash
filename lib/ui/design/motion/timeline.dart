import 'package:flutter/animation.dart' show Curve;
import 'package:flutter/foundation.dart';

import 'motion_clock.dart';

/// A stretch of time on the [MotionClock], for the choreographed moments that have
/// a length rather than a value to follow: the cold open, the ignition sequence,
/// the debrief (DESIGN.md 5.7).
///
/// It runs from 0 to its length once, notifies its painters on every frame, and
/// calls [onDone] at the end. Because it runs on the motion clock it slows with
/// `timeDilation`, which is how these moments are tuned.
class Timeline extends ChangeNotifier implements MotionDriven {
  Timeline({required this.clock, required this.length, this.onDone});

  final MotionClock clock;
  final Duration length;

  /// Called once, when the timeline reaches its end.
  final VoidCallback? onDone;

  double _seconds = 0;
  bool _running = false;
  bool _done = false;

  double get _total => length.inMicroseconds / 1e6;

  /// How far it has run, in seconds.
  double get seconds => _seconds;

  /// How far it has run as a share of its length, 0 to 1.
  double get progress => _total <= 0 ? 1 : (_seconds / _total).clamp(0.0, 1.0);

  bool get isRunning => _running;
  bool get isDone => _done;

  /// Starts from the beginning.
  void start() {
    _seconds = 0;
    _done = false;
    _running = true;
    clock.attach(this);
    notifyListeners();
  }

  /// Jumps to the end at once: tapping through a debrief (DESIGN.md 7.5).
  void skip() {
    if (_done) return;
    _seconds = _total;
    _finish();
  }

  @override
  bool advance(double dt, Duration time) {
    if (!_running) return false;
    _seconds += dt;
    if (_seconds >= _total) {
      _seconds = _total;
      _finish();
      return false;
    }
    notifyListeners();
    return true;
  }

  void _finish() {
    _running = false;
    _done = true;
    clock.detach(this);
    notifyListeners();
    onDone?.call();
  }

  /// [seconds] mapped through the interval `from` to `to` (in seconds) and a curve:
  /// 0 before it, 1 after it, and the curve's value inside.
  static double interval(
    double seconds,
    double from,
    double to, [
    Curve? curve,
  ]) {
    if (seconds <= from) return 0;
    if (seconds >= to) return 1;
    final t = (seconds - from) / (to - from);
    return curve?.transform(t) ?? t;
  }

  @override
  void dispose() {
    clock.detach(this);
    super.dispose();
  }
}

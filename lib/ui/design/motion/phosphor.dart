import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../tokens/motion_tokens.dart';
import 'motion_clock.dart';

/// Phosphor persistence (DESIGN.md 5.5): a luminous element does not switch off
/// at once, it decays like a VFD or a CRT.
///
/// The level rises towards its target with one time constant and falls with a
/// slower one, both exponential. The step is exact for any frame length, so a
/// slow frame decays as far as it should and no further.
class Phosphor {
  const Phosphor({
    this.riseSeconds = TapeMotion.phosphorRiseSeconds,
    this.decaySeconds = TapeMotion.phosphorDecaySeconds,
  });

  final double riseSeconds;
  final double decaySeconds;

  /// The level after [dt] seconds, from [level] towards [target] (both 0 to 1).
  double step(double level, double target, double dt) {
    final tau = target > level ? riseSeconds : decaySeconds;
    return target + (level - target) * math.exp(-dt / tau);
  }
}

/// The phosphor of many elements at once: the segments of the tach arc and of the
/// shift horizon, which are drawn in a batch (DESIGN.md 9.3).
///
/// Set each element's target with [setTarget] and read its [levels] when
/// painting. It steps them all each frame without allocating, and asks for
/// frames only while any of them is still moving.
class PhosphorBank extends ChangeNotifier implements MotionDriven {
  PhosphorBank({
    required this.clock,
    required this.count,
    this.phosphor = const Phosphor(),
    this.epsilon = 1 / 512,
  }) : levels = Float32List(count),
       _targets = Float32List(count);

  final MotionClock clock;
  final int count;
  final Phosphor phosphor;

  /// A level this close to its target has arrived: about a quarter of one step
  /// of an 8-bit colour.
  final double epsilon;

  /// The current level of each element, 0 to 1. Read it when painting.
  final Float32List levels;
  final Float32List _targets;

  /// Sets one element's target level, 0 to 1.
  void setTarget(int index, double target) {
    _targets[index] = target;
    clock.attach(this);
  }

  /// Sets every element's target at once from [target], a function of its index.
  void setAll(double Function(int index) target) {
    for (var i = 0; i < count; i++) {
      _targets[i] = target(i);
    }
    clock.attach(this);
  }

  /// Puts every element at [level] at once, at rest.
  void reset([double level = 0]) {
    levels.fillRange(0, count, level);
    _targets.fillRange(0, count, level);
    notifyListeners();
  }

  double targetOf(int index) => _targets[index];

  @override
  bool advance(double dt, Duration time) {
    // One pair of exponentials for the whole bank, not one per element.
    final rise = math.exp(-dt / phosphor.riseSeconds);
    final fall = math.exp(-dt / phosphor.decaySeconds);
    var moving = false;
    for (var i = 0; i < count; i++) {
      final level = levels[i];
      final target = _targets[i];
      if (level == target) continue;
      final k = target > level ? rise : fall;
      var next = target + (level - target) * k;
      if ((next - target).abs() <= epsilon) {
        next = target;
      } else {
        moving = true;
      }
      levels[i] = next;
    }
    notifyListeners();
    return moving;
  }

  @override
  void dispose() {
    clock.detach(this);
    super.dispose();
  }
}

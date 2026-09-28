import 'package:flutter/foundation.dart';

import '../tokens/motion_tokens.dart';
import 'motion_clock.dart';
import 'spring_value.dart';

/// The parked share (DESIGN.md 7.2): a 0-to-1 blend a screen's Parked
/// choreography reads, 0 in Motion and 1 in Parked.
///
/// The rise runs on `spring.reveal` (the soft, staggered parked transition);
/// the fall on `spring.snap`, inside the [TapeMotion.motionReturn] the motion
/// return allows -- motion beats beauty, so the fall cancels whatever rise is
/// in flight rather than racing it, from where it is and at whatever speed it
/// had already reached (the same chase-and-settle pattern the Strip's pages
/// and the parked dock use). It is a [ValueListenable]: painters take it as
/// their `repaint:` and read it fresh in paint (DESIGN.md 9.3), so nothing
/// rebuilds for the transition, and it says nothing once it has settled.
class ParkedShare extends ChangeNotifier implements ValueListenable<double> {
  ParkedShare({
    required this.source,
    required MotionClock clock,
    required bool initiallyParked,
    this.revealSpec = TapeSprings.reveal,
    this.snapSpec = TapeSprings.snap,
  }) : _spring = SpringValue(
         clock: clock,
         spec: revealSpec,
         initial: initiallyParked ? 1 : 0,
       ) {
    _spring.addListener(notifyListeners);
    source.addListener(_onSource);
  }

  /// The parked-or-motion flag the blend follows.
  final ValueListenable<bool> source;

  /// The spring the rise runs on, and the one the fall cancels it with.
  final SpringSpec revealSpec;
  final SpringSpec snapSpec;

  final SpringValue _spring;

  /// Whether it has come to rest on its target.
  bool get isSettled => _spring.isSettled;

  @override
  double get value => _spring.value;

  void _onSource() {
    if (source.value) {
      _spring
        ..setSpec(revealSpec)
        ..retarget(1);
    } else {
      // The motion return: inside its own 300 ms, cancelling the rise.
      _spring
        ..setSpec(snapSpec)
        ..retarget(0);
    }
  }

  /// One item's own share of a staggered group (DESIGN.md 5.7), from the
  /// group's whole [share]: item [index] starts [TapeMotion.stagger] after
  /// the first, in the group's [TapeMotion.maxStaggered]-item budget, and
  /// everything past that budget moves with the last staggered item.
  /// Exposed for a direct test, and so the choreography's one formula is
  /// sourced once.
  static double staggered(double share, int index) {
    final start =
        index.clamp(0, TapeMotion.maxStaggered - 1) / TapeMotion.maxStaggered;
    return ((share - start) / (1 - start)).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    source.removeListener(_onSource);
    _spring.removeListener(notifyListeners);
    _spring.dispose();
    super.dispose();
  }
}

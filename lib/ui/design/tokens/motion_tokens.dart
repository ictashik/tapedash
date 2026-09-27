import 'dart:math' as math;

import 'package:flutter/animation.dart' show Cubic;
import 'package:flutter/physics.dart' show SpringDescription;

/// A spring, by its stiffness and damping ratio (mass is 1, DESIGN.md 5.3).
class SpringSpec {
  const SpringSpec(this.name, this.stiffness, this.dampingRatio);

  final String name;
  final double stiffness;

  /// 1 is critically damped: it arrives without overshooting.
  final double dampingRatio;

  SpringDescription get description => SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: stiffness,
    ratio: dampingRatio,
  );

  /// The natural frequency, in radians per second.
  double get omega => math.sqrt(stiffness);

  /// The same spring with no overshoot, for reduce motion (DESIGN.md 5.8).
  SpringSpec get withoutOvershoot =>
      dampingRatio >= 1 ? this : SpringSpec(name, stiffness, 1);

  @override
  String toString() => 'spring.$name($stiffness, $dampingRatio)';
}

/// The five springs (DESIGN.md 5.3). Positions and value-driven motion use these,
/// never a fixed-duration tween.
abstract final class TapeSprings {
  /// About 4% overshoot, settles in about 0.35 s: the tach needle, the tapes and
  /// bar fills.
  static const SpringSpec needle = SpringSpec('needle', 260, 0.72);

  /// No overshoot: the value under a numeral, and the eco puck.
  static const SpringSpec gauge = SpringSpec('gauge', 380, 1);

  /// Confident, with a tiny settle: page moves and shared elements.
  static const SpringSpec page = SpringSpec('page', 170, 0.92);

  /// Soft: panels unfolding, sheets.
  static const SpringSpec reveal = SpringSpec('reveal', 120, 0.85);

  /// Instant but not abrupt: toggles and selection.
  static const SpringSpec snap = SpringSpec('snap', 600, 1);

  static const List<SpringSpec> all = [needle, gauge, page, reveal, snap];
}

/// Durations, for fades and draw-ons only. Everything positional uses a spring
/// (DESIGN.md 5.4).
abstract final class TapeDurations {
  static const Duration micro = Duration(milliseconds: 120);
  static const Duration quick = Duration(milliseconds: 220);
  static const Duration scene = Duration(milliseconds: 480);
  static const Duration cinematic = Duration(milliseconds: 1200);

  /// Exits run at about 0.7 of an entrance (DESIGN.md 5.7).
  static const double exitShare = 0.7;
}

/// The two curves (DESIGN.md 5.4).
abstract final class TapeCurves {
  /// Expo-out.
  static const Cubic enter = Cubic(0.16, 1, 0.3, 1);
  static const Cubic exit = Cubic(0.7, 0, 0.84, 0);
}

/// The numbers behind the motion system that are not springs or durations.
abstract final class TapeMotion {
  /// After a stall, one frame counts as no more than this (DESIGN.md 5.9).
  static const double maxFrameSeconds = 0.05;

  /// Phosphor: a luminous element rises with this time constant and decays
  /// more slowly, like a VFD or CRT (DESIGN.md 5.5).
  static const double phosphorRiseSeconds = 0.030;
  static const double phosphorDecaySeconds = 0.180;

  /// Stale data (DESIGN.md 5.2): a value with no new sample for 1.5 s holds, and
  /// fades to the `stale` colour over 600 ms. Fresh data returns it to colour
  /// over 200 ms.
  static const Duration staleAfter = Duration(milliseconds: 1500);
  static const Duration staleFade = Duration(milliseconds: 600);
  static const Duration staleRecover = Duration(milliseconds: 200);

  /// The odometer's detent (DESIGN.md 5.6): a digit rests centred for the first
  /// 0.3 of the way to the next one, rolls through the middle 0.4, and rests on
  /// the next for the last 0.3.
  static const double detentStart = 0.3;
  static const double detentEnd = 0.7;

  /// How far a glyph may be from centre, in digit heights, before it has faded
  /// out. A glyph half-way between two positions is half faded.
  static const double odometerFadeDistance = 1;

  /// The longest lead compensation allowed (DESIGN.md 5.2).
  static const Duration maxLead = Duration(milliseconds: 150);

  /// The needle's trail is sampled this often (DESIGN.md 6.2).
  static const Duration trailInterval = Duration(milliseconds: 30);

  /// The peak-hold tick holds for 3 s and fades over 1 s (DESIGN.md 6.2).
  static const Duration peakHold = Duration(seconds: 3);
  static const Duration peakFade = Duration(seconds: 1);

  /// How long ambient light must stay past a threshold before Daylight or Night
  /// comes on or goes off (DESIGN.md 4.4).
  static const Duration modeDwell = Duration(seconds: 10);

  /// One step of the Design Lab's value slider, for its sample readings
  /// (DESIGN.md 13.2). Not a value the design draws with; it just keeps a literal
  /// out of the Lab's own code, alongside the others here.
  static const Duration labNudgeStep = Duration(milliseconds: 100);

  /// The runtime governor steps a tier down when the 90th percentile frame has
  /// been over budget for 5 s, judged second by second over the last second of
  /// frames, and shows the step as a 400 ms crossfade (DESIGN.md 9.2). A window
  /// longer than a second would keep counting a bad stretch after it had ended.
  static const Duration governorOverBudget = Duration(seconds: 5);
  static const Duration governorWindow = Duration(seconds: 1);
  static const Duration tierCrossfade = Duration(milliseconds: 400);

  /// Nothing may flash faster than this (DESIGN.md 11).
  static const double maxFlashHz = 3;

  /// A smooth 0-to-1 breathing pulse at [hz], for the components that
  /// "pulse" or "breathe" rather than hard-flash: the status strip's
  /// searching adapter at 0.5 Hz, an alert's critical bracket at 1 Hz. Both
  /// are well under [maxFlashHz], which bounds a hard on/off flash (the
  /// shift horizon's redline) -- a different, sharper kind of motion this
  /// sine does not produce.
  static double pulseShare(double phaseSeconds, double hz) =>
      (math.sin(2 * math.pi * hz * phaseSeconds) + 1) / 2;

  /// Burn-in protection (DESIGN.md 4.1): the whole cluster drifts by up to this
  /// many logical pixels, one step of a 3x3 cycle every 3 minutes, eased over
  /// 8 s.
  static const double burnInDrift = 2;
  static const Duration burnInStep = Duration(minutes: 3);
  static const Duration burnInEase = Duration(seconds: 8);

  /// When the car starts to move, the Motion layout is back within this long
  /// (DESIGN.md 7.2).
  static const Duration motionReturn = Duration(milliseconds: 300);

  /// A staggered group starts an item every 30 to 50 ms, and no more than six
  /// items are staggered (DESIGN.md 5.7).
  static const Duration stagger = Duration(milliseconds: 40);
  static const int maxStaggered = 6;

  /// The parallax of each layer against the page's own move (DESIGN.md 7.1):
  /// L0, L1, L2 and L3.
  static const List<double> parallax = [0.1, 0.6, 1.0, 1.05];

  /// Touch bloom (DESIGN.md 6.16): scale and alpha at the start and end.
  static const double bloomScaleFrom = 0.6;
  static const double bloomScaleTo = 1.4;
  static const double bloomAlphaFrom = 0.35;
}

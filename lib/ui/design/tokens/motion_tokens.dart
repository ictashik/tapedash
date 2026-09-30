import 'dart:math' as math;

import 'package:flutter/animation.dart' show Cubic, Curve, Curves;
import 'package:flutter/physics.dart' show SpringDescription;

import '../../../core/dsp/playout.dart';

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
/// How each live signal is played out between samples (DESIGN.md 5.2, step 3):
/// the fast PIDs, which a cheap adapter gives once or twice a second. The caps
/// are how far the value is carried past the newest sample when the next is late;
/// the numbers were tuned on the recordings of the first real drives (`docs/
/// DECISIONS.md`).
abstract final class TapePlayout {
  /// Engine speed.
  static const PlayoutSpec rpm = PlayoutSpec(tailCap: 100, min: 0);

  /// Road speed, km/h.
  static const PlayoutSpec speed = PlayoutSpec(tailCap: 1.5, min: 0);

  /// Throttle position and engine load, in percent.
  static const PlayoutSpec percent = PlayoutSpec(tailCap: 4, min: 0, max: 100);
}

abstract final class TapeDurations {
  static const Duration micro = Duration(milliseconds: 120);
  static const Duration quick = Duration(milliseconds: 220);
  static const Duration scene = Duration(milliseconds: 480);
  static const Duration cinematic = Duration(milliseconds: 1200);

  /// Pit Stop's save animation: the fuel column fills and collapses (DESIGN.md 7.9).
  static const Duration pitStopSave = Duration(milliseconds: 900);

  /// A money figure (₹ this trip, ₹/km) is stale after this long with no new
  /// estimate: it moves with the fuel about once a second, and a trip that has
  /// stopped answering holds its figure rather than fading it like a needle.
  static const Duration moneyStale = Duration(seconds: 30);

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

  /// A signal whose samples come far apart is allowed 2.5 of its own gaps before
  /// it is stale, but never longer than this (DESIGN.md 5.2).
  static const Duration staleAfterMax = Duration(seconds: 4);

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

  /// How far a swipe toward a locked page can pull the strip into the locked
  /// side before it stops, as a share of the page width (DESIGN.md 7.1's
  /// rubber-band). Firm: the lock is a rule, not a suggestion.
  static const double lockedSwipeGive = 0.08;

  /// A release faster than this, in pages per second, is a fling: it moves
  /// one page in its own direction rather than settling to the nearest
  /// (DESIGN.md 7.1).
  static const double pageFlingVelocity = 0.35;

  /// How long the lock glyph shows after a swipe toward a locked page
  /// (DESIGN.md 7.1).
  static const Duration lockGlyph = Duration(milliseconds: 800);

  /// The ignition sequence (DESIGN.md 7.13), Full: each step's window on the
  /// sequence's own clock, in milliseconds. The tach segments light in a
  /// wave, the needle sweeps to redline and back, the numerals roll up from
  /// 0, the horizon draws out from the centre and the flanks fade in.
  static const int ignitionWaveFromMs = 0;
  static const int ignitionWaveToMs = 450;
  static const int ignitionNeedleFromMs = 150;

  /// Where the needle turns back from redline to the live rpm: the middle of
  /// the 150-900 ms sweep window.
  static const int ignitionNeedleTurnMs = 525;
  static const int ignitionNumeralsFromMs = 300;
  static const int ignitionHorizonFromMs = 600;
  static const int ignitionHorizonToMs = 1200;
  static const int ignitionLengthMs = 1200;

  /// The wave is expo-out (DESIGN.md 7.13); the horizon and flanks ease out.
  static const Curve ignitionWaveCurve = Curves.easeOutExpo;
  static const Curve ignitionRevealCurve = Curves.easeOutCubic;

  /// Reduce motion's replacement for the sweep: a plain fade (DESIGN.md 5.8).
  static const int ignitionReducedMs = 200;

  /// Shared elements (DESIGN.md 7.1): the page a flying element is leaving
  /// keeps its own copy only this far into the flight, and the page it is
  /// arriving on shows its own copy only from this far in. Between them the
  /// one travelling copy is the only one on screen -- "the number you were
  /// watching never disappears; it travels." Both are shares of the flight's
  /// own progress, which itself moves on `spring.page`, so the fades inherit
  /// the spring's ease.
  static const double sharedElementDepart = 0.2;
  static const double sharedElementArrive = 0.9;

  /// Touch bloom (DESIGN.md 6.16): scale and alpha at the start and end.
  static const double bloomScaleFrom = 0.6;
  static const double bloomScaleTo = 1.4;
  static const double bloomAlphaFrom = 0.35;

  /// How often the status strip's clock re-reads the wall clock (DESIGN.md
  /// 6.9): finer than a minute, since nothing reading it shows seconds, so
  /// an idle clock costs almost nothing.
  static const Duration wallClockTick = Duration(seconds: 20);
}

/// The Debrief (DESIGN.md 7.5): what runs when a trip ends, in seconds from its
/// start. At most 4.5 s in all; tapping skips to the end.
abstract final class TapeDebrief {
  /// The Money Tape rolls up into the WHERE IT WENT bar (0.6 s).
  static const double barFrom = 0.8;
  static const double barTo = 1.4;

  /// The route draws itself in light with a comet head (1.6 s).
  static const double routeFrom = 1.4;
  static const double routeTo = 3.0;

  /// The receipt's figures roll up from 0 (0.8 s).
  static const double receiptFrom = 3.0;
  static const double receiptTo = 3.8;

  /// The tip fades in last.
  static const double tipFrom = 3.8;
  static const double tipTo = 4.3;

  static const Duration length = Duration(milliseconds: 4500);
}

/// The trip replay on Review (DESIGN.md 6.12): how fast it can run, and how the
/// chase camera frames the car.
abstract final class TapeReplay {
  /// The speeds of a replay, as multiples of real time: a tap on the speed button
  /// goes to the next, and round again.
  static const List<double> rates = [1, 2, 3];

  /// A marker's text stays up for this many seconds of the replay after the moment
  /// it marks (multiplied by the rate, so it is as long to the eye at 3 times).
  static const double eventHoldSeconds = 2.5;

  /// The camera shows the ground the car will cover in this many seconds, across the
  /// panel's width, so that it zooms out as the car speeds up and in as it slows.
  static const double chaseSeconds = 22;

  /// The least ground, in metres, the panel's width shows (a car at a standstill),
  /// and the most.
  static const double chaseMinMetres = 140;
  static const double chaseMaxMetres = 1600;

  /// The chase camera can go further in than a pinch can: a long route's whole
  /// view is a hundred times wider than the ground the camera wants.
  static const double chaseMaxScale = 400;

  /// How quickly the camera follows the car, and the way the map is turned, in
  /// radians per second of natural frequency (a critically damped follow).
  static const double chaseFollowOmega = 7;
  static const double chaseTurnOmega = 3.2;
  static const double chaseZoomOmega = 2.4;

  /// The car's mark, in logical pixels: its half-length.
  static const double carSize = 9;

  /// How far ahead on the route the heading looks, in metres: a corner turns the
  /// map over this distance and GPS scatter does not jerk it.
  static const double headingLookMetres = 35;

  /// More points than the still view, for a zoomed-in camera to follow.
  static const int routePoints = 3000;
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/clock.dart';
import '../../../core/observable.dart';
import '../../../vehicle/reading.dart';
import '../tokens/motion_tokens.dart';
import 'motion_clock.dart';
import 'spring_value.dart';

/// The last three steps of the smoothing pipeline that turns live data into
/// pixels (DESIGN.md 5.2): lead compensation, the spring, and the stale fade.
///
/// The first two steps happen before a reading gets here. The OBD stack stamps
/// each sample at the middle of its round trip (`Reading.at`), and `VehicleState`
/// rejects the impossible ones. What is left:
///
///  3. **Lead compensation** (optional): the target is the value plus its rate
///     times a lead. The lead is 0 until it is tuned on a real car, capped at
///     150 ms, and off while the rate is noisy.
///  4. **Spring**: the displayed value moves towards the target on a spring. Each
///     new sample retargets it from the current position and velocity, so
///     momentum is kept and nothing jumps.
///  5. **Render**: painters read [value] on the frame they draw, from the one
///     [MotionClock].
///
/// **Stale data:** with no sample for [staleAfter] the value holds, and
/// [staleness] rises from 0 to 1 over 600 ms, which the readout draws as a fade
/// to the `stale` colour. A fresh sample brings it back over 200 ms.
///
/// It is a [Listenable] that tells its painters only when the value or the
/// staleness has changed, and it asks the clock for frames only while there is
/// something to do.
class SmoothedSignal extends ChangeNotifier implements MotionDriven {
  SmoothedSignal({
    required this.motion,
    required this.clock,
    required SpringSpec spring,
    this.staleAfter = TapeMotion.staleAfter,
    Duration lead = Duration.zero,
    double initial = 0,
    double precision = 0.001,
    this.animateFirst = false,
    this.noiseFloor = 1,
  }) : _lead = _capped(lead),
       _spring = SpringValue(
         clock: motion,
         spec: spring,
         initial: initial,
         precision: precision,
       ) {
    _spring.addListener(notifyListeners);
  }

  /// The longest lead compensation allowed (DESIGN.md 5.2).
  static const Duration maxLead = TapeMotion.maxLead;

  final MotionClock motion;

  /// The domain clock, which the readings' timestamps are on. Staleness is judged
  /// against real time, not against the (possibly slowed) motion clock.
  final Clock clock;

  /// How long without a sample before the value is stale.
  final Duration staleAfter;

  /// Whether the first reading animates from the initial value. Off, the first
  /// reading is where the value starts, which is right for a readout that appears
  /// with data already flowing.
  final bool animateFirst;

  /// A rate under this, in units per second, is too small to tell noise from
  /// change, so it never counts as noisy.
  final double noiseFloor;

  final SpringValue _spring;
  Duration _lead;
  Observable<Reading?>? _source;

  Reading? _last;
  double _rate = 0;
  double _lastInstantRate = 0;
  int _flips = 0;
  double _staleness = 0;
  bool _disposed = false;

  static Duration _capped(Duration lead) =>
      lead < Duration.zero ? Duration.zero : (lead > maxLead ? maxLead : lead);

  /// The displayed value: on its spring, towards the latest sample.
  double get value => _spring.value;

  /// How fast the displayed value is moving, in units per second.
  double get velocity => _spring.velocity;

  /// Where the spring is heading.
  double get target => _spring.target;

  /// The rate of change of the readings, in units per second, lightly filtered.
  /// The trend vector on a tape reads this (DESIGN.md 6.3).
  double get rate => _rate;

  /// Whether the readings are jumping about too much for the rate to be trusted:
  /// it has changed sign on each of the last two samples.
  bool get isNoisy => _flips >= 2;

  /// Whether there has been a reading yet. Until then there is nothing to show.
  bool get hasValue => _last != null;

  /// 0 for a fresh value, rising to 1 as a stale value fades to its dim colour.
  double get staleness => _staleness;

  /// Whether the value is stale now: nothing has arrived for [staleAfter].
  bool get isStale {
    final last = _last;
    return last != null && last.age(clock.monotonic()) > staleAfter;
  }

  Duration get lead => _lead;

  /// Sets the lead compensation, capped at 150 ms. Default 0 (DESIGN.md 5.2).
  set lead(Duration value) => _lead = _capped(value);

  /// Follows [source]: each new reading goes into the pipeline. A reading
  /// already there is taken at once.
  void bind(Observable<Reading?> source) {
    _source?.removeListener(_onSource);
    _source = source;
    source.addListener(_onSource);
    _onSource();
  }

  void _onSource() {
    final reading = _source?.value;
    if (reading != null) ingest(reading);
  }

  /// Takes one reading.
  void ingest(Reading reading) {
    if (_disposed || !reading.value.isFinite) return;
    final previous = _last;
    if (previous == reading) return;
    _last = reading;

    if (previous == null) {
      if (animateFirst) {
        _spring.retarget(reading.value);
      } else {
        _spring.jumpTo(reading.value);
      }
    } else {
      final seconds = (reading.at - previous.at).inMicroseconds / 1e6;
      if (seconds > 0) {
        final instant = (reading.value - previous.value) / seconds;
        _trackNoise(instant);
        _rate += 0.5 * (instant - _rate);
      }
      final lead = _lead.inMicroseconds / 1e6;
      final compensated = lead > 0 && !isNoisy
          ? reading.value + _rate * lead
          : reading.value;
      _spring.retarget(compensated);
    }
    // Stay on the clock while fresh, to notice when it goes stale.
    motion.attach(this);
  }

  /// Counts consecutive sign flips of the instantaneous rate, ignoring anything
  /// too small to be more than quantisation.
  void _trackNoise(double instant) {
    final last = _lastInstantRate;
    if (last * instant < 0 &&
        last.abs() > noiseFloor &&
        instant.abs() > noiseFloor) {
      _flips++;
    } else if (instant.abs() > noiseFloor) {
      _flips = 0;
    }
    _lastInstantRate = instant;
  }

  @override
  bool advance(double dt, Duration time) {
    final last = _last;
    if (last == null) return false;
    final stale = last.age(clock.monotonic()) > staleAfter;
    final before = _staleness;
    if (stale) {
      _staleness = math.min(
        1,
        _staleness + dt / (TapeMotion.staleFade.inMicroseconds / 1e6),
      );
    } else {
      _staleness = math.max(
        0,
        _staleness - dt / (TapeMotion.staleRecover.inMicroseconds / 1e6),
      );
    }
    if (_staleness != before) notifyListeners();
    // Fresh: keep watching. Stale: keep going until the fade is done.
    return stale ? _staleness < 1 : true;
  }

  @override
  void dispose() {
    _disposed = true;
    _source?.removeListener(_onSource);
    _spring.removeListener(notifyListeners);
    _spring.dispose();
    motion.detach(this);
    super.dispose();
  }
}

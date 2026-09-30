import 'dart:math' as math;

/// What a [TrackingFilter] is told about a signal: how much to trust a sample,
/// and how fast the signal can really change. Both are in the signal's own unit.
class TrackingSpec {
  const TrackingSpec({
    required this.measurementSigma,
    required this.accelerationSigma,
    required this.maxExtrapolation,
    this.min = double.negativeInfinity,
    this.max = double.infinity,
    this.extrapolationTau = const Duration(milliseconds: 500),
    this.horizon = const Duration(milliseconds: 1500),
    this.restartAfter = const Duration(seconds: 4),
  });

  /// The size of the noise on one sample: rounding to the PID's step, timing of
  /// the sample within its round trip, and how much the engine itself wanders.
  final double measurementSigma;

  /// How hard the signal can be pushed, in units per second squared. Big means
  /// "believe each sample, the signal moves fast"; small means "smooth harder,
  /// it moves slowly". The filter's gain follows from this and from how far
  /// apart the samples are: the slower the adapter, the more each sample is
  /// believed, so the filter never smooths a slow adapter into a laggy one.
  final double accelerationSigma;

  /// The most the estimate may be run ahead of the last sample, in the signal's
  /// unit, whatever the velocity says.
  final double maxExtrapolation;

  /// What the signal can physically be: an estimate is never run past these
  /// (an rpm below 0, a throttle above 100 %).
  final double min;
  final double max;

  /// Between samples the estimate runs ahead at the estimated velocity, but the
  /// velocity decays with this time constant, so the run is at most
  /// `velocity * tau` and never a runaway.
  final Duration extrapolationTau;

  /// The longest time the estimate is run ahead for.
  final Duration horizon;

  /// A gap this long between samples means the past says nothing: start again
  /// from the next sample.
  final Duration restartAfter;
}

/// A constant-velocity Kalman filter for one signal, sampled at irregular times.
///
/// The cheap ELM327 clones give a full read of the fast PIDs only once or twice
/// a second, at uneven intervals, with whole-number steps. Springing straight
/// to each sample looks like a stair: a fast move, then a stop. This filter
/// instead keeps an estimate of the value *and its velocity*, and [predict]
/// carries the value on between samples, so the display moves the way the
/// signal does.
///
/// Two states, value and velocity, and their covariance (`p00`, `p01`, `p11`).
/// A sample at time t:
///
///  1. predicts the state forward by dt (`p += v * dt`, and the covariance grows
///     by the piecewise-constant-acceleration process noise
///     `sigmaA^2 * [dt^4/4 dt^3/2; dt^3/2 dt^2]`: in one step the velocity may
///     change by about `sigmaA * dt`),
///  2. corrects it with the innovation (sample minus prediction) at the
///     Kalman gain, which is computed, not tuned, from the two sigmas of the
///     [TrackingSpec].
///
/// Pure Dart, no allocation per call, and deterministic: the tests drive it
/// with made-up time.
class TrackingFilter {
  TrackingFilter(this.spec);

  final TrackingSpec spec;

  bool _started = false;
  double _p = 0;
  double _v = 0;
  double _p00 = 0;
  double _p01 = 0;
  double _p11 = 0;
  Duration _at = Duration.zero;

  /// Whether a sample has been taken.
  bool get hasEstimate => _started;

  /// The estimated value at the time of the last sample.
  double get value => _p;

  /// The estimated rate of change, in units per second.
  double get velocity => _v;

  /// When the last sample was measured.
  Duration get at => _at;

  /// Forgets everything.
  void reset() {
    _started = false;
    _v = 0;
  }

  /// Takes a sample of [z] measured at [at]. A sample that is not a number is
  /// ignored. One at or before the last is folded in as if it were at the same
  /// time, since sample times are estimates and can come out of order by a few
  /// milliseconds.
  void update(double z, Duration at) {
    if (!z.isFinite) return;
    final r = spec.measurementSigma * spec.measurementSigma;
    var dt = _started ? (at - _at).inMicroseconds / 1e6 : 0.0;
    if (!_started || at - _at > spec.restartAfter) {
      _p = z;
      _v = 0;
      _p00 = r;
      _p01 = 0;
      _p11 = spec.accelerationSigma * spec.accelerationSigma;
      _at = at;
      _started = true;
      return;
    }
    if (dt < 0) dt = 0;

    // Predict.
    final q = spec.accelerationSigma * spec.accelerationSigma;
    final dt2 = dt * dt;
    final pPred = _p + _v * dt;
    final p00 = _p00 + 2 * dt * _p01 + dt2 * _p11 + q * dt2 * dt2 / 4;
    final p01 = _p01 + dt * _p11 + q * dt2 * dt / 2;
    final p11 = _p11 + q * dt2;

    // Correct.
    final s = p00 + r;
    final k0 = p00 / s;
    final k1 = p01 / s;
    final innovation = z - pPred;
    _p = pPred + k0 * innovation;
    _v = _v + k1 * innovation;
    _p00 = p00 - k0 * p00;
    _p01 = p01 - k0 * p01;
    _p11 = p11 - k1 * p01;
    if (at > _at) _at = at;
  }

  /// The estimate at time [now]: the last estimate, run ahead at the velocity,
  /// which fades with the spec's time constant, for at most the horizon and at
  /// most `maxExtrapolation`, scaled down by how far the velocity is trusted, and
  /// kept inside `[min, max]`. Before [update] has been called it is 0.
  ///
  /// [now] is later than the last sample by at least the time the sample spent
  /// on the wire, so this is also what makes up for the adapter's latency.
  double predict(Duration now) {
    if (!_started) return 0;
    var ahead = (now - _at).inMicroseconds / 1e6;
    if (ahead <= 0) return _p;
    final horizon = spec.horizon.inMicroseconds / 1e6;
    if (ahead > horizon) ahead = horizon;
    final tau = spec.extrapolationTau.inMicroseconds / 1e6;
    var run = _v * tau * (1 - math.exp(-ahead / tau));
    // How far to believe the velocity: right after a jump it is a guess (its
    // variance is as big as it is), and a settled ramp has a variance far
    // under its square.
    run *= _v * _v / (_v * _v + _p11);
    final cap = spec.maxExtrapolation;
    if (run > cap) run = cap;
    if (run < -cap) run = -cap;
    return math.min(spec.max, math.max(spec.min, _p + run));
  }
}

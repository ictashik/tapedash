import 'dart:math' as math;

/// How a [PlayoutBuffer] plays a signal out, in the signal's own unit.
class PlayoutSpec {
  const PlayoutSpec({
    required this.tailCap,
    this.min = double.negativeInfinity,
    this.max = double.infinity,
    this.delayShare = 0.65,
    this.maxDelay = const Duration(milliseconds: 600),
    this.tailTau = const Duration(milliseconds: 200),
    this.restartAfter = const Duration(seconds: 4),
  });

  /// The most the value is carried on past the newest sample, when the next has
  /// not come, in the signal's unit.
  final double tailCap;

  /// What the signal can physically be; the value is never played outside.
  final double min;
  final double max;

  /// The delay is this share of the usual gap between samples: 0.65 of a 0.8 s
  /// gap is half a second behind, which is enough that the next sample has
  /// mostly arrived before the display needs it.
  final double delayShare;

  /// The longest the delay is allowed to be.
  final Duration maxDelay;

  /// Past the newest sample the last segment's slope is carried on, fading with
  /// this time constant.
  final Duration tailTau;

  /// A gap this long between samples means the past says nothing.
  final Duration restartAfter;
}

/// Plays a signal that arrives once or twice a second out as a continuous line.
///
/// A cheap adapter gives a fast PID once every 0.6 to 1 s, at uneven intervals.
/// Springing to each sample makes the needle move, stop, move, stop (on the first
/// real drive it stood still for 62% of the time the revs were moving), and
/// running ahead of the samples on a guess of their velocity overshoots at
/// every gear change and every throttle blip, then swings back: a pendulum. This
/// does neither. It keeps the last few samples and shows the **straight line
/// between the two either side of a moment a little in the past**, so the value
/// never goes outside what the car has said, and only ever moves between two
/// readings. The price is the delay, which is scaled to the adapter: about two
/// thirds of the usual gap between samples, so a fast adapter is not held back
/// at all.
///
/// When the next sample is late the value is not left standing: the slope of the
/// last segment carries on for a moment, fading, up to [PlayoutSpec.tailCap].
///
/// Pure Dart, deterministic, and it allocates nothing once its buffer is full.
class PlayoutBuffer {
  PlayoutBuffer(this.spec);

  final PlayoutSpec spec;

  static const int _keep = 12;

  final List<Duration> _at = [];
  final List<double> _value = [];

  /// The average gap between samples, in seconds: a running average, 0 until
  /// there are two samples.
  double _gap = 0;

  /// Whether there is a sample.
  bool get hasSamples => _value.isNotEmpty;

  /// The newest sample's value.
  double get latest => _value.isEmpty ? 0 : _value.last;

  /// The usual gap between samples, in seconds.
  double get gapSeconds => _gap;

  /// How far behind the newest possible moment the value is played, in seconds.
  double get delaySeconds =>
      math.min(spec.delayShare * _gap, spec.maxDelay.inMicroseconds / 1e6);

  void reset() {
    _at.clear();
    _value.clear();
    _gap = 0;
  }

  /// Takes a sample of [value] measured at [at]. Not a number: ignored. At or
  /// before the newest sample's time (the times are estimates, and can come out
  /// of order by a few milliseconds): it replaces the newest, so time only moves
  /// forward.
  void add(double value, Duration at) {
    if (!value.isFinite) return;
    if (_at.isNotEmpty) {
      final gap = at - _at.last;
      if (gap > spec.restartAfter) {
        reset();
      } else if (gap <= Duration.zero) {
        _value[_value.length - 1] = value;
        return;
      } else {
        final seconds = gap.inMicroseconds / 1e6;
        _gap = _gap == 0 ? seconds : _gap + 0.2 * (seconds - _gap);
      }
    }
    if (_at.length == _keep) {
      _at.removeAt(0);
      _value.removeAt(0);
    }
    _at.add(at);
    _value.add(value);
  }

  /// The value to show at [now]: 0 before there is a sample.
  double valueAt(Duration now) {
    if (_value.isEmpty) return 0;
    final tp = now - Duration(microseconds: (delaySeconds * 1e6).round());
    final last = _value.length - 1;
    if (last == 0 || tp <= _at.first) return _clamp(_value.first);
    if (tp >= _at[last]) {
      final ahead = (tp - _at[last]).inMicroseconds / 1e6;
      final seconds = (_at[last] - _at[last - 1]).inMicroseconds / 1e6;
      final slope = (_value[last] - _value[last - 1]) / seconds;
      final tau = spec.tailTau.inMicroseconds / 1e6;
      var run = slope * tau * (1 - math.exp(-ahead / tau));
      if (run > spec.tailCap) run = spec.tailCap;
      if (run < -spec.tailCap) run = -spec.tailCap;
      return _clamp(_value[last] + run);
    }
    var k = last;
    while (k > 1 && _at[k - 1] > tp) {
      k--;
    }
    final t0 = _at[k - 1];
    final f = (tp - t0).inMicroseconds / (_at[k] - t0).inMicroseconds;
    return _clamp(_value[k - 1] + f * (_value[k] - _value[k - 1]));
  }

  double _clamp(double v) => math.min(spec.max, math.max(spec.min, v));
}

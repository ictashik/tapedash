// The tach and speedometer on a real drive (docs/DECISIONS.md, first real drives):
// 300 s of the busiest driving of the first long drive, RPM and speed as the BLE
// adapter gave them (about 1.3 samples a second, at uneven times). The signal is
// played through `SmoothedSignal` a frame at a time and measured against the
// straight line through the samples.
//
// Two things went wrong on the first drives, and this is what keeps them fixed:
//  - springing to each sample stood the needle still for over 60% of the time the
//    revs were moving (stair-steps), and
//  - running ahead of the samples on their velocity (a Kalman tracker, which a
//    synthetic test had liked) overshot at each gear change and swung back: the
//    "pendulum". It reversed the needle twice as often as the data does.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/dsp/playout.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/vehicle/reading.dart';

import 'support/motion_rig.dart';

const _frame = Duration(microseconds: 16667);

class _Sample {
  const _Sample(this.sent, this.received, this.value);
  final double sent;
  final double received;
  final double value;

  /// The middle of the round trip, which is when the ECU read it.
  double get measured => sent + (received - sent) / 2;
}

class _Result {
  const _Result({
    required this.rms,
    required this.reversalsPerMinute,
    required this.idealReversalsPerMinute,
    required this.standingShare,
    required this.jerk,
  });

  /// RMS of the display against the line through the samples.
  final double rms;

  /// Times a minute the display changes direction (by more than a hysteresis).
  final double reversalsPerMinute;

  /// The same for the line through the samples: what the data itself does.
  final double idealReversalsPerMinute;

  /// The share of the time the data is moving fast that the display stands
  /// almost still.
  final double standingShare;

  /// RMS of the display's acceleration, in units a second squared.
  final double jerk;
}

List<_Sample> _load(String key) {
  final json =
      jsonDecode(
            File('test/design/fixtures/real_ble_drive.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  return [
    for (final s in (json[key] as List).cast<List<dynamic>>())
      _Sample(
        (s[0] as num).toDouble(),
        (s[1] as num).toDouble(),
        (s[2] as num).toDouble(),
      ),
  ];
}

_Result _play(
  List<_Sample> samples, {
  required SpringSpec spring,
  PlayoutSpec? playout,
  required double scale,
}) {
  final rig = MotionRig();
  final signal = SmoothedSignal(
    motion: rig.motion,
    clock: rig.clock,
    spring: spring,
    playout: playout,
  );
  final origin = rig.clock.monotonic();
  Duration at(double t) => origin + Duration(microseconds: (t * 1e6).round());
  double now() => (rig.clock.monotonic() - origin).inMicroseconds / 1e6;

  final end = samples.last.received - 1;
  final times = <double>[], shown = <double>[], speeds = <double>[];
  var next = 0;
  var lastShown = 0.0;
  while (now() < end) {
    rig.run(_frame);
    final t = now();
    while (next < samples.length && samples[next].received <= t) {
      final s = samples[next++];
      signal.ingest(
        Reading(value: s.value, at: at(s.measured), receivedAt: at(s.received)),
      );
    }
    if (!signal.hasValue) continue;
    times.add(t);
    shown.add(signal.value);
    speeds.add((signal.value - lastShown) / (1 / 60));
    lastShown = signal.value;
  }
  signal.dispose();

  double line(double t) {
    if (t <= samples.first.measured) return samples.first.value;
    for (var k = 1; k < samples.length; k++) {
      if (t <= samples[k].measured) {
        final f =
            (t - samples[k - 1].measured) /
            (samples[k].measured - samples[k - 1].measured);
        return samples[k - 1].value +
            f * (samples[k].value - samples[k - 1].value);
      }
    }
    return samples.last.value;
  }

  int reversals(List<double> v) {
    var count = 0, dir = 0;
    var anchor = v.first;
    final h = 25 * scale;
    for (final x in v) {
      if (dir >= 0 && x < anchor - h) {
        if (dir == 1) count++;
        dir = -1;
        anchor = x;
      } else if (dir <= 0 && x > anchor + h) {
        if (dir == -1) count++;
        dir = 1;
        anchor = x;
      } else if ((dir == 1 && x > anchor) || (dir == -1 && x < anchor)) {
        anchor = x;
      }
    }
    return count;
  }

  var n = 0, moving = 0, standing = 0, jn = 0;
  var se = 0.0, j2 = 0.0;
  final from = times.indexWhere((t) => t > 5);
  for (var f = from; f < times.length; f++) {
    final t = times[f];
    if (t > samples.last.measured) break;
    se += math.pow(shown[f] - line(t), 2);
    n++;
    final ideal = (line(t + 0.1) - line(t - 0.1)) / 0.2;
    if (ideal.abs() > 200 * scale) {
      moving++;
      if (speeds[f].abs() < 40 * scale) standing++;
    }
    if (f > from) {
      final a = (speeds[f] - speeds[f - 1]) / (1 / 60);
      j2 += a * a;
      jn++;
    }
  }
  final minutes = (times.last - 5) / 60;
  return _Result(
    rms: math.sqrt(se / n),
    reversalsPerMinute: reversals(shown.sublist(from)) / minutes,
    idealReversalsPerMinute:
        reversals([for (final t in times.skip(from)) line(t)]) / minutes,
    standingShare: moving == 0 ? 0 : standing / moving,
    jerk: math.sqrt(j2 / jn),
  );
}

void main() {
  final rpm = _load('rpm');
  final speed = _load('speed');

  group('the tach on a real drive (rpm at 1.3 samples a second)', () {
    final plain = _play(rpm, spring: TapeSprings.needle, scale: 1);
    final played = _play(
      rpm,
      spring: TapeSprings.needle,
      playout: TapePlayout.rpm,
      scale: 1,
    );

    test('the fixture is the drive it says it is', () {
      expect(rpm.length, greaterThan(300));
      final gaps = [
        for (var i = 1; i < rpm.length; i++)
          rpm[i].received - rpm[i - 1].received,
      ]..sort();
      expect(gaps[gaps.length ~/ 2], inInclusiveRange(0.6, 0.9));
    });

    test('the needle does not stand still while the revs move', () {
      // The plain spring: still for most of the time. Played out: a third of that.
      expect(plain.standingShare, greaterThan(0.5));
      expect(played.standingShare, lessThan(plain.standingShare * 0.45));
    });

    test('the needle is at least twice as smooth: a third of the jerk', () {
      expect(played.jerk, lessThan(plain.jerk * 0.5));
    });

    test('it reverses about as often as the data does: no pendulum', () {
      expect(
        played.reversalsPerMinute,
        lessThan(played.idealReversalsPerMinute * 1.25),
      );
    });

    test('and it is not much further from the data for the delay', () {
      expect(played.rms, lessThan(plain.rms * 1.25));
    });
  });

  group('the speedometer on a real drive', () {
    final plain = _play(speed, spring: TapeSprings.gauge, scale: 0.015);
    final played = _play(
      speed,
      spring: TapeSprings.gauge,
      playout: TapePlayout.speed,
      scale: 0.015,
    );

    test('the number does not stand still while the speed changes', () {
      expect(played.standingShare, lessThan(plain.standingShare * 0.5));
    });

    test('and it is a good deal smoother', () {
      expect(played.jerk, lessThan(plain.jerk * 0.5));
      expect(
        played.reversalsPerMinute,
        lessThan(played.idealReversalsPerMinute * 1.25),
      );
    });
  });
}

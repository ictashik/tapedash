// The smoothing pipeline (DESIGN.md 5.2 and 14.2): springs retargeted on every
// sample, lead compensation that is off by default and capped, and the stale
// fade that starts at 1.5 s.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/ui/design/motion/observable_listenable.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/vehicle/reading.dart';

import 'support/motion_rig.dart';

void main() {
  late MotionRig rig;

  setUp(() => rig = MotionRig());
  tearDown(() => rig.dispose());

  SmoothedSignal make({
    SpringSpec spring = TapeSprings.gauge,
    Duration lead = Duration.zero,
    bool animateFirst = false,
  }) {
    final signal = SmoothedSignal(
      motion: rig.motion,
      clock: rig.clock,
      spring: spring,
      lead: lead,
      animateFirst: animateFirst,
    );
    addTearDown(signal.dispose);
    return signal;
  }

  group('the first reading', () {
    test(
      'is where the value starts: a readout that appears does not sweep in',
      () {
        final signal = make();
        expect(signal.hasValue, isFalse);

        signal.ingest(rig.reading(50));

        expect(signal.hasValue, isTrue);
        expect(signal.value, 50);
        expect(signal.velocity, 0);
      },
    );

    test('can animate in from the initial value, if asked', () {
      final signal = make(animateFirst: true);

      signal.ingest(rig.reading(50));
      rig.run(const Duration(milliseconds: 50));

      expect(signal.value, inExclusiveRange(0, 50));
    });

    test('a reading that is not a number is ignored', () {
      final signal = make();

      signal.ingest(rig.reading(double.nan));
      signal.ingest(rig.reading(double.infinity));

      expect(signal.hasValue, isFalse);
    });
  });

  group('the spring', () {
    test(
      'later readings move the value on the spring, without overshoot on the gauge spring',
      () {
        final signal = make();
        signal.ingest(rig.reading(0));
        var peak = 0.0;

        signal.ingest(rig.reading(100));
        for (var i = 0; i < 60; i++) {
          rig.run(const Duration(milliseconds: 16));
          peak = math.max(peak, signal.value);
          // Keep it fresh, so the pipeline has no reason to go stale.
          if (i % 20 == 19) signal.ingest(rig.reading(100));
        }

        expect(peak, lessThanOrEqualTo(100 + 1e-6));
        expect(signal.value, closeTo(100, 0.01));
      },
    );

    test('the needle spring overshoots by about 4%', () {
      final signal = make(spring: TapeSprings.needle);
      signal.ingest(rig.reading(0));
      var peak = 0.0;

      signal.ingest(rig.reading(100));
      for (var i = 0; i < 40; i++) {
        rig.run(const Duration(milliseconds: 16));
        peak = math.max(peak, signal.value);
      }

      expect(peak, inInclusiveRange(103, 106));
    });

    test(
      'each sample retargets from where it is, so a steady climb is smooth',
      () {
        final signal = make();
        signal.ingest(rig.reading(0));
        var last = signal.value;
        var biggest = 0.0;

        // 0 to 60 km/h in whole steps, a sample every 100 ms.
        for (var v = 1; v <= 60; v++) {
          signal.ingest(rig.reading(v.toDouble()));
          for (var f = 0; f < 6; f++) {
            rig.run(const Duration(microseconds: 16667));
            biggest = math.max(biggest, (signal.value - last).abs());
            last = signal.value;
          }
        }

        expect(biggest, lessThan(1.5));
        expect(signal.value, greaterThan(58));
        expect(
          signal.velocity,
          greaterThan(5),
          reason: 'still moving, with momentum',
        );
      },
    );

    test('a sample identical to the last changes nothing', () {
      final signal = make();
      final reading = rig.reading(10);
      signal.ingest(reading);
      var notified = 0;
      signal.addListener(() => notified++);

      signal.ingest(reading);

      expect(notified, 0);
    });
  });

  group('stale data (DESIGN.md 5.2)', () {
    test('a fresh value is not stale, and the fade starts at 1.5 s', () {
      final signal = make();
      signal.ingest(rig.reading(50));

      rig.run(const Duration(milliseconds: 1400));
      expect(signal.isStale, isFalse);
      expect(signal.staleness, 0);

      rig.run(const Duration(milliseconds: 200));
      expect(signal.isStale, isTrue);
      expect(signal.staleness, greaterThan(0));
    });

    test('the fade is 600 ms long', () {
      final signal = make();
      signal.ingest(rig.reading(50));

      rig.run(const Duration(milliseconds: 1500));
      final start = signal.staleness;
      rig.run(const Duration(milliseconds: 300));
      final middle = signal.staleness;
      rig.run(const Duration(milliseconds: 400));

      expect(start, lessThan(0.1));
      expect(middle, closeTo(0.5, 0.1));
      expect(signal.staleness, 1);
    });

    test('the value holds while it is stale', () {
      final signal = make();
      signal.ingest(rig.reading(50));

      rig.run(const Duration(seconds: 5));

      expect(signal.value, 50);
      expect(signal.isStale, isTrue);
    });

    test('a fresh reading brings the colour back in 200 ms', () {
      final signal = make();
      signal.ingest(rig.reading(50));
      rig.run(const Duration(seconds: 3));
      expect(signal.staleness, 1);

      signal.ingest(rig.reading(52));
      rig.run(const Duration(milliseconds: 100));
      expect(signal.staleness, closeTo(0.5, 0.1));
      rig.run(const Duration(milliseconds: 120));

      expect(signal.staleness, 0);
      expect(signal.isStale, isFalse);
    });

    test('a slower sensor is stale later, when given a longer time', () {
      final signal = SmoothedSignal(
        motion: rig.motion,
        clock: rig.clock,
        spring: TapeSprings.gauge,
        staleAfter: const Duration(seconds: 12),
      );
      addTearDown(signal.dispose);
      signal.ingest(rig.reading(90));

      rig.run(const Duration(seconds: 10));
      expect(signal.isStale, isFalse);

      rig.run(const Duration(seconds: 3));
      expect(signal.isStale, isTrue);
    });

    test(
      'staleness is judged on the domain clock, not on the (slowed) motion clock',
      () {
        final signal = make();
        signal.ingest(rig.reading(50));

        // 2 s pass in the domain and only a few frames on the motion clock.
        rig.clock.advance(const Duration(seconds: 2));
        rig.motion.tick(0.016);

        expect(signal.isStale, isTrue);
        expect(signal.staleness, greaterThan(0));
      },
    );

    test('once the fade is over, it costs the clock no frames', () {
      final signal = make();
      signal.ingest(rig.reading(50));
      expect(rig.motion.isTicking, isTrue);

      rig.run(const Duration(seconds: 4));

      expect(signal.staleness, 1);
      expect(rig.motion.attachedCount, 0);
      expect(rig.motion.isTicking, isFalse);
    });

    test('a fresh reading after that wakes it', () {
      final signal = make();
      signal.ingest(rig.reading(50));
      rig.run(const Duration(seconds: 4));
      expect(rig.motion.attachedCount, 0);

      signal.ingest(rig.reading(60));

      expect(rig.motion.isTicking, isTrue);
      rig.run(const Duration(milliseconds: 500));
      expect(signal.value, closeTo(60, 0.01));
    });

    test('a fresh signal tells its painters nothing while it is at rest', () {
      final signal = make();
      signal.ingest(rig.reading(50));
      rig.run(const Duration(milliseconds: 300));
      var notified = 0;
      signal.addListener(() => notified++);

      rig.run(const Duration(milliseconds: 900));

      expect(notified, 0, reason: 'nothing changed, so nothing is repainted');
    });

    test('a signal that never had a reading is never stale', () {
      final signal = make();

      rig.run(const Duration(seconds: 5));

      expect(signal.isStale, isFalse);
      expect(signal.hasValue, isFalse);
    });
  });

  group('lead compensation (DESIGN.md 5.2)', () {
    /// Feeds a straight climb of [rate] units per second, a sample every 100 ms.
    SmoothedSignal climbing({
      required double rate,
      Duration lead = Duration.zero,
    }) {
      final signal = make(lead: lead);
      for (var i = 0; i <= 10; i++) {
        signal.ingest(rig.reading(rate * i * 0.1));
        rig.run(const Duration(milliseconds: 100));
      }
      return signal;
    }

    test('is off by default: the target is the reading', () {
      final signal = climbing(rate: 100);

      expect(signal.target, closeTo(100, 1e-9));
      expect(signal.lead, Duration.zero);
    });

    test('adds the rate times the lead to the target', () {
      final signal = climbing(
        rate: 100,
        lead: const Duration(milliseconds: 100),
      );

      expect(signal.rate, closeTo(100, 1));
      expect(signal.target, closeTo(100 + 100 * 0.1, 0.5));
    });

    test('is capped at 150 ms', () {
      final signal = climbing(rate: 100, lead: const Duration(seconds: 2));

      expect(signal.lead, SmoothedSignal.maxLead);
      expect(signal.target, closeTo(100 + 100 * 0.15, 0.5));
    });

    test('a negative lead is no lead', () {
      final signal = climbing(
        rate: 100,
        lead: const Duration(milliseconds: -50),
      );

      expect(signal.lead, Duration.zero);
      expect(signal.target, closeTo(100, 1e-9));
    });

    test('is switched off while the rate is noisy', () {
      final signal = make(lead: const Duration(milliseconds: 100));
      // A speed that jumps up and down by 5 km/h every sample.
      for (var i = 0; i < 8; i++) {
        signal.ingest(rig.reading(i.isEven ? 50 : 55));
        rig.run(const Duration(milliseconds: 100));
      }

      expect(signal.isNoisy, isTrue);
      expect(
        signal.target,
        55,
        reason: 'no lead: the target is the reading, not 55 plus a guess',
      );
    });

    test('a steady climb is not noisy', () {
      final signal = climbing(
        rate: 100,
        lead: const Duration(milliseconds: 100),
      );

      expect(signal.isNoisy, isFalse);
    });

    test(
      'a slow climb read in whole units is not noise: the value steps, never flips',
      () {
        final signal = make();
        // 2 km/h per second, read in whole km/h: the reading steps every fifth sample.
        for (var i = 0; i < 30; i++) {
          signal.ingest(rig.reading((i * 0.2).floorToDouble()));
          rig.run(const Duration(milliseconds: 100));
        }

        expect(signal.isNoisy, isFalse);
      },
    );

    test('a single blip does not make it noisy, but a run of flips does', () {
      final signal = make();
      for (final v in [60.0, 60.0, 62.0, 60.0, 60.0, 60.0]) {
        signal.ingest(rig.reading(v));
        rig.run(const Duration(milliseconds: 100));
      }
      expect(signal.isNoisy, isFalse, reason: 'up and down once');

      for (final v in [63.0, 60.0, 63.0, 60.0]) {
        signal.ingest(rig.reading(v));
        rig.run(const Duration(milliseconds: 100));
      }
      expect(signal.isNoisy, isTrue);
    });

    test('and it settles again once the readings do', () {
      final signal = make();
      for (var i = 0; i < 6; i++) {
        signal.ingest(rig.reading(i.isEven ? 50 : 56));
        rig.run(const Duration(milliseconds: 100));
      }
      expect(signal.isNoisy, isTrue);

      for (var i = 0; i < 4; i++) {
        signal.ingest(rig.reading(50.0 + 10 * i));
        rig.run(const Duration(milliseconds: 100));
      }

      expect(signal.isNoisy, isFalse);
    });

    test('the lead can be tuned afterwards, and is still capped', () {
      final signal = make();

      signal.lead = const Duration(milliseconds: 80);
      expect(signal.lead, const Duration(milliseconds: 80));
      signal.lead = const Duration(seconds: 1);
      expect(signal.lead, SmoothedSignal.maxLead);
    });
  });

  group('the rate', () {
    test(
      'is read from the timestamps of the readings, not from when they arrived',
      () {
        final signal = make();
        // Two samples measured 100 ms apart but delivered together.
        final t = rig.clock.monotonic();
        signal.ingest(
          Reading(
            value: 0,
            at: t - const Duration(milliseconds: 200),
            receivedAt: t,
          ),
        );
        signal.ingest(
          Reading(
            value: 10,
            at: t - const Duration(milliseconds: 100),
            receivedAt: t,
          ),
        );

        expect(
          signal.rate,
          closeTo(50, 1),
          reason: '10 units in 100 ms, halved by the first filter step',
        );
      },
    );

    test('is zero for a value that does not change', () {
      final signal = make();
      for (var i = 0; i < 5; i++) {
        signal.ingest(rig.reading(42));
        rig.run(const Duration(milliseconds: 100));
      }

      expect(signal.rate, 0);
    });
  });

  group('binding to a source', () {
    late ObservableValue<Reading?> source;

    setUp(() => source = ObservableValue<Reading?>(null));

    test('follows the readings of an Observable', () {
      final signal = make()..bind(source);
      expect(signal.hasValue, isFalse);

      source.value = rig.reading(30);
      expect(signal.value, 30);

      rig.run(const Duration(milliseconds: 100));
      source.value = rig.reading(40);
      rig.run(const Duration(milliseconds: 500));
      expect(signal.value, closeTo(40, 0.01));
    });

    test('takes the reading that is already there', () {
      source.value = rig.reading(70);

      final signal = make()..bind(source);

      expect(signal.value, 70);
      expect(signal.hasValue, isTrue);
    });

    test('a null reading changes nothing', () {
      final signal = make()..bind(source);
      source.value = rig.reading(30);

      source.value = null;

      expect(signal.value, 30);
    });

    test('binding to another source lets go of the first', () {
      final other = ObservableValue<Reading?>(null);
      final signal = make()
        ..bind(source)
        ..bind(other);

      expect(source.listenerCount, 0);
      other.value = rig.reading(9);
      expect(signal.value, 9);
    });

    test('dispose lets go of the source, the spring and the clock', () {
      final signal = SmoothedSignal(
        motion: rig.motion,
        clock: rig.clock,
        spring: TapeSprings.gauge,
      )..bind(source);
      source.value = rig.reading(5);
      source.value = rig.reading(6);

      signal.dispose();

      expect(source.listenerCount, 0);
      expect(rig.motion.attachedCount, 0);
    });
  });

  group('ObservableListenable', () {
    test('shows the value of an Observable and notifies when it changes', () {
      final source = ObservableValue<int>(1);
      final view = ObservableListenable<int>(source);
      var notified = 0;
      view.addListener(() => notified++);

      source.value = 2;
      source.value = 2;
      source.value = 3;

      expect(view.value, 3);
      expect(notified, 2);
    });

    test('dispose lets go of the source', () {
      final source = ObservableValue<int>(1);
      final view = ObservableListenable<int>(source);

      view.dispose();

      expect(source.listenerCount, 0);
    });
  });
}

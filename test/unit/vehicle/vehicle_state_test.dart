import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/vehicle/reading.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

Duration ms(int n) => Duration(milliseconds: n);

/// A vehicle state on a fake clock, with a way to feed it samples that arrive
/// as they would: measured a moment before they are received.
class _Rig {
  _Rig([VehicleStateConfig config = const VehicleStateConfig()]) {
    state = VehicleState(clock: clock, scheduler: clock, config: config);
  }

  final clock = FakeClock();
  late final VehicleState state;

  /// Feeds [value] as measured at [atMs] and received at the same moment.
  void feed(Sensor sensor, double value, int atMs) {
    if (clock.monotonic() < ms(atMs)) {
      clock.advance(ms(atMs) - clock.monotonic());
    }
    state.ingest(sensor, value, at: ms(atMs), receivedAt: ms(atMs));
  }

  void advanceTo(int atMs) => clock.advance(ms(atMs) - clock.monotonic());

  /// The values of [sensor] as they were published.
  List<double> record(Sensor sensor) {
    final values = <double>[];
    final o = state.reading(sensor);
    o.addListener(() => values.add(o.value!.value));
    return values;
  }

  void close() => state.dispose();
}

void main() {
  group('readings', () {
    test('there are none to start with', () {
      final rig = _Rig();
      addTearDown(rig.close);

      for (final sensor in Sensor.values) {
        expect(rig.state.reading(sensor).value, isNull, reason: sensor.name);
      }
      expect(rig.state.motion.value, isNull);
    });

    test('a reading is kept with when it was measured and when it arrived', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.clock.advance(ms(500));
      rig.state.ingest(Sensor.rpm, 1726, at: ms(450), receivedAt: ms(500));

      final r = rig.state.rpm.value!;
      expect(r.value, 1726);
      expect(r.at, ms(450));
      expect(r.receivedAt, ms(500));
    });

    test('each sensor has its own', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.feed(Sensor.rpm, 900, 0);
      rig.feed(Sensor.coolant, 85, 0);
      rig.feed(Sensor.voltage, 14.1, 0);

      expect(rig.state.rpm.value!.value, 900);
      expect(rig.state.coolant.value!.value, 85);
      expect(rig.state.voltage.value!.value, 14.1);
      expect(rig.state.speed.value, isNull);
    });

    test('the named ones are the sensors of that name', () {
      final rig = _Rig();
      addTearDown(rig.close);

      expect(rig.state.rpm, same(rig.state.reading(Sensor.rpm)));
      expect(rig.state.speed, same(rig.state.reading(Sensor.speed)));
      expect(rig.state.throttle, same(rig.state.reading(Sensor.throttle)));
      expect(rig.state.load, same(rig.state.reading(Sensor.load)));
      expect(rig.state.coolant, same(rig.state.reading(Sensor.coolant)));
      expect(rig.state.intakeAir, same(rig.state.reading(Sensor.intakeAir)));
      expect(
        rig.state.manifoldPressure,
        same(rig.state.reading(Sensor.manifoldPressure)),
      );
      expect(rig.state.airFlow, same(rig.state.reading(Sensor.airFlow)));
      expect(rig.state.fuelLevel, same(rig.state.reading(Sensor.fuelLevel)));
      expect(rig.state.voltage, same(rig.state.reading(Sensor.voltage)));
      expect(rig.state.fuelRate, same(rig.state.reading(Sensor.fuelRate)));
    });

    test('a listener hears each new reading, at that moment', () {
      final rig = _Rig();
      addTearDown(rig.close);
      final seen = rig.record(Sensor.rpm);

      rig.feed(Sensor.rpm, 800, 0);
      rig.feed(Sensor.rpm, 810, 50);
      rig.feed(Sensor.rpm, 820, 100);

      expect(seen, [800, 810, 820]);
    });

    test('the same value again is still a new reading, with a new time', () {
      final rig = _Rig();
      addTearDown(rig.close);
      final seen = rig.record(Sensor.rpm);

      rig.feed(Sensor.rpm, 800, 0);
      rig.feed(Sensor.rpm, 800, 50);

      expect(seen, [800, 800]);
    });
  });

  group('staleness', () {
    test('a reading that never came is stale', () {
      final rig = _Rig();
      addTearDown(rig.close);

      expect(rig.state.isStale(Sensor.rpm), isTrue);
      expect(rig.state.isStale(Sensor.rpm), isTrue);
    });

    test('fresh until 1.5 s after it arrived, then stale', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.rpm, 800, 1000);

      rig.advanceTo(2500);
      expect(rig.state.isStale(Sensor.rpm), isFalse);
      rig.advanceTo(2501);
      expect(rig.state.isStale(Sensor.rpm), isTrue);
    });

    test('a new reading makes it fresh again', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.rpm, 800, 0);
      rig.advanceTo(3000);
      expect(rig.state.isStale(Sensor.rpm), isTrue);

      rig.feed(Sensor.rpm, 850, 3000);

      expect(rig.state.isStale(Sensor.rpm), isFalse);
    });

    test('staleness counts from when it arrived, not when it was measured', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.advanceTo(1000);
      rig.state.ingest(Sensor.rpm, 800, at: ms(200), receivedAt: ms(1000));

      rig.advanceTo(2400);

      expect(rig.state.isStale(Sensor.rpm), isFalse);
    });

    test('the limit can be changed', () {
      final rig = _Rig(
        const VehicleStateConfig(staleAfter: Duration(seconds: 3)),
      );
      addTearDown(rig.close);
      rig.feed(Sensor.rpm, 800, 0);

      rig.advanceTo(3000);
      expect(rig.state.isStale(Sensor.rpm), isFalse);
      rig.advanceTo(3001);
      expect(rig.state.isStale(Sensor.rpm), isTrue);
    });

    test('values that are read less often go stale later', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.rpm, 800, 0);
      rig.feed(Sensor.load, 30, 0);
      rig.feed(Sensor.coolant, 85, 0);

      rig.advanceTo(1501);
      expect(rig.state.isStale(Sensor.rpm), isTrue);
      expect(rig.state.isStale(Sensor.load), isFalse);
      expect(rig.state.isStale(Sensor.coolant), isFalse);
      rig.advanceTo(3001);
      expect(rig.state.isStale(Sensor.load), isTrue);
      expect(rig.state.isStale(Sensor.coolant), isFalse);
      rig.advanceTo(12001);
      expect(rig.state.isStale(Sensor.coolant), isTrue);
    });

    test('how long each may go: 1.5 s, 3 s or 12 s', () {
      final rig = _Rig();
      addTearDown(rig.close);

      for (final s in [Sensor.rpm, Sensor.speed, Sensor.throttle]) {
        expect(rig.state.staleAfterFor(s), ms(1500), reason: s.name);
      }
      for (final s in [
        Sensor.load,
        Sensor.manifoldPressure,
        Sensor.airFlow,
        Sensor.fuelRate,
      ]) {
        expect(rig.state.staleAfterFor(s), ms(3000), reason: s.name);
      }
      for (final s in [
        Sensor.coolant,
        Sensor.intakeAir,
        Sensor.fuelLevel,
        Sensor.voltage,
      ]) {
        expect(rig.state.staleAfterFor(s), ms(12000), reason: s.name);
      }
    });

    test('a slow sensor read every four seconds is never stale', () {
      final rig = _Rig();
      addTearDown(rig.close);

      for (var t = 0; t <= 60000; t += 4000) {
        rig.feed(Sensor.voltage, 14.1, t);
        rig.advanceTo(t + 3999);
        expect(rig.state.isStale(Sensor.voltage), isFalse, reason: 'at $t');
      }
    });

    test('the age of a reading', () {
      const r = Reading(
        value: 1,
        at: Duration.zero,
        receivedAt: Duration(milliseconds: 100),
      );

      expect(r.age(const Duration(milliseconds: 350)), ms(250));
    });
  });

  group('impossible changes (DESIGN.md 5.2)', () {
    test('the first reading is always taken', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.feed(Sensor.rpm, 9000, 0);

      expect(rig.state.rpm.value!.value, 9000);
    });

    test(
      'a jump of 5,000 rpm in 50 ms is held back, and dropped if the next reading is not near it',
      () {
        final rig = _Rig();
        addTearDown(rig.close);
        final seen = rig.record(Sensor.rpm);

        rig.feed(Sensor.rpm, 800, 0);
        rig.feed(Sensor.rpm, 5800, 50);
        expect(seen, [800], reason: 'held');
        rig.feed(Sensor.rpm, 820, 100);

        expect(seen, [800, 820]);
        expect(rig.state.rejectedReadings(Sensor.rpm), 1);
      },
    );

    test(
      'a jump that the next reading confirms is real, and both are taken',
      () {
        final rig = _Rig();
        addTearDown(rig.close);
        final seen = rig.record(Sensor.rpm);

        rig.feed(Sensor.rpm, 800, 0);
        rig.feed(Sensor.rpm, 3000, 50);
        expect(seen, [800]);
        rig.feed(Sensor.rpm, 3040, 100);

        expect(seen, [800, 3000, 3040]);
        expect(rig.state.rejectedReadings(Sensor.rpm), 0);
      },
    );

    test(
      '10,000 rpm/s over the 100 ms window is 1,000 rpm: at it, taken; over it, held',
      () {
        final rig = _Rig();
        addTearDown(rig.close);
        final seen = rig.record(Sensor.rpm);
        rig.feed(Sensor.rpm, 800, 0);

        rig.feed(Sensor.rpm, 1800, 100);
        expect(seen, [800, 1800]);

        rig.feed(Sensor.rpm, 2801, 200);
        expect(seen, [800, 1800], reason: 'a thousand and one');
      },
    );

    test('a longer gap allows a bigger change', () {
      final rig = _Rig();
      addTearDown(rig.close);
      final seen = rig.record(Sensor.rpm);

      rig.feed(Sensor.rpm, 800, 0);
      rig.feed(Sensor.rpm, 3800, 500);

      expect(seen, [800, 3800], reason: '3,000 in 0.5 s is 6,000 rpm/s');
    });

    test('two readings a few ms apart are judged over the 100 ms window', () {
      final rig = _Rig();
      addTearDown(rig.close);
      final seen = rig.record(Sensor.speed);

      rig.feed(Sensor.speed, 50, 0);
      rig.feed(Sensor.speed, 51, 5);
      rig.feed(Sensor.speed, 52, 8);

      expect(seen, [
        50,
        51,
        52,
      ], reason: 'a step of 1 km/h in 5 ms is not 200 km/h/s');
    });

    test('speed: 15 km/h in 100 ms is the limit', () {
      final rig = _Rig();
      addTearDown(rig.close);
      final seen = rig.record(Sensor.speed);
      rig.feed(Sensor.speed, 50, 0);

      rig.feed(Sensor.speed, 65, 100);
      expect(seen, [50, 65]);

      rig.feed(Sensor.speed, 81, 200);
      expect(seen, [50, 65], reason: '16 km/h');
    });

    test(
      'a glitch does not spoil the next comparison: it is against the last taken',
      () {
        final rig = _Rig();
        addTearDown(rig.close);
        final seen = rig.record(Sensor.rpm);

        rig.feed(Sensor.rpm, 800, 0);
        rig.feed(Sensor.rpm, 5000, 50);
        rig.feed(Sensor.rpm, 200, 100);

        // 200 is 600 below 800 in 100 ms, which is fine.
        expect(seen, [800, 200]);
      },
    );

    test('a glitch after a glitch: the second is held in its turn', () {
      final rig = _Rig();
      addTearDown(rig.close);
      final seen = rig.record(Sensor.rpm);

      rig.feed(Sensor.rpm, 800, 0);
      rig.feed(Sensor.rpm, 5000, 50);
      rig.feed(Sensor.rpm, 9000, 100);
      expect(seen, [800]);
      rig.feed(Sensor.rpm, 9040, 150);

      expect(seen, [800, 9000, 9040]);
      expect(rig.state.rejectedReadings(Sensor.rpm), 1);
    });

    test(
      'a held reading is not published, and does not stale the last one',
      () {
        final rig = _Rig();
        addTearDown(rig.close);
        rig.feed(Sensor.rpm, 800, 0);

        rig.feed(Sensor.rpm, 6000, 50);

        expect(rig.state.rpm.value!.value, 800);
        expect(rig.state.rpm.value!.receivedAt, Duration.zero);
      },
    );

    test('sensors with no rule take anything', () {
      final rig = _Rig();
      addTearDown(rig.close);
      final seen = rig.record(Sensor.coolant);

      rig.feed(Sensor.coolant, 90, 0);
      rig.feed(Sensor.coolant, 20, 10);

      expect(seen, [90, 20]);
      expect(rig.state.rejectedReadings(Sensor.coolant), 0);
    });

    test('one sensor\'s glitch does not touch another', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.rpm, 800, 0);
      rig.feed(Sensor.speed, 30, 0);

      rig.feed(Sensor.rpm, 7000, 50);
      rig.feed(Sensor.speed, 31, 50);

      expect(rig.state.speed.value!.value, 31);
      expect(rig.state.rpm.value!.value, 800);
    });

    test('the window can be changed', () {
      final rig = _Rig(
        const VehicleStateConfig(outlierWindow: Duration(milliseconds: 500)),
      );
      addTearDown(rig.close);
      final seen = rig.record(Sensor.rpm);
      rig.feed(Sensor.rpm, 800, 0);

      rig.feed(Sensor.rpm, 5800, 100);

      expect(seen, [800, 5800], reason: '5,000 rpm in 0.5 s is 10,000 rpm/s');
    });

    test('rejected counts are per sensor and start at 0', () {
      final rig = _Rig();
      addTearDown(rig.close);

      expect(rig.state.rejectedReadings(Sensor.rpm), 0);
      expect(rig.state.rejectedReadings(Sensor.speed), 0);
    });
  });

  group('smoothed speed and acceleration', () {
    test('the first speed gives nothing yet, the second gives a sample', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.feed(Sensor.speed, 36, 0);
      expect(rig.state.motion.value, isNull);
      rig.feed(Sensor.speed, 36, 100);

      expect(rig.state.motion.value, isNotNull);
    });

    test('a steady speed is that speed, with no acceleration', () {
      final rig = _Rig();
      addTearDown(rig.close);

      for (var i = 0; i <= 20; i++) {
        rig.feed(Sensor.speed, 36, i * 100);
      }

      final m = rig.state.motion.value!;
      expect(m.speedMs, closeTo(10, 1e-9));
      expect(m.speedKmh, closeTo(36, 1e-9));
      expect(m.accelerationMs2, closeTo(0, 1e-9));
    });

    test('a step of 10 km/h: worked out from the formula', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.speed, 0, 0);

      rig.feed(Sensor.speed, 10, 100);

      // 10 km/h is 2.777778 m/s. Smoothed from 0: alpha x that, with
      // alpha = 1 - e^-0.1 = 0.0951626.
      final m = rig.state.motion.value!;
      expect(m.speedMs, closeTo(0.264341, 1e-6));
      expect(m.accelerationMs2, closeTo(2.64341, 1e-5));
    });

    test(
      'the smoothing follows the time between samples, not a fixed step',
      () {
        final rig = _Rig();
        addTearDown(rig.close);
        rig.feed(Sensor.speed, 0, 0);

        rig.feed(Sensor.speed, 10, 500);

        // alpha = 1 - e^-0.5 = 0.393469, so 0.393469 x 2.777778 m/s.
        expect(rig.state.motion.value!.speedMs, closeTo(1.092970, 1e-6));
        expect(
          rig.state.motion.value!.accelerationMs2,
          closeTo(1.092970 / 0.5, 1e-5),
        );
      },
    );

    test('it settles on a new speed with a time constant of a second', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.speed, 0, 0);

      // 10 km/h is a step the outlier rule allows.
      for (var i = 1; i <= 10; i++) {
        rig.feed(Sensor.speed, 10, i * 100);
      }

      // Ten steps of 0.1 s is one time constant: the discrete average is
      // 1 - 0.904837^10 of the way to 2.7778 m/s, which is 63.2%.
      expect(
        rig.state.motion.value!.speedMs,
        closeTo(2.7778 * (1 - math.exp(-1)), 1e-3),
      );
    });

    test('braking is negative acceleration', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.speed, 72, 0);
      rig.feed(Sensor.speed, 72, 100);

      rig.feed(Sensor.speed, 60, 200);

      expect(rig.state.motion.value!.accelerationMs2, isNegative);
    });

    test(
      'it agrees with an independent exponential average, on a real drive of samples',
      () {
        // The speeds a 10 Hz poll would see, in whole km/h: a pull-away, a
        // cruise and a stop.
        final speeds = <double>[
          for (var i = 0; i < 80; i++) (i * 0.9).roundToDouble().clamp(0, 50),
          for (var i = 0; i < 100; i++) 50,
          for (var i = 0; i < 60; i++)
            (50 - i * 1.0).roundToDouble().clamp(0, 50),
        ];
        final rig = _Rig();
        addTearDown(rig.close);
        var reference = speeds.first / 3.6;
        final alpha = 1 - math.exp(-0.1);
        final seen = <MotionSample>[];
        rig.state.motion.addListener(() => seen.add(rig.state.motion.value!));

        for (var i = 0; i < speeds.length; i++) {
          rig.feed(Sensor.speed, speeds[i], i * 100);
        }

        for (var i = 1; i < speeds.length; i++) {
          final next = reference + alpha * (speeds[i] / 3.6 - reference);
          expect(seen[i - 1].speedMs, closeTo(next, 1e-9), reason: 'sample $i');
          expect(
            seen[i - 1].accelerationMs2,
            closeTo((next - reference) / 0.1, 1e-9),
          );
          reference = next;
        }
      },
    );

    test(
      'a sample that is no later than the last does not move the average',
      () {
        final rig = _Rig();
        addTearDown(rig.close);
        rig.feed(Sensor.speed, 36, 0);
        rig.feed(Sensor.speed, 36, 100);
        final before = rig.state.motion.value;

        rig.state.ingest(Sensor.speed, 40, at: ms(100), receivedAt: ms(110));

        expect(rig.state.motion.value, same(before));
      },
    );

    test('the time constant can be changed', () {
      final rig = _Rig(
        const VehicleStateConfig(
          speedTimeConstant: Duration(milliseconds: 500),
        ),
      );
      addTearDown(rig.close);
      rig.feed(Sensor.speed, 0, 0);

      rig.feed(Sensor.speed, 10, 100);

      // alpha = 1 - e^-0.2 = 0.181269, so 0.181269 x 2.777778 m/s.
      expect(rig.state.motion.value!.speedMs, closeTo(0.503526, 1e-6));
    });

    test('the sample says when it was measured and when it arrived', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.speed, 10, 0);
      rig.advanceTo(300);

      rig.state.ingest(Sensor.speed, 12, at: ms(250), receivedAt: ms(300));

      expect(rig.state.motion.value!.at, ms(250));
      expect(rig.state.motion.value!.receivedAt, ms(300));
    });

    test(
      'a speed reading held back as an outlier does not reach the average',
      () {
        final rig = _Rig();
        addTearDown(rig.close);
        rig.feed(Sensor.speed, 30, 0);
        rig.feed(Sensor.speed, 30, 100);
        final before = rig.state.motion.value;

        rig.feed(Sensor.speed, 90, 150);

        expect(rig.state.motion.value, same(before));
      },
    );
  });

  group('the engine', () {
    test('is not running until the rpm is above 400', () {
      final rig = _Rig();
      addTearDown(rig.close);
      expect(rig.state.engineRunning.value, isFalse);

      rig.feed(Sensor.rpm, 0, 0);
      expect(rig.state.engineRunning.value, isFalse);
      rig.feed(Sensor.rpm, 250, 100);
      expect(rig.state.engineRunning.value, isFalse, reason: 'cranking');
      rig.feed(Sensor.rpm, 400, 200);
      expect(rig.state.engineRunning.value, isFalse);
      rig.feed(Sensor.rpm, 401, 300);

      expect(rig.state.engineRunning.value, isTrue);
    });

    test('stops when the rpm falls to 0', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.rpm, 800, 0);
      expect(rig.state.engineRunning.value, isTrue);

      rig.feed(Sensor.rpm, 0, 3000);

      expect(rig.state.engineRunning.value, isFalse);
    });

    test('a listener hears it start and stop', () {
      final rig = _Rig();
      addTearDown(rig.close);
      final seen = <bool>[];
      rig.state.engineRunning.addListener(
        () => seen.add(rig.state.engineRunning.value),
      );

      rig.feed(Sensor.rpm, 800, 0);
      rig.feed(Sensor.rpm, 820, 100);
      rig.feed(Sensor.rpm, 0, 3000);

      expect(seen, [true, false], reason: 'only when it changes');
    });

    test('the ignition off stops it, and it stays stopped', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.rpm, 800, 0);

      rig.state.setIgnition(IgnitionState.off);
      expect(rig.state.engineRunning.value, isFalse);
      rig.feed(Sensor.rpm, 900, 100);

      expect(rig.state.engineRunning.value, isFalse);
    });

    test('and it starts again with the ignition', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.state.setIgnition(IgnitionState.off);

      rig.state.setIgnition(IgnitionState.on);
      rig.feed(Sensor.rpm, 900, 0);

      expect(rig.state.engineRunning.value, isTrue);
    });
  });

  group('motion and parked', () {
    test('parked to begin with', () {
      final rig = _Rig();
      addTearDown(rig.close);

      expect(rig.state.mode.value, DrivingMode.parked);
    });

    test('above 3 km/h is motion, at once', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.feed(Sensor.speed, 4, 0);

      expect(rig.state.mode.value, DrivingMode.motion);
    });

    test('3 km/h is not enough', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.feed(Sensor.speed, 3, 0);

      expect(rig.state.mode.value, DrivingMode.parked);
    });

    test('stopping is parked only after 5 s at 0', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.speed, 20, 0);
      rig.feed(Sensor.speed, 10, 100);
      rig.feed(Sensor.speed, 0, 200);

      for (var t = 300; t <= 5100; t += 100) {
        rig.feed(Sensor.speed, 0, t);
      }
      expect(rig.state.mode.value, DrivingMode.motion, reason: '4.9 s at 0');
      rig.feed(Sensor.speed, 0, 5200);

      expect(rig.state.mode.value, DrivingMode.parked);
    });

    test('and if no more speeds arrive, still after 5 s', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.speed, 10, 0);
      rig.feed(Sensor.speed, 0, 100);

      rig.advanceTo(5099);
      expect(rig.state.mode.value, DrivingMode.motion);
      rig.advanceTo(5100);

      expect(rig.state.mode.value, DrivingMode.parked);
    });

    test('moving again before the 5 s cancels it', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.speed, 10, 0);
      rig.feed(Sensor.speed, 0, 100);
      rig.advanceTo(3000);

      rig.feed(Sensor.speed, 8, 3000);
      rig.advanceTo(9000);

      expect(rig.state.mode.value, DrivingMode.motion);
      expect(rig.clock.pendingTasks, 0);
    });

    test('creeping is not standing still: it starts the count again', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.speed, 10, 0);
      rig.feed(Sensor.speed, 0, 100);
      rig.feed(Sensor.speed, 0, 3000);
      rig.feed(Sensor.speed, 1, 3100);
      rig.feed(Sensor.speed, 0, 3200);

      rig.advanceTo(7000);
      expect(
        rig.state.mode.value,
        DrivingMode.motion,
        reason: '3.8 s since 3.2',
      );
      rig.advanceTo(8200);

      expect(rig.state.mode.value, DrivingMode.parked);
    });

    test('the ignition off is parked at once', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.feed(Sensor.speed, 50, 0);
      expect(rig.state.mode.value, DrivingMode.motion);

      rig.state.setIgnition(IgnitionState.off);

      expect(rig.state.mode.value, DrivingMode.parked);
    });

    test('with the ignition off, speed readings do not put it in motion', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.state.setIgnition(IgnitionState.off);

      rig.feed(Sensor.speed, 50, 0);

      expect(rig.state.mode.value, DrivingMode.parked);
    });

    test('with the ignition back on, it follows the speed again', () {
      final rig = _Rig();
      addTearDown(rig.close);
      rig.state.setIgnition(IgnitionState.off);
      rig.state.setIgnition(IgnitionState.on);

      rig.feed(Sensor.speed, 50, 0);

      expect(rig.state.mode.value, DrivingMode.motion);
    });

    test('a listener hears each change, and only changes', () {
      final rig = _Rig();
      addTearDown(rig.close);
      final seen = <DrivingMode>[];
      rig.state.mode.addListener(() => seen.add(rig.state.mode.value));

      rig.feed(Sensor.speed, 20, 0);
      rig.feed(Sensor.speed, 30, 100);
      rig.feed(Sensor.speed, 20, 200);
      rig.feed(Sensor.speed, 10, 300);
      rig.feed(Sensor.speed, 0, 400);
      rig.advanceTo(6000);

      expect(seen, [DrivingMode.motion, DrivingMode.parked]);
    });

    test('the limits can be changed', () {
      final rig = _Rig(
        const VehicleStateConfig(
          movingAboveKmh: 10,
          parkedAfter: Duration(seconds: 2),
        ),
      );
      addTearDown(rig.close);

      rig.feed(Sensor.speed, 8, 0);
      expect(rig.state.mode.value, DrivingMode.parked);
      rig.feed(Sensor.speed, 12, 100);
      expect(rig.state.mode.value, DrivingMode.motion);
      rig.feed(Sensor.speed, 0, 200);
      rig.advanceTo(2200);

      expect(rig.state.mode.value, DrivingMode.parked);
    });

    test('nothing is left scheduled after dispose', () {
      final rig = _Rig();
      rig.feed(Sensor.speed, 10, 0);
      rig.feed(Sensor.speed, 0, 100);
      expect(rig.clock.pendingTasks, 1);

      rig.state.dispose();

      expect(rig.clock.pendingTasks, 0);
    });
  });

  group('the ignition', () {
    test('is unknown to start with', () {
      final rig = _Rig();
      addTearDown(rig.close);

      expect(rig.state.ignition.value, IgnitionState.unknown);
    });

    test('is what it was last told', () {
      final rig = _Rig();
      addTearDown(rig.close);

      rig.state.setIgnition(IgnitionState.on);
      expect(rig.state.ignition.value, IgnitionState.on);
      rig.state.setIgnition(IgnitionState.off);
      expect(rig.state.ignition.value, IgnitionState.off);
    });
  });
}

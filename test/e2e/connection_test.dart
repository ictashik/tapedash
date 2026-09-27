// Layer 3 (CLAUDE.md 10): the connection, from the simulated car to the vehicle
// state, through everything between, for the scenarios that are about the link
// and the ignition. Everything runs on a fake clock, so each of these drives is
// a moment of real time.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/dtc/dtc_service.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import 'e2e_rig.dart';

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  group(
    'adapter_flaky: random NO DATA, dropped prompts, noise, and a disconnect',
    () {
      late E2eRig rig;

      setUpAll(() {
        rig = E2eRig(DriveScenarios.adapterFlaky)..runToEnd();
      });

      tearDownAll(() => rig.close());

      test('runs to the end without a crash, and is connected', () {
        expect(rig.car.isFinished, isTrue);
        expect(rig.status, ConnectionStatus.connected);
        expect(rig.session.problem.value, isNull);
      });

      test('the link is lost once, at four minutes, and comes back', () {
        expect(rig.sequence, [
          ConnectionStatus.searching,
          ConnectionStatus.connected,
          ConnectionStatus.lost,
          ConnectionStatus.connected,
        ]);
        final lostAt = rig.statuses[2].$1;
        final backAt = rig.statuses[3].$1;
        expect(lostAt.inSeconds, closeTo(240, 1));
        // A 15 s outage, tried again after 1, 2, 4 and 8 s: it is found again
        // at about 256 s.
        expect((backAt - lostAt).inSeconds, inInclusiveRange(15, 25));
        expect(rig.session.reconnects, greaterThanOrEqualTo(1));
      });

      test(
        'the values stop while it is out, and go stale, and then resume',
        () {
          final speeds = rig.readings[Sensor.speed]!;
          final lostAt = rig.statuses[2].$1;
          final backAt = rig.statuses[3].$1;

          final during = speeds.where(
            (r) => r.receivedAt > lostAt && r.receivedAt < backAt,
          );
          final after = speeds.where((r) => r.receivedAt >= backAt);

          expect(during, isEmpty);
          expect(after.length, greaterThan(500));
        },
      );

      test('the fast tier is read at over 3 Hz whenever it is connected', () {
        final speeds = rig.readings[Sensor.speed]!;
        final lostAt = rig.statuses[2].$1;
        final backAt = rig.statuses[3].$1;
        // Windows of ten seconds, in the two stretches where it was connected.
        var windows = 0;
        for (
          var start = rig.statuses[1].$1 + const Duration(seconds: 10);
          start + const Duration(seconds: 10) < lostAt;
          start += const Duration(seconds: 10)
        ) {
          final n = speeds
              .where(
                (r) =>
                    r.receivedAt >= start &&
                    r.receivedAt < start + const Duration(seconds: 10),
              )
              .length;
          expect(n / 10, greaterThan(3), reason: 'at ${start.inSeconds} s');
          windows++;
        }
        for (
          var start = backAt + const Duration(seconds: 10);
          start + const Duration(seconds: 10) < rig.clock.monotonic();
          start += const Duration(seconds: 10)
        ) {
          final n = speeds
              .where(
                (r) =>
                    r.receivedAt >= start &&
                    r.receivedAt < start + const Duration(seconds: 10),
              )
              .length;
          expect(n / 10, greaterThan(3), reason: 'at ${start.inSeconds} s');
          windows++;
        }
        expect(windows, greaterThan(35));
      });

      test(
        'no gap in the speed longer than a few seconds, while connected',
        () {
          final speeds = rig.readings[Sensor.speed]!;
          final lostAt = rig.statuses[2].$1;
          final backAt = rig.statuses[3].$1;
          var longest = Duration.zero;
          for (var i = 1; i < speeds.length; i++) {
            final a = speeds[i - 1].receivedAt;
            final b = speeds[i].receivedAt;
            // Not the outage, or the start-up after it.
            if (a < lostAt && b > lostAt) continue;
            if (b - a > longest) longest = b - a;
          }

          expect(longest, lessThan(const Duration(seconds: 5)));
          expect(backAt, isNotNull);
        },
      );

      test(
        'nothing wrong gets through: every reading is close to the truth',
        () {
          var checked = 0;
          for (final r in rig.readings[Sensor.rpm]!) {
            final t = rig.truthAt(r.at);
            expect(
              (r.value - t.rpm).abs(),
              lessThan(350),
              reason: 'rpm at ${r.at}',
            );
            checked++;
          }
          for (final r in rig.readings[Sensor.speed]!) {
            final t = rig.truthAt(r.at);
            expect(
              (r.value - t.speedKmh).abs(),
              lessThan(4),
              reason: 'speed at ${r.at}',
            );
            checked++;
          }
          for (final r in rig.readings[Sensor.coolant]!) {
            final t = rig.truthAt(r.at);
            expect(
              (r.value - t.coolantC).abs(),
              lessThan(2),
              reason: 'coolant at ${r.at}',
            );
            checked++;
          }
          for (final r in rig.readings[Sensor.voltage]!) {
            final t = rig.truthAt(r.at);
            expect(
              (r.value - t.voltage).abs(),
              lessThan(0.3),
              reason: 'voltage at ${r.at}',
            );
            checked++;
          }
          expect(checked, greaterThan(5000));
        },
      );

      test(
        'no impossible reading was needed to be thrown away, or very few',
        () {
          expect(rig.vehicle.rejectedReadings(Sensor.rpm), lessThan(5));
          expect(rig.vehicle.rejectedReadings(Sensor.speed), lessThan(5));
        },
      );

      test('the noise was there: the adapter really was flaky', () {
        final noData = rig.log.entries
            .where((e) => e.text.contains('NO DATA'))
            .length;

        expect(noData, greaterThan(20));
        expect(rig.session.client.timeouts, greaterThan(0));
      });
    },
  );

  group('minimal_old_car: only 04, 05, 0C, 0D and 11', () {
    late E2eRig rig;

    setUpAll(() {
      rig = E2eRig(
        DriveScenarios.cityStopGo,
        profile: VehicleProfiles.minimalOldCar,
      )..runToEnd(limit: const Duration(minutes: 10));
    });

    tearDownAll(() => rig.close());

    test('the gauges that can work do work', () {
      expect(rig.status, ConnectionStatus.connected);
      for (final s in [
        Sensor.rpm,
        Sensor.speed,
        Sensor.throttle,
        Sensor.load,
        Sensor.coolant,
      ]) {
        expect(rig.readings[s]!.length, greaterThan(100), reason: s.name);
        expect(rig.vehicle.isStale(s), isFalse, reason: s.name);
      }
    });

    test('the rest are nowhere: none is guessed at', () {
      for (final s in [
        Sensor.intakeAir,
        Sensor.airFlow,
        Sensor.manifoldPressure,
        Sensor.fuelLevel,
        Sensor.voltage,
        Sensor.fuelRate,
      ]) {
        expect(rig.readings[s], isEmpty, reason: s.name);
        expect(rig.vehicle.reading(s).value, isNull, reason: s.name);
      }
    });

    test('the car is asked for what it has, and nothing else', () {
      final asked = <int>{};
      for (final e in rig.log.entries) {
        if (e.direction != SessionDirection.sent) continue;
        final t = e.text.trim();
        // Requests for PIDs, with the count digit: not the support requests.
        if (t.startsWith('01') && t.length.isOdd && t.length >= 5) {
          final hex = t.substring(2, t.length - 1);
          for (var i = 0; i + 1 < hex.length; i += 2) {
            asked.add(int.parse(hex.substring(i, i + 2), radix: 16));
          }
        }
      }

      expect(asked, {0x04, 0x05, 0x0C, 0x0D, 0x11});
    });

    test('the support is known to the session: exactly five, and PID 01', () {
      expect(rig.session.adapterInfo.value!.supportedPids, {
        0x01,
        0x04,
        0x05,
        0x0C,
        0x0D,
        0x11,
      });
    });

    test('and it needs no fallback: nothing was retried', () {
      expect(rig.session.adapterInfo.value!.retries, 0);
      expect(rig.session.poller!.compatibilityMode, isFalse);
    });
  });

  group('dtc_present: P0420 and P0171', () {
    test('the codes are read and decoded', () {
      final rig = E2eRig(DriveScenarios.dtcPresent);
      addTearDown(rig.close);
      expect(
        rig.runUntil(() => rig.status == ConnectionStatus.connected),
        isTrue,
      );
      DtcReadResult? result;

      rig.session.dtc!.read((r) => result = r);
      rig.run(5);

      expect(result!.ok, isTrue);
      expect(result!.stored.map((d) => d.code), ['P0420', 'P0171']);
      expect(result!.pending, isEmpty);
    });

    test(
      'clearing is refused while the car moves, and the ECU is not asked',
      () {
        final rig = E2eRig(DriveScenarios.dtcPresent);
        addTearDown(rig.close);
        rig.runUntil(() => rig.status == ConnectionStatus.connected);
        expect(rig.runUntil(() => rig.car.state.speedMs > 5), isTrue);
        rig.run(2);
        final before = rig.log.entries
            .where(
              (e) => e.direction == SessionDirection.sent && e.text == '04\r',
            )
            .length;
        DtcClearOutcome? outcome;

        rig.session.dtc!.clear((o) => outcome = o);
        rig.run(2);

        expect(outcome, DtcClearOutcome.notStationary);
        expect(rig.car.storedDtcs, ['P0420', 'P0171']);
        expect(
          rig.log.entries
              .where(
                (e) => e.direction == SessionDirection.sent && e.text == '04\r',
              )
              .length,
          before,
          reason: 'no 04 was sent',
        );
      },
    );

    test(
      'and it is cleared once the car has stopped, and the light goes out',
      () {
        final rig = E2eRig(DriveScenarios.dtcPresent);
        addTearDown(rig.close);
        rig.runUntil(() => rig.status == ConnectionStatus.connected);
        // Drive, and wait for the first stop after moving off.
        rig.runUntil(() => rig.car.state.speedMs > 5);
        expect(
          rig.runUntil(
            () =>
                rig.car.state.speedMs == 0 &&
                rig.vehicle.speed.value?.value == 0,
          ),
          isTrue,
        );
        DtcClearOutcome? outcome;

        rig.session.dtc!.clear((o) => outcome = o);
        rig.run(2);

        expect(outcome, DtcClearOutcome.cleared);
        expect(rig.car.storedDtcs, isEmpty);
        expect(rig.car.milOn, isFalse);
        DtcReadResult? after;
        rig.session.dtc!.read((r) => after = r);
        rig.run(5);
        expect(after!.stored, isEmpty);
      },
    );
  });

  group('mixed_commute: the ignition off, and on again', () {
    late E2eRig rig;

    setUpAll(() {
      rig = E2eRig(
        DriveScenarios.mixedCommute(ignitionOff: const Duration(seconds: 90)),
      )..runToEnd();
    });

    tearDownAll(() => rig.close());

    test('is connected, waits for the ignition, and is connected again', () {
      expect(rig.sequence, [
        ConnectionStatus.searching,
        ConnectionStatus.connected,
        ConnectionStatus.waitingForIgnition,
        ConnectionStatus.connected,
      ]);
      expect(rig.session.reconnects, 0, reason: 'the link itself never went');
    });

    test('the engine is seen to stop and start', () {
      // Running, off, running: three changes, counting the first start.
      expect(rig.engine.map((e) => e.$2), [true, false, true]);
    });

    test('while it waits the car is parked, and the ignition is off', () {
      final off = rig.statuses[2].$1;
      final on = rig.statuses[3].$1;
      // The time the ECU was actually silent, and the session knew it.
      expect(on - off, greaterThan(const Duration(seconds: 60)));
      expect(on - off, lessThan(const Duration(seconds: 100)));
    });

    test('the values after it are the car\'s again', () {
      final rpms = rig.readings[Sensor.rpm]!;
      final on = rig.statuses[3].$1;

      final after = rpms.where((r) => r.receivedAt > on).toList();

      expect(after.length, greaterThan(1000));
      for (final r in after.take(200)) {
        expect((r.value - rig.truthAt(r.at).rpm).abs(), lessThan(350));
      }
    });

    test('the car is found again within seconds of the ignition going on', () {
      // The scenario turns the ignition on 90 s after it went off.
      final off = rig.statuses[2].$1;
      final on = rig.statuses[3].$1;

      expect(
        on - off,
        lessThan(const Duration(seconds: 90) + const Duration(seconds: 12)),
      );
    });
  });

  group('traffic_jam: long idling and crawling', () {
    late E2eRig rig;

    setUpAll(() {
      rig = E2eRig(DriveScenarios.trafficJam)..runToEnd();
    });

    tearDownAll(() => rig.close());

    test(
      'stays connected all the way: standing still is not the ignition off',
      () {
        expect(rig.sequence, [
          ConnectionStatus.searching,
          ConnectionStatus.connected,
        ]);
      },
    );

    test('the engine runs all through, and is never taken to have stopped', () {
      expect(rig.engine.map((e) => e.$2), [true]);
      expect(rig.vehicle.ignition.value, IgnitionState.on);
    });

    test('the car is mostly parked, and moves a little', () {
      final speeds = rig.readings[Sensor.speed]!;
      final still = speeds.where((r) => r.value == 0).length;

      expect(still / speeds.length, greaterThan(0.5));
      expect(speeds.any((r) => r.value > 0), isTrue);
    });
  });

  group('cold_start_idle: the engine starts', () {
    late E2eRig rig;

    setUpAll(() {
      rig = E2eRig(DriveScenarios.coldStartIdle)..runToEnd();
    });

    tearDownAll(() => rig.close());

    test('the engine is running once, and only after the rpm is above 400', () {
      expect(rig.engine.map((e) => e.$2), [true]);
      final rpms = rig.readings[Sensor.rpm]!;
      final started = rig.engine.first.$1;
      // Whatever it read while cranking was below 400, and none of it counted.
      final before = rpms.where((r) => r.receivedAt < started);
      expect(before.every((r) => r.value <= 400), isTrue);
    });

    test(
      'the coolant warms as the truth does, and the voltage is the alternator\'s',
      () {
        final coolant = rig.readings[Sensor.coolant]!;
        final voltage = rig.readings[Sensor.voltage]!;

        expect(coolant.last.value, greaterThan(coolant.first.value + 10));
        // The first reading comes a few seconds after the engine has started,
        // so it is already the alternator's voltage.
        expect(voltage.first.value, inInclusiveRange(12.0, 14.5));
        expect(voltage.last.value, closeTo(14.1, 0.5));
      },
    );
  });

  group('every profile connects and reads what it has', () {
    for (final profile in VehicleProfiles.all) {
      test(profile.name, () {
        final rig = E2eRig(DriveScenarios.cityStopGo, profile: profile);
        addTearDown(rig.close);

        rig.run(120);

        expect(rig.status, ConnectionStatus.connected);
        expect(rig.session.adapterInfo.value!.supportedPids, {
          0x01,
          ...profile.supportedPids,
        });
        for (final sensor in Sensor.values) {
          final has = profile.supportedPids.contains(
            {
              Sensor.rpm: 0x0C,
              Sensor.speed: 0x0D,
              Sensor.throttle: 0x11,
              Sensor.load: 0x04,
              Sensor.coolant: 0x05,
              Sensor.intakeAir: 0x0F,
              Sensor.manifoldPressure: 0x0B,
              Sensor.airFlow: 0x10,
              Sensor.fuelLevel: 0x2F,
              Sensor.voltage: 0x42,
              Sensor.fuelRate: 0x5E,
            }[sensor],
          );
          // The fuel source is polled by default: 5E, else MAF, else MAP.
          final polledByDefault = switch (sensor) {
            Sensor.fuelRate => has,
            Sensor.airFlow => has && !profile.supportedPids.contains(0x5E),
            Sensor.manifoldPressure =>
              has &&
                  !profile.supportedPids.contains(0x5E) &&
                  !profile.supportedPids.contains(0x10),
            _ => has,
          };
          expect(
            rig.readings[sensor]!.isNotEmpty,
            polledByDefault,
            reason: '${profile.name} ${sensor.name}',
          );
        }
      });
    }
  });

  group('a Bluetooth clone, 80 ms plus or minus 40', () {
    test('the fast tier is read at over 3 Hz, all the way (CLAUDE.md 10)', () {
      final rig = E2eRig(
        DriveScenarios.cityStopGo,
        quirks: AdapterQuirks.bluetoothClone,
      );
      addTearDown(rig.close);

      rig.run(600);

      final speeds = rig.readings[Sensor.speed]!;
      var windows = 0;
      for (
        var start = const Duration(seconds: 15);
        start + const Duration(seconds: 10) <= rig.clock.monotonic();
        start += const Duration(seconds: 10)
      ) {
        final n = speeds
            .where(
              (r) =>
                  r.receivedAt >= start &&
                  r.receivedAt < start + const Duration(seconds: 10),
            )
            .length;
        expect(n / 10, greaterThan(3), reason: 'at ${start.inSeconds} s');
        windows++;
      }
      expect(windows, greaterThan(50));
      // Batching, and the count digit, make it three times that.
      expect(rig.session.pollRate.value, greaterThan(6));
    });

    test(
      'the adapter ignores adaptive timing, and the digit makes up for it',
      () {
        final rig = E2eRig(
          DriveScenarios.cityStopGo,
          quirks: AdapterQuirks.bluetoothClone,
        );
        addTearDown(rig.close);

        rig.run(60);

        // Every poll ends with the response count, so none waits 200 ms for more.
        final polls = rig.log.entries.where(
          (e) =>
              e.direction == SessionDirection.sent &&
              e.text.startsWith('01') &&
              e.text.trim().length.isOdd &&
              e.text.trim().length >= 5,
        );
        expect(polls, isNotEmpty);
        expect(polls.every((e) => e.text.trim().endsWith('1')), isTrue);
      },
    );
  });
}

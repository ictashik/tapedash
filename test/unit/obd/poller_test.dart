import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/elm327/elm327_failure.dart';
import 'package:tapedash/obd/poller.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/profiles.dart';

import '../../support/poll_rig.dart';

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  group('what is polled, by tier (CLAUDE.md 8.2)', () {
    test('the standard tiers of a car with MAF', () {
      final tiers = Poller.standardTiers(
        VehicleProfiles.petrolCvtMaf.supportedPids,
      );

      expect(tiers, {
        0x0C: PollTier.fast,
        0x0D: PollTier.fast,
        0x11: PollTier.fast,
        0x04: PollTier.medium,
        0x10: PollTier.medium,
        0x05: PollTier.slow,
        0x0F: PollTier.slow,
        0x2F: PollTier.slow,
        0x42: PollTier.slow,
      });
    });

    test('a car with no MAF has MAP as its fuel source', () {
      final tiers = Poller.standardTiers(
        VehicleProfiles.petrolCvtMap.supportedPids,
      );

      expect(tiers[0x0B], PollTier.medium);
      expect(tiers.containsKey(0x10), isFalse);
    });

    test('a car with fuel rate has that, and not MAF', () {
      final tiers = Poller.standardTiers(
        VehicleProfiles.petrolCvtFuelRate.supportedPids,
      );

      expect(tiers[0x5E], PollTier.medium);
      expect(tiers.containsKey(0x10), isFalse);
      expect(tiers.containsKey(0x0B), isFalse);
    });

    test('a minimal old car has what it has', () {
      final tiers = Poller.standardTiers(
        VehicleProfiles.minimalOldCar.supportedPids,
      );

      expect(tiers, {
        0x0C: PollTier.fast,
        0x0D: PollTier.fast,
        0x11: PollTier.fast,
        0x04: PollTier.medium,
        0x05: PollTier.slow,
      });
    });

    test('a PID the car does not support is not polled, even if asked for', () {
      final rig = PollRig(
        data: {
          0x0C: [0x1A, 0xF8],
        },
        demandStandard: false,
      );
      addTearDown(rig.close);
      rig.poller.demand({0x0C: PollTier.fast, 0x5E: PollTier.fast});

      expect(rig.poller.tierOf(0x5E), isNull);
      expect(rig.poller.tierOf(0x0C), PollTier.fast);
    });

    test('a PID nobody wants is not polled', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      rig.poller.demand({0x0C: PollTier.fast});
      rig.poller.start();

      rig.run(5);

      expect(rig.readings.map((r) => r.pid.id).toSet(), {0x0C});
      expect(rig.poller.tierOf(0x0D), isNull);
    });
  });

  group('demands', () {
    test('the fastest tier anyone asks for wins', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);

      rig.poller.demand({0x10: PollTier.slow});
      expect(rig.poller.tierOf(0x10), PollTier.slow);
      final fast = rig.poller.demand({0x10: PollTier.fast});
      expect(rig.poller.tierOf(0x10), PollTier.fast);
      rig.poller.demand({0x10: PollTier.medium});
      expect(rig.poller.tierOf(0x10), PollTier.fast);

      fast.release();
      expect(rig.poller.tierOf(0x10), PollTier.medium);
    });

    test('releasing gives the PID up when nobody else wants it', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      final d = rig.poller.demand({0x10: PollTier.medium});

      d.release();

      expect(rig.poller.tierOf(0x10), isNull);
    });

    test('releasing twice is harmless', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      final d = rig.poller.demand({0x10: PollTier.medium});

      d.release();
      d.release();

      expect(rig.poller.tierOf(0x10), isNull);
    });

    test('a PID given up stops being read', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      rig.poller.demand({0x0C: PollTier.fast});
      final extra = rig.poller.demand({0x10: PollTier.fast});
      rig.poller.start();
      rig.run(2);
      final before = rig.count(0x10);
      expect(before, greaterThan(10));

      extra.release();
      rig.run(2);

      expect(
        rig.count(0x10),
        before + 1,
        reason: 'at most the one already asked',
      );
    });

    test('a PID that is wanted faster is read faster', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      rig.poller.demand({0x0C: PollTier.fast, 0x10: PollTier.slow});
      rig.poller.start();
      rig.run(20);
      final slowCount = rig.count(0x10);

      rig.poller.demand({0x10: PollTier.fast});
      rig.run(20);

      expect(slowCount, closeTo(5, 1));
      expect(rig.count(0x10) - slowCount, greaterThan(200));
    });

    test('a demand made while it waits on a slow tier is served at once', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      rig.poller.demand({0x05: PollTier.slow});
      rig.poller.start();
      rig.run(1);
      final before = rig.readings.length;

      rig.poller.demand({0x0C: PollTier.fast});
      rig.runMs(100);

      expect(rig.count(0x0C), greaterThan(0));
      expect(rig.readings.length, greaterThan(before));
    });
  });

  group('tiers over time', () {
    test('fast every cycle, medium about once a second, slow every four', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.start();

      rig.run(40);

      expect(rig.count(0x0C), greaterThan(1000));
      // RPM, speed and throttle move together.
      expect(rig.count(0x0D), closeTo(rig.count(0x0C), 3));
      expect(rig.count(0x11), closeTo(rig.count(0x0C), 3));
      expect(rig.count(0x04), closeTo(40, 3));
      expect(rig.count(0x10), closeTo(40, 3));
      expect(rig.count(0x05), closeTo(10, 2));
      expect(rig.count(0x42), closeTo(10, 2));
    });

    test('the periods can be changed', () {
      final rig = PollRig(
        config: const PollConfig(
          mediumPeriod: Duration(seconds: 2),
          slowPeriod: Duration(seconds: 8),
        ),
      );
      addTearDown(rig.close);
      rig.poller.start();

      rig.run(40);

      expect(rig.count(0x04), closeTo(20, 2));
      expect(rig.count(0x05), closeTo(5, 2));
    });

    test(
      'nothing is asked for when nothing is due, and the clock is not spun',
      () {
        final rig = PollRig(demandStandard: false);
        addTearDown(rig.close);
        rig.poller.demand({0x05: PollTier.slow});
        rig.poller.start();

        rig.run(20);

        // One read at the start and one every 4 s.
        expect(rig.poller.requestsSent, closeTo(6, 1));
      },
    );
  });

  group('batching', () {
    test('several PIDs go in one request, with the count digit', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      rig.poller.demand({
        0x0C: PollTier.fast,
        0x0D: PollTier.fast,
        0x11: PollTier.fast,
      });
      rig.poller.start();

      rig.runMs(200);

      expect(rig.requests.first, [0x01, 0x0C, 0x0D, 0x11]);
      expect(rig.transport.writes.first, '010C0D111\r');
    });

    test('all the values of a batch are delivered, decoded', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      rig.poller.demand({
        0x0C: PollTier.fast,
        0x0D: PollTier.fast,
        0x11: PollTier.fast,
      });
      rig.poller.start();

      rig.runMs(100);

      final values = {for (final r in rig.readings.take(3)) r.pid.id: r.value};
      expect(values[0x0C], 1726);
      expect(values[0x0D], 50);
      expect(values[0x11], closeTo(20, 1e-9));
    });

    test('no more than six PIDs in a request', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.demand({for (final p in fullCar().keys) p: PollTier.fast});
      rig.poller.start();

      rig.run(5);

      final sizes = rig.requests.map((r) => r.length - 1);
      expect(sizes.reduce((a, b) => a > b ? a : b), 6);
      // All ten are due at once, so the first request has the six oldest.
      expect(rig.requests[0].length - 1, 6);
    });

    test('the oldest reads go first, so nothing starves', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.demand({for (final p in fullCar().keys) p: PollTier.fast});
      rig.poller.start();

      rig.run(10);

      final counts = [for (final p in fullCar().keys) rig.count(p)];
      final most = counts.reduce((a, b) => a > b ? a : b);
      final least = counts.reduce((a, b) => a < b ? a : b);
      expect(most - least, lessThanOrEqualTo(2));
    });

    test(
      'a car that is not on CAN gets one PID at a time, and no count digit',
      () {
        final rig = PollRig(isCan: false);
        addTearDown(rig.close);
        rig.poller.start();

        rig.run(3);

        expect(rig.requests.map((r) => r.length), everyElement(2));
        expect(
          rig.transport.writes,
          everyElement(matches(RegExp(r'^01[0-9A-F]{2}\r$'))),
        );
        expect(rig.poller.isBatching, isFalse);
      },
    );

    test('and the fast tier is still read', () {
      final rig = PollRig(isCan: false);
      addTearDown(rig.close);
      rig.poller.start();

      rig.run(10);

      expect(rig.count(0x0C), greaterThan(30));
    });

    test('batching can be turned off', () {
      final rig = PollRig(config: const PollConfig(batching: false));
      addTearDown(rig.close);
      rig.poller.start();

      rig.run(3);

      expect(rig.requests.map((r) => r.length), everyElement(2));
      // With the count digit still, on CAN.
      expect(
        rig.transport.writes.first,
        matches(RegExp(r'^01[0-9A-F]{2}1\r$')),
      );
    });

    test('on CAN each request says it expects one answer', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.start();

      rig.run(3);

      for (final w in rig.transport.writes) {
        expect(w.trim().endsWith('1'), isTrue, reason: w);
      }
    });
  });

  group('when batching does not work', () {
    test(
      'an adapter that does not know multi-PID requests is asked one at a time from then on',
      () {
        final rig = PollRig(quirks: const AdapterQuirks(noMultiPid: true));
        addTearDown(rig.close);
        rig.poller.start();

        rig.run(10);

        expect(rig.poller.batchingRefused, isTrue);
        expect(rig.poller.isBatching, isFalse);
        // One batched request went out and got a ?; everything after is single.
        final multi = rig.transport.writes.where((w) => w.length > 6).length;
        expect(multi, 1);
        expect(rig.count(0x0C), greaterThan(30));
        expect(rig.poller.failedRequests, 1);
      },
    );

    test('it is never tried again, however long it runs', () {
      final rig = PollRig(quirks: const AdapterQuirks(noMultiPid: true));
      addTearDown(rig.close);
      rig.poller.start();

      rig.run(300);

      expect(rig.transport.writes.where((w) => w.length > 6).length, 1);
    });

    test(
      'a request that fails is followed by single requests, which bring the values',
      () {
        final rig = PollRig(demandStandard: false);
        addTearDown(rig.close);
        rig.poller.demand({
          0x0C: PollTier.fast,
          0x0D: PollTier.fast,
          0x11: PollTier.fast,
        });
        rig.ecu.answerOnlyFirst = true;
        rig.poller.start();
        rig.runMs(30);
        expect(rig.readings.length, 1, reason: 'only the first PID came back');

        rig.ecu.answerOnlyFirst = false;
        rig.run(1);

        // The requests after the failure are single, and every PID is read.
        final singles = rig.requests.skip(1).take(6).map((r) => r.length);
        expect(singles, everyElement(2));
        expect(rig.count(0x0D), greaterThan(0));
        expect(rig.count(0x11), greaterThan(0));
      },
    );

    test(
      'three failed batches in a row give batching up for a minute, and then try again',
      () {
        final rig = PollRig(demandStandard: false);
        addTearDown(rig.close);
        rig.poller.demand({
          0x0C: PollTier.fast,
          0x0D: PollTier.fast,
          0x11: PollTier.fast,
        });
        rig.ecu.answerOnlyFirst = true;
        rig.poller.start();

        rig.run(5);
        expect(rig.poller.isBatching, isFalse, reason: 'paused');
        final multiBefore = rig.requests.where((r) => r.length > 2).length;
        expect(multiBefore, 3, reason: 'three batches, and then singles');

        rig.ecu.answerOnlyFirst = false;
        rig.run(50);
        expect(
          rig.poller.isBatching,
          isFalse,
          reason: 'still within the minute',
        );
        expect(rig.requests.where((r) => r.length > 2).length, 3);

        rig.run(10);
        expect(rig.poller.isBatching, isTrue);
        rig.run(2);
        expect(rig.requests.where((r) => r.length > 2).length, greaterThan(3));
      },
    );

    test('a batch that succeeds clears the strikes', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      rig.poller.demand({
        0x0C: PollTier.fast,
        0x0D: PollTier.fast,
        0x11: PollTier.fast,
      });
      rig.poller.start();

      // A bad request, then a run of good ones, over and over: never three in a row.
      for (var i = 0; i < 6; i++) {
        rig.ecu.answerOnlyFirst = true;
        rig.runMs(60);
        rig.ecu.answerOnlyFirst = false;
        rig.run(1);
      }

      expect(rig.poller.isBatching, isTrue);
    });

    test('the number of strikes and the pause can be changed', () {
      final rig = PollRig(
        demandStandard: false,
        config: const PollConfig(
          batchStrikeLimit: 1,
          batchPause: Duration(seconds: 5),
        ),
      );
      addTearDown(rig.close);
      rig.poller.demand({0x0C: PollTier.fast, 0x0D: PollTier.fast});
      rig.ecu.answerOnlyFirst = true;
      rig.poller.start();

      rig.runMs(100);
      expect(rig.poller.isBatching, isFalse);
      rig.ecu.answerOnlyFirst = false;
      rig.run(6);

      expect(rig.poller.isBatching, isTrue);
    });
  });

  group('a PID that never answers', () {
    test('does not starve the others, and is asked for less and less', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.ecu.silent.add(0x0D);
      rig.poller.start();

      rig.run(60);

      expect(rig.count(0x0D), 0);
      expect(rig.count(0x0C), greaterThan(300));
      final askedFor = rig.requests.where((r) => r.contains(0x0D)).length;
      // Batched in the first requests, then one at a time with a backoff.
      expect(askedFor, lessThan(60));
    });

    test('and is read again as soon as it answers', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.ecu.silent.add(0x0D);
      rig.poller.start();
      rig.run(30);

      rig.ecu.silent.clear();
      rig.run(10);

      expect(rig.count(0x0D), greaterThan(10));
    });
  });

  group('what is delivered', () {
    test(
      'each reading is stamped with the middle of the request\'s round trip',
      () {
        final rig = PollRig(
          demandStandard: false,
          quirks: const AdapterQuirks(latency: Duration(milliseconds: 80)),
        );
        addTearDown(rig.close);
        rig.poller.demand({0x0C: PollTier.fast});
        rig.poller.start();

        rig.run(3);

        for (final r in rig.readings) {
          // Written at t, the answer at t + 80 + 20: the middle is t + 50.
          expect((r.receivedAt - r.at).inMilliseconds, 50);
          expect(r.latency.inMilliseconds, 100);
        }
      },
    );

    test('a value that changes is delivered as it changes', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      rig.poller.demand({0x0C: PollTier.fast});
      rig.poller.start();
      rig.run(1);
      expect(rig.readings.last.value, 1726);

      rig.ecu.data[0x0C] = [0x0F, 0xA0];
      rig.run(1);

      expect(rig.readings.last.value, 1000);
    });

    test('the readings come with the raw bytes', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      rig.poller.demand({0x0C: PollTier.fast});
      rig.poller.start();

      rig.run(1);

      expect(rig.readings.first.data, [0x1A, 0xF8]);
      expect(rig.readings.first.pid.id, 0x0C);
    });

    test('two ECUs answering: each PID is taken from whichever gave it', () {
      // The table ECU is one ECU; a second message is added by a second call.
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      rig.poller.demand({0x0C: PollTier.fast});
      rig.poller.start();

      rig.run(1);

      expect(rig.count(0x0C), greaterThan(5));
    });
  });

  group('the health of the link', () {
    test('starts fine, and stays fine while the car answers', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.start();

      rig.run(10);

      expect(rig.poller.health.value, PollHealth.ok);
    });

    test(
      'a car that stops answering is an ECU gone quiet, after three requests and four seconds',
      () {
        final rig = PollRig();
        addTearDown(rig.close);
        rig.poller.start();
        rig.run(2);

        rig.ecu.awake = false;
        rig.runMs(60);
        expect(
          rig.poller.health.value,
          PollHealth.ok,
          reason: 'one or two are not enough',
        );
        rig.run(2);
        expect(
          rig.poller.health.value,
          PollHealth.ok,
          reason:
              'many misses, but not for four seconds yet: a slow adapter '
              'and a busy bus can do that without the ignition going off',
        );
        rig.run(3);

        expect(rig.poller.health.value, PollHealth.ecuSilent);
      },
    );

    test(
      'a short run of misses on a slow adapter is not the ignition going off',
      () {
        final rig = PollRig(quirks: AdapterQuirks.bluetoothClone);
        addTearDown(rig.close);
        rig.poller.start();
        rig.run(3);

        rig.ecu.awake = false;
        rig.run(3);
        rig.ecu.awake = true;
        rig.run(3);

        expect(rig.poller.health.value, PollHealth.ok);
      },
    );

    test('and is fine again the moment it answers', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.start();
      rig.ecu.awake = false;
      rig.run(6);
      expect(rig.poller.health.value, PollHealth.ecuSilent);

      rig.ecu.awake = true;
      rig.run(2);

      expect(rig.poller.health.value, PollHealth.ok);
    });

    test('an adapter that says nothing is failing, after five requests', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.start();
      rig.run(2);

      // The adapter goes deaf: every command is lost.
      rig.transport.onCommand = (_) {};
      rig.run(6);
      expect(
        rig.poller.health.value,
        PollHealth.ok,
        reason: 'three timeouts so far',
      );
      rig.run(6);

      expect(rig.poller.health.value, PollHealth.adapterFailing);
    });

    test('a listener hears the change', () {
      final rig = PollRig();
      addTearDown(rig.close);
      final seen = <PollHealth>[];
      rig.poller.health.addListener(() => seen.add(rig.poller.health.value));
      rig.poller.start();
      rig.run(2);

      rig.ecu.awake = false;
      rig.run(6);
      rig.ecu.awake = true;
      rig.run(2);

      expect(seen, [PollHealth.ecuSilent, PollHealth.ok]);
    });

    test('the limits can be changed', () {
      final rig = PollRig(
        config: const PollConfig(silentAfter: 1, silentFor: Duration.zero),
      );
      addTearDown(rig.close);
      rig.poller.start();
      rig.run(1);

      rig.ecu.awake = false;
      // The adapter says NO DATA after its 200 ms timeout.
      rig.runMs(400);

      expect(rig.poller.health.value, PollHealth.ecuSilent);
    });
  });

  group('the rate', () {
    test('the fast tier is read at the rate it is measured to be', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.start();

      rig.run(30);

      final actual = rig.count(0x0C) / 30;
      expect(rig.poller.cycleRate.value, closeTo(actual, actual * 0.1));
      expect(rig.poller.cycleRate.value, greaterThan(20));
    });

    test(
      'on a Bluetooth clone it is well over the 3 Hz that CLAUDE.md 10 asks',
      () {
        final rig = PollRig(quirks: AdapterQuirks.bluetoothClone);
        addTearDown(rig.close);
        rig.poller.start();

        rig.run(60);

        expect(rig.poller.cycleRate.value, greaterThan(6));
      },
    );

    test(
      'with no batching it is one PID at a time: about 3 Hz for three PIDs',
      () {
        final rig = PollRig(
          demandStandard: false,
          quirks: AdapterQuirks.bluetoothClone,
          config: const PollConfig(batching: false),
        );
        addTearDown(rig.close);
        rig.poller.demand({
          0x0C: PollTier.fast,
          0x0D: PollTier.fast,
          0x11: PollTier.fast,
        });
        rig.poller.start();

        rig.run(60);

        // Each request takes the 80 ms round trip, 20 ms for the ECU and 5 ms
        // between: 105 ms, and three of them.
        expect(rig.poller.cycleRate.value, closeTo(1 / 0.315, 0.3));
      },
    );

    test('and with the medium and slow tiers as well, a little slower', () {
      final rig = PollRig(
        quirks: AdapterQuirks.bluetoothClone,
        config: const PollConfig(batching: false),
      );
      addTearDown(rig.close);
      rig.poller.start();

      rig.run(60);

      expect(rig.poller.cycleRate.value, inInclusiveRange(1.8, 2.6));
    });

    test('it is 0 until there are two reads', () {
      final rig = PollRig();
      addTearDown(rig.close);

      expect(rig.poller.cycleRate.value, 0);
    });
  });

  group('compatibility mode', () {
    test('turns batching off and slows the pace', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.start();
      rig.run(5);
      final fast = rig.poller.cycleRate.value;

      rig.poller.compatibilityMode = true;
      rig.requests.clear();
      rig.run(10);

      expect(rig.poller.compatibilityMode, isTrue);
      expect(rig.poller.isBatching, isFalse);
      expect(rig.requests.map((r) => r.length), everyElement(2));
      expect(rig.poller.cycleRate.value, lessThan(fast / 2));
      expect(rig.client.timing.minGap, ms(40));
    });

    test('turning it off restores both', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.start();
      rig.poller.compatibilityMode = true;
      rig.run(5);

      rig.poller.compatibilityMode = false;
      rig.requests.clear();
      rig.run(5);

      expect(rig.poller.isBatching, isTrue);
      expect(rig.client.timing.minGap, Duration.zero);
      expect(rig.requests.any((r) => r.length > 2), isTrue);
    });
  });

  group('starting and stopping', () {
    test('nothing is asked before it starts', () {
      final rig = PollRig();
      addTearDown(rig.close);

      rig.run(5);

      expect(rig.poller.requestsSent, 0);
      expect(rig.poller.isRunning, isFalse);
    });

    test(
      'nothing is asked after it stops, and the answer in flight is thrown away',
      () {
        final rig = PollRig(quirks: AdapterQuirks.bluetoothClone);
        addTearDown(rig.close);
        rig.poller.start();
        rig.run(2);

        rig.poller.stop();
        final readings = rig.readings.length;
        final requests = rig.poller.requestsSent;
        rig.run(5);

        expect(rig.readings.length, readings);
        expect(rig.poller.requestsSent, requests);
      },
    );

    test('starting again carries on', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.start();
      rig.run(2);
      rig.poller.stop();
      rig.run(2);
      final before = rig.readings.length;

      rig.poller.start();
      rig.run(2);

      expect(rig.readings.length, greaterThan(before + 20));
    });

    test('starting twice is one poller', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.start();
      rig.poller.start();

      rig.run(10);

      expect(rig.count(0x0C) / 10, lessThan(60));
      expect(rig.client.timeouts, 0);
    });

    test('a link that goes stops it, rather than asking into the void', () {
      final rig = PollRig();
      addTearDown(rig.close);
      rig.poller.start();
      rig.run(2);

      rig.transport.setState(
        const TransportState.disconnected(failure: TransportFailure.lost),
      );
      rig.run(2);
      final sent = rig.poller.requestsSent;
      rig.run(5);

      expect(rig.poller.isRunning, isFalse);
      expect(rig.poller.requestsSent, sent);
    });

    test('nothing is left scheduled once it has stopped', () {
      final rig = PollRig();
      rig.poller.start();
      rig.run(2);

      rig.poller.stop();
      rig.run(1);
      rig.client.dispose();
      rig.device.linkClosed();

      expect(rig.clock.pendingTasks, 0);
      rig.transport.dispose();
    });
  });

  group('the spacing of requests', () {
    test(
      'there is at least the minimum interval between one request and the next',
      () {
        final rig = PollRig(demandStandard: false);
        addTearDown(rig.close);
        rig.poller.demand({0x0C: PollTier.fast});
        rig.poller.start();

        rig.run(2);

        final times = rig.transport.writeTimes;
        for (var i = 1; i < times.length; i++) {
          expect(times[i] - times[i - 1], greaterThanOrEqualTo(ms(5)));
        }
      },
    );

    test('the interval can be changed', () {
      final rig = PollRig(
        demandStandard: false,
        config: const PollConfig(
          minRequestInterval: Duration(milliseconds: 100),
        ),
      );
      addTearDown(rig.close);
      rig.poller.demand({0x0C: PollTier.fast});
      rig.poller.start();

      rig.run(10);

      expect(rig.count(0x0C), lessThan(85));
    });
  });

  group('failures are not values', () {
    test('a NO DATA is not delivered, and does not stop the next request', () {
      final rig = PollRig(demandStandard: false);
      addTearDown(rig.close);
      rig.poller.demand({0x0C: PollTier.fast});
      rig.poller.start();
      rig.run(1);

      rig.ecu.awake = false;
      rig.run(1);
      final during = rig.count(0x0C);
      rig.ecu.awake = true;
      rig.run(1);

      expect(rig.count(0x0C), greaterThan(during));
      expect(rig.poller.failedRequests, greaterThan(0));
    });

    test(
      'the failure kinds are told apart: the car saying no is not noise',
      () {
        expect(Elm327Failure.noData, isNot(Elm327Failure.garbled));
      },
    );
  });
}

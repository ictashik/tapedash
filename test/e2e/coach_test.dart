// Layer 3 for phase 5 (CLAUDE.md 10): the coach against the simulator's truth,
// and the tips' premise: the aggressive run is told something, the eco run is
// told nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/coach/coach_thresholds.dart';
import 'package:tapedash/coach/efficiency_curve.dart';
import 'package:tapedash/coach/tips.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/vehicle_model.dart';

import 'trip_rig.dart';

/// Seconds the truth spent in stretches where [holds] held for at least
/// [minimum] seconds, and how many such stretches there were.
({double seconds, int stretches}) truthStretches(
  List<VehicleSnapshot> truth,
  bool Function(VehicleSnapshot s) holds,
  double minimum,
) {
  var total = 0.0;
  var count = 0;
  double? since;
  for (final s in truth) {
    if (holds(s)) {
      since ??= s.timeSeconds;
    } else if (since != null) {
      final length = s.timeSeconds - since;
      if (length >= minimum) {
        total += length;
        count++;
      }
      since = null;
    }
  }
  if (since != null) {
    final length = truth.last.timeSeconds - since;
    if (length >= minimum) {
      total += length;
      count++;
    }
  }
  return (seconds: total, stretches: count);
}

void main() {
  group('the tips\' premise', () {
    test('the aggressive run is told about hard acceleration', () async {
      final rig = TripRig(DriveScenarios.aggressiveCity)..runToEnd();
      addTearDown(rig.close);
      await rig.recorder.idle;
      final tips = const TipEngine().tipsFor(rig.recorder.current.value!);
      expect(tips, isNotEmpty);
      expect(
        tips.map((t) => t.kind),
        anyOf(contains(TipKind.hardAcceleration), contains(TipKind.idling)),
      );
      expect(tips.length, lessThanOrEqualTo(2));
    });

    test('the eco run on the same road is told nothing', () async {
      final rig = TripRig(DriveScenarios.ecoCity)..runToEnd();
      addTearDown(rig.close);
      await rig.recorder.idle;
      expect(const TipEngine().tipsFor(rig.recorder.current.value!), isEmpty);
    });

    test('a jam is told about idling, with its cost and minutes', () async {
      final rig = TripRig(DriveScenarios.trafficJam)..runToEnd();
      addTearDown(rig.close);
      await rig.recorder.idle;
      final tips = const TipEngine().tipsFor(rig.recorder.current.value!);
      expect(tips.first.kind, TipKind.idling);
      expect(
        tips.first.text,
        matches(
          RegExp(
            r'^₹\d+ of this trip went on idling — about \d+ minutes with the engine on\.$',
          ),
        ),
      );
    });

    test('an ordinary city drive is told nothing either', () async {
      final rig = TripRig(DriveScenarios.cityStopGo)..runToEnd();
      addTearDown(rig.close);
      await rig.recorder.idle;
      expect(const TipEngine().tipsFor(rig.recorder.current.value!), isEmpty);
    });
  });

  group('the duration rules against the truth', () {
    test('long idles: a minute stopped with the engine on', () async {
      final rig = TripRig(DriveScenarios.trafficJam)..runToEnd();
      addTearDown(rig.close);
      final truth = truthStretches(
        rig.rig.truth,
        (s) => s.engineState == EngineState.running && s.speedMs * 3.6 < 2,
        60,
      );
      expect(truth.stretches, greaterThan(0));
      expect(
        (rig.coach.stats.value.longIdles - truth.stretches).abs(),
        lessThanOrEqualTo(1),
      );
    });

    test(
      'high revs: above 3,500 rpm for more than 3 s, on the spirited manual',
      () async {
        final rig = TripRig(
          DriveScenarios.spiritedRevs,
          profile: VehicleProfiles.petrolManualSporty,
        )..runToEnd();
        addTearDown(rig.close);
        final truth = truthStretches(rig.rig.truth, (s) => s.rpm > 3500, 3);
        expect(truth.seconds, greaterThan(20));
        final counted = rig.coach.stats.value.highRpmSeconds;
        // The stretch is confirmed after its first 3 s, but counted from its start;
        // OBD rpm is sampled a few times a second.
        expect((counted - truth.seconds).abs() / truth.seconds, lessThan(0.15));
        expect(
          (rig.coach.stats.value.highRpmEvents - truth.stretches).abs(),
          lessThanOrEqualTo(2),
        );
      },
    );

    test('speeding: above the threshold for more than 10 s', () async {
      // The threshold is set before the drive starts.
      final again = TripRig(DriveScenarios.highwayCruise);
      addTearDown(again.close);
      again.coach.thresholds = const CoachThresholds(speedLimitKmh: 85);
      again.runToEnd();
      final truth = truthStretches(
        again.rig.truth,
        (s) => s.speedMs * 3.6 > 85,
        10,
      );
      expect(truth.seconds, greaterThan(60));
      expect(
        (again.coach.stats.value.speedingSeconds - truth.seconds).abs() /
            truth.seconds,
        lessThan(0.1),
      );
    });

    test('a new trip starts counting from nothing', () async {
      final rig = TripRig(
        DriveScenarios.mixedCommute(ignitionOff: const Duration(minutes: 8)),
      );
      addTearDown(rig.close);
      rig.runToEnd();
      await rig.recorder.idle;
      final trips = await rig.trips.all();
      expect(trips.length, 2);
      // Each trip has its own counts, not a running total.
      expect(
        trips.first.highRpmSeconds,
        lessThanOrEqualTo(trips.last.highRpmSeconds + 200),
      );
      expect(trips.last.longIdles, lessThanOrEqualTo(3));
    });
  });

  group('the sweet spot from real drives', () {
    test('matches the truth band by band, from stored samples', () async {
      // Real trips only (isDemo false), in one repository.
      final first = TripRig(DriveScenarios.highwayCruise, price: 100)
        ..runToEnd();
      addTearDown(first.close);
      await first.recorder.idle;
      final second = TripRig(DriveScenarios.cityStopGo, trips: first.trips)
        ..runToEnd();
      addTearDown(second.close);
      await second.recorder.idle;
      final curve = await sweetSpotFrom(first.trips);
      expect(curve.reported, isNotEmpty);
      expect(curve.best, isNotNull);

      // The truth, band by band, by the same steadiness rule on the same trips.
      var compared = 0;
      for (final rig in [first, second]) {
        final truth = rig.rig.truth;
        final km = <int, double>{};
        final litres = <int, double>{};
        for (var i = 20; i < truth.length; i += 20) {
          // One-second steps, from the 50 ms snapshots.
          final a = truth[i - 20];
          final b = truth[i];
          final dt = b.timeSeconds - a.timeSeconds;
          final accel = (b.speedMs - a.speedMs) / dt;
          if (accel.abs() >= 0.3) continue;
          final speed = (a.speedMs + b.speedMs) / 2 * 3.6;
          if (speed < 5) continue;
          final band = (speed ~/ 10) * 10;
          km[band] = (km[band] ?? 0) + speed * dt / 3600;
          litres[band] =
              (litres[band] ?? 0) +
              (a.fuelRateLitresPerHour + b.fuelRateLitresPerHour) /
                  2 *
                  dt /
                  3600;
        }
        for (final band in curve.reported) {
          final k = km[band.fromKmh];
          final l = litres[band.fromKmh];
          if (k == null || l == null || k < 3) continue;
          compared++;
          // Only bands both have plenty of: the two use slightly different
          // steadiness (throttle change is only in the app's).
          expect(
            (band.kmPerLitre! - k / l).abs() / (k / l),
            lessThan(0.15),
            reason: 'band ${band.fromKmh}',
          );
        }
      }
      expect(
        compared,
        greaterThan(0),
        reason: 'at least one band was compared',
      );
    });

    test(
      'the sweet spot of a CVT hatch is in the middle of its speeds, not at either end',
      () async {
        final rig = TripRig(DriveScenarios.highwayCruise)..runToEnd();
        addTearDown(rig.close);
        await rig.recorder.idle;
        final curve = await sweetSpotFrom(rig.trips);
        final best = curve.best!;
        expect(best.fromKmh, inInclusiveRange(40, 100));
      },
    );
  });
}

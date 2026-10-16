import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/survey/survey_schedule.dart';

const _a = '18DAF110';
const _b = '18DAF111';

// Like the first real car: the second ECU has more PIDs, and the PIDs both
// have are read from it.
final _supported = <String, Set<int>>{
  _a: {0x01, 0x04, 0x05, 0x0C, 0x0D, 0x11, 0x20, 0x34, 0x42, 0x2E},
  _b: {0x01, 0x04, 0x05, 0x0C, 0x0D, 0x0E, 0x10, 0x11, 0x20, 0x42, 0x44, 0x49},
};

SurveySchedule _build([Map<String, Set<int>>? supported]) =>
    SurveySchedule.build(supported ?? _supported, const SurveyConfig());

void main() {
  group('the tiers', () {
    test('the things the engine is doing are read most often', () {
      for (final pid in [0x0C, 0x0D, 0x11, 0x10, 0x04, 0x42]) {
        expect(SurveyPids.tierOf(pid), SurveyTier.core);
      }
      for (final pid in [0x0E, 0x44, 0x49, 0x4A, 0x34, 0x06]) {
        expect(SurveyPids.tierOf(pid), SurveyTier.fast);
      }
      for (final pid in [0x05, 0x0F, 0x33]) {
        expect(SurveyPids.tierOf(pid), SurveyTier.medium);
      }
      expect(SurveyPids.tierOf(0x01), SurveyTier.still);
      expect(SurveyPids.tierOf(0xA4), SurveyTier.still);
    });

    test('core is read twice as often as fast, and so on down', () {
      const c = SurveyConfig();
      expect(
        c.periodOf(SurveyTier.core),
        lessThan(c.periodOf(SurveyTier.fast)),
      );
      expect(
        c.periodOf(SurveyTier.fast),
        lessThan(c.periodOf(SurveyTier.medium)),
      );
      expect(
        c.periodOf(SurveyTier.medium),
        lessThan(c.periodOf(SurveyTier.still)),
      );
    });
  });

  group('building', () {
    test('a PID both ECUs have is read from the one with more PIDs', () {
      final s = _build();

      final rpm = s.items.where((i) => i.pid == 0x0C);
      final main = rpm.firstWhere(
        (i) => i.period == const SurveyConfig().coreEvery,
      );
      expect(main.ecu, _b);
    });

    test('the other ECU has the core PIDs too, as a rare cross-check', () {
      final s = _build();

      final check = s.items.where((i) => i.ecu == _a && i.pid == 0x0C);
      expect(check, hasLength(1));
      expect(check.single.period, const SurveyConfig().crossCheckEvery);
      // But not the ones that are not core.
      expect(s.items.where((i) => i.ecu == _a && i.pid == 0x05), isEmpty);
    });

    test('a PID only one ECU has is read from it', () {
      final s = _build();

      expect(s.items.where((i) => i.pid == 0x34).single.ecu, _a);
      expect(s.items.where((i) => i.pid == 0x10).single.ecu, _b);
    });

    test('PIDs that only list other PIDs are not in the schedule', () {
      final s = _build();

      expect(s.items.where((i) => i.pid == 0x20), isEmpty);
    });

    test('knows its ECUs', () {
      expect(_build().ecus, {_a, _b});
    });
  });

  group('choosing', () {
    test('nothing has been read, so everything is due; six go together', () {
      final s = _build();

      final r = s.next(Duration.zero, maxBatch: 6)!;

      expect(r.pids.length, 6);
      expect(r.pids.toSet().length, 6);
    });

    test('a batch is from one ECU', () {
      final s = _build();
      final r = s.next(Duration.zero, maxBatch: 6)!;

      final owners = {
        for (final p in r.pids)
          s.items.firstWhere((i) => i.pid == p && i.ecu == r.ecu).ecu,
      };
      expect(owners, {r.ecu});
    });

    test('the batch size is honoured', () {
      final s = _build();

      expect(s.next(Duration.zero, maxBatch: 3)!.pids, hasLength(3));
      expect(s.next(Duration.zero, maxBatch: 1)!.pids, hasLength(1));
    });

    test('what was read a moment ago waits for what was not', () {
      final s = _build();
      var now = Duration.zero;
      final read = <int>{};
      // Go round: after enough requests every PID of the main ECU has been
      // read once, before any is read twice.
      for (var i = 0; i < 6; i++) {
        final r = s.next(now, maxBatch: 6, stayOn: _b)!;
        s.record(r, now, got: r.pids.toSet(), config: const SurveyConfig());
        now += const Duration(milliseconds: 170);
        read.addAll(r.pids);
      }
      expect(read, containsAll([0x0C, 0x0D, 0x10, 0x11, 0x04, 0x42]));
    });

    test('the PIDs wanted most come round most often', () {
      final s = _build();
      var now = Duration.zero;
      final counts = <int, int>{};
      for (var i = 0; i < 200; i++) {
        final r = s.next(now, maxBatch: 6, stayOn: _b);
        if (r == null) break;
        s.record(r, now, got: r.pids.toSet(), config: const SurveyConfig());
        for (final p in r.pids) {
          if (r.ecu == _b) counts[p] = (counts[p] ?? 0) + 1;
        }
        now += const Duration(milliseconds: 170);
      }

      // Core against a PID read once a minute.
      expect(counts[0x0C]!, greaterThan(counts[0x01] ?? 0));
      expect(counts[0x0C]!, greaterThanOrEqualTo(counts[0x44] ?? 0));
    });

    SurveySchedule readEverythingOnce() {
      final s = _build();
      var now = Duration.zero;
      String? on;
      while (s.items.any((i) => i.lastRead == null)) {
        final r = s.next(now, maxBatch: 6, stayOn: on)!;
        s.record(r, now, got: r.pids.toSet(), config: const SurveyConfig());
        on = r.ecu;
        now += const Duration(milliseconds: 170);
      }
      return s;
    }

    test('it stays on an ECU unless there is nothing left to gain there', () {
      final s = readEverythingOnce();
      // Just after: the second ECU's core PIDs (every 0.4 s) are a little late,
      // the first ECU's are not due for a good while.
      final now =
          s.items.map((i) => i.lastRead!).reduce((a, b) => a > b ? a : b) +
          const Duration(milliseconds: 300);

      // Listening to the second: one more request there, not a trip.
      expect(s.next(now, maxBatch: 6, stayOn: _b)!.ecu, _b);
      // Listening to the first, with nothing due there, it goes back to the
      // second, which has things due.
      expect(s.next(now, maxBatch: 6, stayOn: _a)!.ecu, _b);
    });

    test(
      'it goes to the other ECU once that is twice as late as it should be',
      () {
        final s = readEverythingOnce();
        var now = s.items
            .map((i) => i.lastRead!)
            .reduce((a, b) => a > b ? a : b);
        // Keep the second ECU fresh, and let the first fall behind: its fast PIDs
        // are due every 2 s.
        while (s.items
                .where((i) => i.ecu == _a)
                .map((i) => i.urgency(now))
                .reduce((a, b) => a > b ? a : b) <
            2) {
          now += const Duration(milliseconds: 170);
          final r = s.next(now, maxBatch: 6, stayOn: _b);
          if (r != null && r.ecu == _b) {
            s.record(r, now, got: r.pids.toSet(), config: const SurveyConfig());
          } else {
            break;
          }
        }

        // The second has had its turn and may still be the busier, but the first
        // is now far enough behind to be worth the trip.
        expect(s.next(now, maxBatch: 6, stayOn: _b)!.ecu, _a);
      },
    );

    test('a PID with an unknown length is asked for alone', () {
      final s = _build({
        _a: {0xA4, 0x0C, 0x0D},
      });
      var now = Duration.zero;
      final alone = <List<int>>[];
      for (var i = 0; i < 6; i++) {
        final r = s.next(now, maxBatch: 6)!;
        if (r.pids.contains(0xA4)) alone.add(r.pids);
        s.record(r, now, got: r.pids.toSet(), config: const SurveyConfig());
        now += const Duration(milliseconds: 170);
      }

      expect(alone, isNotEmpty);
      expect(alone.every((p) => p.length == 1), isTrue);
    });

    test('nothing to ask gives null', () {
      expect(SurveySchedule([]).next(Duration.zero, maxBatch: 6), isNull);
    });
  });

  group('misses', () {
    test('a PID that is never answered is left alone for a while', () {
      final s = _build({
        _a: {0x0C, 0x0D, 0x44},
      });
      const config = SurveyConfig();
      var now = Duration.zero;
      for (var i = 0; i < 5; i++) {
        final r = s.next(now, maxBatch: 6)!;
        s.record(r, now, got: {0x0C, 0x0D}, config: config);
        now += const Duration(milliseconds: 170);
      }

      final item = s.items.firstWhere((i) => i.pid == 0x44);
      expect(item.suspendedUntil, isNotNull);
      final r = s.next(now, maxBatch: 6)!;
      expect(r.pids, isNot(contains(0x44)));
      // It comes back.
      now += config.suspendFor + const Duration(seconds: 1);
      expect(s.next(now, maxBatch: 6)!.pids, contains(0x44));
    });

    test('an answer clears the count', () {
      final s = _build({
        _a: {0x0C, 0x44},
      });
      const config = SurveyConfig();
      var now = Duration.zero;
      for (var i = 0; i < 4; i++) {
        final r = s.next(now, maxBatch: 6)!;
        s.record(r, now, got: {0x0C}, config: config);
        now += const Duration(milliseconds: 170);
      }
      final r = s.next(now, maxBatch: 6)!;
      s.record(r, now, got: {0x0C, 0x44}, config: config);

      expect(s.items.firstWhere((i) => i.pid == 0x44).misses, 0);
      expect(s.items.firstWhere((i) => i.pid == 0x44).suspendedUntil, isNull);
    });

    test('clearing the suspensions puts everything back', () {
      final s = _build({
        _a: {0x0C, 0x44},
      });
      for (final i in s.items) {
        i.suspendedUntil = const Duration(hours: 1);
      }
      expect(s.next(Duration.zero, maxBatch: 6), isNull);

      s.clearSuspensions();

      expect(s.next(Duration.zero, maxBatch: 6), isNotNull);
    });
  });
}

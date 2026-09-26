import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';

import '../../../tool/record_sim.dart';

SessionLog _record(
  String scenario, {
  String? profile,
  AdapterQuirks? quirks,
  int seed = 1,
  Duration limit = const Duration(minutes: 40),
}) => SessionLog.parse(
  recordSession(
    RecordOptions(
      scenario: DriveScenarios.byName(scenario)!,
      profile: profile == null ? null : VehicleProfiles.byName(profile),
      quirks: quirks,
      seed: seed,
      limit: limit,
    ),
  ),
);

Iterable<String> _sent(SessionLog log) => log.entries
    .where((e) => e.direction == SessionDirection.sent)
    .map((e) => e.text);

/// What came back to each time [command] was sent, joined into one string.
List<String> _answers(SessionLog log, String command) {
  final answers = <String>[];
  StringBuffer? current;
  for (final entry in log.entries) {
    if (entry.direction == SessionDirection.sent) {
      final done = current;
      if (done != null) answers.add(done.toString());
      current = entry.text == command ? StringBuffer() : null;
    } else if (entry.direction == SessionDirection.received) {
      current?.write(entry.text);
    }
  }
  final last = current;
  if (last != null) answers.add(last.toString());
  return answers;
}

void main() {
  group('the log', () {
    test('says what it is a recording of', () {
      final log = _record('cold_start_idle', seed: 7);

      expect(log.header['scenario'], 'cold_start_idle');
      expect(log.header['profile'], 'petrol_cvt_maf');
      expect(log.header['seed'], '7');
      expect(log.header['quirks'], 'none');
      expect(log.header['source'], contains('record_sim'));
    });

    test('a profile and quirks can be chosen', () {
      final log = _record(
        'cold_start_idle',
        profile: 'minimal_old_car',
        quirks: AdapterQuirks.bluetoothClone,
      );

      expect(log.header['profile'], 'minimal_old_car');
      expect(log.header['quirks'], contains('latency 80 ms'));
    });

    test('starts with the link coming up, then the start-up commands', () {
      final log = _record('cold_start_idle');

      expect(log.entries.take(2).map((e) => (e.direction, e.text)), [
        (SessionDirection.event, 'connecting'),
        (SessionDirection.event, 'connected'),
      ]);
      expect(_sent(log).take(12).toList(), [
        'ATZ\r',
        'ATE0\r',
        'ATL0\r',
        'ATS0\r',
        'ATH0\r',
        'ATAT1\r',
        'ATSP0\r',
        '0100\r',
        '0120\r',
        '0140\r',
        '03\r',
        '07\r',
      ]);
    });

    test('a command is never sent before the last one has its prompt', () {
      final log = _record('cold_start_idle');
      var waiting = false;

      for (final entry in log.entries) {
        switch (entry.direction) {
          case SessionDirection.sent:
            expect(waiting, isFalse, reason: 'sent while waiting: $entry');
            waiting = true;
          case SessionDirection.received:
            if (entry.text.endsWith('>')) waiting = false;
          case SessionDirection.event:
            break;
        }
      }
    });

    test('times never go backwards', () {
      final log = _record('city_stop_go');

      var last = Duration.zero;
      for (final entry in log.entries) {
        expect(entry.at, greaterThanOrEqualTo(last));
        last = entry.at;
      }
    });

    test('every command ends with a carriage return', () {
      final log = _record('cold_start_idle');

      expect(_sent(log), everyElement(endsWith('\r')));
    });

    test('a drive that ends stops the recording a few seconds later', () {
      final log = _record('cold_start_idle');

      // Five minutes of idling, and the last answers come in after it.
      expect(log.entries.last.at.inSeconds, inInclusiveRange(300, 306));
    });

    test('the limit cuts a long drive short', () {
      final log = _record('highway_cruise', limit: const Duration(seconds: 30));

      expect(log.entries.last.at.inSeconds, inInclusiveRange(30, 36));
    });
  });

  group('what is polled', () {
    Set<String> polled(SessionLog log) => _sent(log).toSet();

    test('the PIDs the profile has, and none it has not', () {
      final maf = polled(_record('cold_start_idle', profile: 'petrol_cvt_maf'));
      final map = polled(_record('cold_start_idle', profile: 'petrol_cvt_map'));
      final rate = polled(
        _record('cold_start_idle', profile: 'petrol_cvt_fuelrate'),
      );
      final old = polled(
        _record('cold_start_idle', profile: 'minimal_old_car'),
      );

      // The fuel source: 5E if there is one, else MAF, else MAP.
      expect(maf, contains('01101\r'));
      expect(maf, isNot(contains('015E1\r')));
      expect(map, isNot(contains('01101\r')));
      expect(map, contains('010B1\r'));
      expect(rate, contains('015E1\r'));
      expect(rate, isNot(contains('01101\r')));
      // The old car has only 04, 05, 0C, 0D and 11.
      expect(old.where((c) => c.startsWith('01') && c.length == 6).toSet(), {
        '010C1\r',
        '010D1\r',
        '01111\r',
        '01041\r',
        '01051\r',
      });
    });

    test('it asks for the range PIDs only when there is something in them', () {
      final old = polled(
        _record('cold_start_idle', profile: 'minimal_old_car'),
      );
      final full = polled(
        _record('cold_start_idle', profile: 'petrol_cvt_maf'),
      );

      expect(old, contains('0100\r'));
      expect(old, isNot(contains('0120\r')));
      expect(old, isNot(contains('0140\r')));
      expect(full, containsAll(['0100\r', '0120\r', '0140\r']));
    });

    test(
      'the fast tier every cycle, the medium every third, the slow every twelfth',
      () {
        final sent = _sent(_record('cold_start_idle')).toList();
        int count(String c) => sent.where((s) => s == c).length;

        final fast = count('010C1\r');
        // The recording can end part way through a cycle.
        expect(count('010D1\r'), closeTo(fast, 1));
        expect(count('01111\r'), closeTo(fast, 1));
        expect(fast, greaterThan(1000));
        expect(count('01041\r'), closeTo(fast / 3, 2));
        expect(count('01101\r'), closeTo(fast / 3, 2));
        expect(count('01051\r'), closeTo(fast / 12, 2));
        expect(count('01421\r'), closeTo(fast / 12, 2));
      },
    );

    test('the answers are the car\'s: the rpm is an engine idling', () {
      final log = _record('cold_start_idle');
      final rpms = <double>[];
      var awaiting = false;
      for (final entry in log.entries) {
        if (entry.direction == SessionDirection.sent) {
          awaiting = entry.text == '010C1\r';
        } else if (awaiting &&
            entry.direction == SessionDirection.received &&
            entry.text.startsWith('410C')) {
          final hex = entry.text.substring(4, 8);
          rpms.add(int.parse(hex, radix: 16) / 4);
          awaiting = false;
        }
      }

      expect(rpms.length, greaterThan(1000));
      // Cold: fast idle, settling towards 750 over the five minutes.
      expect(
        rpms.skip(rpms.length ~/ 2).reduce((a, b) => a + b) /
            (rpms.length - rpms.length ~/ 2),
        inInclusiveRange(700, 1300),
      );
    });
  });

  group('the adapter', () {
    test('a Bluetooth clone: an 80 ms round trip, and 20 ms for the ECU', () {
      final log = _record(
        'cold_start_idle',
        quirks: AdapterQuirks.bluetoothClone,
        limit: const Duration(minutes: 1),
      );
      final trips = <int>[];
      Duration? sentAt;
      for (final entry in log.entries) {
        if (entry.direction == SessionDirection.sent &&
            entry.text == '010C1\r') {
          sentAt = entry.at;
        } else if (sentAt != null &&
            entry.direction == SessionDirection.received) {
          trips.add((entry.at - sentAt).inMilliseconds);
          sentAt = null;
        }
      }

      expect(trips.length, greaterThan(50));
      // Echo is off by then, so the first thing back is the answer: the link's
      // 40 to 120 ms, and the ECU's 20 ms on top.
      expect(trips.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(58));
      expect(trips.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(142));
      final mean = trips.reduce((a, b) => a + b) / trips.length;
      expect(mean, closeTo(100, 8));
    });

    test('adapter_flaky: the first command is lost, and is sent again', () {
      final log = _record('adapter_flaky');

      final atz = log.entries
          .where(
            (e) => e.direction == SessionDirection.sent && e.text == 'ATZ\r',
          )
          .take(2)
          .toList();
      expect(atz.length, 2);
      // Nothing came back for the first, so it waited out its 3 s.
      expect(atz[1].at - atz[0].at, const Duration(seconds: 3));
    });

    test('adapter_flaky: the link drops, and the app reconnects', () {
      final log = _record('adapter_flaky');
      final events = log.entries
          .where((e) => e.direction == SessionDirection.event)
          .toList();

      final lost = events.firstWhere((e) => e.text == 'disconnected (lost)');
      expect(lost.at.inSeconds, 240);
      // It tries every three seconds during the 15 s outage, and fails.
      final failed = events.where(
        (e) => e.text == 'disconnected (unreachable)',
      );
      expect(failed.length, inInclusiveRange(4, 6));
      final back = events.firstWhere(
        (e) => e.text == 'connected' && e.at > lost.at,
      );
      expect(back.at.inSeconds, inInclusiveRange(255, 260));
      // And it starts the adapter up again.
      final after = _sent(log).toList();
      expect(
        after.where((c) => c == 'ATSP0\r').length,
        greaterThanOrEqualTo(2),
      );
    });

    test('adapter_flaky: some answers are NO DATA', () {
      final log = _record('adapter_flaky');

      final noData = log.entries.where((e) => e.text.contains('NO DATA'));
      expect(noData.length, greaterThan(20));
    });

    test('mixed_commute: the ignition off gives NO DATA for three minutes', () {
      final log = _record('mixed_commute');

      final times = log.entries
          .where((e) => e.text.contains('NO DATA'))
          .map((e) => e.at.inSeconds)
          .toList();
      expect(times, isNotEmpty);
      expect(times.last - times.first, inInclusiveRange(170, 190));
    });

    test('dtc_present: the codes are read at connect, and there are two', () {
      final log = _record('dtc_present');

      final answers = _answers(log, '03\r');
      // 43, two codes, P0420 and P0171: one frame, so no line count.
      expect(answers.first, '430204200171\r\r>');
      expect(_answers(log, '07\r').first, '4700\r\r>');
    });

    test('a car with no codes says so: 43 00', () {
      final log = _record('cold_start_idle');

      expect(_answers(log, '03\r').first, '4300\r\r>');
    });
  });

  group('determinism', () {
    test('the same options record the same log, to the byte', () {
      String run() => recordSession(
        RecordOptions(
          scenario: DriveScenarios.cityStopGo,
          quirks: AdapterQuirks.flaky,
          seed: 3,
          limit: const Duration(minutes: 3),
        ),
      );

      expect(run(), run());
    });

    test('another seed changes the noise but not the drive', () {
      String run(int seed) => recordSession(
        RecordOptions(
          scenario: DriveScenarios.cityStopGo,
          seed: seed,
          limit: const Duration(minutes: 3),
        ),
      );

      expect(run(1), isNot(run(2)));
    });
  });

  group('speed', () {
    test('a whole drive is recorded in a moment', () {
      final watch = Stopwatch()..start();

      _record('city_stop_go');

      expect(watch.elapsed.inSeconds, lessThan(20));
    });
  });
}

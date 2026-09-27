import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/elm327/elm327_parser.dart';
import 'package:tapedash/obd/pids/pid.dart';
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

/// The PIDs each polling request asked for: `0104050C0D0F101` is 04 05 0C 0D 0F
/// and the count digit 1.
List<List<int>> _polls(SessionLog log) {
  final out = <List<int>>[];
  for (final sent in _sent(log)) {
    final command = sent.substring(0, sent.length - 1);
    // A request for PIDs: mode 01, one or more PIDs, and the count digit. The
    // support requests (0100, 0120...) have no digit.
    if (!command.startsWith('01') ||
        command.length.isEven ||
        command.length < 5) {
      continue;
    }
    final hex = command.substring(2, command.length - 1);
    out.add([
      for (var i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }
  return out;
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

    test(
      'starts with the link coming up, then the start-up of CLAUDE.md 8.1',
      () {
        final log = _record('cold_start_idle');

        expect(log.entries.take(2).map((e) => (e.direction, e.text)), [
          (SessionDirection.event, 'connecting'),
          (SessionDirection.event, 'connected'),
        ]);
        expect(_sent(log).take(11).toList(), [
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
          'ATDPN\r',
        ]);
      },
    );

    test(
      'the settle comes first: nothing is sent for 300 ms after connecting',
      () {
        final log = _record('cold_start_idle');

        final connected = log.entries.firstWhere((e) => e.text == 'connected');
        final firstSent = log.entries.firstWhere(
          (e) => e.direction == SessionDirection.sent,
        );
        expect(firstSent.at - connected.at, const Duration(milliseconds: 300));
      },
    );

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
    Set<int> polled(SessionLog log) => {for (final p in _polls(log)) ...p};

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
      expect(maf, {0x04, 0x05, 0x0C, 0x0D, 0x0F, 0x10, 0x11, 0x2F, 0x42});
      expect(map, {0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F, 0x11, 0x2F, 0x42});
      expect(rate, {0x04, 0x05, 0x0C, 0x0D, 0x0F, 0x11, 0x2F, 0x42, 0x5E});
      expect(old, {0x04, 0x05, 0x0C, 0x0D, 0x11});
    });

    test('it asks for the range PIDs only when there is something in them', () {
      final old = _sent(
        _record('cold_start_idle', profile: 'minimal_old_car'),
      ).toSet();
      final full = _sent(
        _record('cold_start_idle', profile: 'petrol_cvt_maf'),
      ).toSet();

      expect(old, contains('0100\r'));
      expect(old, isNot(contains('0120\r')));
      expect(old, isNot(contains('0140\r')));
      expect(full, containsAll(['0100\r', '0120\r', '0140\r']));
    });

    test('several PIDs go in one request, with the count digit', () {
      final log = _record('cold_start_idle');

      final polls = _sent(log).where((c) => c.startsWith('01') && c.length > 6);
      expect(polls, isNotEmpty);
      // The steady state: RPM, speed and throttle in one, and a 1 at the end.
      expect(polls, contains('01110C0D1\r'));
    });

    test(
      'the fast tier every cycle, the medium every second, the slow every four',
      () {
        final polls = _polls(_record('cold_start_idle'));
        int asked(int pid) => polls.where((p) => p.contains(pid)).length;

        expect(asked(0x0C), greaterThan(1000));
        expect(asked(0x04), closeTo(300, 12));
        expect(asked(0x10), closeTo(300, 12));
        expect(asked(0x05), closeTo(75, 6));
        expect(asked(0x42), closeTo(75, 6));
      },
    );

    test('the answers are the car\'s: the rpm is an engine idling', () {
      final log = _record('cold_start_idle');
      final rpms = <double>[];
      var awaiting = false;
      final text = StringBuffer();
      void finish() {
        if (!awaiting) return;
        awaiting = false;
        final parsed = Elm327Parser.parse(text.toString());
        final messages = Elm327Parser.messages(parsed.lines);
        if (messages == null || messages.isEmpty) return;
        final answer = Mode01Answer.parse(messages.first);
        final v = answer?.valueOf(Pids.rpm);
        if (v != null) rpms.add(v.value);
      }

      for (final entry in log.entries) {
        if (entry.direction == SessionDirection.sent) {
          finish();
          text.clear();
          final polls = entry.text.startsWith('01') && entry.text.length > 4;
          awaiting = polls && entry.text.contains('0C');
        } else if (entry.direction == SessionDirection.received) {
          text.write(entry.text);
        }
      }
      finish();

      expect(rpms.length, greaterThan(1000));
      // Cold: fast idle, settling towards 750 over the five minutes.
      final tail = rpms.skip(rpms.length ~/ 2).toList();
      final mean = tail.reduce((a, b) => a + b) / tail.length;
      expect(mean, inInclusiveRange(700, 1300));
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
            entry.text == '01110C0D1\r') {
          sentAt = entry.at;
        } else if (sentAt != null &&
            entry.direction == SessionDirection.received) {
          trips.add((entry.at - sentAt).inMilliseconds);
          sentAt = null;
        }
      }

      expect(trips.length, greaterThan(50));
      // Echo is off by then, so the first thing back is the answer: the link's
      // 40 to 120 ms, and the ECU's 20 ms and a few for the second frame.
      expect(trips.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(60));
      expect(trips.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(146));
      final mean = trips.reduce((a, b) => a + b) / trips.length;
      expect(mean, closeTo(102, 8));
    });

    test(
      'adapter_flaky: the first command is lost, and is sent again after 4 s',
      () {
        final log = _record('adapter_flaky');

        final atz = log.entries
            .where(
              (e) => e.direction == SessionDirection.sent && e.text == 'ATZ\r',
            )
            .take(2)
            .toList();
        expect(atz.length, 2);
        // Nothing came back for the first, so it waited out the reset's 4 s and
        // the settle of 100 ms after a timeout.
        expect(atz[1].at - atz[0].at, const Duration(milliseconds: 4100));
      },
    );

    test('adapter_flaky: the link drops, and the app reconnects', () {
      final log = _record('adapter_flaky');
      final events = log.entries
          .where((e) => e.direction == SessionDirection.event)
          .toList();

      final lost = events.firstWhere((e) => e.text == 'disconnected (lost)');
      expect(lost.at.inSeconds, 240);
      // It tries after 1, 2, 4 and 8 s during the 15 s outage: three fail.
      final failed = events.where(
        (e) => e.text == 'disconnected (unreachable)',
      );
      expect(failed.length, 3);
      final back = events.firstWhere(
        (e) => e.text == 'connected' && e.at > lost.at,
      );
      expect(back.at.inSeconds, inInclusiveRange(255, 260));
      // And it starts the adapter up again, this time with the protocol it found.
      final sent = _sent(log).toList();
      expect(sent.where((c) => c == 'ATZ\r').length, greaterThanOrEqualTo(3));
      expect(sent.where((c) => c == 'ATSP6\r').length, greaterThanOrEqualTo(1));
    });

    test('adapter_flaky: some answers are NO DATA', () {
      final log = _record('adapter_flaky');

      final noData = log.entries.where((e) => e.text.contains('NO DATA'));
      expect(noData.length, greaterThan(10));
    });

    test(
      'mixed_commute: the ignition off gives NO DATA, and the car is asked about once a second',
      () {
        final log = _record('mixed_commute');

        final times = log.entries
            .where((e) => e.text.contains('NO DATA'))
            .map((e) => e.at.inSeconds)
            .toList();
        expect(times, isNotEmpty);
        expect(times.last - times.first, inInclusiveRange(170, 190));
        // Probed once a second or so for three minutes, and not in a flood.
        expect(times.length, inInclusiveRange(100, 260));
      },
    );

    test(
      'dtc_present: the codes are read once connected, and there are two',
      () {
        final log = _record('dtc_present');

        final answers = _answers(log, '03\r');
        // 43, two codes, P0420 and P0171: one frame, so no line count.
        expect(answers.first, '430204200171\r\r>');
        expect(_answers(log, '07\r').first, '4700\r\r>');
      },
    );

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

      expect(watch.elapsed.inSeconds, lessThan(30));
    });
  });
}

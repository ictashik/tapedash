import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/survey/survey_runner.dart';
import 'package:tapedash/obd/survey/survey_schedule.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenario_events.dart';

import '../support/rewriting_transport.dart';
import '../support/survey_rig.dart';

const _a = '18DAF110';
const _b = '18DAF111';

Set<int> _pids(Iterable<int> from) => {
  for (final p in from)
    if (p % 0x20 != 0) p,
};

void main() {
  group('a survey of a car with two ECUs on 29-bit CAN', () {
    late SurveyRig rig;

    setUp(() {
      rig = SurveyRig()..start();
      rig.run(90);
    });
    tearDown(() => rig.close());

    test('it finds both ECUs and each one\'s PIDs', () {
      expect(rig.progress.ecus, [_a, _b]);

      final supported = rig.summary.supported;
      expect(supported[_a]!.where((p) => p % 0x20 != 0).toSet(), {
        0x01,
        ...VehicleProfiles.surveyTwin.supportedPids,
      });
      expect(supported[_b]!.where((p) => p % 0x20 != 0).toSet(), {
        0x01,
        ...VehicleProfiles.surveyTwin.secondEcuPids,
      });
    });

    test('it goes through the phases in order and ends up driving', () {
      // (It begins in connecting, which is not a change.)
      expect(rig.sequence, [
        SurveyPhase.starting,
        SurveyPhase.discovering,
        SurveyPhase.probing,
        SurveyPhase.driving,
      ]);
      expect(rig.progress.phase, SurveyPhase.driving);
    });

    test('every PID each ECU has is read at least once', () {
      final s = rig.summary;
      for (final ecu in [_a, _b]) {
        for (final pid in _pids(s.supported[ecu]!)) {
          expect(
            s.readsOf(pid, ecu: ecu),
            isNotEmpty,
            reason: '$ecu PID ${pid.toRadixString(16)}',
          );
        }
      }
    });

    test('it listens to one ECU at a time, and each read is its own', () {
      expect(rig.progress.filter, SurveyFilter.working);
      final s = rig.summary;
      expect(s.commands, contains('ATCRA$_a'));
      expect(s.commands, contains('ATCRA$_b'));
      // The MAF is only on the second ECU, so it is never attributed to the
      // first.
      expect(s.readsOf(0x10, ecu: _a), isEmpty);
      expect(s.readsOf(0x10, ecu: _b), isNotEmpty);
      // And the wide-range oxygen sensor only on the first.
      expect(s.readsOf(0x34, ecu: _b), isEmpty);
      expect(s.readsOf(0x34, ecu: _a), isNotEmpty);
    });

    test('values decode: the idling engine reads about 750 rpm', () {
      final rpm = rig.summary.readsOf(0x0C, ecu: _b).last.data;
      final value = (256 * rpm[0] + rpm[1]) / 4;
      expect(value, inInclusiveRange(600, 900));
    });

    test('the other modes are read: codes, test results, calibration', () {
      final s = rig.summary;
      final commands = s.others.map((o) => o.command).toSet();
      bool asked(String c) => commands.any((x) => x.startsWith(c));

      // (Each request carries a last digit, the number of answers to wait for.)
      for (final c in ['03', '07', '0A', '0900', '0600']) {
        expect(asked(c), isTrue, reason: c);
      }
      // Calibration ID, its verification number and the ECU name, per ECU.
      for (final c in ['0904', '0906', '090A']) {
        expect(commands.any((x) => x.startsWith(c)), isTrue, reason: c);
      }
      // Monitors with results.
      expect(commands.any((x) => x.startsWith('0601')), isTrue);
      final cal = s.others.firstWhere((o) => o.command.startsWith('0904'));
      expect(cal.payload.take(3), [0x49, 0x04, 0x01]);
    });

    test('it reads, and only reads: no clear, no VIN, no writing', () {
      final commands = rig.summary.commands;
      const allowed = [
        'ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATH1', 'ATAT1', 'ATSP', //
        'ATDPN', 'ATI', 'AT@1', 'ATRV', 'ATCRA',
      ];
      for (final c in commands) {
        if (c.startsWith('AT')) {
          expect(
            allowed.any(c.startsWith),
            isTrue,
            reason: 'unexpected adapter command $c',
          );
        } else {
          // A request for data: Mode 01, 03, 06, 07, 09 or 0A, never 04 (clear
          // codes) and never 0902 (the VIN).
          expect(c.startsWith('04'), isFalse, reason: c);
          expect(c.startsWith('0902'), isFalse, reason: c);
          expect(
            ['01', '03', '06', '07', '09', '0A'].any(c.startsWith),
            isTrue,
            reason: c,
          );
        }
      }
    });

    test('the drive reads six PIDs to a request', () {
      final sixes = rig.summary.commands.where(
        (c) => c.startsWith('01') && c.length == 2 + 12 + 1,
      );
      expect(sixes.length, greaterThan(100));
      expect(rig.progress.batch, 6);
    });

    test('the engine\'s revs come round faster than the 1.3 a second the '
        'dashboard gets', () {
      final reads = rig.summary.readsOf(0x0C, ecu: _b);
      final from = const Duration(seconds: 40);
      final to = const Duration(seconds: 90);
      final n = reads.where((r) => r.at >= from && r.at < to).length;
      final perSecond = n / (to - from).inSeconds;

      expect(perSecond, greaterThan(2.0));
    });

    test('it reads the adapter\'s own voltage as well', () {
      expect(
        rig.summary.commands.where((c) => c == 'ATRV').length,
        greaterThan(5),
      );
      expect(rig.progress.adapterVolts, isNotNull);
    });

    test('the log is a log: it formats and reads back to the same survey', () {
      final text = rig.log.format();
      final back = SessionLog.parse(text);

      expect(back.entries.length, rig.log.entries.length);
      expect(back.header['survey'], '1');
      expect(
        back.entries.where((e) => e.direction == SessionDirection.note),
        isNotEmpty,
      );
    });

    test('it writes down what it decided', () {
      final notes = rig.notes;

      expect(notes.any((n) => n.startsWith('ecu id=$_a pids=')), isTrue);
      expect(notes.any((n) => n.startsWith('ecu id=$_b pids=')), isTrue);
      expect(notes, contains('probe done'));
      expect(notes.any((n) => n.startsWith('vitals ')), isTrue);
    });

    test('finishing ends it and says so', () {
      rig.runner.finish('test');

      expect(rig.progress.phase, SurveyPhase.finished);
      expect(rig.notes.any((n) => n.startsWith('done reason=test')), isTrue);
      int sent() => rig.log.entries
          .where((e) => e.direction == SessionDirection.sent)
          .length;
      final before = sent();
      rig.run(10);
      expect(sent(), before);
    });
  });

  group('a car with one ECU on 11-bit CAN', () {
    test('it needs no filter and sends none', () {
      final rig = SurveyRig(profile: VehicleProfiles.petrolCvtMaf)..start();
      rig.run(60);

      expect(rig.progress.phase, SurveyPhase.driving);
      expect(rig.progress.ecus, ['7E8']);
      expect(rig.summary.commands.where((c) => c.startsWith('ATCRA')), isEmpty);
      expect(rig.summary.readsOf(0x0C), isNotEmpty);
      rig.close();
    });
  });

  group('an adapter that does not take the receive filter', () {
    test('the survey says so, and goes on hearing every ECU', () {
      final rig = SurveyRig(
        quirks: AdapterQuirks.measuredBle.copyWith(noReceiveFilter: true),
      )..start();
      rig.run(120);

      expect(rig.progress.filter, SurveyFilter.refused);
      expect(rig.progress.phase, SurveyPhase.driving);
      expect(rig.notes.any((n) => n.startsWith('ATCRA refused')), isTrue);
      // Still reads the PIDs only the second ECU has.
      expect(rig.summary.readsOf(0x10), isNotEmpty);
      // The batches that lose a message to the missing flow control are given
      // up, down to a request each.
      expect(rig.progress.batch, lessThan(6));
      rig.close();
    });
  });

  group('an adapter that does not take several PIDs at once', () {
    test('the batch falls to one, and every PID is still read', () {
      final rig = SurveyRig(
        quirks: AdapterQuirks.measuredBle.copyWith(noMultiPid: true),
      )..start();
      rig.run(120);

      expect(rig.progress.batch, 1);
      expect(rig.notes.any((n) => n.contains('batch 6->3')), isTrue);
      expect(rig.notes.any((n) => n.contains('batch 3->1')), isTrue);
      final s = rig.summary;
      for (final pid in _pids(VehicleProfiles.surveyTwin.secondEcuPids)) {
        expect(
          s.readsOf(pid),
          isNotEmpty,
          reason: 'PID ${pid.toRadixString(16)}',
        );
      }
      rig.close();
    });
  });

  group('when the car is switched off', () {
    test('it waits, and starts again when the car answers', () {
      final rig = SurveyRig(
        scenario: surveyScenario(idleFirst: 60, ignitionOff: 40, idleAfter: 60),
      )..start();
      rig.run(200);

      expect(
        rig.sequence,
        containsAllInOrder([
          SurveyPhase.driving,
          SurveyPhase.waitingForCar,
          SurveyPhase.driving,
        ]),
      );
      expect(rig.notes.any((n) => n.startsWith('car silent')), isTrue);
      expect(rig.notes.any((n) => n.startsWith('car back after')), isTrue);
      // It reads the car again afterwards.
      final after = rig.summary
          .readsOf(0x0C, ecu: _b)
          .where((r) => r.at > const Duration(seconds: 130));
      expect(after, isNotEmpty);
      rig.close();
    });

    test('it does not rediscover or probe again', () {
      final rig = SurveyRig(
        scenario: surveyScenario(idleFirst: 60, ignitionOff: 40, idleAfter: 60),
      )..start();
      rig.run(200);

      expect(rig.sequence.where((p) => p == SurveyPhase.probing), hasLength(1));
      expect(
        rig.sequence.where((p) => p == SurveyPhase.discovering),
        hasLength(1),
      );
      rig.close();
    });

    test('a car that stays off ends the survey', () {
      final rig = SurveyRig(
        scenario: surveyScenario(
          idleFirst: 30,
          ignitionOff: 3000,
          idleAfter: 1,
        ),
        config: const SurveyConfig(giveUpAfter: Duration(minutes: 2)),
      )..start();
      rig.run(400);

      expect(rig.progress.phase, SurveyPhase.finished);
      expect(rig.notes.any((n) => n.contains('the car stayed off')), isTrue);
      rig.close();
    });
  });

  group('when the link drops', () {
    test('it opens the link again and carries on without starting over', () {
      final rig = SurveyRig(
        scenario: surveyScenario(
          idleFirst: 200,
          faults: const [
            AdapterDisconnect(
              at: Duration(seconds: 100),
              outage: Duration(seconds: 8),
            ),
          ],
        ),
      )..start();
      rig.run(180);

      expect(rig.progress.linkDrops, 1);
      expect(rig.progress.phase, SurveyPhase.driving);
      expect(rig.notes.any((n) => n.startsWith('link lost')), isTrue);
      expect(
        rig.notes.any((n) => n.startsWith('resumed after reconnect')),
        isTrue,
      );
      expect(rig.sequence.where((p) => p == SurveyPhase.probing), hasLength(1));
      final after = rig.summary
          .readsOf(0x0C, ecu: _b)
          .where((r) => r.at > const Duration(seconds: 125));
      expect(after.length, greaterThan(50));
      rig.close();
    });
  });

  group('a flaky adapter', () {
    test('does not stop it: answers are missed and it carries on', () {
      final rig = SurveyRig(quirks: AdapterQuirks.flaky)..start();
      rig.run(180);

      expect(rig.progress.phase, SurveyPhase.driving);
      expect(rig.progress.failed, greaterThan(0));
      expect(rig.summary.readsOf(0x0C), isNotEmpty);
      rig.close();
    });
  });

  group('the survey does not write to the log what it cannot know', () {
    test('no VIN is anywhere in the log', () {
      final rig = SurveyRig()..start();
      rig.run(90);

      expect(rig.log.format(), isNot(contains('TAPEDASHSIM000001')));
      rig.close();
    });
  });

  group('an adapter that does something unexpected', () {
    test('headers it prints in a format nobody expected: the survey goes on '
        'without them', () {
      final rig = SurveyRig(
        // Every frame line is printed as a numbered line instead.
        wrap: (sim) => RewritingTransport(
          sim,
          (text) => text.replaceAllMapped(
            RegExp(r'(18DAF1[0-9A-F]{2})([0-9A-F]{16})'),
            (m) => '0:${m.group(2)}',
          ),
        ),
      )..start();
      rig.run(120);

      expect(rig.progress.phase, SurveyPhase.driving);
      expect(
        rig.notes.any((n) => n.startsWith('headed replies unreadable')),
        isTrue,
      );
      // Without headers the ECUs cannot be told apart: one, called ALL.
      expect(rig.progress.ecus, ['ALL']);
      expect(rig.summary.readsOf(0x0C), isNotEmpty);
      rig.close();
    });

    test('an adapter that resets itself is started up again', () {
      var armed = false;
      var fired = false;
      final rig = SurveyRig(
        wrap: (sim) => RewritingTransport(sim, (text) {
          // One reply, once the survey is driving, is the adapter saying it
          // reset after a drop in its supply.
          if (armed && !fired && text.contains('>')) {
            fired = true;
            return 'LV RESET\r\r>';
          }
          return text;
        }),
      )..start();
      rig.run(60);
      armed = true;
      rig.run(60);

      expect(fired, isTrue);
      expect(rig.notes.any((n) => n.startsWith('adapter reset')), isTrue);
      expect(rig.progress.phase, SurveyPhase.driving);
      // Started up again, but did not start the survey over.
      expect(rig.sequence.where((p) => p == SurveyPhase.probing), hasLength(1));
      final after = rig.summary
          .readsOf(0x0C, ecu: _b)
          .where((r) => r.at > const Duration(seconds: 80));
      expect(after.length, greaterThan(50));
      rig.close();
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/profiles.dart';

import 'package:tapedash/sim/scenarios.dart';

import '../../../tool/record_sim.dart';
import '../../../tool/record_survey.dart';
import '../../../tool/survey_summary.dart';

SessionLog _survey({
  int minutes = 3,
  int seed = 1,
  SurveyRecordOptions? options,
}) => SessionLog.parse(
  recordSurvey(
    options ??
        SurveyRecordOptions(
          seed: seed,
          length: Duration(minutes: minutes),
        ),
  ),
);

void main() {
  group('record_survey', () {
    test('makes a survey log of the twin-ECU car', () {
      final log = _survey();

      expect(log.header['survey'], '1');
      expect(log.header['profile'], 'petrol_cvt_twin_ecu');
      expect(
        log.entries.where((e) => e.direction == SessionDirection.sent),
        isNotEmpty,
      );
      expect(
        log.entries.any(
          (e) =>
              e.direction == SessionDirection.note &&
              e.text.startsWith('survey ecu id=18DAF110'),
        ),
        isTrue,
      );
    });

    test('the same options make the same log, to the byte', () {
      expect(
        recordSurvey(const SurveyRecordOptions(length: Duration(minutes: 2))),
        recordSurvey(const SurveyRecordOptions(length: Duration(minutes: 2))),
      );
    });

    test('another seed changes the noise but not the survey', () {
      final a = recordSurvey(
        const SurveyRecordOptions(length: Duration(minutes: 2)),
      );
      final b = recordSurvey(
        const SurveyRecordOptions(seed: 2, length: Duration(minutes: 2)),
      );

      expect(a, isNot(b));
    });

    test('a one-ECU car on 11-bit CAN is surveyed too', () {
      final log = _survey(
        options: SurveyRecordOptions(
          profile: VehicleProfiles.petrolCvtMaf,
          length: const Duration(minutes: 2),
        ),
      );

      final text = summarize(log);
      expect(text, contains('7E8:'));
      expect(text, isNot(contains('18DAF1')));
    });

    test('it ends with its own note of how it went', () {
      final log = _survey();

      expect(
        log.entries
            .where((e) => e.direction == SessionDirection.note)
            .any(
              (e) =>
                  e.text.startsWith('survey done reason=end of the recording'),
            ),
        isTrue,
      );
    });
  });

  group('survey_summary', () {
    late SessionLog log;
    late String text;

    setUpAll(() {
      log = _survey();
      text = summarize(log, name: 'sample.log');
    });

    test('says what was recorded and with what', () {
      expect(text, contains('Survey log: sample.log'));
      expect(text, contains('profile: petrol_cvt_twin_ecu'));
      expect(text, contains('ATI: ELM327 v1.5'));
      expect(text, contains('ATRV:'));
    });

    test('lists both ECUs and their PIDs', () {
      expect(text, contains('18DAF110: 20 PIDs'));
      expect(text, contains('18DAF111: 26 PIDs'));
    });

    test('has a table for each ECU, with PID names and rates', () {
      expect(text, contains('PIDs read from 18DAF110'));
      expect(text, contains('PIDs read from 18DAF111'));
      expect(text, contains('Engine speed'));
      expect(text, contains('Timing advance'));
      expect(text, isNot(contains('PIDs read from ALL')));
    });

    test('decodes the PIDs it knows and shows raw bytes for the rest', () {
      // Engine speed is decoded; timing advance is a byte, with no formula
      // guessed.
      expect(
        RegExp(
          r'0C +Engine speed +\d+ +[\d.]+ +[\d.]+ \.\. [\d.]+ \(Engine speed\)',
        ).hasMatch(text),
        isTrue,
      );
      expect(
        RegExp(
          r'0E +Timing advance +\d+ +[\d.]+ +[0-9A-F]{2} \.\. [0-9A-F]{2}\n',
        ).hasMatch(text),
        isTrue,
      );
    });

    test(
      'shows the text answers as text: the calibration ID and the ECU name',
      () {
        expect(text, contains('"TAPEDASH-SIM-ECM"'));
        expect(text, contains('"TAPEDASH-SIM-PCM"'));
        expect(text, contains('"ECM-SIM"'));
      },
    );

    test('says what the survey did', () {
      expect(text, contains('What the survey did'));
      expect(text, contains('probe done'));
      expect(text, contains('drive batch=6 filter=working ecus=2'));
    });

    test('has no VIN in it', () {
      expect(text, isNot(contains('TAPEDASHSIM000001')));
    });

    test('csv has a line for each reading and a header', () {
      final csv = csvOf(log).trim().split('\n');

      expect(csv.first, 't_s,ecu,pid,hex,value');
      expect(csv.length, greaterThan(1000));
      // A decoded one.
      final rpm = csv.firstWhere((l) => l.contains(',18DAF111,0C,'));
      expect(double.tryParse(rpm.split(',').last), isNotNull);
      // One with no formula has no value.
      final timing = csv.firstWhere((l) => l.contains(',18DAF111,0E,'));
      expect(timing.endsWith(','), isTrue);
    });

    test('marks appear in the report, in order', () {
      final marked = SessionLog(
        header: log.header,
        entries: [
          ...log.entries,
          SessionEntry(
            log.entries.last.at + const Duration(seconds: 1),
            SessionDirection.note,
            'survey mark id=ac state=on',
          ),
          SessionEntry(
            log.entries.last.at + const Duration(seconds: 11),
            SessionDirection.note,
            'survey mark id=ac state=off',
          ),
        ],
      );

      final t = summarize(marked);

      expect(t, contains('Marks'));
      expect(t.indexOf('ac on'), lessThan(t.indexOf('ac off')));
    });

    test('a dashboard recording is read too, and said not to be a survey', () {
      final dash = SessionLog.parse(
        recordSession(
          RecordOptions(
            scenario: DriveScenarios.coldStartIdle,
            quirks: AdapterQuirks.none,
            limit: const Duration(minutes: 1),
          ),
        ),
      );

      final t = summarize(dash);

      expect(t, contains('not marked as a survey'));
      expect(t, contains('Engine speed'));
    });
  });
}

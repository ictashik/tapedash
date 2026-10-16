import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/survey_drive.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/obd/survey/survey_log_reader.dart';
import 'package:tapedash/obd/survey/survey_runner.dart';
import 'package:tapedash/obd/survey/survey_schedule.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/obd/transport/session_sink.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/obd/transport_factory.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/simulated_car.dart';

import '../../support/survey_rig.dart';

class _Factory implements TransportFactory {
  _Factory(this.make);

  final Transport Function() make;
  final List<Transport> made = [];

  @override
  Transport create(AdapterConfig config) {
    final t = make();
    made.add(t);
    return t;
  }
}

/// A sink that can be told to fail.
class _FlakySink extends MemorySessionSink {
  bool failing = false;
  int attempts = 0;

  @override
  Future<void> save(String name, String text) async {
    attempts++;
    if (failing) throw StateError('no space');
    return super.save(name, text);
  }
}

const _adapter = AdapterConfig(
  kind: AdapterKind.wifi,
  address: '192.168.0.10',
  name: 'Test adapter',
);

/// A drive that pulls away and keeps going.
DriveScenario _moving() => DriveScenario(
  name: 'survey_moving',
  description: 'idle, then away at 40 km/h',
  route: SimRoute.straight(20000),
  engineRunningAtStart: true,
  startCoolantC: 85,
  driverBuilder: () =>
      ScriptedDriver([IdleFor(30), GoToSpeed(40, holdSeconds: 2000)]),
);

void main() {
  late FakeClock clock;
  late SimulatedCar car;
  late _Factory factory;
  late _FlakySink sink;
  late SurveyDrive drive;

  void build({
    DriveScenario? scenario,
    Duration flush = const Duration(seconds: 20),
    SurveyConfig config = const SurveyConfig(),
  }) {
    clock = FakeClock()..advance(const Duration(hours: 1));
    car = SimulatedCar(
      scenario: scenario ?? surveyScenario(idleFirst: 2000),
      profile: VehicleProfiles.surveyTwin,
      scheduler: clock,
    )..start();
    factory = _Factory(
      () => SimTransport(
        car: car,
        scheduler: clock,
        quirks: AdapterQuirks.measuredBle,
      ),
    );
    sink = _FlakySink();
    drive = SurveyDrive(
      adapter: _adapter,
      transports: factory,
      clock: clock,
      scheduler: clock,
      sink: sink,
      config: config,
      flushEvery: flush,
      appVersion: '9.9.9',
    );
  }

  void run(int seconds) => clock.advance(Duration(seconds: seconds));

  tearDown(() async {
    await drive.dispose();
    car.stop();
  });

  group('before and at the start', () {
    test('it waits to be started: nothing is made, nothing sent', () {
      build();
      run(30);

      expect(drive.stage.value, SurveyStage.ready);
      expect(factory.made, isEmpty);
      expect(sink.files, isEmpty);
    });

    test('starting makes the adapter\'s transport and begins', () {
      build();

      drive.start();

      expect(drive.stage.value, SurveyStage.running);
      expect(factory.made, hasLength(1));
      run(40);
      expect(drive.progress.value.phase, SurveyPhase.driving);
      expect(drive.progress.value.ecus, hasLength(2));
    });

    test('starting twice does nothing the second time', () {
      build();
      drive.start();
      drive.start();

      expect(factory.made, hasLength(1));
    });

    test('the file is named for the time and the kind of adapter', () {
      build();
      drive.start();

      expect(
        drive.fileName,
        matches(RegExp(r'^survey-\d{8}-\d{6}-wifi\.log$')),
      );
    });
  });

  group('the file', () {
    test('is written while it runs, and is a session log with a header', () {
      build();
      drive.start();
      run(45);

      expect(sink.files.keys.single, drive.fileName);
      final log = SessionLog.parse(sink.files.values.single);
      expect(log.header['survey'], '1');
      expect(log.header['app'], 'tapedash 9.9.9');
      expect(log.header['adapter'], 'Test adapter');
      expect(log.header['kind'], 'wifi');
      expect(
        log.entries.where((e) => e.direction == SessionDirection.note),
        isNotEmpty,
      );
    });

    test(
      'is rewritten as it grows, so a dead phone leaves the last good copy',
      () {
        build();
        drive.start();
        run(25);
        final early = sink.files.values.single.length;
        run(40);

        expect(sink.files.values.single.length, greaterThan(early));
      },
    );

    test('reads back as a survey of both ECUs', () {
      build();
      drive.start();
      run(60);
      final summary = SurveyLogReader.read(
        SessionLog.parse(sink.files.values.single),
      );

      expect(summary.supported.keys, hasLength(2));
      expect(summary.readsOf(0x0C), isNotEmpty);
    });

    test(
      'a phone that will not take it is told on the screen, and tried again',
      () async {
        build();
        sink.failing = true;
        drive.start();
        run(25);
        await pumpEventQueue();

        expect(drive.saveFailed.value, isTrue);
        expect(drive.stage.value, SurveyStage.running, reason: 'it goes on');

        sink.failing = false;
        run(25);
        await pumpEventQueue();
        expect(drive.saveFailed.value, isFalse);
        expect(sink.files, isNotEmpty);
      },
    );
  });

  group('marks', () {
    test('a mark goes into the log with its time', () {
      build();
      drive.start();
      run(60);

      drive.mark('headlights', true);
      run(5);
      drive.mark('headlights', false);
      run(25);

      final notes = SurveyLogReader.read(
        SessionLog.parse(sink.files.values.single),
      ).notes.map((n) => n.$2).toList();
      expect(notes, contains('mark id=headlights state=on'));
      expect(notes, contains('mark id=headlights state=off'));
      expect(
        notes.indexOf('mark id=headlights state=on'),
        lessThan(notes.indexOf('mark id=headlights state=off')),
      );
    });

    test('before the survey has begun, a mark is ignored', () {
      build();

      drive.mark('ac', true);

      expect(factory.made, isEmpty);
    });
  });

  group('ending it', () {
    test(
      'finish saves the log, stops reading and lets go of the adapter',
      () async {
        build();
        drive.start();
        run(60);

        final done = drive.finish();
        run(1);
        await done;

        expect(drive.stage.value, SurveyStage.finished);
        expect(factory.made.single.currentState.isConnected, isFalse);
        final text = sink.files.values.single;
        expect(text, contains('survey done reason=stopped by the user'));
        // Nothing more is sent.
        final lines = text.split('\n').where((l) => l.contains(' > ')).length;
        run(30);
        await pumpEventQueue();
        expect(
          sink.files.values.single
              .split('\n')
              .where((l) => l.contains(' > '))
              .length,
          lines,
        );
      },
    );

    test('closing it while it runs saves what it has', () async {
      build();
      drive.start();
      run(45);
      sink.files.clear();

      await drive.dispose();

      expect(sink.files, isNotEmpty);
    });

    test('the survey ending itself (the car stayed off) finishes it', () async {
      build(
        scenario: surveyScenario(
          idleFirst: 30,
          ignitionOff: 5000,
          idleAfter: 1,
        ),
        config: const SurveyConfig(giveUpAfter: Duration(minutes: 2)),
      );
      drive.start();
      run(500);
      await pumpEventQueue();

      expect(drive.stage.value, SurveyStage.finished);
      expect(sink.files.values.single, contains('the car stayed off'));
    });
  });

  group('only when the car has stopped', () {
    test('the finish button is held back while the car moves', () {
      build(scenario: _moving());
      drive.start();
      run(150);

      expect(drive.progress.value.speedKmh, greaterThan(0));
      expect(drive.canFinish.value, isFalse);
    });

    test('and comes back once the car has stood still for a few seconds', () {
      build();
      drive.start();
      run(60);

      expect(drive.progress.value.speedKmh, 0);
      expect(drive.canFinish.value, isTrue);
    });

    test('it is allowed while the car is off, or before it has begun', () {
      build();
      expect(drive.canFinish.value, isTrue);
    });
  });
}

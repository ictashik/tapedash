// The survey drive's screen (docs/SURVEY.md) on a simulated twin-ECU car: what it
// says before, during and after, that nothing is pressable while the car moves,
// and that it fits the three screen shapes.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/survey_drive.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/obd/survey/survey_log_reader.dart';
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
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/pages/survey/survey_page.dart';

import '../design/support/harness.dart';
import '../support/survey_rig.dart';

class _Factory implements TransportFactory {
  _Factory(this.make);

  final Transport Function() make;
  int made = 0;

  @override
  Transport create(AdapterConfig config) {
    made++;
    return make();
  }
}

const _adapter = AdapterConfig(
  kind: AdapterKind.ble,
  address: '81:23:45:67:89:BA',
  name: 'OBDBLE',
);

DriveScenario _moving() => DriveScenario(
  name: 'survey_moving',
  description: 'away at 40 km/h',
  route: SimRoute.straight(20000),
  engineRunningAtStart: true,
  startCoolantC: 85,
  driverBuilder: () =>
      ScriptedDriver([IdleFor(5), GoToSpeed(40, holdSeconds: 3000)]),
);

void main() {
  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late SimulatedCar car;
  late _Factory factory;
  late MemorySessionSink sink;
  late SurveyDrive drive;
  var closed = 0;

  setUpAll(() async {
    await loadTapeFonts();
  });

  void build(DriveScenario scenario) {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(hours: 1));
    car = SimulatedCar(
      scenario: scenario,
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
    sink = MemorySessionSink();
    drive = SurveyDrive(
      adapter: _adapter,
      transports: factory,
      clock: clock,
      scheduler: clock,
      sink: sink,
    );
    closed = 0;
  }

  tearDown(() async {
    await drive.dispose();
    car.stop();
    kit.dispose();
    motion.dispose();
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(720, 360),
  }) async {
    setWindow(tester, size);
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: SurveyPage(
          drive: drive,
          width: size.width,
          height: size.height,
          onClose: () => closed++,
        ),
      ),
    );
    await tester.pump();
  }

  /// Runs the fake clock, a second at a time, with the screen following.
  Future<void> run(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder button(String label) => find.widgetWithText(TapeButton, label);

  for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
    testWidgets('fits ${size.width.toInt()}x360 before, during and after', (
      tester,
    ) async {
      build(surveyScenario(idleFirst: 3000));
      await show(tester, size: size);
      expect(tester.takeException(), isNull);

      drive.start();
      await run(tester, 60);
      expect(tester.takeException(), isNull);
      expect(button('FINISH SURVEY'), findsOneWidget);

      await tester.tap(button('FINISH SURVEY'));
      await run(tester, 3);
      expect(find.text('Survey saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('before: it says what it does and does not do', (tester) async {
    build(surveyScenario());
    await show(tester);

    expect(find.text('Find out what your car can report'), findsOneWidget);
    expect(find.textContaining('It only reads'), findsOneWidget);
    expect(find.textContaining('does not clear codes'), findsOneWidget);
    expect(button('START SURVEY'), findsOneWidget);
    expect(button('NOT NOW'), findsOneWidget);
    // Nothing has touched the adapter.
    expect(factory.made, 0);
  });

  testWidgets('NOT NOW leaves without starting anything', (tester) async {
    build(surveyScenario());
    await show(tester);

    await tester.tap(button('NOT NOW'));
    await tester.pump();

    expect(closed, 1);
    expect(factory.made, 0);
    expect(drive.stage.value, SurveyStage.ready);
  });

  testWidgets('START SURVEY begins, and the screen follows the phases', (
    tester,
  ) async {
    build(surveyScenario(idleFirst: 3000));
    await show(tester);

    await tester.tap(button('START SURVEY'));
    await tester.pump();
    expect(drive.stage.value, SurveyStage.running);
    expect(find.textContaining('Connecting'), findsOneWidget);

    await run(tester, 60);
    expect(find.textContaining('Drive as you usually do'), findsOneWidget);
    expect(find.text('2 answering'), findsOneWidget);
    expect(find.textContaining('a second'), findsOneWidget);
  });

  testWidgets('the clock counts the time since the start', (tester) async {
    build(surveyScenario(idleFirst: 3000));
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 75);

    expect(find.text('01:15'), findsOneWidget);
  });

  testWidgets('while the car moves there is nothing to press', (tester) async {
    build(_moving());
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 150);

    expect(drive.progress.value.speedKmh, greaterThan(0));
    expect(find.textContaining('Nothing to do while driving'), findsOneWidget);
    expect(button('FINISH SURVEY'), findsNothing);
    expect(button('HEADLIGHTS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parked, the marks and the finish button appear', (tester) async {
    build(surveyScenario(idleFirst: 3000));
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 60);

    expect(find.textContaining('Nothing to do while driving'), findsNothing);
    expect(button('FINISH SURVEY'), findsOneWidget);
    for (final (_, label) in surveyMarks) {
      expect(button(label.toUpperCase()), findsOneWidget, reason: label);
    }
  });

  testWidgets('a mark is noted in the log with its time, on and then off', (
    tester,
  ) async {
    build(surveyScenario(idleFirst: 3000));
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 60);

    await tester.tap(button('HEADLIGHTS'));
    await run(tester, 5);
    await tester.tap(button('HEADLIGHTS'));
    await run(tester, 25);

    final notes = SurveyLogReader.read(
      SessionLog.parse(sink.files.values.single),
    ).notes.map((n) => n.$2).toList();
    expect(
      notes,
      containsAllInOrder([
        'mark id=headlights state=on',
        'mark id=headlights state=off',
      ]),
    );
  });

  testWidgets('FINISH SURVEY saves, says where, and the dashboard comes back', (
    tester,
  ) async {
    build(surveyScenario(idleFirst: 3000));
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 60);

    await tester.tap(button('FINISH SURVEY'));
    await run(tester, 3);

    expect(drive.stage.value, SurveyStage.finished);
    expect(find.text('Survey saved'), findsOneWidget);
    expect(find.text(drive.fileName!), findsOneWidget);
    expect(find.textContaining('Android/data/'), findsOneWidget);
    expect(sink.files.keys.single, drive.fileName);

    await tester.tap(button('DASHBOARD'));
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('a phone that will not take the file is told', (tester) async {
    build(surveyScenario(idleFirst: 3000));
    sink = _FailingSink();
    drive = SurveyDrive(
      adapter: _adapter,
      transports: factory,
      clock: clock,
      scheduler: clock,
      sink: sink,
    );
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 60);

    await tester.tap(button('FINISH SURVEY'));
    await run(tester, 3);

    expect(find.text('Could not save the survey'), findsOneWidget);
    expect(find.textContaining('Free some space'), findsOneWidget);
  });
}

class _FailingSink extends MemorySessionSink {
  @override
  Future<void> save(String name, String text) async {
    throw StateError('full');
  }
}

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
    testWidgets('fits ${size.width.toInt()}x360 in every state', (
      tester,
    ) async {
      build(surveyScenario(idleFirst: 3000));
      await show(tester, size: size);
      expect(tester.takeException(), isNull);

      drive.start();
      await run(tester, 3);
      expect(find.text('Getting ready'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await run(tester, 40);
      expect(button('BEGIN CHECKS'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(button('BEGIN CHECKS'));
      await run(tester, 2);
      expect(find.text('Everything off'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A step with the longest instruction.
      await run(tester, 15 + 15 + 10 + 12 + 12 + 10 + 25 + 12 + 15 + 10 + 15);
      await run(tester, 10 + 20 + 10 + 2);
      expect(find.text('Gentle revs (optional)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(button('STOP CHECKS'));
      await run(tester, 2);
      expect(button('FINISH SURVEY'), findsOneWidget);
      expect(tester.takeException(), isNull);

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
    expect(find.textContaining('It leads you'), findsOneWidget);
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

  testWidgets('START SURVEY gets ready, then offers the checks', (
    tester,
  ) async {
    build(surveyScenario(idleFirst: 3000));
    await show(tester);

    await tester.tap(button('START SURVEY'));
    await tester.pump();
    expect(drive.stage.value, SurveyStage.running);
    expect(find.text('Getting ready'), findsOneWidget);
    expect(find.textContaining('Connecting'), findsOneWidget);

    await run(tester, 45);
    expect(find.text('Parked checks'), findsOneWidget);
    expect(button('BEGIN CHECKS'), findsOneWidget);
    expect(button('SKIP CHECKS'), findsOneWidget);
  });

  testWidgets('the checks lead, one step at a time, with a countdown', (
    tester,
  ) async {
    build(surveyScenario(idleFirst: 3000));
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 45);

    await tester.tap(button('BEGIN CHECKS'));
    await run(tester, 2);
    expect(find.text('Everything off'), findsOneWidget);
    expect(find.text('STEP 1 OF 16'), findsOneWidget);
    expect(find.text('13'), findsOneWidget, reason: '15 s, two gone');

    await run(tester, 14);
    expect(find.text('Headlights on'), findsOneWidget);
    expect(find.text('STEP 2 OF 16'), findsOneWidget);
    expect(find.textContaining('Switch the headlights on'), findsOneWidget);

    await tester.tap(button('NEXT STEP'));
    await run(tester, 1);
    expect(find.text('Headlights off'), findsOneWidget);
  });

  testWidgets('each switch it asks for is written in the log by itself', (
    tester,
  ) async {
    build(surveyScenario(idleFirst: 3000));
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 45);
    await tester.tap(button('BEGIN CHECKS'));
    await run(tester, 15 + 15 + 12);

    await tester.tap(button('STOP CHECKS'));
    await run(tester, 1);
    await tester.tap(button('FINISH SURVEY'));
    await run(tester, 3);

    final marks = SurveyLogReader.read(
      SessionLog.parse(sink.files.values.single),
    ).marks;
    expect(marks.map((m) => '${m.id}:${m.on}').take(2), [
      'headlights:true',
      'headlights:false',
    ]);
    expect(marks.every((m) => m.pass == 1), isTrue);
  });

  testWidgets(
    'SKIP CHECKS goes to the drive; the checks come back at the end',
    (tester) async {
      build(surveyScenario(idleFirst: 3000));
      await show(tester);
      await tester.tap(button('START SURVEY'));
      await run(tester, 45);

      await tester.tap(button('SKIP CHECKS'));
      await run(tester, 2);

      // Skipped, so they are offered again now as well as at the end.
      expect(
        find.textContaining('Pull away when you are ready'),
        findsOneWidget,
      );
      expect(button('DO THE CHECKS NOW'), findsOneWidget);
      expect(button('FINISH SURVEY'), findsOneWidget);
    },
  );

  testWidgets('after the first checks it says what the drive should be', (
    tester,
  ) async {
    build(surveyScenario(idleFirst: 3000));
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 45);
    await tester.tap(button('BEGIN CHECKS'));
    await run(tester, 2);
    await tester.tap(button('STOP CHECKS'));
    await run(tester, 2);

    expect(find.textContaining('Pull away when you are ready'), findsOneWidget);
    expect(find.textContaining('twenty minutes or more'), findsOneWidget);
    // Stopped part way: they can be done now.
    expect(button('DO THE CHECKS NOW'), findsOneWidget);
  });

  testWidgets('checks gone through are not offered again until it has driven', (
    tester,
  ) async {
    build(surveyScenario(idleFirst: 5000));
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 45);
    await tester.tap(button('BEGIN CHECKS'));
    await run(tester, 240);

    expect(drive.guide.state.value.passesDone, 1);
    expect(button('REPEAT THE CHECKS'), findsNothing);
    expect(button('DO THE CHECKS NOW'), findsNothing);
    expect(button('FINISH SURVEY'), findsOneWidget);

    await run(tester, 800);
    expect(button('REPEAT THE CHECKS'), findsOneWidget);
    expect(find.textContaining('with the engine warm'), findsOneWidget);
  });

  testWidgets('the clock counts the time since the start', (tester) async {
    build(surveyScenario(idleFirst: 3000));
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 45);
    await tester.tap(button('SKIP CHECKS'));
    await run(tester, 30);

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
    expect(button('BEGIN CHECKS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the checks stop at once if the car moves', (tester) async {
    build(
      DriveScenario(
        name: 'survey_late_move',
        description: 'idle, then away',
        route: SimRoute.straight(20000),
        engineRunningAtStart: true,
        startCoolantC: 85,
        driverBuilder: () =>
            ScriptedDriver([IdleFor(75), GoToSpeed(40, holdSeconds: 3000)]),
      ),
    );
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 45);
    await tester.tap(button('BEGIN CHECKS'));
    await run(tester, 60);

    expect(drive.guide.state.value.active, isFalse);
    expect(
      find.text(
        'Nothing to do while driving. When you stop, the next step '
        'appears here.',
      ),
      findsOneWidget,
    );
    expect(button('NEXT STEP'), findsNothing);
  });

  testWidgets('FINISH SURVEY saves, says where, and the dashboard comes back', (
    tester,
  ) async {
    build(surveyScenario(idleFirst: 3000));
    await show(tester);
    await tester.tap(button('START SURVEY'));
    await run(tester, 45);
    await tester.tap(button('SKIP CHECKS'));
    await run(tester, 3);

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
    await run(tester, 45);
    await tester.tap(button('SKIP CHECKS'));
    await run(tester, 3);

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

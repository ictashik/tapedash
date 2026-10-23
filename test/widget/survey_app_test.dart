// The survey drive inside the whole app (docs/SURVEY.md): Garage offers it for a
// real adapter, the dashboard lets go of the adapter for it, and takes it back
// when it ends. A simulated twin-ECU car behind the transport factory.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/radio_transport_factory.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/obd/transport/session_sink.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';
import 'package:tapedash/ui/pages/garage/garage_page.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';
import 'package:tapedash/ui/pages/survey/survey_page.dart';

class _TwinFactory extends RadioTransportFactory {
  _TwinFactory(this.car, this.clock);

  final SimulatedCar car;
  final FakeClock clock;
  final List<SimTransport> made = [];

  @override
  Transport create(AdapterConfig config) {
    final t = SimTransport(
      car: car,
      scheduler: clock,
      quirks: AdapterQuirks.measuredBle,
    );
    made.add(t);
    return t;
  }
}

const _adapter = AdapterConfig(
  kind: AdapterKind.ble,
  address: '81:23:45:67:89:BA',
  name: 'OBDBLE',
);

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => TapeFonts.load());

  late AppServices app;
  late FakeClock clock;
  late SimulatedCar car;
  late _TwinFactory factory;
  late MemorySessionSink sink;

  setUp(() async {
    app = await AppServices.memory();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    car = SimulatedCar(
      scenario: DriveScenarios.coldStartIdle,
      profile: VehicleProfiles.surveyTwin,
      scheduler: clock,
    )..start();
    factory = _TwinFactory(car, clock);
    sink = MemorySessionSink();
    await app.adapters.choose(_adapter);
    app.settings.onboarded.value = true;
  });

  tearDown(() => car.stop());

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TapeDashApp(
        clock: clock,
        scheduler: clock,
        services: app,
        transports: factory,
        sessionSink: sink,
        skipColdOpen: true,
      ),
    );
  }

  Future<void> run(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 100) {
      clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openSurveyFromGarage(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TapeButton, 'GARAGE'));
    await run(tester, 400);
    expect(find.byType(GaragePage), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Survey drive'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Survey drive'));
    await tester.pump();
    await tester.tap(find.text('Survey drive'));
  }

  testWidgets('the dashboard works against a car with two ECUs', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 30000);

    expect(find.byType(TheStrip), findsOneWidget);
    final drive = tester.widget<DrivePage>(find.byType(DrivePage));
    expect(drive.signals.vehicle.rpm.value, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Garage offers the survey, and it replaces the dashboard', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 30000);
    expect(factory.made, hasLength(1));

    await openSurveyFromGarage(tester);
    await run(tester, 1500);

    expect(find.byType(SurveyPage), findsOneWidget);
    expect(find.byType(TheStrip), findsNothing);
    expect(find.text('Find out what your car can report'), findsOneWidget);
    // The dashboard let go of the adapter before the survey could have it.
    expect(factory.made.first.currentState.isConnected, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NOT NOW gives the adapter back to the dashboard', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 30000);
    await openSurveyFromGarage(tester);
    await run(tester, 1500);

    await tester.tap(find.widgetWithText(TapeButton, 'NOT NOW'));
    await run(tester, 30000);

    expect(find.byType(SurveyPage), findsNothing);
    expect(find.byType(TheStrip), findsOneWidget);
    // The survey never made a transport; the dashboard made a second.
    expect(factory.made, hasLength(2));
    final drive = tester.widget<DrivePage>(find.byType(DrivePage));
    expect(drive.signals.vehicle.rpm.value, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a whole survey, and the dashboard comes back after it', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 30000);
    await openSurveyFromGarage(tester);
    await run(tester, 1500);

    await tester.tap(find.widgetWithText(TapeButton, 'START SURVEY'));
    await run(tester, 60000);

    // Parked and read: the checks are offered, and they lead.
    expect(find.text('Parked checks'), findsOneWidget);
    await tester.tap(find.widgetWithText(TapeButton, 'BEGIN CHECKS'));
    await run(tester, 2000);
    expect(find.text('Everything off'), findsOneWidget);
    await run(tester, 18000);
    expect(find.text('Headlights on'), findsOneWidget);
    await run(tester, 8000);
    await tester.tap(find.widgetWithText(TapeButton, 'STOP CHECKS'));
    await run(tester, 2000);
    expect(find.text('2 answering'), findsOneWidget);
    await tester.tap(find.widgetWithText(TapeButton, 'FINISH SURVEY'));
    await run(tester, 3000);
    expect(find.text('Survey saved'), findsOneWidget);

    // The file is on the phone, and is a survey of both ECUs.
    final name = sink.files.keys.singleWhere((n) => n.startsWith('survey-'));
    expect(name, endsWith('-ble.log'));
    final log = SessionLog.parse(sink.files[name]!);
    expect(log.header['survey'], '1');
    expect(log.header['adapter'], 'OBDBLE');
    final text = sink.files[name]!;
    expect(text, contains('survey ecu id=18DAF110'));
    expect(text, contains('survey ecu id=18DAF111'));
    expect(text, contains('survey mark id=headlights state=on pass=1'));
    expect(text, contains('survey mark id=headlights state=off pass=1'));

    await tester.tap(find.widgetWithText(TapeButton, 'DASHBOARD'));
    await run(tester, 30000);

    expect(find.byType(SurveyPage), findsNothing);
    expect(find.byType(TheStrip), findsOneWidget);
    // The survey's link was closed before the dashboard opened its own.
    expect(factory.made, hasLength(3));
    expect(factory.made[1].currentState.isConnected, isFalse);
    expect(factory.made[2].currentState.isConnected, isTrue);
    final drive = tester.widget<DrivePage>(find.byType(DrivePage));
    expect(drive.signals.vehicle.rpm.value, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on the GPS alone there is no adapter to survey: no row in '
      'Garage', (tester) async {
    await app.adapters.setSource(DriveSource.gps);
    await boot(tester);
    await run(tester, 5000);

    await tester.tap(find.widgetWithText(TapeButton, 'GARAGE'));
    await run(tester, 400);

    expect(find.byType(GaragePage), findsOneWidget);
    expect(find.text('Survey drive'), findsNothing);
  });
}

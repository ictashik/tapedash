// The whole app on a chosen adapter (CLAUDE.md 7, 11): a launch that goes straight
// to the user's own adapter, a car on a simulated adapter behind the transport
// factory, Garage's source group, and the switch to the GPS alone and back.
// Nothing is ever substituted for the source the person chose. Everything but the
// hardware.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/gps_shell.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/transport/session_sink.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/onboarding/connect_flow.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';
import 'package:tapedash/ui/pages/garage/garage_page.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';

import '../support/sim_shell.dart';

const _adapter = AdapterConfig(
  kind: AdapterKind.bluetoothClassic,
  address: '00:1D:A5:00:00:01',
  name: 'OBDII',
);

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => TapeFonts.load());

  late AppServices app;
  late FakeClock clock;
  late SimulatedCar car;
  late SimRadioFactory factory;
  late MemorySessionSink sink;

  setUp(() async {
    app = await AppServices.memory();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    car = SimulatedCar(scenario: DriveScenarios.coldStartIdle, scheduler: clock)
      ..start();
    factory = SimRadioFactory(car, clock);
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

  testWidgets('a launch with an adapter chosen goes straight to it', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 30000);

    expect(find.byType(TheStrip), findsOneWidget);
    expect(factory.made, [_adapter], reason: 'no other adapter was tried');
    final drive = tester.widget<DrivePage>(find.byType(DrivePage));
    expect(drive.signals.vehicle.rpm.value, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stopped with the engine running: END TRIP is in the dock, and ends the trip',
    (tester) async {
      await boot(tester);
      // Idle from cold: the engine is on and the car is standing, so it is
      // parked, the dock is up, and a trip is being recorded.
      await run(tester, 45000);
      final end = find.widgetWithText(TapeButton, 'END TRIP');
      expect(end, findsOneWidget);
      expect((await app.trips.all()).where((t) => !t.isOpen), isEmpty);

      await tester.tap(end);
      await run(tester, 1500);

      final trips = await app.trips.all();
      expect(trips.length, 1);
      expect(trips.single.isOpen, isFalse, reason: 'the trip is over');
      // The engine is still running and the car still standing: no new trip, and
      // the button is gone, since there is nothing to end.
      await run(tester, 20000);
      expect((await app.trips.all()).length, 1);
      expect(find.widgetWithText(TapeButton, 'END TRIP'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Garage shows the adapter, and can switch to GPS only and back', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 30000);
    await tester.tap(find.widgetWithText(TapeButton, 'GARAGE'));
    await run(tester, 400);
    expect(find.byType(GaragePage), findsOneWidget);
    // The list builds what is on screen; the adapter is at the top.
    expect(find.text('OBDII  ·  Bluetooth'), findsOneWidget);

    await tester.tap(find.text('GPS ONLY').first);
    await run(tester, 1500);
    expect(app.adapters.source.value, DriveSource.gps);
    expect(app.adapters.adapter.value, _adapter, reason: 'still remembered');
    expect(find.byType(GpsShell), findsOneWidget);
    expect(find.byType(DrivePage), findsNothing);
    expect(tester.takeException(), isNull);

    // And back to the car: the adapter is opened again, no other source in
    // between.
    await run(tester, 8000); // parked, so Garage can open
    await tester.tap(find.widgetWithText(TapeButton, 'GARAGE'));
    await run(tester, 600);
    await tester.tap(find.text('CAR ADAPTER').first);
    await run(tester, 30000);
    expect(app.adapters.source.value, DriveSource.obd);
    expect(find.byType(GpsShell), findsNothing);
    expect(find.byType(DrivePage), findsOneWidget);
    expect(factory.made.length, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an adapter that never answers is not replaced by anything', (
    tester,
  ) async {
    // The adapter is chosen and out of reach: the radio finds nothing to talk to.
    // The screen stays an adapter drive, searching, and never becomes a
    // different source.
    factory.unreachable = true;
    await boot(tester);
    await run(tester, 60000);
    expect(app.adapters.source.value, DriveSource.obd);
    expect(find.byType(DrivePage), findsOneWidget);
    expect(find.byType(GpsShell), findsNothing);
    final drive = tester.widget<DrivePage>(find.byType(DrivePage));
    expect(drive.signals.connection.value, isNot(ConnectionStatus.connected));
    expect(tester.takeException(), isNull);
  });

  testWidgets('recording is written while driving from the adapter', (
    tester,
  ) async {
    await app.adapters.setRecordSessions(true);
    await boot(tester);
    await run(tester, 45000);
    expect(sink.files, isNotEmpty);
    expect(sink.files.keys.single, contains('bluetoothClassic'));
    expect(sink.files.values.single, contains('# adapter: OBDII'));
  });

  testWidgets('a launch with no adapter and no choice yet asks the question', (
    tester,
  ) async {
    await app.adapters.forget();
    app.settings.onboarded.value = false;
    await boot(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('CONNECT MY CAR'), findsOneWidget);
    expect(find.byType(TheStrip), findsNothing);
  });

  testWidgets('CONNECT MY CAR opens the connect flow, and Cancel comes back', (
    tester,
  ) async {
    await app.adapters.forget();
    app.settings.onboarded.value = false;
    await boot(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('CONNECT MY CAR'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ConnectFlow), findsOneWidget);
    expect(find.text('How does your adapter connect?'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CONNECT MY CAR'), findsOneWidget);
  });

  testWidgets('a connection state is shown while the adapter is found', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 200);
    // Not connected yet: the drive is there, in its searching state, not blank.
    final drive = tester.widget<DrivePage>(find.byType(DrivePage));
    expect(drive.signals.connection.value, isNot(ConnectionStatus.connected));
    await run(tester, 30000);
    expect(drive.signals.connection.value, ConnectionStatus.connected);
  });
}

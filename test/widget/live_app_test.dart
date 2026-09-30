// The whole app on a chosen adapter (CLAUDE.md 7, 11): a launch that goes straight
// to the user's own adapter, a car on a simulated adapter behind the transport
// factory, Garage's adapter group, and the switch back to the demo. Everything
// but the hardware.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/radio_transport_factory.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/transport/session_sink.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/onboarding/connect_flow.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';
import 'package:tapedash/ui/pages/garage/garage_page.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';

class SimRadioFactory extends RadioTransportFactory {
  SimRadioFactory(this.car, this.clock);

  final SimulatedCar car;
  final FakeClock clock;
  final List<AdapterConfig> made = [];

  @override
  Transport create(AdapterConfig config) {
    made.add(config);
    return SimTransport(car: car, scheduler: clock);
  }
}

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
    expect(factory.made, [_adapter], reason: 'no demo, no other adapter');
    final drive = tester.widget<DrivePage>(find.byType(DrivePage));
    expect(drive.signals.demoMode, isFalse);
    expect(drive.signals.vehicle.rpm.value, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the demo does not run behind a real drive', (tester) async {
    await boot(tester);
    await run(tester, 30000);
    // Only the adapter's transport was ever made; the demo builds its own
    // simulated car, which would show as extra work on the clock. Nothing to
    // count directly, so check the drive is the adapter's.
    final drive = tester.widget<DrivePage>(find.byType(DrivePage));
    expect(drive.signals.demoMode, isFalse);
  });

  testWidgets('Garage shows the adapter, and can switch to the demo and back', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 30000);
    await tester.tap(find.widgetWithText(TapeButton, 'GARAGE'));
    await run(tester, 400);
    expect(find.byType(GaragePage), findsOneWidget);
    expect(find.text('OBDII  ·  Bluetooth'), findsOneWidget);

    await tester.ensureVisible(find.text('Drive from this adapter'));
    await tester.pump();
    await tester.tap(find.text('Drive from this adapter'));
    await run(tester, 1500);
    expect(app.adapters.useAdapter.value, isFalse);
    expect(app.adapters.adapter.value, _adapter, reason: 'still remembered');
    final demo = tester.widget<DrivePage>(find.byType(DrivePage));
    expect(demo.signals.demoMode, isTrue);
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

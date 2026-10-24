// Moving the app's data on screen (docs/EXCHANGE.md 5, 6): Garage's Data rows on a
// phone, the Data wheel on a watch, and what adb asks at the launch, all on the
// whole app over a simulated car.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/exchange_profile.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/exchange/exchange_service.dart';
import 'package:tapedash/exchange/tdx_format.dart';
import 'package:tapedash/platform/exchange_host.dart';
import 'package:tapedash/platform/fake_device_features.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/components/watch/watch_wheel.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/pages/watch/watch_reel.dart';
import 'package:tapedash/ui/pages/watch/watch_sheets.dart';

import '../support/sim_shell.dart';
import '../unit/exchange/tdx_format_test.dart' show fill, samples, trip;

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => TapeFonts.load());

  late FakeClock clock;
  late SimRig rig;
  late Directory temp;
  late FakeExchangeHost host;

  Directory inbox() => Directory('${temp.path}/exchange/inbox');
  Directory outbox() => Directory('${temp.path}/exchange/outbox');

  setUp(() async {
    clock = FakeClock()..advance(const Duration(days: 20000));
    rig = await SimRig.create(clock, scenario: DriveScenarios.coldStartIdle);
    temp = Directory.systemTemp.createTempSync('tapedash_exchange_ui_');
    host = FakeExchangeHost();
    addTearDown(() {
      rig.car.stop();
      temp.deleteSync(recursive: true);
    });
  });

  Future<void> boot(
    WidgetTester tester,
    Size logical, {
    FakeDeviceFeatures? device,
  }) async {
    tester.view.physicalSize = logical * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      rig.widget(
        exchangeHost: host,
        exchangeRoot: Directory('${temp.path}/exchange'),
        device: device,
      ),
    );
  }

  /// Lets real file work finish. A widget test's own clock does not move it, and
  /// each step of it hands back to the test's clock: so wait and pump, again.
  Future<void> io(WidgetTester tester, [int steps = 40]) async {
    for (var i = 0; i < steps; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 8)),
      );
      await tester.pump();
    }
  }

  Future<void> run(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 100) {
      clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await io(tester);
  }

  /// The trips that are over: the car on the rig is itself recording one.
  Future<int> finished() async =>
      (await rig.app.trips.all()).where((t) => !t.isOpen).length;

  /// A file another device made: one trip, a fill-up and a price.
  Future<File> otherDevicesFile(String name) async {
    final other = await SimRig.create(
      FakeClock()..advance(const Duration(days: 20000)),
    );
    await other.app.money.setPrice(111.0);
    await other.app.trips.createWithSamples(trip(day: 3), samples(8));
    await other.app.fills.add(fill);
    final dir = Directory.systemTemp.createTempSync('tapedash_other_');
    addTearDown(() {
      other.car.stop();
      dir.deleteSync(recursive: true);
    });
    final coordinatorFile = File('${dir.path}/$name');
    // Write it with the exchange service, as that device would.
    final bytes = <int>[];
    final service = ExchangeService(
      trips: other.app.trips,
      fills: other.app.fills,
      rest: other.app.restVoltage,
      profile: ExchangeProfile(other.app),
      device: const TdxDeviceInfo(id: 'other', kind: 'watch'),
      appVersion: '0.9.0',
    );
    await service.export(
      scopes: TdxScope.portable,
      emit: bytes.addAll,
      now: DateTime.utc(2026, 10, 24),
    );
    coordinatorFile.writeAsBytesSync(bytes);
    return coordinatorFile;
  }

  group('on a phone', () {
    Future<void> openData(WidgetTester tester) async {
      await boot(tester, const Size(720, 360));
      await run(tester, 45000); // idling: parked, with the dock up
      await tester.tap(find.widgetWithText(TapeButton, 'GARAGE'));
      await run(tester, 1500);
      await tester.dragUntilVisible(
        find.widgetWithText(TapeButton, 'EXPORT'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await run(tester, 300);
    }

    testWidgets('Garage has Export, which writes a file and says so', (
      tester,
    ) async {
      await rig.app.trips.createWithSamples(trip(day: 1), samples(5));
      await openData(tester);
      expect(find.widgetWithText(TapeButton, 'EXPORT'), findsOneWidget);
      expect(find.widgetWithText(TapeButton, 'IMPORT A FILE'), findsNothing);

      await tester.tap(find.widgetWithText(TapeButton, 'EXPORT'));
      await run(tester, 1500);
      expect(outbox().listSync(), hasLength(1));
      expect(find.textContaining('Exported 1 trip'), findsOneWidget);
    });

    testWidgets(
      'a phone with a picker offers it, and a file waiting in the inbox',
      (tester) async {
        host.canPick = true;
        await boot(tester, const Size(720, 360));
        await run(tester, 45000);
        // A file arrives by adb while the app is open.
        final file = await otherDevicesFile('from-watch.tdx.gz');
        Directory('${temp.path}/exchange/inbox').createSync(recursive: true);
        file.copySync('${inbox().path}/from-watch.tdx.gz');
        await tester.tap(find.widgetWithText(TapeButton, 'GARAGE'));
        await run(tester, 1500);
        await tester.dragUntilVisible(
          find.widgetWithText(TapeButton, 'EXPORT'),
          find.byType(Scrollable).first,
          const Offset(0, -200),
        );
        await run(tester, 300);
        expect(
          find.widgetWithText(TapeButton, 'IMPORT A FILE'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(TapeButton, 'IMPORT 1 WAITING'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(TapeButton, 'IMPORT 1 WAITING'));
        await run(tester, 2500);
        expect(await finished(), 1);
        expect(
          find.textContaining('Added 1 trip and 1 fill-up'),
          findsOneWidget,
        );
        // The setup came with the file and is offered, with what it would change.
        expect(find.text('Price: 111.0 a litre'), findsOneWidget);
        await tester.tap(find.widgetWithText(TapeButton, 'APPLY THE SETUP'));
        await run(tester, 500);
        expect(rig.app.money.price.value, 111.0);
      },
    );
  });

  group('what adb asks', () {
    testWidgets(
      'an export at the launch is written without touching the screen',
      (tester) async {
        await rig.app.trips.createWithSamples(trip(day: 1), samples(5));
        host.request = const ExchangeRequest(operation: 'export');
        await boot(tester, const Size(720, 360));
        await run(tester, 3000);
        final files = outbox().listSync();
        expect(files, hasLength(1));
        expect(
          File('${temp.path}/exchange/result.json').readAsStringSync(),
          contains('"operation": "export"'),
        );
      },
    );

    testWidgets(
      'an import while the app is running, by the push and the start',
      (tester) async {
        await boot(tester, const Size(720, 360));
        await run(tester, 3000);
        final file = await otherDevicesFile('pushed.tdx.gz');
        file.copySync('${inbox().path}/pushed.tdx.gz');
        host.arrive(
          const ExchangeRequest(operation: 'import', applyProfile: true),
        );
        await run(tester, 3000);
        expect(await finished(), 1);
        expect(
          rig.app.money.price.value,
          111.0,
          reason: 'the setup was asked for',
        );
        expect(
          Directory('${temp.path}/exchange/done').listSync(),
          hasLength(1),
        );
        expect(inbox().listSync(), isEmpty);
      },
    );
  });

  group('on a watch', () {
    testWidgets('the menu has Data, which exports and says what it did', (
      tester,
    ) async {
      await rig.app.trips.createWithSamples(trip(day: 1), samples(5));
      final device = FakeDeviceFeatures();
      await boot(tester, const Size(225, 225), device: device);
      await run(tester, 45000);
      tester.state<WatchReelState>(find.byType(WatchReel)).goTo(3);
      await run(tester, 1500);
      await tester.tapAt(const Offset(112, 112));
      await run(tester, 800);
      // Connect, Speed from, Price, Look, Data.
      for (var i = 0; i < 4; i++) {
        device.turnBezel(1);
        await run(tester, 400);
      }
      expect(find.text('DATA'), findsWidgets);
      await tester.tapAt(const Offset(112, 112));
      await run(tester, 800);
      // Export is the first row.
      await tester.tapAt(const Offset(112, 112));
      await run(tester, 2000);
      expect(outbox().listSync(), hasLength(1));
      expect(find.byType(WatchMessage), findsOneWidget);
      expect(find.textContaining('Exported 1 trip'), findsOneWidget);
      // A tap closes the message, and Back the Data wheel.
      await tester.tapAt(const Offset(112, 112));
      await run(tester, 500);
      expect(find.byType(WatchMessage), findsNothing);
      expect(find.byType(WatchWheel), findsOneWidget);
    });
  });
}

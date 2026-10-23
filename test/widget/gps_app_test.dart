// The app on the phone's GPS alone (CLAUDE.md 7, 9): the choice that leads to it,
// the screen with the speed and what a GPS can add up to, the words when the
// location is missing, the dock with only what applies, and the HUD with only the
// speed. Everything but a satellite.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/gps_shell.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/hud/hud_view.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';
import 'package:tapedash/ui/pages/drive/gps_cluster.dart';
import 'package:tapedash/ui/pages/garage/garage_page.dart';

import '../support/fake_location.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => TapeFonts.load());

  late AppServices app;
  late FakeClock clock;
  late FakeLocation location;

  setUp(() async {
    app = await AppServices.memory();
    await app.adapters.setSource(DriveSource.gps);
    app.settings.onboarded.value = true;
    clock = FakeClock()..advance(const Duration(seconds: 100));
    location = FakeLocation();
  });

  tearDown(() => location.close());

  Future<void> boot(
    WidgetTester tester, {
    Size size = const Size(1440, 720),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TapeDashApp(
        clock: clock,
        scheduler: clock,
        services: app,
        location: location,
        skipColdOpen: true,
      ),
    );
  }

  /// Runs [ms] with one fix a second at [kmh].
  Future<void> drive(WidgetTester tester, int ms, {double kmh = 0}) async {
    for (var t = 0; t < ms; t += 100) {
      clock.advance(const Duration(milliseconds: 100));
      if (t % 1000 == 0) location.emit(kmh: kmh);
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Runs [ms] with no fixes at all.
  Future<void> wait(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 100) {
      clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a launch with GPS chosen goes straight to it, and starts it', (
    tester,
  ) async {
    await boot(tester);
    await tester.pump();
    expect(find.byType(GpsShell), findsOneWidget);
    expect(find.byType(GpsCluster), findsOneWidget);
    expect(
      find.byType(DrivePage),
      findsNothing,
      reason: 'no tach, no clusters',
    );
    expect(location.started, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('until there is a speed it says it is looking, in words', (
    tester,
  ) async {
    await boot(tester);
    await wait(tester, 500);
    expect(find.text('LOOKING FOR GPS'), findsOneWidget);
    expect(find.textContaining('KM/H'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with the location refused it says so, and Allow asks again', (
    tester,
  ) async {
    location.permission = false;
    await boot(tester);
    await wait(tester, 500);
    expect(find.text('LOCATION NEEDED'), findsOneWidget);
    expect(find.widgetWithText(TapeButton, 'ALLOW LOCATION'), findsOneWidget);

    location.permission = true;
    await tester.tap(find.widgetWithText(TapeButton, 'ALLOW LOCATION'));
    await wait(tester, 300);
    expect(location.started, 2);
    await drive(tester, 3000, kmh: 0);
    expect(find.text('LOCATION NEEDED'), findsNothing);
    expect(find.text('KM/H'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone with no GPS says that, and nothing is made up', (
    tester,
  ) async {
    location.unavailable = true;
    await boot(tester);
    await wait(tester, 500);
    expect(find.text('NO GPS'), findsOneWidget);
    expect(find.widgetWithText(TapeButton, 'ALLOW LOCATION'), findsNothing);
  });

  testWidgets('with a speed, the screen has the unit and the trip figures', (
    tester,
  ) async {
    await boot(tester);
    await drive(tester, 6000, kmh: 54);
    expect(find.text('KM/H'), findsWidgets);
    for (final label in [
      'DISTANCE',
      'MOVING',
      'AVERAGE',
      'FASTEST',
      'HEADING',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // No tach, no money, no demo: nothing to read.
    expect(find.textContaining('DEMO'), findsNothing);
    expect(find.textContaining('MONEY'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving, the dock is away; standing, it has Garage, HUD and '
      'Reset trip, and none of the car\'s', (tester) async {
    await boot(tester);
    await drive(tester, 6000, kmh: 54);
    // Moving: the dock has fallen away and Garage will not open.
    await tester.tap(
      find.widgetWithText(TapeButton, 'GARAGE'),
      warnIfMissed: false,
    );
    await drive(tester, 400, kmh: 54);
    expect(find.byType(GaragePage), findsNothing);

    await drive(tester, 9000, kmh: 0);
    expect(find.widgetWithText(TapeButton, 'GARAGE'), findsOneWidget);
    expect(find.widgetWithText(TapeButton, 'HUD'), findsOneWidget);
    expect(find.widgetWithText(TapeButton, 'RESET TRIP'), findsOneWidget);
    expect(find.widgetWithText(TapeButton, 'PIT STOP'), findsNothing);
    expect(find.widgetWithText(TapeButton, 'DIAGNOSTICS'), findsNothing);
    expect(find.widgetWithText(TapeButton, 'INSIGHTS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reset trip puts the figures back to nothing', (tester) async {
    await boot(tester);
    await drive(tester, 8000, kmh: 72);
    final gps = tester.widget<GpsCluster>(find.byType(GpsCluster)).signals.gps;
    expect(gps.figures.value.distanceKm, greaterThan(0.1));
    await drive(tester, 9000, kmh: 0); // parked, so the dock is up
    await tester.tap(find.widgetWithText(TapeButton, 'RESET TRIP'));
    await wait(tester, 300);
    expect(gps.figures.value.distanceKm, 0);
    expect(gps.figures.value.maxKmh, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the HUD is the speed alone', (tester) async {
    await boot(tester);
    await drive(tester, 6000, kmh: 54);
    Future<void> doubleTap() async {
      await tester.tapAt(const Offset(320, 180));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(320, 180));
      await tester.pump();
    }

    await doubleTap();
    expect(find.byType(HudView), findsOneWidget);
    expect(find.text('KM/H'), findsWidgets);
    expect(find.textContaining('MONEY'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await doubleTap();
    expect(find.byType(HudView), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Garage on the GPS: the source can go back to the car, and the '
      'connect flow opens when there is no adapter', (tester) async {
    await boot(tester);
    await drive(tester, 9000, kmh: 0);
    await tester.tap(find.widgetWithText(TapeButton, 'GARAGE'));
    await drive(tester, 600, kmh: 0);
    expect(find.byType(GaragePage), findsOneWidget);
    expect(find.text('SPEED FROM'), findsOneWidget);
    await tester.tap(find.text('CAR ADAPTER').first);
    await drive(tester, 800, kmh: 0);
    expect(
      app.adapters.source.value,
      DriveSource.gps,
      reason: 'nothing chosen',
    );
    expect(find.text('How does your adapter connect?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [640.0, 720.0, 800.0]) {
    testWidgets('lays out at ${width.toInt()}x360 with no exception', (
      tester,
    ) async {
      await boot(tester, size: Size(width * 2, 720));
      await drive(tester, 6000, kmh: 88);
      expect(find.byType(GpsCluster), findsOneWidget);
      await drive(tester, 9000, kmh: 0);
      expect(tester.takeException(), isNull);
    });
  }
}

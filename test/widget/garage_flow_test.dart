// Garage and Diagnostics through the whole app: the dock opens them while parked,
// what Garage changes reaches the theme, the reel and the price, and Diagnostics
// shows the demo adapter.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/design/theme/palette.dart' show DriverSide;
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/diagnostics/diagnostics_page.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';
import 'package:tapedash/ui/pages/garage/garage_page.dart';
import 'package:tapedash/ui/pages/pitstop/pit_stop_page.dart';

import '../support/sim_shell.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => TapeFonts.load());

  late AppServices app;
  late FakeClock clock;

  setUp(() async {
    app = await AppServices.memory();
    clock = FakeClock()..advance(const Duration(seconds: 100));
  });

  Future<void> boot(
    WidgetTester tester, {
    String scenario = 'cold_start_idle',
  }) async {
    tester.view.physicalSize = const Size(1440, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // The default idles with the engine on: parked after five seconds.
    final rig = await SimRig.create(
      clock,
      scenario: DriveScenarios.byName(scenario)!,
      services: app,
    );
    addTearDown(rig.dispose);
    await tester.pumpWidget(rig.widget());
  }

  Future<void> run(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 100) {
      clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, String dockLabel) async {
    await tester.tap(find.widgetWithText(TapeButton, dockLabel));
    await run(tester, 400);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.text('CLOSE'));
    await run(tester, 400);
  }

  Future<void> visible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder.first);
    await tester.pump();
  }

  testWidgets(
    'parked, the dock opens Garage and Diagnostics, and Close returns',
    (tester) async {
      await boot(tester);
      await run(tester, 30000);
      expect(find.byType(GaragePage), findsNothing);

      await open(tester, 'GARAGE');
      expect(find.byType(GaragePage), findsOneWidget);
      await close(tester);
      expect(find.byType(GaragePage), findsNothing);

      await open(tester, 'DIAGNOSTICS');
      expect(find.byType(DiagnosticsPage), findsOneWidget);
      // The demo car is on a simulated adapter, read by the same stack.
      expect(find.text('ELM327 v1.5'), findsOneWidget);
      expect(find.textContaining('CAN'), findsWidgets);
      await close(tester);
      expect(find.byType(DiagnosticsPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Garage cannot be opened while the car moves', (tester) async {
    await boot(tester, scenario: 'highway_cruise');
    // Pulling away and up to speed: the dock is down and its buttons do nothing.
    await run(tester, 60000);
    await tester.tap(
      find.widgetWithText(TapeButton, 'GARAGE'),
      warnIfMissed: false,
    );
    await run(tester, 300);
    expect(find.byType(GaragePage), findsNothing);
  });

  testWidgets(
    'the livery and the driver side chosen in Garage reach the theme',
    (tester) async {
      await boot(tester);
      await run(tester, 30000);
      await open(tester, 'GARAGE');
      TapeThemeData theme() =>
          TapeTheme.of(tester.element(find.byType(GaragePage)));
      expect(theme().livery.id, LiveryId.ion);
      expect(theme().driverSide, DriverSide.right);

      await visible(tester, find.text('Livery'));
      await tester.tap(find.text('Livery'));
      await run(tester, 200);
      await tester.tap(find.text('MONO  ·  Luxury, restrained'));
      await run(tester, 400);
      expect(theme().livery.id, LiveryId.mono);

      await visible(tester, find.text('LEFT'));
      await tester.tap(find.text('LEFT'));
      await run(tester, 400);
      expect(theme().driverSide, DriverSide.left);

      await visible(tester, find.text('Reduce motion'));
      await tester.tap(find.text('Reduce motion'));
      await run(tester, 400);
      expect(theme().reduceMotion, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the layout picked in Garage moves the Drive reel', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 30000);
    await open(tester, 'GARAGE');
    await visible(tester, find.text('Layout'));
    await tester.tap(find.text('Layout'));
    await run(tester, 200);
    await tester.tap(find.text('Road'));
    await run(tester, 300);
    await close(tester);
    await run(tester, 2000);
    final reel = tester.state<DrivePageState>(find.byType(DrivePage));
    expect(reel.reel, closeTo(4, 0.05));
    expect(app.settings.cluster.value, 4);
  });

  testWidgets('the car\'s price is set from Garage, on the real settings', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 30000);
    await open(tester, 'GARAGE');
    await visible(tester, find.text('Price a litre'));
    await tester.tap(find.text('Price a litre'));
    await run(tester, 400);
    expect(find.byType(PitStopPage), findsOneWidget);
    for (final k in '108.5'.split('')) {
      await tester.tap(find.text(k).first);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(TapeButton, 'SAVE'));
    await run(tester, 2500);
    expect(app.money.price.value, closeTo(108.5, 1e-9));
    expect(find.byType(PitStopPage), findsNothing);
  });
}

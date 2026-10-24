// The whole app on a watch (DESIGN.md 16): a screen under 300 lp is a watch, the
// adapter's drive is the reel of faces and not the phone's strip, the bezel turns
// it, the menu's wheels change the price and the look, Back does nothing while the
// car moves, and the numerals are never lighter than the watch allows.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/drive_shell.dart';
import 'package:tapedash/app/watch_shell.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/platform/fake_device_features.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/ui/design/components/watch/watch_wheel.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/watch.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';
import 'package:tapedash/ui/pages/watch/watch_reel.dart';

import '../support/sim_shell.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => TapeFonts.load());

  late FakeClock clock;
  late FakeDeviceFeatures device;
  late SimRig rig;
  late int pops;

  Future<void> boot(
    WidgetTester tester, {
    String scenario = 'cold_start_idle',
    Size logical = const Size(225, 225),
  }) async {
    clock = FakeClock()..advance(const Duration(seconds: 100));
    device = FakeDeviceFeatures();
    rig = await SimRig.create(clock, scenario: DriveScenarios.byName(scenario));
    addTearDown(rig.car.stop);
    tester.view.physicalSize = logical * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    pops = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') pops++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(rig.widget(device: device));
  }

  Future<void> run(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 100) {
      clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  WatchReelState reel(WidgetTester tester) =>
      tester.state<WatchReelState>(find.byType(WatchReel));

  testWidgets('a 225 lp screen is a watch: the reel, not the phone\'s strip', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 30000);

    expect(find.byType(WatchShell), findsOneWidget);
    expect(find.byType(DriveShell), findsNothing);
    expect(find.byType(TheStrip), findsNothing);
    expect(rig.factory.made, [simAdapter]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone-sized screen is still the phone', (tester) async {
    await boot(tester, logical: const Size(720, 360));
    await run(tester, 30000);
    expect(find.byType(DriveShell), findsOneWidget);
    expect(find.byType(WatchShell), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final d in [192.0, 198.0, 240.0, 280.0]) {
    testWidgets('and it runs without an error at $d lp', (tester) async {
      await boot(tester, logical: Size(d, d));
      await run(tester, 30000);
      reel(tester).goTo(1);
      await run(tester, 2000);
      expect(find.byType(WatchShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the bezel turns the reel while parked', (tester) async {
    await boot(tester);
    await run(tester, 45000);
    expect(reel(tester).reachable.value, 4, reason: 'parked: four faces');

    device.turnBezel(1);
    await run(tester, 1500);
    expect(reel(tester).current, 1);
    device.turnBezel(1);
    await run(tester, 1500);
    expect(reel(tester).current, 2);
    device.turnBezel(-1);
    await run(tester, 1500);
    expect(reel(tester).current, 1);
  });

  testWidgets('moving: only two faces, and Back does nothing', (tester) async {
    await boot(tester, scenario: 'highway_cruise');
    await run(tester, 60000);
    expect(reel(tester).reachable.value, 2, reason: 'moving: two faces');

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(pops, 0, reason: 'a knock on the wrist must not close the dash');
    expect(find.byType(WatchShell), findsOneWidget);
  });

  testWidgets('parked: Back leaves, as Android does', (tester) async {
    await boot(tester);
    await run(tester, 45000);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(pops, 1);
  });

  testWidgets('the menu: Look changes the livery, Back closes it first', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 45000);
    reel(tester).goTo(3);
    await run(tester, 1500);
    expect(find.byType(WatchWheel), findsNothing);

    // The last face takes the tap itself and opens the menu.
    await tester.tapAt(const Offset(112, 112));
    await run(tester, 800);
    expect(find.byType(WatchWheel), findsOneWidget);
    expect(reel(tester).current, 3);

    // Back closes the menu and does not leave.
    await tester.binding.handlePopRoute();
    await run(tester, 300);
    expect(find.byType(WatchWheel), findsNothing);
    expect(pops, 0);

    // Open it again and go to Look: Connect, Speed from, Price, Look.
    await tester.tapAt(const Offset(112, 112));
    await run(tester, 800);
    for (var i = 0; i < 3; i++) {
      device.turnBezel(1);
      await run(tester, 400);
    }
    await tester.tapAt(const Offset(112, 112));
    await run(tester, 800);
    // The look wheel: ION, EMBER, VFD, MONO. Two on, and choose.
    device.turnBezel(1);
    await run(tester, 400);
    await tester.tapAt(const Offset(112, 112));
    await run(tester, 800);
    expect(rig.app.settings.livery.value, LiveryId.ember);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the menu: the price is a dial, a detent is 10 paise', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 45000);
    reel(tester).goTo(3);
    await run(tester, 1500);
    await tester.tapAt(const Offset(112, 112));
    await run(tester, 800);
    // Connect, Speed from, Price.
    for (var i = 0; i < 2; i++) {
      device.turnBezel(1);
      await run(tester, 400);
    }
    await tester.tapAt(const Offset(112, 112));
    await run(tester, 800);
    final before = rig.app.money.price.value ?? 100.0;
    device.turnBezel(1);
    await run(tester, 600);
    await tester.tapAt(const Offset(112, 112));
    await run(tester, 800);
    expect(rig.app.money.price.value, closeTo(before + 0.1, 1e-9));
  });

  testWidgets('numerals are never lighter than the watch allows', (
    tester,
  ) async {
    await boot(tester);
    rig.app.settings.livery.value = LiveryId.mono;
    await run(tester, 2000);
    final theme = TapeTheme.of(tester.element(find.byType(WatchShell)));
    expect(theme.livery.id, LiveryId.mono);
    expect(
      theme.livery.numeralWeight,
      greaterThanOrEqualTo(TapeWatch.minNumeralWeight),
    );
    expect(Liveries.mono.numeralWeight, lessThan(TapeWatch.minNumeralWeight));
  });
}

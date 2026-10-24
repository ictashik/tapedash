// A watch's first run (DESIGN.md 16.8): the cold open's two buttons inside the circle,
// the connect flow as wheels (type, find, done) with the same radios and trial of the
// link as the phone's, and the GPS-only drive on the watch.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/watch_gps_shell.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/platform/adapter_radio.dart';
import 'package:tapedash/platform/exchange_host.dart';
import 'package:tapedash/platform/fake_device_features.dart';
import 'package:tapedash/ui/brand/wordmark.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/components/watch/watch_face.dart';
import 'package:tapedash/ui/design/components/watch/watch_wheel.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/design/tokens/spacing.dart';
import 'package:tapedash/ui/onboarding/connect_flow.dart';
import 'package:tapedash/ui/pages/watch/watch_gps_face.dart';
import 'package:tapedash/ui/pages/watch/watch_sheets.dart';

import '../design/support/harness.dart';
import '../support/fake_location.dart';
import 'connect_flow_test.dart' show FakeChecker, FakeRadio, adapter;

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => TapeFonts.load());

  group('the choice', () {
    late AppServices app;
    late FakeClock clock;

    setUp(() async {
      app = await AppServices.memory();
      clock = FakeClock()..advance(const Duration(seconds: 100));
    });

    Future<void> boot(WidgetTester tester, double d) async {
      tester.view.physicalSize = Size(d, d) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TapeDashApp(
          clock: clock,
          scheduler: clock,
          services: app,
          exchangeHost: FakeExchangeHost(),
          device: FakeDeviceFeatures(),
          skipColdOpen: true,
        ),
      );
      for (var i = 0; i < 30; i++) {
        clock.advance(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    for (final d in [192.0, 198.0, 225.0, 240.0, 280.0]) {
      testWidgets('both buttons are inside the circle and touchable at $d lp', (
        tester,
      ) async {
        await boot(tester, d);
        final face = WatchFace(d);
        final buttons = find.byType(TapeButton);
        expect(buttons, findsNWidgets(2));
        for (final e in buttons.evaluate()) {
          final box = e.renderObject! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          expect(face.contains(rect), isTrue, reason: '$rect at $d');
          expect(
            rect.height,
            greaterThanOrEqualTo(TapeSpace.touchTarget - 0.01),
          );
        }
        // The wordmark is over the buttons, not on them, and in the circle.
        final mark = tester.getRect(find.byType(Wordmark));
        expect(
          mark.bottom,
          lessThanOrEqualTo(tester.getRect(buttons.first).top),
        );
        expect(mark.top, greaterThan(0));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'GPS SPEED ONLY chooses the GPS and CONNECT MY CAR opens the flow',
      (tester) async {
        await boot(tester, 225);
        await tester.tap(find.widgetWithText(TapeButton, 'CONNECT MY CAR'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ConnectFlow), findsOneWidget);
        expect(
          tester.widget<ConnectFlow>(find.byType(ConnectFlow)).watch,
          isTrue,
        );
      },
    );
  });

  group('the connect flow on a watch', () {
    late TapeRenderKit kit;
    late ManualMotionClock motion;
    late AppServices app;
    late FakeChecker checker;
    late Map<RadioKind, FakeRadio> radios;
    late StreamController<int> bezel;
    var done = 0;
    var cancelled = 0;

    setUpAll(loadTapeFonts);

    setUp(() async {
      kit = TapeRenderKit();
      motion = ManualMotionClock();
      app = await AppServices.memory();
      checker = FakeChecker();
      radios = {for (final k in RadioKind.values) k: FakeRadio(k)};
      bezel = StreamController<int>.broadcast();
      done = 0;
      cancelled = 0;
    });

    tearDown(() {
      bezel.close();
      kit.dispose();
      motion.dispose();
    });

    Future<void> show(WidgetTester tester) async {
      setWindow(tester, const Size(225, 225));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: ConnectFlow(
            services: app,
            checker: checker,
            radios: (k) => radios[k]!,
            width: 225,
            height: 225,
            watch: true,
            rotary: bezel.stream,
            onDone: () => done++,
            onCancel: () => cancelled++,
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        motion.tick(1 / 60);
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> tapCentre(WidgetTester tester) async {
      await tester.tapAt(const Offset(112.5, 112.5));
      await settle(tester);
    }

    Future<void> turn(WidgetTester tester, int n) async {
      for (var i = 0; i < n; i++) {
        bezel.add(1);
        await tester.pump();
        for (var k = 0; k < 30; k++) {
          motion.tick(1 / 60);
        }
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settle(tester);
    }

    ConnectFlowState flow(WidgetTester tester) =>
        tester.state<ConnectFlowState>(find.byType(ConnectFlow));

    testWidgets('type, find, done: a Bluetooth adapter is tried and saved', (
      tester,
    ) async {
      radios[RadioKind.bluetoothClassic]!
        ..pairedList = [adapter('OBDII', 'AA:01', paired: true)]
        ..nearby = [adapter('Speaker', 'AA:02')];
      await show(tester);
      expect(find.byType(WatchWheel), findsOneWidget);
      expect(find.text('BLUETOOTH'), findsOneWidget);

      await tapCentre(tester); // Bluetooth
      expect(flow(tester).step, ConnectStep.find);
      expect(find.text('OBDII'), findsOneWidget);
      expect(find.textContaining('CLASSIC'), findsWidgets);

      await tapCentre(tester); // OBDII, the first: it looks like an adapter
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(checker.tried.single.address, 'AA:01');
      expect(done, 1);
      expect(app.adapters.adapter.value!.address, 'AA:01');
      expect(app.adapters.source.value, DriveSource.obd);
      expect(app.settings.onboarded.value, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the bezel moves to the next adapter, and that one is tried', (
      tester,
    ) async {
      radios[RadioKind.bluetoothClassic]!.pairedList = [
        adapter('OBDII', 'AA:01', paired: true),
        adapter('Veepeak', 'AA:03', paired: true),
      ];
      await show(tester);
      await tapCentre(tester);
      await turn(tester, 1);
      await tapCentre(tester);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(checker.tried.single.address, isIn(['AA:01', 'AA:03']));
      expect(done, 1);
    });

    testWidgets(
      'an adapter that will not answer offers the way out, in a wheel',
      (tester) async {
        checker.reachableNow = false;
        radios[RadioKind.bluetoothClassic]!.pairedList = [
          adapter('OBDII', 'AA:01', paired: true),
        ];
        await show(tester);
        await tapCentre(tester);
        await tapCentre(tester);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(done, 0);
        expect(flow(tester).failed, isNotNull);
        expect(find.text('FORGET, PAIR AGAIN'), findsOneWidget);
        // Use it anyway is a row too: two on.
        await turn(tester, 1);
        expect(find.text('USE ANYWAY'), findsOneWidget);
        await tapCentre(tester);
        expect(done, 1);
        expect(app.adapters.adapter.value!.address, 'AA:01');
      },
    );

    testWidgets('a WiFi adapter is the usual address, tried and saved', (
      tester,
    ) async {
      await show(tester);
      await turn(tester, 1);
      await tapCentre(tester); // WiFi
      expect(flow(tester).step, ConnectStep.find);
      expect(find.text('USE 192.168.0.10'), findsOneWidget);
      await tapCentre(tester);
      expect(done, 1);
      final saved = app.adapters.adapter.value!;
      expect(saved.kind, AdapterKind.wifi);
      expect(saved.address, '192.168.0.10');
      expect(saved.port, 35000);
    });

    testWidgets('Back, as a swipe to the right and as the button, steps back', (
      tester,
    ) async {
      await show(tester);
      await tapCentre(tester);
      expect(flow(tester).step, ConnectStep.find);
      await tester.fling(find.byType(ConnectFlow), const Offset(150, 0), 900);
      await settle(tester);
      expect(flow(tester).step, ConnectStep.type);

      await tapCentre(tester);
      expect(flow(tester).step, ConnectStep.find);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(flow(tester).step, ConnectStep.type);
      expect(cancelled, 0);

      // From the first step, Back is Cancel, and the Cancel row is the same.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(cancelled, 1);
    });

    testWidgets('a radio that is off or not allowed says so with a way on', (
      tester,
    ) async {
      radios[RadioKind.bluetoothClassic]!.current = const RadioStatus(
        supported: true,
        enabled: true,
        permitted: false,
      );
      radios[RadioKind.ble]!.current = const RadioStatus(
        supported: true,
        enabled: true,
        permitted: false,
      );
      await show(tester);
      await tapCentre(tester);
      expect(find.text('ALLOW'), findsOneWidget);
      await tapCentre(tester);
      expect(radios[RadioKind.bluetoothClassic]!.permissionAsks, 1);
    });

    testWidgets('it asks nothing of the car or the price', (tester) async {
      radios[RadioKind.bluetoothClassic]!.pairedList = [
        adapter('OBDII', 'AA:01', paired: true),
      ];
      await show(tester);
      await tapCentre(tester);
      await tapCentre(tester);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(flow(tester).step, isNot(ConnectStep.car));
      expect(app.money.price.value, isNull);
    });
  });

  group('the GPS alone on a watch', () {
    late AppServices app;
    late FakeClock clock;
    late FakeLocation location;
    late FakeDeviceFeatures device;
    late int pops;

    setUp(() async {
      app = await AppServices.memory();
      await app.adapters.setSource(DriveSource.gps);
      app.settings.onboarded.value = true;
      clock = FakeClock()..advance(const Duration(seconds: 100));
      location = FakeLocation();
      device = FakeDeviceFeatures();
      pops = 0;
    });

    tearDown(() => location.close());

    Future<void> boot(WidgetTester tester, {double d = 225}) async {
      tester.view.physicalSize = Size(d, d) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
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
      await tester.pumpWidget(
        TapeDashApp(
          clock: clock,
          scheduler: clock,
          services: app,
          location: location,
          device: device,
          exchangeHost: FakeExchangeHost(),
          skipColdOpen: true,
        ),
      );
    }

    Future<void> drive(WidgetTester tester, int ms, {double kmh = 0}) async {
      for (var t = 0; t < ms; t += 100) {
        clock.advance(const Duration(milliseconds: 100));
        if (t % 1000 == 0) location.emit(kmh: kmh);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('is a watch screen, and says why while there is no speed', (
      tester,
    ) async {
      location.permission = false;
      await boot(tester);
      await tester.pump();
      expect(find.byType(WatchGpsShell), findsOneWidget);
      expect(find.byType(WatchGpsFace), findsOneWidget);
      expect(find.text('LOCATION'), findsOneWidget);
      expect(find.text('TAP TO ALLOW'), findsOneWidget);
      await tester.tap(find.text('TAP TO ALLOW'));
      await tester.pump();
      expect(location.started, greaterThan(1), reason: 'it asked again');
    });

    testWidgets('shows the speed, and the menu is parked only', (tester) async {
      await boot(tester);
      await drive(tester, 12000, kmh: 52);
      expect(find.text('KM/H'), findsOneWidget);
      expect(find.text('LOCATION'), findsNothing);
      // Moving: Back does nothing.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(pops, 0);
      // The tap cannot open the menu while moving.
      await tester.tapAt(const Offset(112, 112));
      await drive(tester, 500, kmh: 52);
      expect(find.byType(WatchWheel), findsNothing);

      // Stopped for good: parked, and the menu cover is reachable.
      await drive(tester, 12000);
      device.turnBezel(1);
      await drive(tester, 1500);
      expect(find.byType(WatchMenuCover), findsOneWidget);
      await tester.tapAt(const Offset(112, 112));
      await drive(tester, 1000);
      expect(find.byType(WatchWheel), findsOneWidget);
      expect(
        find.text('RESET TRIP'),
        findsNothing,
        reason: 'in the wheel, off screen',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a tap on the speed goes on to the menu, parked, and not moving',
      (tester) async {
        await boot(tester);
        await drive(tester, 12000, kmh: 52);
        await tester.tapAt(const Offset(112, 112));
        await drive(tester, 1500, kmh: 52);
        expect(find.byType(WatchMenuCover), findsNothing, reason: 'moving');
        await drive(tester, 12000);
        await tester.tapAt(const Offset(112, 112));
        await drive(tester, 1500);
        expect(find.byType(WatchMenuCover), findsOneWidget);
        await tester.tapAt(const Offset(112, 112));
        await drive(tester, 1000);
        expect(find.byType(WatchWheel), findsOneWidget);
      },
    );

    testWidgets('the menu has no price, and Reset trip puts the distance back', (
      tester,
    ) async {
      await boot(tester);
      await drive(tester, 20000, kmh: 60);
      await drive(tester, 12000);
      expect(
        tester
            .widget<WatchGpsFace>(find.byType(WatchGpsFace))
            .signals
            .gps
            .figures
            .value
            .distanceKm,
        greaterThan(0.1),
      );
      device.turnBezel(1);
      await drive(tester, 1500);
      await tester.tapAt(const Offset(112, 112));
      await drive(tester, 1000);
      // Connect, Speed from, Look, Data, Reset trip (no Price on the GPS alone).
      expect(find.text('CONNECT'), findsOneWidget);
      expect(find.text('PRICE'), findsNothing);
      for (var i = 0; i < 4; i++) {
        device.turnBezel(1);
        await drive(tester, 400);
      }
      expect(find.text('RESET TRIP'), findsOneWidget);
      await tester.tapAt(const Offset(112, 112));
      await drive(tester, 800);
      // Back to the speed: the distance is nothing again.
      device.turnBezel(-1);
      await drive(tester, 1500);
      expect(
        tester
            .widget<WatchGpsFace>(find.byType(WatchGpsFace))
            .signals
            .gps
            .figures
            .value
            .distanceKm,
        0,
      );
    });
  });
}

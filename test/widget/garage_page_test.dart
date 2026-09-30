// Garage (DESIGN.md 7.8): each setting changes at once and is remembered, the
// lists to pick from open and close, the data can be deleted only by a full slide,
// and it closes itself when the car starts to move.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/app_settings.dart';
import 'package:tapedash/app/demo_drive.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/fuel/fuel_constants.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/trips/trip_library.dart';
import 'package:tapedash/ui/design/components/controls/slide_to_confirm.dart';
import 'package:tapedash/ui/design/components/controls/tape_slider.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/mode_controller.dart' show ModeSetting;
import 'package:tapedash/ui/design/theme/palette.dart' show DriverSide;
import 'package:tapedash/ui/design/tokens/colors.dart' show HudColor;
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/garage/garage_page.dart';
import 'package:tapedash/vehicle/vehicle_state.dart' show DrivingMode;

import '../design/support/harness.dart';

void main() {
  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late AppServices app;
  late AppSettings settings;
  late TripLibrary library;
  late ValueNotifier<DrivingMode> mode;
  late DemoDrive demo;
  var closed = 0;
  var priceAsked = 0;
  var endTrips = 0;

  setUpAll(loadTapeFonts);

  setUp(() async {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock();
    app = await AppServices.memory();
    settings = app.settings;
    library = TripLibrary(app.trips);
    mode = ValueNotifier(DrivingMode.parked);
    demo = DemoDrive(clock: clock, scheduler: clock);
    closed = 0;
    priceAsked = 0;
    endTrips = 0;
  });

  tearDown(() {
    kit.dispose();
    motion.dispose();
    mode.dispose();
    demo.dispose();
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(720, 360),
    bool withDemo = true,
  }) async {
    setWindow(tester, size);
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: GaragePage(
          settings: app.settings,
          services: app,
          library: library,
          mode: mode,
          width: size.width,
          height: size.height,
          onClose: () => closed++,
          onSetPrice: () => priceAsked++,
          demo: withDemo ? demo : null,
          onEndTrip: () => endTrips++,
          version: '9.9',
        ),
      ),
    );
    await tester.pump();
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

  for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
    testWidgets('lays out at ${size.width.toInt()}x360', (tester) async {
      await show(tester, size: size);
      expect(find.text('CAR'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Down the whole list: nothing overflows anywhere.
      await visible(tester, find.textContaining('TapeDash 9.9'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the car: fuel, engine size and tank set the setup', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('DIESEL'));
    await tester.pump();
    expect(app.setup.value.fuelType, FuelType.diesel);

    // A tap on a slider sets it where it lands: the far end is the top.
    final engine = find.widgetWithText(TapeSlider, 'ENGINE SIZE');
    final at = tester.getTopRight(engine) + const Offset(-2, 34);
    await tester.tapAt(at);
    await tester.pump();
    expect(app.setup.value.displacementLitres, closeTo(6.0, 0.1));
    expect(app.setup.value.fuelType, FuelType.diesel, reason: 'the rest holds');

    final tank = find.widgetWithText(TapeSlider, 'TANK');
    await tester.tapAt(tester.getTopLeft(tank) + const Offset(2, 34));
    await tester.pump();
    expect(app.setup.value.tankLitres, closeTo(20, 1));
  });

  testWidgets('the fuel price row says what is set, and opens the form', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Not set'), findsOneWidget);
    await tester.tap(find.text('Price a litre'));
    expect(priceAsked, 1);

    await app.money.setPrice(102.5);
    await tester.pump();
    expect(find.text('₹102.50'), findsOneWidget);
  });

  testWidgets('the calibration line follows the fill-ups', (tester) async {
    await show(tester);
    expect(find.textContaining('Two full tanks in Pit Stop'), findsOneWidget);
    await tester.runAsync(() async {
      for (final day in [1, 8, 15]) {
        app.ledger.addEstimate(30);
        await app.saveFillUp(
          at: DateTime(2026, 3, day),
          litres: 30,
          amount: 3000,
          fullTank: true,
        );
      }
    });
    await tester.pump();
    expect(find.text('Estimates, checked twice.'), findsOneWidget);
  });

  testWidgets('the livery is picked from a list, and Back returns', (
    tester,
  ) async {
    await show(tester);
    await visible(tester, find.text('Livery'));
    await tester.tap(find.text('Livery'));
    await tester.pump();
    expect(find.text('ION  ·  Cool, electric, modern'), findsOneWidget);
    expect(
      find.text('CAR'),
      findsNothing,
      reason: 'the list replaces the page',
    );
    expect(
      tester.state<GaragePageState>(find.byType(GaragePage)).isPicking,
      isTrue,
    );

    await tester.tap(find.text('EMBER  ·  Warm, sporty'));
    await tester.pump();
    expect(settings.livery.value, LiveryId.ember);
    expect(find.text('CAR'), findsOneWidget);

    // Back without choosing leaves it alone.
    await visible(tester, find.text('Livery'));
    await tester.tap(find.text('Livery'));
    await tester.pump();
    await tester.tap(find.text('BACK'));
    await tester.pump();
    expect(settings.livery.value, LiveryId.ember);
    expect(find.text('CAR'), findsOneWidget);
    expect(closed, 0, reason: 'Back is not Close');
  });

  testWidgets('driver side, coach preset, fidelity and ignition segments', (
    tester,
  ) async {
    await show(tester);
    await visible(tester, find.text('LEFT'));
    await tester.tap(find.text('LEFT'));
    await tester.pump();
    expect(settings.driverSide.value, DriverSide.left);

    await visible(tester, find.text('SPORTY'));
    await tester.tap(find.text('SPORTY'));
    await tester.pump();
    expect(settings.coachPreset.value, CoachPreset.sporty);
    expect(
      settings.thresholds.hardAccelerationMs2,
      CoachPreset.sporty.thresholds.hardAccelerationMs2,
    );
    expect(settings.thresholds.speedLimitKmh, settings.speedLimitKmh.value);

    await visible(tester, find.text('LITE'));
    await tester.tap(find.text('LITE'));
    await tester.pump();
    expect(settings.tierPin.value?.label, 'LITE');
    // Two selectors have an AUTO: the brightness mode's, then the fidelity's.
    await tester.tap(find.text('AUTO').last);
    await tester.pump();
    expect(settings.tierPin.value, isNull);

    await tester.tap(find.text('SUBTLE'));
    await tester.pump();
    expect(settings.ignition.value.name, 'subtle');
  });

  testWidgets('the brightness mode is held from Garage', (tester) async {
    await show(tester);
    expect(settings.modeSetting.value, ModeSetting.auto);
    await visible(tester, find.text('DAYLIGHT'));
    await tester.tap(find.text('DAYLIGHT'));
    await tester.pump();
    expect(settings.modeSetting.value, ModeSetting.daylight);
    await tester.tap(find.text('NIGHT'));
    await tester.pump();
    expect(settings.modeSetting.value, ModeSetting.night);
  });

  testWidgets('a hot phone is said, with what to do; a cool one is not', (
    tester,
  ) async {
    final temperature = ObservableValue<double?>(38);
    setWindow(tester, const Size(720, 360));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: GaragePage(
          settings: settings,
          services: app,
          library: library,
          mode: mode,
          width: 720,
          height: 360,
          onClose: () {},
          phoneTemperature: temperature,
        ),
      ),
    );
    await tester.pump();
    await visible(tester, find.text('BRIGHTNESS MODE'));
    expect(find.textContaining('The phone is hot'), findsNothing);
    temperature.value = 48;
    await tester.pump();
    expect(find.text('The phone is hot (48°C)'), findsOneWidget);
    expect(find.textContaining('Unplug the charger'), findsOneWidget);
  });

  testWidgets('the HUD: colour from a list, the flips, position and size', (
    tester,
  ) async {
    await show(tester);
    await visible(tester, find.text('Colour'));
    await tester.tap(find.text('Colour'));
    await tester.pump();
    await tester.tap(find.text('Amber'));
    await tester.pump();
    expect(settings.hud.color, HudColor.amber);

    await visible(tester, find.textContaining('Flip left to right'));
    expect(settings.hud.flipHorizontal, isTrue, reason: 'on by default');
    await tester.tap(find.textContaining('Flip left to right'));
    await tester.pump();
    expect(settings.hud.flipHorizontal, isFalse);
    await tester.tap(find.textContaining('Flip top to bottom'));
    await tester.pump();
    expect(settings.hud.flipVertical, isTrue);

    final size = find.widgetWithText(TapeSlider, 'SIZE');
    await visible(tester, size);
    await tester.tapAt(tester.getTopRight(size) + const Offset(-2, 34));
    await tester.pump();
    expect(settings.hud.scale, closeTo(1.4, 0.05));
  });

  testWidgets('the alignment pattern is asked for, and Garage closes', (
    tester,
  ) async {
    var aligned = 0;
    setWindow(tester, const Size(720, 360));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: GaragePage(
          settings: settings,
          services: app,
          library: library,
          mode: mode,
          width: 720,
          height: 360,
          onClose: () => closed++,
          onAlignment: () => aligned++,
        ),
      ),
    );
    await visible(tester, find.text('Alignment pattern'));
    await tester.tap(find.text('Alignment pattern'));
    await tester.pump();
    expect(aligned, 1);
    expect(closed, 1);
  });

  testWidgets('the speed threshold snaps to fives', (tester) async {
    await show(tester);
    final slider = find.widgetWithText(TapeSlider, 'SPEED THRESHOLD');
    await visible(tester, slider);
    await tester.tapAt(tester.getCenter(slider) + const Offset(0, 8));
    await tester.pump();
    expect(settings.speedLimitKmh.value % 5, 0);
    expect(settings.speedLimitKmh.value, inInclusiveRange(60, 160));
  });

  testWidgets('demo: the drive and the car are picked, and the trip can end', (
    tester,
  ) async {
    await show(tester);
    await visible(tester, find.text('Drive'));
    await tester.tap(find.text('Drive'));
    await tester.pump();
    await visible(tester, find.text('highway_cruise'));
    await tester.tap(find.text('highway_cruise'));
    await tester.pump();
    expect(demo.scenario.value, 'highway_cruise');
    expect(settings.demoScenario.value, 'highway_cruise');

    await visible(tester, find.text('Car'));
    await tester.tap(find.text('Car'));
    await tester.pump();
    await visible(tester, find.text('petrol_manual_sporty'));
    await tester.tap(find.text('petrol_manual_sporty'));
    await tester.pump();
    expect(demo.profile.value, 'petrol_manual_sporty');
    expect(settings.demoProfile.value, 'petrol_manual_sporty');

    await visible(tester, find.text('End this trip now'));
    await tester.tap(find.text('End this trip now'));
    await tester.pump();
    expect(endTrips, 1);
    expect(closed, 1);
  });

  testWidgets('a list to pick from starts at its top, and Back returns to '
      'where the page was', (tester) async {
    await show(tester);
    await visible(tester, find.text('Drive'));
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(before, greaterThan(100));
    await tester.tap(find.text('Drive'));
    await tester.pump();
    expect(find.text('cold_start_idle'), findsOneWidget, reason: 'its top');

    await tester.tap(find.text('BACK'));
    await tester.pump();
    await tester.pump();
    final after = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(after, before);
  });

  testWidgets('with no demo there is no demo group', (tester) async {
    await show(tester, withDemo: false);
    await visible(tester, find.textContaining('TapeDash 9.9'));
    expect(find.text('DEMO MODE'), findsNothing);
  });

  testWidgets('delete all needs the full slide, then the log is empty', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await app.trips.create(Trip(startedAt: DateTime(2026, 3, 1)));
      await app.money.setPrice(100);
      await library.refresh();
    });
    await show(tester);
    final slider = find.byType(SlideToConfirm);
    await visible(tester, slider);
    final start = tester.getTopLeft(slider) + const Offset(30, 28);

    var drag = await tester.startGesture(start);
    await drag.moveBy(const Offset(80, 0));
    await drag.moveBy(const Offset(1, 0));
    await drag.up();
    await tester.pump();
    expect(
      library.trips.value,
      isNotEmpty,
      reason: 'a short slide does nothing',
    );
    motion.advance(const Duration(seconds: 2));
    await tester.pump();

    // In a list, the first move only decides that it is a sideways drag: it
    // takes a hand's several small moves, as a real one makes.
    drag = await tester.startGesture(start);
    for (var i = 0; i < 20; i++) {
      await drag.moveBy(Offset(tester.getSize(slider).width / 15, 0));
    }
    await drag.up();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(library.trips.value, isEmpty);
    expect(await app.trips.all(includeDemo: true), isEmpty);
    expect(app.money.price.value, isNull);
  });

  testWidgets('a setting is remembered by a new run of the app', (
    tester,
  ) async {
    await show(tester);
    await visible(tester, find.text('LEFT'));
    await tester.tap(find.text('LEFT'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    final again = AppSettings(app.store);
    await tester.runAsync(again.load);
    expect(again.driverSide.value, DriverSide.left);
  });

  testWidgets('it closes itself when the car starts to move, and has Close', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('CLOSE'));
    await tester.pump();
    expect(closed, 1);
    mode.value = DrivingMode.motion;
    await tester.pump();
    expect(closed, 2);
  });
}

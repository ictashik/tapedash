// Garage (DESIGN.md 7.8): each setting changes at once and is remembered, the
// lists to pick from open and close, the data can be deleted only by a full slide,
// and it closes itself when the car starts to move.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/app_settings.dart';
import 'package:tapedash/app/drive_sound.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/fuel_blend.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/fuel/fuel_constants.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/obd/link_diary.dart';
import 'package:tapedash/sound/engine_profile.dart';
import 'package:tapedash/sound/engine_sound.dart';
import 'package:tapedash/sound/pcm_sink.dart';
import 'package:tapedash/sound/voice_host.dart';
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

/// A voice that plays nothing and says it started.
class _QuietVoice implements VoiceHost {
  bool running = false;

  @override
  Stream<String> get events => const Stream.empty();

  @override
  Future<SinkStart> start(
    EngineProfile profile, {
    required double volume,
    bool requireExternalOutput = false,
  }) async {
    running = true;
    return SinkStart.started;
  }

  @override
  void setProfile(EngineProfile profile) {}

  @override
  void setVolume(double volume) {}

  @override
  void setControls({
    required double rpm,
    required double load,
    required bool active,
  }) {}

  @override
  Future<void> stop() async => running = false;
}

class _NoSource implements EngineSoundSource {
  @override
  bool read(EngineControls out) => false;
}

void main() {
  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late AppServices app;
  late AppSettings settings;
  late TripLibrary library;
  late ValueNotifier<DrivingMode> mode;
  var closed = 0;
  var priceAsked = 0;
  var adapterAsked = 0;

  setUpAll(loadTapeFonts);

  setUp(() async {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock();
    app = await AppServices.memory();
    settings = app.settings;
    library = TripLibrary(app.trips);
    mode = ValueNotifier(DrivingMode.parked);
    closed = 0;
    priceAsked = 0;
    adapterAsked = 0;
  });

  tearDown(() {
    kit.dispose();
    motion.dispose();
    mode.dispose();
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(720, 360),
    bool withAdapters = false,
    bool gpsOnly = false,
    LinkDiary? diary,
    DriveSound? sound,
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
          adapters: withAdapters ? app.adapters : null,
          diary: diary,
          onChangeAdapter: () => adapterAsked++,
          gpsOnly: gpsOnly,
          sound: sound,
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

  testWidgets('the ethanol in the petrol: E20 to begin with, set from Garage', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('ETHANOL IN THE PETROL'), findsOneWidget);
    expect(app.setup.value.blend, PetrolBlend.e20);

    await tester.tap(find.text('E10'));
    await tester.pump();
    expect(app.setup.value.blend, PetrolBlend.e10);
    expect(app.setup.value.fuelType, FuelType.petrol, reason: 'the rest holds');

    await tester.tap(find.text('E0'));
    await tester.pump();
    expect(app.setup.value.blend, PetrolBlend.e0);
  });

  testWidgets('a diesel has no ethanol to set, and keeps the blend for later', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('E10'));
    await tester.pump();

    await tester.tap(find.text('DIESEL'));
    await tester.pump();
    expect(find.text('ETHANOL IN THE PETROL'), findsNothing);
    expect(app.setup.value.blend, PetrolBlend.e10);

    await tester.tap(find.text('PETROL'));
    await tester.pump();
    expect(find.text('ETHANOL IN THE PETROL'), findsOneWidget);
    expect(app.setup.value.blend, PetrolBlend.e10);
  });

  testWidgets('the fuel price row says what is set, and opens the form', (
    tester,
  ) async {
    await show(tester);
    // The car group has a row more (the ethanol), so the price is further down.
    await visible(tester, find.text('Not set'));
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

  testWidgets('a list to pick from starts at its top, and Back returns to '
      'where the page was', (tester) async {
    await show(tester);
    await visible(tester, find.text('Colour'));
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(before, greaterThan(100));
    await tester.tap(find.text('Colour'));
    await tester.pump();
    expect(
      find.text(HudColor.values.first.label),
      findsOneWidget,
      reason: 'its top',
    );

    await tester.tap(find.text('BACK'));
    await tester.pump();
    await tester.pump();
    final after = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(after, before);
  });

  testWidgets('there is no demo group: Garage has no demo to steer', (
    tester,
  ) async {
    await show(tester, withAdapters: true);
    await visible(tester, find.textContaining('TapeDash 9.9'));
    expect(find.textContaining('Demo', findRichText: true), findsNothing);
    expect(find.text('DEMO MODE'), findsNothing);
  });

  testWidgets('Speed from: GPS only is chosen, and the adapter kept', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await app.adapters.choose(
        const AdapterConfig(
          kind: AdapterKind.ble,
          address: 'AA:BB:CC:DD:EE:FF',
          name: 'OBDBLE',
        ),
      );
    });
    await show(tester, withAdapters: true);
    expect(app.adapters.source.value, DriveSource.obd);
    await visible(tester, find.text('GPS ONLY').first);
    await tester.tap(find.text('GPS ONLY').first);
    await tester.pump();
    expect(app.adapters.source.value, DriveSource.gps);
    expect(app.adapters.adapter.value, isNotNull, reason: 'still remembered');
    await visible(tester, find.text('CAR ADAPTER').first);
    await tester.tap(find.text('CAR ADAPTER').first);
    await tester.pump();
    expect(app.adapters.source.value, DriveSource.obd);
    expect(adapterAsked, 0);
  });

  testWidgets(
    'Speed from: Car adapter with none chosen opens the connect flow, '
    'and changes nothing itself',
    (tester) async {
      await tester.runAsync(() => app.adapters.setSource(DriveSource.gps));
      await show(tester, withAdapters: true);
      await visible(tester, find.text('CAR ADAPTER').first);
      await tester.tap(find.text('CAR ADAPTER').first);
      await tester.pump();
      expect(adapterAsked, 1);
      expect(app.adapters.source.value, DriveSource.gps);
    },
  );

  testWidgets('on the GPS alone Garage leaves out what is about the car', (
    tester,
  ) async {
    await show(tester, withAdapters: true, gpsOnly: true);
    expect(find.text('SPEED FROM'), findsOneWidget);
    expect(find.text('CAR'), findsNothing);
    await visible(tester, find.text('HUD'));
    await visible(tester, find.textContaining('TapeDash 9.9'));
    expect(find.text('FUEL PRICE'), findsNothing);
    expect(find.text('COACH'), findsNothing);
    expect(find.text('DATA'), findsNothing);
  });

  testWidgets('the connection log is a row, opens newest first, and Back '
      'returns', (tester) async {
    await tester.runAsync(() async {
      await app.adapters.choose(
        const AdapterConfig(
          kind: AdapterKind.ble,
          address: 'AA:BB:CC:DD:EE:FF',
          name: 'OBDBLE',
        ),
      );
    });
    final diary = LinkDiary(clock: clock);
    diary.add('ble: attempt 1 of 3: connecting');
    diary.add('ble: link status=133 state=disconnected');
    await show(tester, withAdapters: true, diary: diary);
    await visible(tester, find.text('Connection log'));
    expect(find.text('2 lines, newest first'), findsOneWidget);
    await tester.tap(find.text('Connection log'));
    await tester.pump();
    final lines = [
      for (final e in find.byType(Text).evaluate())
        if ((e.widget as Text).data?.contains('ble:') ?? false)
          (e.widget as Text).data!,
    ];
    expect(lines, hasLength(2));
    expect(lines.first, contains('status=133'), reason: 'newest first');
    expect(lines.last, contains('attempt 1'));
    await tester.tap(find.text('BACK'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Connection log'), findsOneWidget);
  });

  testWidgets('with no adapter chosen there is no connection log row', (
    tester,
  ) async {
    await show(tester, withAdapters: true, diary: LinkDiary(clock: clock));
    expect(find.text('Connection log'), findsNothing);
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

  group('the engine sound', () {
    late DriveSound sound;

    setUp(() {
      sound = DriveSound(
        settings: settings,
        live: _NoSource(),
        scheduler: clock,
        clock: clock,
        hostFactory: _QuietVoice.new,
      );
    });

    tearDown(() => sound.dispose());

    testWidgets('it has a group of its own, off to begin with', (tester) async {
      await show(tester, sound: sound);

      await visible(tester, find.text('Also on the phone speaker'));
      expect(find.text('ENGINE SOUND'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(settings.soundEnabled.value, isFalse);
      expect(find.text('Inline-4'), findsOneWidget);
    });

    testWidgets('with none given the group is not there', (tester) async {
      await show(tester);

      expect(find.text('Also on the phone speaker'), findsNothing);
      expect(find.text('Test the sound'), findsNothing);
    });

    testWidgets('the toggle turns it on, and the status says it is playing', (
      tester,
    ) async {
      sound.start();
      await show(tester, sound: sound);
      await visible(tester, find.text('Engine sound'));

      await tester.tap(find.text('Engine sound'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();

      expect(settings.soundEnabled.value, isTrue);
      expect(find.text('Playing'), findsOneWidget);
    });

    testWidgets('an engine is chosen from a list of them, each described', (
      tester,
    ) async {
      await show(tester, sound: sound);
      await visible(tester, find.text('Inline-4'));

      await tester.tap(find.text('Inline-4'));
      await tester.pump();
      for (final p in EngineProfile.all) {
        await visible(tester, find.textContaining(p.name));
        expect(find.textContaining(p.name), findsOneWidget, reason: p.id);
      }
      await visible(tester, find.textContaining('V8'));
      await tester.tap(find.textContaining('V8'));
      await tester.pump();

      expect(settings.soundProfile.value, 'v8');
      await visible(tester, find.text('V8'));
      expect(find.text('V8'), findsOneWidget);
    });

    testWidgets('the speaker is allowed by its own toggle', (tester) async {
      await show(tester, sound: sound);
      await visible(tester, find.text('Also on the phone speaker'));
      expect(settings.soundOnSpeaker.value, isFalse);

      await tester.tap(find.text('Also on the phone speaker'));
      await tester.pump();

      expect(settings.soundOnSpeaker.value, isTrue);
    });

    testWidgets('the test row plays, and says so, and stops', (tester) async {
      sound.start();
      await show(tester, sound: sound);
      await visible(tester, find.text('Test the sound'));

      await tester.tap(find.text('Test the sound'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();

      expect(sound.testing.value, isTrue);
      expect(find.text('Stop the test'), findsOneWidget);

      await tester.tap(find.text('Stop the test'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(sound.testing.value, isFalse);
      expect(find.text('Test the sound'), findsOneWidget);
    });

    for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
      testWidgets('lays out at ${size.width.toInt()}x360', (tester) async {
        await show(tester, size: size, sound: sound);

        await visible(tester, find.text('Also on the phone speaker'));
        await visible(tester, find.textContaining('TapeDash 9.9'));

        expect(tester.takeException(), isNull);
      });
    }
  });
}

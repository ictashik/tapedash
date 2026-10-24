// The phone's side of the display: the light drives Daylight and Night, the
// brightness follows the mode, a hot phone dims and drops to Lite at 30 fps, and
// what Garage holds is kept. On a fake phone and a fake clock.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_settings.dart';
import 'package:tapedash/app/display_controller.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/platform/device_features.dart';
import 'package:tapedash/platform/fake_device_features.dart';
import 'package:tapedash/ui/design/fidelity/fidelity_tier.dart';
import 'package:tapedash/ui/design/fidelity/governor.dart';
import 'package:tapedash/ui/design/fidelity/tier_detector.dart';
import 'package:tapedash/ui/design/theme/mode_controller.dart';
import 'package:tapedash/ui/design/theme/palette.dart' show TapeMode;

/// A phone whose every answer is an error.
class BrokenPhone extends FakeDeviceFeatures {
  @override
  Future<SensorSupport> sensorSupport() async => throw StateError('no sensors');
  @override
  Future<double?> batteryTemperatureCelsius() async =>
      throw StateError('no battery');
  @override
  Future<void> setBrightness(double? level) async =>
      throw StateError('no window');
}

void main() {
  late FakeClock clock;
  late FakeDeviceFeatures device;
  late AppSettings settings;
  late DisplayController display;

  setUp(() {
    clock = FakeClock();
    device = FakeDeviceFeatures();
    settings = AppSettings(MemoryKeyValueStore());
    display = DisplayController(
      device: device,
      clock: clock,
      scheduler: clock,
      settings: settings,
      watchFrames: false,
    );
  });

  tearDown(() async {
    await display.dispose();
    await device.dispose();
  });

  Future<void> emit(double lux) async {
    device.emitLux(lux);
    await Future<void>.delayed(Duration.zero);
  }

  /// A light that stays at [lux] for [seconds].
  Future<void> light(double lux, int seconds) async {
    for (var t = 0; t <= seconds; t++) {
      await emit(lux);
      clock.advance(const Duration(seconds: 1));
    }
  }

  test(
    'it starts in the normal mode, on the phone\'s own brightness',
    () async {
      await display.start();
      expect(display.mode.value, TapeMode.normal);
      expect(display.brightness, isNull);
      expect(device.brightness, isNull);
      expect(display.tier.value.tier, FidelityTier.balanced);
      expect(display.phoneHot.value, isFalse);
    },
  );

  group('the light', () {
    test('bright sun for 10 s is Daylight, at full brightness', () async {
      await display.start();
      await light(8000, 4);
      expect(
        display.mode.value,
        TapeMode.normal,
        reason: 'not yet: a passing glare',
      );
      await light(8000, 8);
      expect(display.mode.value, TapeMode.daylight);
      expect(device.brightness, 1);
    });

    test('a dark road for 10 s is Night, at its floor and up', () async {
      await display.start();
      await light(3, 12);
      expect(display.mode.value, TapeMode.night);
      expect(device.brightness, inInclusiveRange(0.12, 0.3));
    });

    test(
      'at night the brightness follows the light, without a value a reading',
      () async {
        await display.start();
        await light(3, 12);
        final dark = device.brightness!;
        await emit(15);
        expect(device.brightness!, greaterThan(dark));
      },
    );

    test('back in the middle, the phone\'s own brightness returns', () async {
      await display.start();
      await light(8000, 12);
      expect(device.brightness, 1);
      // Daylight is left below 2,000 lux, after the dwell.
      await light(500, 12);
      expect(display.mode.value, TapeMode.normal);
      expect(device.brightness, isNull);
    });

    test('a phone with no light sensor stays in the normal mode', () async {
      device.support = const SensorSupport(
        ambientLight: false,
        accelerometer: true,
      );
      await display.start();
      await light(8000, 12);
      expect(display.mode.value, TapeMode.normal);
    });
  });

  group('Garage\'s brightness mode', () {
    test('holds a mode whatever the light does, at once', () async {
      await display.start();
      settings.modeSetting.value = ModeSetting.daylight;
      expect(display.mode.value, TapeMode.daylight);
      expect(device.brightness, 1);
      await light(3, 12);
      expect(display.mode.value, TapeMode.daylight);

      settings.modeSetting.value = ModeSetting.night;
      expect(display.mode.value, TapeMode.night);
      settings.modeSetting.value = ModeSetting.auto;
      expect(display.mode.value, TapeMode.night, reason: 'the light says so');
    });

    test('a mode held from the last run is held from the start', () async {
      settings.modeSetting.value = ModeSetting.night;
      final held = DisplayController(
        device: device,
        clock: clock,
        scheduler: clock,
        settings: settings,
        watchFrames: false,
      );
      addTearDown(held.dispose);
      expect(held.mode.value, TapeMode.night);
    });
  });

  group('a hot phone', () {
    test(
      'above 45 the glyph shows; the tier and brightness are left alone',
      () async {
        device.batteryTemperature = 46;
        await display.start();
        expect(display.temperature.value, 46);
        expect(display.phoneHot.value, isTrue);
        expect(display.phoneTooHot.value, isFalse);
        expect(display.tier.value.tier, FidelityTier.balanced);
      },
    );

    test('at 45 exactly it is not hot yet', () async {
      device.batteryTemperature = 45;
      await display.start();
      expect(display.phoneHot.value, isFalse);
    });

    test('above 50 it dims and drops to Lite at 30 fps, for good', () async {
      device.batteryTemperature = 51;
      await display.start();
      expect(display.phoneTooHot.value, isTrue);
      expect(display.tier.value.tier, FidelityTier.lite);
      expect(display.tier.value.fpsCap, 30);
      expect(display.tier.value.reason, TierReason.thermal);
      expect(device.brightness, lessThanOrEqualTo(0.5));

      // Cooling off does not bring the fidelity back during the trip.
      device.batteryTemperature = 35;
      clock.advance(const Duration(seconds: 31));
      await Future<void>.delayed(Duration.zero);
      expect(display.phoneTooHot.value, isFalse);
      expect(display.tier.value.tier, FidelityTier.lite);
    });

    test(
      'it dims a Daylight screen too, though Daylight wants the maximum',
      () async {
        device.batteryTemperature = 51;
        await display.start();
        settings.modeSetting.value = ModeSetting.daylight;
        expect(device.brightness, 0.5);
      },
    );

    test('the temperature is read again every half minute', () async {
      device.batteryTemperature = 30;
      await display.start();
      expect(display.phoneHot.value, isFalse);
      device.batteryTemperature = 47;
      clock.advance(const Duration(seconds: 29));
      await Future<void>.delayed(Duration.zero);
      expect(display.phoneHot.value, isFalse);
      clock.advance(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(display.phoneHot.value, isTrue);
    });

    test('a phone with no battery temperature is never hot', () async {
      device.batteryTemperature = null;
      await display.start();
      expect(display.temperature.value, isNull);
      expect(display.phoneHot.value, isFalse);
    });
  });

  group('the tier', () {
    test('the cold open\'s benchmark sets where it starts', () async {
      await display.start();
      display.onDetected(
        const TierDecision(
          tier: FidelityTier.full,
          fpsCap: null,
          p90Milliseconds: 5,
        ),
      );
      expect(display.tier.value.tier, FidelityTier.full);
      expect(display.tier.value.reason, TierReason.detected);
    });

    test('a tier held in Garage is kept, and Auto lets go of it', () async {
      await display.start();
      settings.tierPin.value = FidelityTier.lite;
      expect(display.tier.value.tier, FidelityTier.lite);
      expect(display.tier.value.reason, TierReason.user);
      display.onDetected(
        const TierDecision(
          tier: FidelityTier.full,
          fpsCap: null,
          p90Milliseconds: 5,
        ),
      );
      expect(display.tier.value.tier, FidelityTier.lite, reason: 'held');

      settings.tierPin.value = null;
      display.onDetected(
        const TierDecision(
          tier: FidelityTier.full,
          fpsCap: null,
          p90Milliseconds: 5,
        ),
      );
      expect(display.tier.value.tier, FidelityTier.full);
    });

    test('a tier held from the last run is held from the start', () async {
      settings.tierPin.value = FidelityTier.full;
      final held = DisplayController(
        device: device,
        clock: clock,
        scheduler: clock,
        settings: settings,
        watchFrames: false,
      );
      addTearDown(held.dispose);
      expect(held.tier.value.tier, FidelityTier.full);
    });
  });

  group('a watch (DESIGN.md 16.9)', () {
    late DisplayController watch;

    setUp(() {
      watch = DisplayController(
        device: device,
        clock: clock,
        scheduler: clock,
        settings: settings,
        watchFrames: false,
        watch: true,
        hotAt: 41,
        tooHotAt: 45,
      );
    });

    tearDown(() async => watch.dispose());

    test('starts at Lite, where a phone starts at Balanced', () {
      expect(watch.tier.value.tier, FidelityTier.lite);
      expect(display.tier.value.tier, FidelityTier.balanced);
    });

    test('is held to Balanced however fast the cold open was', () {
      watch.onDetected(
        const TierDecision(
          tier: FidelityTier.full,
          fpsCap: null,
          p90Milliseconds: 3,
        ),
      );
      expect(watch.tier.value.tier, FidelityTier.balanced);
      expect(watch.tier.value.fpsCap, 60);
      // Lite and Balanced are taken as they come.
      watch.onDetected(
        const TierDecision(
          tier: FidelityTier.lite,
          fpsCap: 30,
          p90Milliseconds: 20,
        ),
      );
      expect(watch.tier.value.tier, FidelityTier.lite);
      expect(watch.tier.value.fpsCap, 30);
    });

    test(
      'is warm at 41 degrees and too hot, dimmed and at Lite, at 45',
      () async {
        device.batteryTemperature = 42;
        await watch.start();
        expect(watch.phoneHot.value, isTrue);
        expect(watch.phoneTooHot.value, isFalse);
        expect(watch.brightness, isNull);

        device.batteryTemperature = 46;
        clock.advance(const Duration(seconds: 31));
        await Future<void>.delayed(Duration.zero);
        expect(watch.phoneTooHot.value, isTrue);
        expect(watch.brightness, 0.5);
        expect(watch.tier.value.tier, FidelityTier.lite);
      },
    );

    test('a phone is not warm at 42 degrees', () async {
      device.batteryTemperature = 42;
      await display.start();
      expect(display.phoneHot.value, isFalse);
    });
  });

  test('a phone that fails at everything is a reason to carry on', () async {
    final broken = BrokenPhone();
    final shaky = DisplayController(
      device: broken,
      clock: clock,
      scheduler: clock,
      settings: settings,
      watchFrames: false,
    );
    addTearDown(shaky.dispose);
    await shaky.start();
    settings.modeSetting.value = ModeSetting.night;
    expect(shaky.mode.value, TapeMode.night);
    expect(shaky.phoneHot.value, isFalse);
    await broken.dispose();
  });

  test('starting twice does nothing more, and dispose is safe', () async {
    await display.start();
    await display.start();
    await display.dispose();
    await display.dispose();
  });
}

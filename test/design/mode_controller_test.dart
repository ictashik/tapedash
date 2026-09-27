// Daylight and Night follow the light sensor with hysteresis (DESIGN.md 4.4).
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/theme/mode_controller.dart';
import 'package:tapedash/ui/design/theme/palette.dart';

void main() {
  late FakeClock clock;
  late ModeController controller;

  /// Reads [lux] once a second for [seconds].
  void light(double lux, int seconds) {
    for (var i = 0; i < seconds; i++) {
      controller.onLux(lux);
      clock.advance(const Duration(seconds: 1));
    }
  }

  setUp(() {
    clock = FakeClock();
    controller = ModeController(clock: clock);
  });

  test('starts in normal', () {
    expect(controller.mode.value, TapeMode.normal);
  });

  group('Daylight', () {
    test('needs 10 s above 5,000 lux', () {
      light(6000, 9);
      expect(controller.mode.value, TapeMode.normal);

      light(6000, 2);
      expect(controller.mode.value, TapeMode.daylight);
    });

    test('is not entered by a lux of exactly 5,000', () {
      light(5000, 30);

      expect(controller.mode.value, TapeMode.normal);
    });

    test('a passing shadow restarts the count', () {
      light(6000, 8);
      light(3000, 1);
      light(6000, 8);

      expect(controller.mode.value, TapeMode.normal);

      light(6000, 3);
      expect(controller.mode.value, TapeMode.daylight);
    });

    test('is held between 2,000 and 5,000', () {
      light(6000, 12);
      light(3000, 60);

      expect(controller.mode.value, TapeMode.daylight);
    });

    test('is left after 10 s below 2,000', () {
      light(6000, 12);
      light(1500, 9);
      expect(controller.mode.value, TapeMode.daylight);

      light(1500, 2);
      expect(controller.mode.value, TapeMode.normal);
    });
  });

  group('Night', () {
    test('needs 10 s below 20 lux', () {
      light(5, 9);
      expect(controller.mode.value, TapeMode.normal);

      light(5, 2);
      expect(controller.mode.value, TapeMode.night);
    });

    test('is held between 20 and 60 lux', () {
      light(5, 12);
      light(40, 60);

      expect(controller.mode.value, TapeMode.night);
    });

    test('is left after 10 s above 60 lux', () {
      light(5, 12);
      light(100, 9);
      expect(controller.mode.value, TapeMode.night);

      light(100, 2);
      expect(controller.mode.value, TapeMode.normal);
    });

    test('a street light does not end it', () {
      light(5, 12);
      light(200, 5);
      light(5, 3);
      light(200, 5);

      expect(controller.mode.value, TapeMode.night);
    });
  });

  test('a tunnel: from Daylight straight to Night', () {
    light(8000, 12);
    expect(controller.mode.value, TapeMode.daylight);

    light(1, 12);
    expect(controller.mode.value, TapeMode.night);
  });

  test('a burst of light from Night can go straight to Daylight', () {
    light(1, 12);
    light(9000, 12);

    expect(controller.mode.value, TapeMode.daylight);
  });

  test('a reading that is not a number is ignored', () {
    light(6000, 5);
    controller.onLux(double.nan);
    light(6000, 6);

    expect(controller.mode.value, TapeMode.daylight);
  });

  group('the setting', () {
    test('a fixed mode holds whatever the light does', () {
      controller.setting = ModeSetting.night;
      light(9000, 60);

      expect(controller.mode.value, TapeMode.night);
    });

    test('auto picks up from what the light said meanwhile', () {
      controller.setting = ModeSetting.night;
      light(9000, 60);

      controller.setting = ModeSetting.auto;
      expect(controller.mode.value, TapeMode.daylight);
    });

    test('the mode is announced when it changes, and not otherwise', () {
      final seen = <TapeMode>[];
      controller.mode.addListener(() => seen.add(controller.mode.value));

      light(6000, 12);
      light(6000, 30);
      light(1000, 12);

      expect(seen, [TapeMode.daylight, TapeMode.normal]);
    });

    test('starts in a fixed mode if it is given one', () {
      final fixed = ModeController(clock: clock, setting: ModeSetting.daylight);

      expect(fixed.mode.value, TapeMode.daylight);
      expect(ModeSetting.auto.fixed, isNull);
    });
  });

  group('screen brightness', () {
    test('Daylight is at maximum', () {
      expect(ScreenBrightness.forMode(TapeMode.daylight, 20000), 1);
    });

    test('normal is left to the phone', () {
      expect(ScreenBrightness.forMode(TapeMode.normal, 300), isNull);
    });

    test('Night follows the light from a 12% floor', () {
      expect(ScreenBrightness.forMode(TapeMode.night, 0), 0.12);
      expect(ScreenBrightness.forMode(TapeMode.night, null), 0.12);

      var last = 0.12;
      for (final lux in [1.0, 5.0, 10.0, 20.0, 40.0, 60.0]) {
        final b = ScreenBrightness.forMode(TapeMode.night, lux)!;
        expect(b, greaterThan(last), reason: '$lux lux');
        last = b;
      }
      expect(last, closeTo(ScreenBrightness.nightCeiling, 1e-9));
    });

    test('Night never goes below the floor, and never above its ceiling', () {
      for (final lux in [-5.0, 0.0, 1000.0, 1e9]) {
        expect(
          ScreenBrightness.forMode(TapeMode.night, lux),
          inInclusiveRange(0.12, ScreenBrightness.nightCeiling),
        );
      }
    });

    test('the HUD keeps a 20% floor at night', () {
      expect(
        ScreenBrightness.forMode(
          TapeMode.night,
          0,
          floor: ScreenBrightness.hudNightFloor,
        ),
        0.20,
      );
    });
  });
}

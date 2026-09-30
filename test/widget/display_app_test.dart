// The display wired into the app: the light sensor drives Daylight and Night in the
// theme and the screen's brightness, and a hot phone shows its glyph, dims, and
// drops to Lite at 30 fps.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/platform/device_features.dart';
import 'package:tapedash/platform/fake_device_features.dart';
import 'package:tapedash/ui/design/fidelity/fidelity_tier.dart';
import 'package:tapedash/ui/design/motion/motion_scope.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/design/theme/mode_controller.dart' show ModeSetting;
import 'package:tapedash/ui/design/theme/palette.dart' show TapeMode;
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => TapeFonts.load());

  late AppServices app;
  late FakeClock clock;
  late FakeDeviceFeatures device;

  setUp(() async {
    app = await AppServices.memory();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    device = FakeDeviceFeatures();
  });

  tearDown(() => device.dispose());

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TapeDashApp(
        clock: clock,
        scheduler: clock,
        onboarding: false,
        services: app,
        device: device,
        scenario: 'cold_start_idle',
      ),
    );
  }

  Future<void> run(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 100) {
      clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  BuildContext context(WidgetTester tester) =>
      tester.element(find.byType(DrivePage));

  testWidgets('sun for ten seconds is Daylight, at full brightness', (
    tester,
  ) async {
    await boot(tester);
    await run(tester, 500);
    expect(TapeTheme.of(context(tester)).mode, TapeMode.normal);

    for (var i = 0; i < 14; i++) {
      device.emitLux(9000);
      await run(tester, 1000);
    }
    expect(TapeTheme.of(context(tester)).mode, TapeMode.daylight);
    expect(device.brightness, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a held mode in Garage wins over the light', (tester) async {
    await boot(tester);
    await run(tester, 500);
    app.settings.modeSetting.value = ModeSetting.night;
    await run(tester, 300);
    expect(TapeTheme.of(context(tester)).mode, TapeMode.night);
    device.emitLux(9000);
    await run(tester, 12000);
    expect(TapeTheme.of(context(tester)).mode, TapeMode.night);
  });

  testWidgets(
    'a hot phone: the glyph, then Lite at 30 fps and a dimmer screen',
    (tester) async {
      device.batteryTemperature = 46;
      await boot(tester);
      await run(tester, 500);
      final drive = tester.widget<DrivePage>(find.byType(DrivePage));
      expect(drive.signals.phoneHot.value, isTrue);
      expect(TapeTheme.of(context(tester)).tier, FidelityTier.balanced);

      device.batteryTemperature = 52;
      await run(tester, 31000);
      expect(TapeTheme.of(context(tester)).tier, FidelityTier.lite);
      expect(MotionScope.of(context(tester)).maxFps, 30);
      expect(device.brightness, lessThanOrEqualTo(0.5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a phone with no sensors carries on as it is', (tester) async {
    device.support = const SensorSupport(
      ambientLight: false,
      accelerometer: false,
    );
    device.batteryTemperature = null;
    await boot(tester);
    await run(tester, 15000);
    expect(TapeTheme.of(context(tester)).mode, TapeMode.normal);
    expect(TapeTheme.of(context(tester)).tier, FidelityTier.balanced);
  });
}

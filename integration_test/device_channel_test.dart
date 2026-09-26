// DeviceChannel against the real Android side (DeviceChannel.kt), on an
// emulator or a phone: CLAUDE.md 10, layer 5.
//
//   flutter test integration_test/device_channel_test.dart -d <device>
//
// An emulator has no real sensors, so these check that the plumbing works and
// that readings are plausible. They cannot say whether a particular phone's
// sensors behave; that waits for the hardware handoff (CLAUDE.md 11).
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapedash/platform/device_channel.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final device = DeviceChannel();

  testWidgets('every screen call completes', (tester) async {
    await device.setKeepScreenOn(true);
    await device.setImmersive(true);
    await device.setBrightness(0.5);
    await device.setBrightness(3); // clamped to 1
    await device.setBrightness(0); // the Android side keeps a floor
    await device.setBrightness(null); // back to the phone's own setting
    await device.setImmersive(false);
    await device.setKeepScreenOn(false);
  });

  testWidgets('the battery temperature is plausible', (tester) async {
    final celsius = await device.batteryTemperatureCelsius();

    expect(celsius, isNotNull);
    expect(celsius, inInclusiveRange(-20, 100));
    debugPrint('battery temperature: $celsius C');
  });

  testWidgets('sensor support is reported', (tester) async {
    final support = await device.sensorSupport();

    debugPrint('sensor support: $support');
    expect(support, isNotNull);
  });

  testWidgets('an unknown method is not implemented', (tester) async {
    await expectLater(
      const MethodChannel('tapedash/device').invokeMethod<void>('nope'),
      throwsA(isA<MissingPluginException>()),
    );
  });

  testWidgets('a bad argument is an error, not a crash', (tester) async {
    await expectLater(
      const MethodChannel(
        'tapedash/device',
      ).invokeMethod<void>('setKeepScreenOn', {'enabled': 'yes'}),
      throwsA(isA<PlatformException>()),
    );
  });

  testWidgets('acceleration reads about one g at rest', (tester) async {
    final support = await device.sensorSupport();
    if (!support.accelerometer) {
      await expectLater(
        device.acceleration.first,
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
      return;
    }

    final reading = await device.acceleration.first.timeout(
      const Duration(seconds: 10),
    );
    final magnitude = sqrt(
      reading.x * reading.x + reading.y * reading.y + reading.z * reading.z,
    );

    debugPrint('acceleration: $reading, magnitude $magnitude');
    expect(magnitude, closeTo(9.81, 1.5));
  });

  testWidgets('two listeners each get the accelerometer', (tester) async {
    final support = await device.sensorSupport();
    if (!support.accelerometer) return;

    final first = device.acceleration.first.timeout(
      const Duration(seconds: 10),
    );
    final second = device.acceleration.first.timeout(
      const Duration(seconds: 10),
    );

    expect((await first).z, isNotNaN);
    expect((await second).z, isNotNaN);
  });

  testWidgets('the accelerometer can be started again after it stops', (
    tester,
  ) async {
    final support = await device.sensorSupport();
    if (!support.accelerometer) return;

    for (var i = 0; i < 3; i++) {
      final reading = await device.acceleration.first.timeout(
        const Duration(seconds: 10),
      );
      expect(reading.z, isNotNaN, reason: 'round $i');
    }
  });

  testWidgets('ambient light is a reading or a clear error', (tester) async {
    final support = await device.sensorSupport();
    if (!support.ambientLight) {
      await expectLater(
        device.ambientLux.first,
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
      return;
    }

    // A light sensor reports on change, so an emulator may be silent until its
    // value is changed by hand. Report which happened rather than guessing.
    final lux = await device.ambientLux.first.timeout(
      const Duration(seconds: 5),
      onTimeout: () => double.nan,
    );
    debugPrint(
      'ambient light: ${lux.isNaN ? 'no reading within 5 s' : '$lux lux'}',
    );
    if (!lux.isNaN) expect(lux, greaterThanOrEqualTo(0));
  });
}

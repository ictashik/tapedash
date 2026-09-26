import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/platform/device_features.dart';
import 'package:tapedash/platform/fake_device_features.dart';

void main() {
  test('remembers the screen settings it is given', () async {
    final device = FakeDeviceFeatures();

    await device.setKeepScreenOn(true);
    await device.setImmersive(true);
    await device.setBrightness(0.4);

    expect(device.keepScreenOn, isTrue);
    expect(device.immersive, isTrue);
    expect(device.brightness, 0.4);

    await device.setBrightness(null);
    expect(device.brightness, isNull);
  });

  test('clamps brightness like the real channel, and rejects NaN', () async {
    final device = FakeDeviceFeatures();

    await device.setBrightness(3);
    expect(device.brightness, 1.0);

    await device.setBrightness(-1);
    expect(device.brightness, 0.0);

    expect(() => device.setBrightness(double.nan), throwsArgumentError);
  });

  test('reports the configured temperature and sensors', () async {
    final device = FakeDeviceFeatures()
      ..batteryTemperature = 47.5
      ..support = const SensorSupport(ambientLight: false, accelerometer: true);

    expect(await device.batteryTemperatureCelsius(), 47.5);
    expect(
      await device.sensorSupport(),
      const SensorSupport(ambientLight: false, accelerometer: true),
    );

    device.batteryTemperature = null;
    expect(await device.batteryTemperatureCelsius(), isNull);
  });

  test(
    'its sensors emit what is pushed into them, to any number of listeners',
    () async {
      final device = FakeDeviceFeatures();
      final lux = <double>[];
      final acceleration = <Acceleration>[];
      device.ambientLux.listen(lux.add);
      device.ambientLux.listen(lux.add);
      device.acceleration.listen(acceleration.add);

      device
        ..emitLux(5000)
        ..emitAcceleration(const Acceleration(0, 9.8, 0));
      await Future<void>.delayed(Duration.zero);

      expect(lux, [5000, 5000]);
      expect(acceleration, [const Acceleration(0, 9.8, 0)]);
    },
  );

  test('dispose ends the sensor streams', () async {
    final device = FakeDeviceFeatures();
    final done = device.ambientLux.toList();

    await device.dispose();

    expect(await done, isEmpty);
  });
}

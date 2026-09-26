// DeviceChannel against mocked platform channels. The Android side
// (DeviceChannel.kt) is not exercised here; see docs/STATUS.md for what has and
// has not been verified on a device.
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/platform/device_channel.dart';
import 'package:tapedash/platform/device_features.dart';

const _methods = MethodChannel('tapedash/device');
const _light = EventChannel('tapedash/device/light');
const _acceleration = EventChannel('tapedash/device/acceleration');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Object? Function(MethodCall call) reply;

  setUp(() {
    calls = [];
    reply = (_) => null;
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      return reply(call);
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_methods, null);
      messenger.setMockStreamHandler(_light, null);
      messenger.setMockStreamHandler(_acceleration, null);
    });
  });

  group('screen', () {
    test('setKeepScreenOn sends the flag', () async {
      final device = DeviceChannel();

      await device.setKeepScreenOn(true);
      await device.setKeepScreenOn(false);

      expect(calls.map((c) => c.method), [
        'setKeepScreenOn',
        'setKeepScreenOn',
      ]);
      expect(calls.map((c) => c.arguments), [
        {'enabled': true},
        {'enabled': false},
      ]);
    });

    test('setImmersive sends the flag', () async {
      final device = DeviceChannel();

      await device.setImmersive(true);

      expect(calls.single.method, 'setImmersive');
      expect(calls.single.arguments, {'enabled': true});
    });

    test(
      'setBrightness sends the level, and null for the phone\'s own',
      () async {
        final device = DeviceChannel();

        await device.setBrightness(0.5);
        await device.setBrightness(null);

        expect(calls.map((c) => c.method), ['setBrightness', 'setBrightness']);
        expect(calls.map((c) => c.arguments), [
          {'level': 0.5},
          {'level': null},
        ]);
      },
    );

    test('setBrightness clamps to 0..1', () async {
      final device = DeviceChannel();

      for (final level in [
        1.7,
        -0.2,
        double.infinity,
        double.negativeInfinity,
      ]) {
        await device.setBrightness(level);
      }

      expect(
        calls.map((c) => (c.arguments as Map<Object?, Object?>)['level']),
        [1.0, 0.0, 1.0, 0.0],
      );
    });

    test('setBrightness sends a double even for a whole number', () async {
      await DeviceChannel().setBrightness(1);

      expect(
        (calls.single.arguments as Map<Object?, Object?>)['level'],
        isA<double>(),
      );
    });

    test('setBrightness rejects NaN without calling the platform', () {
      expect(
        () => DeviceChannel().setBrightness(double.nan),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test('a platform error reaches the caller', () async {
      reply = (_) => throw PlatformException(code: 'no_window');

      await expectLater(
        DeviceChannel().setImmersive(true),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'no_window'),
        ),
      );
    });
  });

  group('batteryTemperatureCelsius', () {
    test('is what the platform reports', () async {
      reply = (_) => 31.5;

      expect(await DeviceChannel().batteryTemperatureCelsius(), 31.5);
      expect(calls.single.method, 'batteryTemperature');
    });

    test('accepts a whole number', () async {
      reply = (_) => 31;

      expect(await DeviceChannel().batteryTemperatureCelsius(), 31.0);
    });

    test('is null when the phone does not report one', () async {
      reply = (_) => null;

      expect(await DeviceChannel().batteryTemperatureCelsius(), isNull);
    });
  });

  group('sensorSupport', () {
    test('reads both flags', () async {
      reply = (_) => {'ambientLight': true, 'accelerometer': false};

      expect(
        await DeviceChannel().sensorSupport(),
        const SensorSupport(ambientLight: true, accelerometer: false),
      );
      expect(calls.single.method, 'sensorSupport');
    });

    test('treats a missing answer or missing keys as no sensor', () async {
      const none = SensorSupport(ambientLight: false, accelerometer: false);

      reply = (_) => null;
      expect(await DeviceChannel().sensorSupport(), none);

      reply = (_) => <String, Object?>{};
      expect(await DeviceChannel().sensorSupport(), none);
    });
  });

  group('ambientLux', () {
    test('emits lux as doubles', () async {
      messenger.setMockStreamHandler(
        _light,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(120.5);
            events.success(50); // the codec may hand over a whole number
            events.endOfStream();
          },
        ),
      );

      expect(await DeviceChannel().ambientLux.toList(), [120.5, 50.0]);
    });

    test('is one shared stream', () {
      final device = DeviceChannel();

      expect(identical(device.ambientLux, device.ambientLux), isTrue);
    });

    test(
      'listeners share a single native listener, which stops with the last',
      () async {
        var listens = 0;
        var cancels = 0;
        messenger.setMockStreamHandler(
          _light,
          MockStreamHandler.inline(
            onListen: (arguments, events) => listens++,
            onCancel: (arguments) => cancels++,
          ),
        );
        final device = DeviceChannel();

        final first = device.ambientLux.listen((_) {});
        final second = device.ambientLux.listen((_) {});
        await Future<void>.delayed(Duration.zero);
        expect(listens, 1);

        await first.cancel();
        await Future<void>.delayed(Duration.zero);
        expect(cancels, 0, reason: 'a listener is still there');

        await second.cancel();
        await Future<void>.delayed(Duration.zero);
        expect(cancels, 1);
      },
    );

    test('a phone without the sensor is an error, then the end', () async {
      messenger.setMockStreamHandler(
        _light,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.error(code: 'unavailable', message: 'No such sensor');
            events.endOfStream();
          },
        ),
      );
      final seen = <Object>[];

      await DeviceChannel().ambientLux.handleError(seen.add).toList();

      expect(
        seen.single,
        isA<PlatformException>().having((e) => e.code, 'code', 'unavailable'),
      );
    });
  });

  group('acceleration', () {
    test('emits x, y and z', () async {
      messenger.setMockStreamHandler(
        _acceleration,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(Float64List.fromList([0.1, 9.81, -0.2]));
            events.success(<Object?>[1, 2, 3]);
            events.endOfStream();
          },
        ),
      );

      expect(await DeviceChannel().acceleration.toList(), [
        const Acceleration(0.1, 9.81, -0.2),
        const Acceleration(1, 2, 3),
      ]);
    });

    test('a reading without exactly three values is an error', () async {
      messenger.setMockStreamHandler(
        _acceleration,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(Float64List.fromList([1, 2]));
            events.success(Float64List.fromList([1, 2, 3]));
            events.endOfStream();
          },
        ),
      );
      final errors = <Object>[];

      final readings = await DeviceChannel().acceleration
          .handleError(errors.add)
          .toList();

      expect(errors.single, isA<FormatException>());
      expect(readings, [const Acceleration(1, 2, 3)]);
    });

    test('is one shared stream, separate from the light stream', () {
      final device = DeviceChannel();

      expect(identical(device.acceleration, device.acceleration), isTrue);
      expect(identical(device.acceleration, device.ambientLux), isFalse);
    });
  });

  group('value types', () {
    test('Acceleration and SensorSupport compare by value', () {
      expect(const Acceleration(1, 2, 3), const Acceleration(1, 2, 3));
      expect(const Acceleration(1, 2, 3), isNot(const Acceleration(1, 2, 4)));
      expect(
        const SensorSupport(ambientLight: true, accelerometer: false),
        const SensorSupport(ambientLight: true, accelerometer: false),
      );
      expect(
        const SensorSupport(ambientLight: true, accelerometer: false),
        isNot(const SensorSupport(ambientLight: false, accelerometer: false)),
      );
    });
  });
}

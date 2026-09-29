// NativeLocationSource against mocked platform channels. The Android side
// (GpsChannel.kt) is not exercised here; see docs/STATUS.md for what has and has
// not been verified on a device.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/platform/native_location_source.dart';

const _methods = MethodChannel('tapedash/gps');
const _events = EventChannel('tapedash/gps/fixes');

Map<String, Object?> message({
  double lat = 12.9716,
  double lon = 77.5946,
  Object? speed = 8.3,
  Object? bearing = 90.0,
  Object? accuracy = 4.5,
  int time = 1750000000000,
}) => {
  'latitude': lat,
  'longitude': lon,
  'speed': speed,
  'bearing': bearing,
  'altitude': 920.0,
  'accuracy': accuracy,
  'timeMillis': time,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Object? Function(MethodCall call) reply;
  MockStreamHandlerEventSink? sink;

  setUp(() {
    calls = [];
    sink = null;
    reply = (call) => switch (call.method) {
      'requestPermission' || 'hasPermission' || 'isEnabled' => true,
      _ => null,
    };
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      return reply(call);
    });
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (arguments, events) => sink = events,
        onCancel: (arguments) => sink = null,
      ),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(_methods, null);
      messenger.setMockStreamHandler(_events, null);
    });
  });

  group('fixFrom', () {
    test('reads every field', () {
      final fix = NativeLocationSource.fixFrom(message())!;
      expect(fix.latitude, 12.9716);
      expect(fix.longitude, 77.5946);
      expect(fix.speedMs, 8.3);
      expect(fix.headingDegrees, 90);
      expect(fix.altitudeM, 920);
      expect(fix.accuracyM, 4.5);
      expect(fix.time.millisecondsSinceEpoch, 1750000000000);
    });

    test('a bearing that is not known stays null', () {
      expect(
        NativeLocationSource.fixFrom(message(bearing: null))!.headingDegrees,
        isNull,
      );
    });

    test(
      'no speed is 0 m/s, and no accuracy is a bad one, not a perfect one',
      () {
        final fix = NativeLocationSource.fixFrom(
          message(speed: -1.0, accuracy: -1.0),
        )!;
        expect(fix.speedMs, 0);
        expect(fix.accuracyM, greaterThan(100));
      },
    );

    test('integers from the platform are read as numbers', () {
      final fix = NativeLocationSource.fixFrom(message(speed: 8, accuracy: 5))!;
      expect(fix.speedMs, 8);
      expect(fix.accuracyM, 5);
    });

    test('anything malformed is dropped, not thrown', () {
      expect(NativeLocationSource.fixFrom(null), isNull);
      expect(NativeLocationSource.fixFrom('nope'), isNull);
      expect(NativeLocationSource.fixFrom({'latitude': 1}), isNull);
      expect(
        NativeLocationSource.fixFrom({...message(), 'latitude': 'x'}),
        isNull,
      );
    });
  });

  group('permission', () {
    test(
      'hasPermission, requestPermission and isEnabled ask the platform',
      () async {
        final gps = NativeLocationSource();
        expect(await gps.hasPermission(), isTrue);
        expect(await gps.requestPermission(), isTrue);
        expect(await gps.isEnabled(), isTrue);
        expect(
          [for (final c in calls) c.method],
          ['hasPermission', 'requestPermission', 'isEnabled'],
        );
      },
    );

    test(
      'a refused permission stops start and leaves it not running',
      () async {
        reply = (call) => call.method == 'requestPermission' ? false : null;
        final gps = NativeLocationSource();
        await expectLater(
          gps.start(),
          throwsA(isA<LocationPermissionException>()),
        );
        expect(gps.isRunning, isFalse);
        expect(calls.map((c) => c.method), isNot(contains('start')));
      },
    );

    test(
      'a permission taken away while starting is the same refusal',
      () async {
        reply = (call) {
          if (call.method == 'start') {
            throw PlatformException(code: 'permission_denied');
          }
          return true;
        };
        final gps = NativeLocationSource();
        await expectLater(
          gps.start(),
          throwsA(isA<LocationPermissionException>()),
        );
        expect(gps.isRunning, isFalse);
      },
    );
  });

  group('running', () {
    test(
      'start asks for the permission, then starts, and fixes flow',
      () async {
        final gps = NativeLocationSource();
        final fixes = <double>[];
        gps.fixes.listen((f) => fixes.add(f.speedMs));

        await gps.start();
        expect(gps.isRunning, isTrue);
        expect(
          [for (final c in calls) c.method],
          ['requestPermission', 'start'],
        );

        sink!.success(message(speed: 5.0));
        sink!.success(message(speed: 6.0));
        sink!.success('garbage');
        sink!.success(message(speed: 7.0));
        await Future<void>.delayed(Duration.zero);
        expect(fixes, [5, 6, 7]);
      },
    );

    test('start twice starts once', () async {
      final gps = NativeLocationSource();
      await gps.start();
      await gps.start();
      expect(calls.where((c) => c.method == 'start').length, 1);
    });

    test('stop tells the platform and ends the stream', () async {
      final gps = NativeLocationSource();
      await gps.start();
      await gps.stop();
      expect(gps.isRunning, isFalse);
      expect(calls.last.method, 'stop');
      expect(sink, isNull);
      await gps.stop(); // safe when stopped.
    });

    test('a stream error means the receiver has gone', () async {
      final gps = NativeLocationSource();
      await gps.start();
      sink!.error(code: 'gone');
      await Future<void>.delayed(Duration.zero);
      expect(gps.isRunning, isFalse);
    });
  });
}

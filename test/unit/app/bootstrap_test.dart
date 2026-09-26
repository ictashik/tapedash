import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/bootstrap.dart';
import 'package:tapedash/platform/fake_device_features.dart';

/// A device on which the chosen steps fail the way the platform can fail.
class _FailingDevice extends FakeDeviceFeatures {
  _FailingDevice({
    this.failImmersive = false,
    this.failKeepScreenOn = false,
    this.pluginMissing = false,
  });

  final bool failImmersive;
  final bool failKeepScreenOn;
  final bool pluginMissing;

  Exception _error() => pluginMissing
      ? MissingPluginException('no channel')
      : PlatformException(code: 'no_window');

  @override
  Future<void> setImmersive(bool enabled) async {
    if (failImmersive) throw _error();
    await super.setImmersive(enabled);
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) async {
    if (failKeepScreenOn) throw _error();
    await super.setKeepScreenOn(enabled);
  }
}

/// A bug and not a platform failure, so it has to surface.
class _BuggyDevice extends FakeDeviceFeatures {
  @override
  Future<void> setImmersive(bool enabled) async => throw StateError('bug');
}

void main() {
  test('hides the system bars and keeps the screen on', () async {
    final device = FakeDeviceFeatures();

    await configureWindow(device);

    expect(device.immersive, isTrue);
    expect(device.keepScreenOn, isTrue);
  });

  test('still keeps the screen on when hiding the bars fails', () async {
    final device = _FailingDevice(failImmersive: true);

    await configureWindow(device);

    expect(device.immersive, isFalse);
    expect(device.keepScreenOn, isTrue);
  });

  test('still hides the bars when keeping the screen on fails', () async {
    final device = _FailingDevice(failKeepScreenOn: true);

    await configureWindow(device);

    expect(device.immersive, isTrue);
    expect(device.keepScreenOn, isFalse);
  });

  test('does not throw when the platform side is missing', () async {
    final device = _FailingDevice(
      failImmersive: true,
      failKeepScreenOn: true,
      pluginMissing: true,
    );

    await expectLater(configureWindow(device), completes);
  });

  test('does not hide other kinds of failure', () async {
    await expectLater(configureWindow(_BuggyDevice()), throwsStateError);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/device_features.dart';

/// Puts the window the way a dashboard needs it: system bars hidden and the
/// screen kept on.
///
/// Neither can be allowed to stop the app. If the bars stay visible or the
/// screen may time out, that is a flaw and not a reason to show nothing, so a
/// failure is logged and the app starts anyway.
Future<void> configureWindow(DeviceFeatures device) async {
  await _attempt('hide the system bars', () => device.setImmersive(true));
  await _attempt('keep the screen on', () => device.setKeepScreenOn(true));
}

Future<void> _attempt(String what, Future<void> Function() action) async {
  try {
    await action();
  } on PlatformException catch (error) {
    debugPrint('Could not $what: $error');
  } on MissingPluginException catch (error) {
    debugPrint('Could not $what: $error');
  }
}

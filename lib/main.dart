import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'app/bootstrap.dart';
import 'platform/device_channel.dart';
import 'ui/design/render/tape_fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final device = DeviceChannel();
  await configureWindow(device);
  // Awaited before the first frame, so the cold open never shows in a fallback
  // face (DESIGN.md 4.5). A failure here is not a reason to show nothing: the
  // bootstrap log already covers that pattern for the window setup, and the
  // fonts follow it, since a launch with no numerals at all is worse than one
  // in the system font for a moment.
  try {
    await TapeFonts.load();
  } on Object catch (error) {
    debugPrint('Could not load the bundled fonts: $error');
  }
  // The trip log and the settings, on the phone. A failure to open them is not
  // a reason to show nothing: the app then runs with empty in-memory ones and
  // says so in the log.
  AppServices? services;
  try {
    services = await AppServices.open();
  } on Object catch (error) {
    debugPrint('Could not open the trip log and settings: $error');
  }
  runApp(TapeDashApp(services: services, device: device));
}

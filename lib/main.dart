import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'platform/device_channel.dart';
import 'ui/design/render/tape_fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureWindow(DeviceChannel());
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
  runApp(const TapeDashApp());
}

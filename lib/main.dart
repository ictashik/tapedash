import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'platform/device_channel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureWindow(DeviceChannel());
  runApp(const TapeDashApp());
}

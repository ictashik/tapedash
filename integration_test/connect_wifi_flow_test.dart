// The whole connect path on a real Android, to the simulator over WiFi: the cold
// open, CONNECT MY CAR, WiFi at 10.0.2.2, the car, the price, the layout, and then
// the drive screen showing the simulated car through the real transport, the real
// settings store and the real trip log.
//
//   dart run tool/sim_server.dart --port 35000 --scenario city_stop_go
//   flutter test integration_test/connect_wifi_flow_test.dart -d emulator-5554
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapedash/main.dart' as app;
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';

import 'sim_connect.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'connecting a WiFi adapter from first launch to live values',
    (tester) async {
      await app.main();
      await connectToSimulator(tester);

      final drive = tester.widget<DrivePage>(find.byType(DrivePage));
      await until(
        tester,
        () => drive.signals.connection.value == ConnectionStatus.connected,
        'the adapter to connect',
      );
      await until(
        tester,
        () => drive.signals.vehicle.rpm.value != null,
        'live values',
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

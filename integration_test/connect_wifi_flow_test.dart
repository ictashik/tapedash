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
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/components/controls/tape_numpad.dart';
import 'package:tapedash/ui/design/icons/icons.dart';
import 'package:tapedash/ui/onboarding/connect_flow.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'connecting a WiFi adapter from first launch to live values',
    (tester) async {
      await app.main();

      Future<void> until(
        bool Function() done,
        String what, {
        int seconds = 40,
      }) async {
        for (var i = 0; i < seconds * 10; i++) {
          if (done()) return;
          await tester.pump(const Duration(milliseconds: 100));
        }
        fail('timed out waiting for $what');
      }

      // The buttons are there while the cold open is still playing; the choice is
      // made once it is ready.
      final connect = find.widgetWithText(TapeButton, 'CONNECT MY CAR');
      await until(
        () =>
            connect.evaluate().isNotEmpty &&
            tester.widget<TapeButton>(connect).enabled,
        'the choice after the cold open',
      );
      await tester.tap(find.text('CONNECT MY CAR'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(ConnectFlow), findsOneWidget);

      await tester.tap(find.text('WiFi'));
      await tester.pump(const Duration(milliseconds: 400));

      // The address: clear the usual one and type the emulator's host.
      final back = find.descendant(
        of: find.byType(TapeNumpad),
        matching: find.byType(TapeIconView),
      );
      for (var i = 0; i < 14; i++) {
        await tester.tap(back);
        await tester.pump(const Duration(milliseconds: 30));
      }
      for (final k in '10.0.2.2'.split('')) {
        await tester.tap(
          find.descendant(of: find.byType(TapeNumpad), matching: find.text(k)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.text('10.0.2.2'), findsOneWidget);

      await tester.tap(find.text('TEST'));
      await until(
        () => find.text('The adapter answered.').evaluate().isNotEmpty,
        'the test to answer (is tool/sim_server.dart running on the host?)',
        seconds: 15,
      );

      await tester.tap(find.text('NEXT'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('NEXT')); // the car, as it is
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('SKIP')); // no price yet
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('START DRIVING'));

      await until(
        () => find.byType(DrivePage).evaluate().isNotEmpty,
        'the drive screen',
      );
      final drive = tester.widget<DrivePage>(find.byType(DrivePage));
      expect(drive.signals.demoMode, isFalse, reason: 'this is the adapter');
      await until(
        () => drive.signals.connection.value == ConnectionStatus.connected,
        'the adapter to connect',
      );
      await until(() => drive.signals.vehicle.rpm.value != null, 'live values');
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

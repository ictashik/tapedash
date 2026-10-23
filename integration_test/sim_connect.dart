// The connect path to the simulator over WiFi, for the integration tests that need
// a car on a real Android without a real car (CLAUDE.md 10, layer 5): the cold open,
// CONNECT MY CAR, WiFi at the emulator's host (10.0.2.2), the car, the price and the
// layout, and then the drive screen on the simulated car.
//
//   dart run tool/sim_server.dart --port 35000 --scenario city_stop_go
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/components/controls/tape_numpad.dart';
import 'package:tapedash/ui/design/icons/icons.dart';
import 'package:tapedash/ui/onboarding/connect_flow.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';

/// Pumps until [done], or fails naming [what] after [seconds].
Future<void> until(
  WidgetTester tester,
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

/// From first launch to the drive screen, on `tool/sim_server.dart` at [host].
Future<void> connectToSimulator(
  WidgetTester tester, {
  String host = '10.0.2.2',
}) async {
  // The buttons are there while the cold open is still playing; the choice is
  // made once it is ready.
  final connect = find.widgetWithText(TapeButton, 'CONNECT MY CAR');
  await until(
    tester,
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

  // The address: clear the usual one and type the host.
  final back = find.descendant(
    of: find.byType(TapeNumpad),
    matching: find.byType(TapeIconView),
  );
  for (var i = 0; i < 14; i++) {
    await tester.tap(back);
    await tester.pump(const Duration(milliseconds: 30));
  }
  for (final k in host.split('')) {
    await tester.tap(
      find.descendant(of: find.byType(TapeNumpad), matching: find.text(k)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(find.text(host), findsOneWidget);

  await tester.tap(find.text('TEST'));
  await until(
    tester,
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
    tester,
    () => find.byType(DrivePage).evaluate().isNotEmpty,
    'the drive screen',
  );
}

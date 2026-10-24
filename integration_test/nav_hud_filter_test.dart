// Only Google Maps' navigation notification is a turn (docs/NAV.md), on a real
// Android: another notification of Maps' (a traffic alert) must not take the HUD
// over, must not change the turn while one is up, and its going away must not end
// the navigation. The stand-in is posted from inside the app (the debug build's
// `tapedash/nav/standin` channel), so nothing here needs adb or a moving car.
//
//   adb shell pm clear io.github.ictashik.tapedash        # a first launch
//   tool/nav_spike.sh enable                              # notification access
//   dart run tool/sim_server.dart --port 35000 --scenario city_stop_go
//   flutter test integration_test/nav_hud_filter_test.dart -d <device>
//
// or all of it: tool/test_nav_e2e.sh.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapedash/app/drive_shell.dart';
import 'package:tapedash/app/nav_service.dart';
import 'package:tapedash/main.dart' as app;
import 'package:tapedash/ui/hud/nav_hud.dart';

import 'sim_connect.dart';

const _standIn = MethodChannel('tapedash/nav/standin');

Future<void> _post(Map<String, Object?> extras) =>
    _standIn.invokeMethod<void>('post', extras);

/// Lets the notification be posted, heard by the listener and carried to the HUD.
Future<void> _settle(WidgetTester tester, {int seconds = 3}) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('only the navigation notification is a turn', (tester) async {
    await app.main();
    await connectToSimulator(tester);
    await tester.pump(const Duration(milliseconds: 500));

    final settings = tester
        .widget<DriveShell>(find.byType(DriveShell))
        .app!
        .settings;
    settings.navEnabled.value = true;
    settings.hud.active = true;
    await _settle(tester, seconds: 2);

    // Another of Maps' notifications: a title and an ETA, and not navigation.
    await _post({
      'id': 4712,
      'category': 'none',
      'title': 'Heavy traffic on your commute',
      'sub': 'Arrive 9:25 PM',
    });
    await _settle(tester);
    expect(
      find.byType(NavHud),
      findsNothing,
      reason: 'a traffic alert is not a turn',
    );

    // The navigation notification.
    await _post({
      'title': '300 m · Turn left onto MG Road',
      'short': '300 m',
      'sub': 'Arrive 3:45 PM',
      'progress': 100,
      'max': 5000,
      'arrow': 'left',
    });
    await _settle(tester);
    expect(find.byType(NavHud), findsOneWidget);
    NavService nav() => tester.widget<NavHud>(find.byType(NavHud)).nav;
    expect(nav().tracker.state.value.instruction, 'Turn left onto MG Road');
    expect(nav().tracker.state.value.distanceText, '300 m');

    // The traffic alert changes: the turn does not.
    await _post({
      'id': 4712,
      'category': 'none',
      'title': 'Something else entirely',
      'sub': 'Arrive 11:11 PM',
    });
    await _settle(tester, seconds: 2);
    expect(nav().tracker.state.value.instruction, 'Turn left onto MG Road');
    expect(nav().tracker.state.value.etaText, '3:45 PM');

    // The traffic alert goes away: the navigation goes on.
    await _post({'id': 4712, 'remove': true});
    await _settle(tester, seconds: 2);
    expect(
      find.byType(NavHud),
      findsOneWidget,
      reason: 'another notification going away is not the end of the route',
    );
    expect(nav().status.value, NavLinkStatus.guiding);

    // The navigation notification goes: the HUD goes back to the chosen layout.
    await _post({'remove': true});
    await _settle(tester);
    expect(find.byType(NavHud), findsNothing);

    expect(tester.takeException(), isNull);
  });
}

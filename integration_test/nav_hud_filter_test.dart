// Only Google Maps' navigation notification is a turn (docs/NAV.md), on a real
// Android: another notification of Maps' (a traffic alert) must not take the HUD
// over, must not change the turn while one is up, and its going away must not end
// the navigation. The stand-in is posted from inside the app (the debug build's
// `tapedash/nav/standin` channel), so nothing here needs adb or a moving car.
//
// Nothing here waits a fixed time for something NOT to happen, which would pass on a
// slow device by being too early. After each case a marker notification is posted
// and waited for: the phone hands notifications to the listener in order, so when the
// marker has arrived everything before it has been heard, and nothing wrong may have
// shown in between.
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
import 'package:tapedash/nav/nav_state.dart';
import 'package:tapedash/ui/hud/nav_hud.dart';

import 'sim_connect.dart';

const _standIn = MethodChannel('tapedash/nav/standin');

Future<void> _post(Map<String, Object?> extras) =>
    _standIn.invokeMethod<void>('post', extras);

/// The navigation notification, as Maps would post it, with [distance] to the turn.
Map<String, Object?> _turn(String distance) => {
  'title': '$distance · Turn left onto MG Road',
  'short': distance,
  'sub': 'Arrive 3:45 PM',
  'progress': 100,
  'max': 5000,
  'arrow': 'left',
};

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
    await tester.pump(const Duration(seconds: 1));

    NavService? nav() => find.byType(NavHud).evaluate().isEmpty
        ? null
        : tester.widget<NavHud>(find.byType(NavHud)).nav;
    NavState? state() => nav()?.tracker.state.value;

    /// What is on the HUD is only ever the real turn, whatever else was posted.
    void onlyTheTurn() {
      final s = state();
      if (s == null) return;
      expect(
        s.instruction,
        'Turn left onto MG Road',
        reason:
            'the HUD shows something that is not the navigation notification: $s',
      );
    }

    /// Pumps until [done], checking each time that nothing wrong is on the HUD.
    Future<void> until_(
      bool Function() done,
      String what, {
      int seconds = 40,
    }) => until(
      tester,
      () {
        onlyTheTurn();
        return done();
      },
      what,
      seconds: seconds,
    );

    // Another of Maps' notifications, first: a title and an ETA, and not navigation.
    await _post({
      'id': 4712,
      'category': 'none',
      'title': 'Heavy traffic on your commute',
      'sub': 'Arrive 9:25 PM',
    });
    // Then the navigation notification, which is the marker for the one before it.
    await _post(_turn('300 m'));
    await until_(
      () => state()?.distanceText == '300 m',
      'the navigation notification on the HUD',
    );
    expect(find.byType(NavHud), findsOneWidget);
    expect(state()!.instruction, 'Turn left onto MG Road');
    expect(state()!.etaText, '3:45 PM', reason: 'not the traffic alert\'s ETA');

    // The traffic alert changes: the turn does not. (The marker: the turn, nearer.)
    await _post({
      'id': 4712,
      'category': 'none',
      'title': 'Something else entirely',
      'sub': 'Arrive 11:11 PM',
    });
    await _post(_turn('250 m'));
    await until_(() => state()?.distanceText == '250 m', 'the marker, 250 m');
    expect(state()!.etaText, '3:45 PM');

    // The traffic alert goes away: the navigation goes on. (The marker again.)
    await _post({'id': 4712, 'remove': true});
    await _post(_turn('200 m'));
    await until_(() => state()?.distanceText == '200 m', 'the marker, 200 m');
    expect(
      find.byType(NavHud),
      findsOneWidget,
      reason: 'another notification going away is not the end of the route',
    );
    expect(nav()!.status.value, NavLinkStatus.guiding);

    // The navigation notification goes: the HUD goes back to the chosen layout.
    await _post({'remove': true});
    await until(
      tester,
      () => find.byType(NavHud).evaluate().isEmpty,
      'the HUD to go back when the navigation notification went',
    );

    expect(tester.takeException(), isNull);
  });
}

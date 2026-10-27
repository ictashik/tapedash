// Garage's Navigation group (docs/NAV.md): off to begin with, turned on by one
// switch, and plain about what stands in the way and about what the access means.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/nav_service.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/nav/nav_notification.dart';
import 'package:tapedash/platform/nav_channel.dart';
import 'package:tapedash/trips/trip_library.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/pages/garage/garage_page.dart';
import 'package:tapedash/vehicle/vehicle_state.dart' show DrivingMode;

import '../design/support/harness.dart';
import '../support/nav_fixtures.dart';

void main() {
  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late AppServices app;
  late ValueNotifier<DrivingMode> mode;
  late FakeNavSource source;
  late NavService nav;

  setUpAll(loadTapeFonts);

  setUp(() async {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock(start: DateTime(2026, 10, 24, 20, 58));
    app = await AppServices.memory();
    mode = ValueNotifier(DrivingMode.parked);
    source = FakeNavSource(access: true);
    nav = NavService(
      settings: app.settings,
      source: source,
      clock: clock,
      scheduler: clock,
    )..start();
  });

  tearDown(() {
    nav.dispose();
    kit.dispose();
    motion.dispose();
    mode.dispose();
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(720, 360),
    bool withNav = true,
    bool gpsOnly = false,
  }) async {
    setWindow(tester, size);
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: GaragePage(
          settings: app.settings,
          services: app,
          library: TripLibrary(app.trips),
          mode: mode,
          width: size.width,
          height: size.height,
          onClose: () {},
          gpsOnly: gpsOnly,
          nav: withNav ? nav : null,
          version: '9.9',
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> visible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder.first);
    await tester.pump();
  }

  const toggle = 'Show Google Maps turns on the HUD';

  testWidgets('has no Navigation group when there is no navigation feed', (
    tester,
  ) async {
    await show(tester, withNav: false);

    expect(find.text('NAVIGATION'), findsNothing);
  });

  for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
    testWidgets('lays out at ${size.width.toInt()}x360', (tester) async {
      await show(tester, size: size);
      await visible(tester, find.text(toggle));

      expect(find.text('NAVIGATION'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('is off to begin with, and says it reads nothing', (
    tester,
  ) async {
    await show(tester);
    await visible(tester, find.text(toggle));

    expect(app.settings.navEnabled.value, isFalse);
    expect(find.text('Off'), findsOneWidget);
    expect(
      find.text('TapeDash is not reading any notification.'),
      findsOneWidget,
    );
    expect(source.listeners, 0);
  });

  testWidgets('says what it does, in plain words, including the cost', (
    tester,
  ) async {
    await show(tester);
    await visible(tester, find.text('What this does'));

    expect(find.textContaining('TapeDash stays offline'), findsOneWidget);
    expect(
      find.textContaining('sends it nothing and keeps nothing'),
      findsOneWidget,
    );
    expect(find.textContaining('see every'), findsOneWidget);
    expect(find.textContaining('at any time'), findsOneWidget);
    // And the one thing that can spoil the glass.
    await visible(tester, find.text('If a small map floats over the HUD'));
    expect(find.textContaining('Picture-in-picture'), findsOneWidget);
  });

  testWidgets('the switch turns it on and the service listens', (tester) async {
    await show(tester);
    await visible(tester, find.text(toggle));

    await tester.tap(find.text(toggle));
    await tester.pump();
    await tester.pump();

    expect(app.settings.navEnabled.value, isTrue);
    expect(source.listeners, 1);
    expect(find.text('On: waiting for Google Maps'), findsOneWidget);
  });

  testWidgets('says when Maps is guiding', (tester) async {
    app.settings.navEnabled.value = true;
    await show(tester);
    await tester.pump();
    source.push(
      NavPosted(
        NavNotification(
          title: '650 m · Turn right onto Mission Rd',
          subText: 'Arrive 9:25 PM',
          shortCriticalText: '650 m',
          progress: 1,
          progressMax: 100,
          arrow: fixtureArrow('a'),
        ),
      ),
    );
    await tester.pump();
    await visible(tester, find.text(toggle));

    expect(find.text('On: following Google Maps'), findsOneWidget);
  });

  testWidgets('without access it says so and offers Android\'s screen', (
    tester,
  ) async {
    source.access = false;
    app.settings.navEnabled.value = true;
    await show(tester);
    await tester.pump();
    await visible(tester, find.text('Open notification access'));

    expect(find.text('Needs notification access'), findsOneWidget);

    await tester.tap(find.text('Open notification access'));
    await tester.pump();

    expect(source.accessScreenOpened, 1);
  });

  testWidgets('says what to do about a card over the HUD, and opens the page', (
    tester,
  ) async {
    app.settings.navEnabled.value = true;
    await show(tester);
    await tester.pump();
    await visible(tester, find.text('If a card drops over the HUD at a turn'));

    expect(find.textContaining('Navigation urgent updates'), findsOneWidget);
    expect(find.textContaining('Pop on screen'), findsOneWidget);

    await visible(
      tester,
      find.text('Open Google Maps\' notification settings'),
    );
    await tester.tap(find.text('Open Google Maps\' notification settings'));
    await tester.pump();

    expect(source.mapsSettingsOpened, 1);
    expect(source.accessScreenOpened, 0);
  });

  testWidgets('offers Maps\' settings only when there is a Maps to set', (
    tester,
  ) async {
    // Off: nothing is read and there is nothing to set.
    await show(tester);
    await visible(tester, find.text(toggle));
    expect(find.text('Open Google Maps\' notification settings'), findsNothing);
  });

  testWidgets('does not offer Maps\' settings when Maps is not on the phone', (
    tester,
  ) async {
    source.maps = null;
    app.settings.navEnabled.value = true;
    await show(tester);
    await tester.pump();
    await visible(tester, find.text(toggle));

    expect(find.text('Open Google Maps\' notification settings'), findsNothing);
  });

  testWidgets('does not offer the screen when there is nothing to grant', (
    tester,
  ) async {
    app.settings.navEnabled.value = true;
    await show(tester);
    await tester.pump();
    await visible(tester, find.text(toggle));

    expect(find.text('Open notification access'), findsNothing);
  });

  testWidgets('without Google Maps on the phone it says so', (tester) async {
    source.maps = null;
    app.settings.navEnabled.value = true;
    await show(tester);
    await tester.pump();
    await visible(tester, find.text(toggle));

    expect(find.text('Google Maps is not on this phone'), findsOneWidget);
  });

  testWidgets('is in the GPS-only Garage too', (tester) async {
    await show(tester, gpsOnly: true);
    await visible(tester, find.text(toggle));

    expect(find.text('NAVIGATION'), findsOneWidget);
  });
}

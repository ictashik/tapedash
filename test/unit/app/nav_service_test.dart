// The navigation HUD's feed: it follows the Garage switch, listens to the phone's
// listener only while the switch is on, and keeps what Google Maps says.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_settings.dart';
import 'package:tapedash/app/nav_service.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/nav/nav_notification.dart';
import 'package:tapedash/nav/nav_state.dart';
import 'package:tapedash/platform/nav_channel.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../support/nav_fixtures.dart';

NavNotification _turn({String distance = '650 m'}) => NavNotification(
  title: '$distance · Turn right onto Mission Rd',
  subText: 'Arrive 9:25 PM',
  shortCriticalText: distance,
  progress: 100,
  progressMax: 5000,
  template: 'android.app.Notification\$ProgressStyle',
  arrow: fixtureArrow('e687a80d8d'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeClock clock;
  late AppSettings settings;
  late FakeNavSource source;
  late NavService service;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    clock = FakeClock(start: DateTime(2026, 10, 24, 20, 58));
    settings = AppSettings(MemoryKeyValueStore());
    await settings.load();
    source = FakeNavSource(access: true);
    service = NavService(
      settings: settings,
      source: source,
      clock: clock,
      scheduler: clock,
    )..start();
    addTearDown(service.dispose);
  });

  test(
    'is off, and listens to nothing, until the switch is turned on',
    () async {
      await settle();

      expect(service.status.value, NavLinkStatus.off);
      expect(source.listeners, 0, reason: 'a switch that is off reads nothing');
      // Even a notification that arrives is not heard.
      source.push(NavPosted(_turn()));
      await settle();
      expect(service.tracker.state.value.phase, NavPhase.idle);
    },
  );

  test(
    'turning it on listens, asks about access and Maps, and waits',
    () async {
      settings.navEnabled.value = true;
      await settle();

      expect(source.listeners, 1);
      expect(service.access.value, isTrue);
      expect(service.mapsVersion.value, '25.33.03');
      expect(service.status.value, NavLinkStatus.waiting);
    },
  );

  test('says what Maps says, and that it is guiding', () async {
    settings.navEnabled.value = true;
    await settle();

    source.push(NavPosted(_turn()));
    await settle();

    expect(service.status.value, NavLinkStatus.guiding);
    expect(service.tracker.state.value.distanceText, '650 m');
    expect(service.tracker.state.value.arrow!.id, 'e687a80d8d');
  });

  test('Maps taking its notification away puts it back to waiting', () async {
    settings.navEnabled.value = true;
    await settle();
    source.push(NavPosted(_turn()));
    await settle();

    source.push(const NavRemoved());
    await settle();

    expect(service.status.value, NavLinkStatus.waiting);
    expect(service.tracker.state.value.phase, NavPhase.idle);
  });

  test(
    'turning the switch off stops listening and clears what it held',
    () async {
      settings.navEnabled.value = true;
      await settle();
      source.push(NavPosted(_turn()));
      await settle();

      settings.navEnabled.value = false;
      await settle();

      expect(source.listeners, 0);
      expect(service.status.value, NavLinkStatus.off);
      expect(service.tracker.state.value.phase, NavPhase.idle);
    },
  );

  test('is stale when Maps goes quiet on a moving car', () async {
    final vehicle = ObservableValue<MotionSample?>(null);
    final moving = NavService(
      settings: settings,
      source: source,
      clock: clock,
      scheduler: clock,
      speed: vehicle,
    )..start();
    addTearDown(moving.dispose);
    settings.navEnabled.value = true;
    await settle();
    source.push(NavPosted(_turn()));
    await settle();
    expect(moving.status.value, NavLinkStatus.guiding);

    // The car goes at 14 m/s and Maps says nothing for twenty seconds.
    for (var i = 0; i < 200; i++) {
      clock.advance(const Duration(milliseconds: 100));
      vehicle.value = MotionSample(
        speedMs: 14,
        accelerationMs2: 0,
        at: clock.monotonic(),
        receivedAt: clock.monotonic(),
      );
    }

    expect(moving.status.value, NavLinkStatus.stale);
    expect(moving.tracker.distanceToTurnEstimateM.value, isNull);
  });

  test('the distance counts down on the car\'s own speed', () async {
    final vehicle = ObservableValue<MotionSample?>(null);
    final counting = NavService(
      settings: settings,
      source: source,
      clock: clock,
      scheduler: clock,
      speed: vehicle,
    )..start();
    addTearDown(counting.dispose);
    settings.navEnabled.value = true;
    await settle();
    source.push(NavPosted(_turn()));
    await settle();

    for (var i = 0; i < 30; i++) {
      clock.advance(const Duration(milliseconds: 100));
      vehicle.value = MotionSample(
        speedMs: 14,
        accelerationMs2: 0,
        at: clock.monotonic(),
        receivedAt: clock.monotonic(),
      );
    }

    expect(
      counting.tracker.distanceToTurnEstimateM.value,
      closeTo(650 - 40, 3),
    );
  });

  group('what is missing', () {
    test('without Android\'s access it says so', () async {
      source.access = false;
      settings.navEnabled.value = true;
      await settle();

      expect(service.status.value, NavLinkStatus.needsAccess);
    });

    test('and is told when the access is granted', () async {
      source.access = false;
      settings.navEnabled.value = true;
      await settle();

      source.push(const NavLink(connected: true));
      await settle();

      expect(service.access.value, isTrue);
      expect(service.status.value, NavLinkStatus.waiting);
    });

    test('access taken away puts it back, and drops what it had', () async {
      settings.navEnabled.value = true;
      await settle();
      source.push(NavPosted(_turn()));
      await settle();

      source.push(const NavLink(connected: false));
      await settle();

      expect(service.status.value, NavLinkStatus.needsAccess);
      expect(service.tracker.state.value.phase, NavPhase.idle);
    });

    test('with no Google Maps on the phone it says that first', () async {
      source.maps = null;
      source.access = false;
      settings.navEnabled.value = true;
      await settle();

      expect(service.status.value, NavLinkStatus.noMaps);
    });

    test('what is arriving comes first: it is heard, so it is there', () async {
      // No Maps found, and the access said to be missing, and yet a navigation
      // notification arrives: it is shown (an emulator with a stand-in is this).
      source.maps = null;
      source.access = false;
      settings.navEnabled.value = true;
      await settle();
      expect(service.status.value, NavLinkStatus.noMaps);

      source.push(NavPosted(_turn()));
      await settle();

      expect(service.status.value, NavLinkStatus.guiding);
      expect(service.tracker.state.value.distanceText, '650 m');
    });

    test('asks again when the app comes back to the screen', () async {
      source.access = false;
      settings.navEnabled.value = true;
      await settle();
      expect(service.status.value, NavLinkStatus.needsAccess);

      // The person went to Android's settings and granted it.
      source.access = true;
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(service.status.value, NavLinkStatus.waiting);
    });

    test('opens Android\'s access screen', () async {
      expect(await service.openAccessSettings(), isTrue);
      expect(source.accessScreenOpened, 1);
    });
  });

  test('leaves nothing listening or scheduled when it is disposed', () async {
    settings.navEnabled.value = true;
    await settle();

    service.dispose();
    await settle();

    expect(source.listeners, 0);
    expect(clock.pendingTasks, 0);
  });

  test('the switch is off by default and is remembered', () async {
    final store = MemoryKeyValueStore();
    final first = AppSettings(store);
    await first.load();
    expect(first.navEnabled.value, isFalse);

    first.navEnabled.value = true;
    final second = AppSettings(store);
    await second.load();

    expect(second.navEnabled.value, isTrue);
  });
}

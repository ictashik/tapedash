import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/nav/nav_notification.dart';
import 'package:tapedash/nav/nav_state.dart';
import 'package:tapedash/nav/nav_tracker.dart';

import '../../support/nav_fixtures.dart';

NavNotification _turn({String distance = '650 m', int progress = 171}) =>
    NavNotification(
      title: '$distance · Turn right at Richmond Cir onto Mission Rd',
      subText: 'Arrive 9:25 PM',
      shortCriticalText: distance,
      progress: progress,
      progressMax: 6605,
      template: 'android.app.Notification\$ProgressStyle',
      arrow: fixtureArrow('e687a80d8d'),
    );

/// Gives the tracker a speed for [seconds], a sample every 100 ms.
void _drive(
  FakeClock clock,
  NavTracker tracker,
  double speedMs,
  double seconds,
) {
  for (var i = 0; i < seconds * 10; i++) {
    clock.advance(const Duration(milliseconds: 100));
    tracker.onSpeed(speedMs);
  }
}

void main() {
  late FakeClock clock;
  late NavTracker tracker;

  setUp(() {
    clock = FakeClock(start: DateTime(2026, 10, 24, 20, 58));
    tracker = NavTracker(clock: clock, scheduler: clock);
  });

  tearDown(() => tracker.dispose());

  test('starts with nothing navigating', () {
    expect(tracker.state.value.phase, NavPhase.idle);
    expect(tracker.freshness.value, NavFreshness.none);
    expect(tracker.distanceToTurnEstimateM.value, isNull);
  });

  test('a notification of Maps makes it guiding and fresh', () {
    tracker.onNotification(_turn());

    expect(tracker.state.value.phase, NavPhase.guiding);
    expect(tracker.state.value.distanceText, '650 m');
    expect(tracker.freshness.value, NavFreshness.fresh);
    expect(tracker.distanceToTurnEstimateM.value, 650);
  });

  test('Maps taking its notification away ends the navigation', () {
    tracker.onNotification(_turn());
    tracker.onRemoved();

    expect(tracker.state.value.phase, NavPhase.idle);
    expect(tracker.freshness.value, NavFreshness.none);
    expect(tracker.distanceToTurnEstimateM.value, isNull);
  });

  test('tells its listeners when the state changes', () {
    var calls = 0;
    tracker.state.addListener(() => calls++);

    tracker.onNotification(_turn());
    tracker.onNotification(_turn(distance: '600 m', progress: 191));
    tracker.onRemoved();

    expect(calls, 3);
  });

  group('stale', () {
    test('after fifteen seconds of silence with the car moving', () {
      tracker.onNotification(_turn());
      _drive(clock, tracker, 14, 14);
      expect(tracker.freshness.value, NavFreshness.fresh);

      _drive(clock, tracker, 14, 2);
      expect(tracker.freshness.value, NavFreshness.stale);
      // A stale distance is not counted down: it is not known.
      expect(tracker.distanceToTurnEstimateM.value, isNull);
    });

    test('a new post makes it fresh again', () {
      tracker.onNotification(_turn());
      _drive(clock, tracker, 14, 20);
      expect(tracker.freshness.value, NavFreshness.stale);

      tracker.onNotification(_turn(distance: '300 m', progress: 500));

      expect(tracker.freshness.value, NavFreshness.fresh);
      expect(tracker.distanceToTurnEstimateM.value, 300);
    });

    test('a standing car is given longer, since Maps has less to say', () {
      tracker.onNotification(_turn());
      _drive(clock, tracker, 0, 120);
      expect(tracker.freshness.value, NavFreshness.fresh);

      _drive(clock, tracker, 0, 70);
      expect(tracker.freshness.value, NavFreshness.stale);
    });

    test('nothing is stale when nothing is navigating', () {
      _drive(clock, tracker, 14, 60);
      expect(tracker.freshness.value, NavFreshness.none);
    });
  });

  group('the distance to the turn between posts', () {
    test('counts down by the car\'s own speed', () {
      tracker.onNotification(_turn());
      tracker.onSpeed(14);

      _drive(clock, tracker, 14, 3);

      // 14 m/s for 3 s is 42 m (the first sample only sets the time).
      expect(tracker.distanceToTurnEstimateM.value, closeTo(650 - 42, 1.5));
    });

    test('goes back to Maps\' figure at each post', () {
      tracker.onNotification(_turn());
      tracker.onSpeed(14);
      _drive(clock, tracker, 14, 3);

      tracker.onNotification(_turn(distance: '600 m', progress: 191));

      expect(tracker.distanceToTurnEstimateM.value, 600);
    });

    test('does not go below nothing', () {
      tracker.onNotification(_turn(distance: '20 m'));
      tracker.onSpeed(14);

      _drive(clock, tracker, 14, 5);

      expect(tracker.distanceToTurnEstimateM.value, 0);
    });

    test('does not count a gap in the speed as time on the road', () {
      tracker.onNotification(_turn());
      tracker.onSpeed(14);
      clock.advance(const Duration(seconds: 2, milliseconds: 500));
      tracker.onSpeed(14);

      expect(tracker.distanceToTurnEstimateM.value, 650);
    });

    test('is not made when the notification has no distance', () {
      tracker.onNotification(
        NavNotification(
          title: 'Head north',
          subText: 'Arrive 9:25 PM',
          shortCriticalText: '',
          progress: 1,
          progressMax: 6699,
          arrow: fixtureArrow('5c317d6e0e'),
        ),
      );
      tracker.onSpeed(14);
      _drive(clock, tracker, 14, 2);

      expect(tracker.distanceToTurnEstimateM.value, isNull);
    });

    test('is not made while rerouting', () {
      tracker.onNotification(_turn());
      tracker.onNotification(
        const NavNotification(title: 'Rerouting...', subText: 'Arrive '),
      );
      tracker.onSpeed(14);
      _drive(clock, tracker, 14, 2);

      expect(tracker.state.value.phase, NavPhase.rerouting);
      expect(tracker.distanceToTurnEstimateM.value, isNull);
    });
  });

  test('keeps the arrows it has seen, by id', () {
    expect(tracker.arrowFor('e687a80d8d'), isNull);

    tracker.onNotification(_turn());

    expect(tracker.arrowFor('e687a80d8d')!.id, 'e687a80d8d');
  });

  test('leaves nothing scheduled when it is disposed', () {
    final other = FakeClock();
    final t = NavTracker(clock: other, scheduler: other);
    expect(other.pendingTasks, 1);

    t.dispose();

    expect(other.pendingTasks, 0);
  });

  test('a whole captured drive, replayed in step with its own time', () {
    final records = loadNavFixture('maps_25_33_android16.jsonl');
    var at = 0;
    final seen = <NavPhase>{};
    var staleMoments = 0;
    tracker.freshness.addListener(() {
      if (tracker.freshness.value == NavFreshness.stale) staleMoments++;
    });

    for (final r in records) {
      // The capture's car stood still until about 93 s in, and then went at
      // about 14 m/s (its GPS was stepped 22 m every 1.5 s).
      while (at < r.t) {
        clock.advance(const Duration(milliseconds: 100));
        tracker.onSpeed(at < 93000 ? 0 : 14);
        at += 100;
      }
      if (r.event == 'posted') {
        tracker.onNotification(r.notification!);
        seen.add(tracker.state.value.phase);
      } else {
        tracker.onRemoved();
        seen.add(tracker.state.value.phase);
        expect(tracker.freshness.value, NavFreshness.none);
      }
    }

    expect(
      seen,
      containsAll([
        NavPhase.starting,
        NavPhase.guiding,
        NavPhase.rerouting,
        NavPhase.idle,
      ]),
    );
    // Maps was quiet for 17 s while the car stood (before navigation began), and
    // never for long while it moved: the longest gap then was 5 s.
    expect(staleMoments, 0);
  });
}

// What a replay's readouts read, and the marked moments it passes
// (DESIGN.md 6.12).
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/coach/sample_events.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/trips/trip_playback.dart';
import 'package:tapedash/ui/design/motion/playback_channel.dart';
import 'package:tapedash/ui/design/motion/trip_player.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

import 'support/motion_rig.dart';

TripSample at(double t, {double speed = 40, double? load}) => TripSample(
  seconds: t,
  speedKmh: speed,
  rpm: 2000 + t * 7,
  throttle: 20,
  litresPerHour: 3,
  load: load,
);

void main() {
  late MotionRig rig;
  late TripPlayer player;

  setUp(() {
    rig = MotionRig();
    player = TripPlayer(
      clock: rig.motion,
      playback: TripPlayback([for (var i = 0; i <= 60; i++) at(i.toDouble())]),
    );
  });

  tearDown(() {
    player.dispose();
    rig.dispose();
  });

  group('PlaybackChannel', () {
    test('it reads the play head\'s moment as it is asked', () {
      final rpm = PlaybackChannel(player, (f) => f.rpm);

      expect(rpm.value, 2000);
      player.seekTo(10);
      expect(rpm.value, closeTo(2070, 1e-9));
      expect(rpm.staleness, 0);
      expect(rpm.hasValue, isTrue);
      rpm.dispose();
    });

    test(
      'with a step it is rounded to it, so that digits rest on whole ones',
      () {
        final rpm = PlaybackChannel(player, (f) => f.rpm, step: 10);

        player.seekTo(10.4); // 2072.8
        expect(rpm.value, 2070);
        player.seekTo(10.6); // 2074.2
        expect(rpm.value, 2070);
        player.seekTo(11); // 2077
        expect(rpm.value, 2080);
        rpm.dispose();
      },
    );

    test('a channel the trip did not record has no value to show', () {
      final load = PlaybackChannel(player, (f) => f.load);

      expect(load.hasValue, isFalse);
      expect(load.value, 0);
      load.dispose();
    });

    test('it tells its painters when the play head moves, and only then', () {
      final speed = PlaybackChannel(player, (f) => f.speedKmh);
      var n = 0;
      speed.addListener(() => n++);

      rig.run(const Duration(seconds: 1));
      expect(n, 0, reason: 'not playing');
      player.play();
      rig.run(const Duration(seconds: 1));
      expect(n, greaterThan(50));
      speed.dispose();
    });

    test('once disposed it no longer listens to the player', () {
      PlaybackChannel(player, (f) => f.speedKmh).dispose();

      // A seek after it is gone must not reach it.
      expect(() => player.seekTo(5), returnsNormally);
    });
  });

  group('ReplayEvents', () {
    // Hard braking at sample 20, a long idle at 40.
    final events = [
      const SampleEvent(SampleEventType.hardBraking, 20),
      const SampleEvent(SampleEventType.longIdle, 40),
    ];

    test('nothing before the first moment', () {
      final e = ReplayEvents(player: player, events: events);

      player.seekTo(5);
      expect(e.current, isNull);
      e.dispose();
    });

    test('a moment is shown for a few seconds after it, then goes', () {
      final e = ReplayEvents(player: player, events: events);

      player.seekTo(20);
      expect(e.current, SampleEventType.hardBraking);
      player.seekTo(20 + TapeReplay.eventHoldSeconds - 0.1);
      expect(e.current, SampleEventType.hardBraking);
      player.seekTo(20 + TapeReplay.eventHoldSeconds + 0.1);
      expect(e.current, isNull);
      e.dispose();
    });

    test('at 3 times it is held three times as long in the replay\'s time', () {
      final e = ReplayEvents(player: player, events: events);
      player
        ..cycleRate()
        ..cycleRate();

      player.seekTo(20 + TapeReplay.eventHoldSeconds * 2.5);
      expect(e.current, SampleEventType.hardBraking);
      e.dispose();
    });

    test('it follows a scrub either way', () {
      final e = ReplayEvents(player: player, events: events);

      player.seekTo(41);
      expect(e.current, SampleEventType.longIdle);
      player.seekTo(21);
      expect(e.current, SampleEventType.hardBraking);
      player.seekTo(10);
      expect(e.current, isNull);
      e.dispose();
    });

    test('it says so only when the moment changes', () {
      final e = ReplayEvents(player: player, events: events);
      var n = 0;
      e.addListener(() => n++);

      player.seekTo(20.5);
      player.seekTo(21);
      player.seekTo(21.5);
      expect(n, 1);
      player.seekTo(30);
      expect(n, 2);
      e.dispose();
    });

    test('no events is never a moment', () {
      final e = ReplayEvents(player: player, events: const []);

      player.seekTo(30);
      expect(e.current, isNull);
      e.dispose();
    });
  });
}

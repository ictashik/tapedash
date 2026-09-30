// The transport of a trip replay: play, pause, the three speeds, seeking, and
// the end (DESIGN.md 6.12).
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/trips/trip_playback.dart';
import 'package:tapedash/ui/design/motion/trip_player.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

import 'support/motion_rig.dart';

TripSample at(double t, double speed) => TripSample(
  seconds: t,
  speedKmh: speed,
  rpm: 1000 + speed * 20,
  throttle: 10,
  litresPerHour: 3,
);

void main() {
  late MotionRig rig;
  late TripPlayer player;

  setUp(() {
    rig = MotionRig();
    // A 60 s trip, accelerating from 0 to 60 km/h: a km/h a second.
    player = TripPlayer(
      clock: rig.motion,
      playback: TripPlayback([
        for (var i = 0; i <= 60; i++) at(i.toDouble(), i.toDouble()),
      ]),
    );
  });

  tearDown(() {
    player.dispose();
    rig.dispose();
  });

  test('it starts at the beginning, paused, at 1 times', () {
    expect(player.seconds, 0);
    expect(player.isPlaying, isFalse);
    expect(player.rate, 1);
    expect(player.duration, 60);
    expect(player.frame.speedKmh, 0);
  });

  test('playing moves it on in real time, and the frame follows', () {
    player.play();
    rig.run(const Duration(seconds: 10));

    expect(player.seconds, closeTo(10, 0.05));
    expect(player.frame.speedKmh, closeTo(10, 0.05));
    expect(player.progress, closeTo(10 / 60, 0.001));
  });

  test('at 2 and 3 times it goes two and three times as fast', () {
    player.cycleRate();
    expect(player.rate, 2);
    player.play();
    rig.run(const Duration(seconds: 10));
    expect(player.seconds, closeTo(20, 0.1));

    player.cycleRate();
    expect(player.rate, 3);
    rig.run(const Duration(seconds: 10));
    expect(player.seconds, closeTo(50, 0.2));
  });

  test('the speeds go round: 1, 2, 3, 1', () {
    final seen = <double>[player.rate];
    for (var i = 0; i < 4; i++) {
      player.cycleRate();
      seen.add(player.rate);
    }

    expect(seen, [1, 2, 3, 1, 2]);
    expect(TapeReplay.rates, [1, 2, 3]);
  });

  test('pausing holds the moment, and playing carries on from it', () {
    player.play();
    rig.run(const Duration(seconds: 5));
    player.pause();
    final held = player.seconds;

    rig.run(const Duration(seconds: 5));
    expect(player.seconds, held);
    expect(player.isPlaying, isFalse);

    player.play();
    rig.run(const Duration(seconds: 5));
    expect(player.seconds, closeTo(held + 5, 0.05));
  });

  test('it lets go of the clock when it is not playing', () {
    expect(rig.motion.attachedCount, 0);
    player.play();
    expect(rig.motion.attachedCount, 1);
    player.pause();
    expect(rig.motion.attachedCount, 0);
  });

  test('seeking moves it, playing or not, and the frame with it', () {
    player.seekTo(30);
    expect(player.seconds, 30);
    expect(player.frame.speedKmh, closeTo(30, 1e-9));
    expect(player.isPlaying, isFalse);

    player.play();
    player.seekTo(45);
    rig.run(const Duration(seconds: 1));
    expect(player.seconds, closeTo(46, 0.05));
    expect(player.isPlaying, isTrue);
  });

  test('seeking is kept between 0 and the end', () {
    player.seekTo(-5);
    expect(player.seconds, 0);
    player.seekTo(500);
    expect(player.seconds, 60);
  });

  test('seeking to a sample goes to that sample\'s time', () {
    player.seekToSample(12.5);

    expect(player.seconds, closeTo(12.5, 1e-9));
  });

  test('at the end it stops, and playing again starts from the beginning', () {
    player.seekTo(58);
    player.cycleRate();
    player.cycleRate();
    player.play();
    rig.run(const Duration(seconds: 2));

    expect(player.seconds, 60);
    expect(player.isAtEnd, isTrue);
    expect(player.isPlaying, isFalse);
    expect(rig.motion.attachedCount, 0);

    player.play();
    expect(player.seconds, 0);
    expect(player.isPlaying, isTrue);
  });

  test('every move notifies, and the frame object is the same one', () {
    var count = 0;
    player.addListener(() => count++);
    final frame = player.frame;

    player.play();
    rig.run(const Duration(seconds: 1));

    expect(count, greaterThan(50));
    expect(identical(player.frame, frame), isTrue);
  });

  test('a stalled frame does not make it jump: a frame is at most 50 ms', () {
    player.play();
    rig.motion.tick(2); // a two-second stall

    expect(player.seconds, closeTo(0.05, 1e-9));
  });

  test('a trip with nothing to replay does nothing', () {
    final empty = TripPlayer(
      clock: rig.motion,
      playback: TripPlayback(const []),
    );
    empty.play();

    expect(empty.isPlaying, isFalse);
    expect(empty.duration, 0);
    empty.dispose();
  });
}

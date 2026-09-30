// The engine sound of the running app: it follows the Garage's settings and the
// screen, keeps the replay and the test from sounding over the live voice, and
// reads the drive's signals as an engine. On a fake host, so that no audio is
// needed.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_settings.dart';
import 'package:tapedash/app/drive_sound.dart';
import 'package:tapedash/app/engine_sound_sources.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/sound/engine_profile.dart';
import 'package:tapedash/sound/engine_sound.dart';
import 'package:tapedash/sound/pcm_sink.dart';
import 'package:tapedash/sound/voice_host.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/trips/trip_playback.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/trip_player.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

/// A voice that only records what it is asked.
class _Host implements VoiceHost {
  final List<String> calls = [];
  // ignore: close_sinks
  final StreamController<String> controller = StreamController.broadcast();
  SinkStart result = SinkStart.started;
  bool? requireExternal;
  EngineProfile? profile;
  double? volume;
  double rpm = 0;
  double load = 0;
  bool active = false;
  bool running = false;

  @override
  Stream<String> get events => controller.stream;

  @override
  Future<SinkStart> start(
    EngineProfile profile, {
    required double volume,
    bool requireExternalOutput = false,
  }) async {
    calls.add('start ${profile.id}');
    this.profile = profile;
    this.volume = volume;
    requireExternal = requireExternalOutput;
    running = result == SinkStart.started;
    return result;
  }

  @override
  void setProfile(EngineProfile profile) {
    calls.add('profile ${profile.id}');
    this.profile = profile;
  }

  @override
  void setVolume(double volume) {
    calls.add('volume $volume');
    this.volume = volume;
  }

  @override
  void setControls({
    required double rpm,
    required double load,
    required bool active,
  }) {
    this.rpm = rpm;
    this.load = load;
    this.active = active;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    running = false;
  }
}

class _Source implements EngineSoundSource {
  bool live = true;

  @override
  bool read(EngineControls out) {
    out
      ..rpm = 2500
      ..load = 0.4;
    return live;
  }
}

Future<void> flush() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeClock clock;
  late AppSettings settings;
  late List<_Host> hosts;
  late List<String> notes;
  late _Source source;
  late DriveSound sound;

  setUp(() {
    clock = FakeClock();
    settings = AppSettings(MemoryKeyValueStore());
    hosts = [];
    notes = [];
    source = _Source();
    sound = DriveSound(
      settings: settings,
      live: source,
      scheduler: clock,
      clock: clock,
      hostFactory: () {
        final h = _Host();
        hosts.add(h);
        return h;
      },
      note: notes.add,
    );
  });

  tearDown(() async {
    sound.dispose();
    await flush();
  });

  group('following the settings', () {
    test('it is off until turned on: no voice is even made', () async {
      sound.start();
      await flush();

      expect(hosts, isEmpty);
      expect(sound.status.value, SoundStatus.off);
    });

    test(
      'turned on it plays the chosen engine at the chosen volume, on car audio only',
      () async {
        settings.soundProfile.value = 'v8';
        settings.soundVolume.value = 0.5;
        settings.soundEnabled.value = true;
        sound.start();
        await flush();

        final host = hosts.single;
        expect(host.running, isTrue);
        expect(host.profile, EngineProfile.v8);
        expect(host.volume, 0.5);
        expect(host.requireExternal, isTrue);
        expect(sound.status.value, SoundStatus.playing);
      },
    );

    test(
      'it is on when the setting is turned on later, and off when it is turned off',
      () async {
        sound.start();
        settings.soundEnabled.value = true;
        await flush();
        expect(hosts.single.running, isTrue);

        settings.soundEnabled.value = false;
        await flush();

        expect(hosts.single.running, isFalse);
        expect(sound.status.value, SoundStatus.off);
      },
    );

    test(
      'allowing the speaker restarts it, without the car audio requirement',
      () async {
        settings.soundEnabled.value = true;
        sound.start();
        await flush();

        settings.soundOnSpeaker.value = true;
        await flush();

        expect(hosts.last.requireExternal, isFalse);
        expect(hosts.last.running, isTrue);
      },
    );

    test('a new profile and volume reach the voice while it plays', () async {
      settings.soundEnabled.value = true;
      sound.start();
      await flush();

      settings.soundProfile.value = 'electric';
      settings.soundVolume.value = 0.9;
      await flush();

      expect(hosts.single.calls, contains('profile electric'));
      expect(hosts.single.calls, contains('volume 0.9'));
    });

    test('with no car audio it says so and does not play', () async {
      settings.soundEnabled.value = true;
      final first = DriveSound(
        settings: settings,
        live: source,
        scheduler: clock,
        clock: clock,
        hostFactory: () => _Host()..result = SinkStart.noExternalOutput,
        note: notes.add,
      )..start();
      await flush();

      expect(first.status.value, SoundStatus.noOutput);
      expect(notes.last, contains('no car audio'));
      first.dispose();
    });

    test('what it does is written to the notes', () async {
      settings.soundEnabled.value = true;
      sound.start();
      await flush();

      expect(notes.first, 'sound on inline4 at 70 %');
    });
  });

  group('the screen', () {
    test(
      'it stops when the app leaves the screen, and starts again on return',
      () async {
        settings.soundEnabled.value = true;
        sound.start();
        await flush();

        sound.didChangeAppLifecycleState(AppLifecycleState.paused);
        await flush();
        expect(hosts.single.running, isFalse);

        sound.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await flush();
        expect(hosts.last.running, isTrue);
      },
    );

    test(
      'an output that went away while the screen was off is started again on return',
      () async {
        settings.soundEnabled.value = true;
        sound.start();
        await flush();
        hosts.single.controller.add('lost');
        await flush();
        expect(sound.status.value, SoundStatus.lost);

        sound.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await flush();

        expect(sound.status.value, SoundStatus.playing);
      },
    );

    test('a system dialog over the app (inactive) changes nothing', () async {
      settings.soundEnabled.value = true;
      sound.start();
      await flush();

      sound.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await flush();

      expect(hosts.single.running, isTrue);
    });

    test('an output lost on a drive stays lost, and Garage says so', () async {
      settings.soundEnabled.value = true;
      sound.start();
      await flush();

      hosts.single.controller.add('lost');
      await flush();

      expect(sound.status.value, SoundStatus.lost);
      expect(notes.last, contains('lost'));
    });
  });

  group('the test in Garage', () {
    test(
      'it plays a demonstration on any output, and gives the speaker back',
      () async {
        settings.soundEnabled.value = true;
        sound.start();
        await flush();
        final live = hosts.single;

        await sound.test();
        await flush();

        expect(sound.testing.value, isTrue);
        expect(live.running, isFalse, reason: 'the live voice makes way');
        final demo = hosts.last;
        expect(demo, isNot(same(live)));
        expect(demo.running, isTrue);
        expect(demo.requireExternal, isFalse, reason: 'on the speaker too');
        clock.advance(const Duration(seconds: 1));
        expect(demo.active, isTrue);
        expect(demo.rpm, greaterThan(700));

        clock.advance(const Duration(seconds: 13));
        await flush();

        expect(sound.testing.value, isFalse);
        expect(demo.running, isFalse);
        expect(live.running, isTrue, reason: 'the live voice is back');
      },
    );

    test('pressed again it stops', () async {
      sound.start();

      await sound.test();
      await flush();
      expect(sound.testing.value, isTrue);

      await sound.test();
      await flush();
      expect(sound.testing.value, isFalse);
      expect(hosts.single.running, isFalse);
    });

    test('it works with the sound turned off in Garage', () async {
      sound.start();

      await sound.test();
      await flush();

      expect(hosts.single.running, isTrue);
    });

    test('a phone that cannot play says so and leaves the test off', () async {
      final refusing = DriveSound(
        settings: settings,
        live: source,
        scheduler: clock,
        clock: clock,
        hostFactory: () => _Host()..result = SinkStart.failed,
      )..start();

      await refusing.test();
      await flush();

      expect(refusing.testing.value, isFalse);
      refusing.dispose();
    });
  });

  group('a replay in Review', () {
    late ManualMotionClock motion;
    late TripPlayer player;

    setUp(() {
      motion = ManualMotionClock();
      player = TripPlayer(
        clock: motion,
        playback: TripPlayback([
          for (var i = 0; i <= 30; i++)
            TripSample(
              seconds: i.toDouble(),
              speedKmh: 40,
              rpm: 2000 + i * 20,
              throttle: 30,
              litresPerHour: 3,
            ),
        ]),
      );
    });

    tearDown(() {
      player.dispose();
      motion.dispose();
    });

    test(
      'it follows the play head, on any output, while the live voice makes way',
      () async {
        settings.soundEnabled.value = true;
        sound.start();
        await flush();

        sound.begin(player);
        await flush();

        expect(hosts.first.running, isFalse);
        final replay = hosts.last;
        expect(replay.running, isTrue);
        expect(replay.requireExternal, isFalse);

        // Paused: silent. Playing: the trip's revs, a moment ahead.
        clock.advance(const Duration(milliseconds: 100));
        expect(replay.active, isFalse);
        player.play();
        player.seekTo(10);
        clock.advance(const Duration(milliseconds: 100));
        expect(replay.active, isTrue);
        expect(replay.rpm, closeTo(2000 + 20 * (10 + 0.3), 15));
      },
    );

    test('at 3 times it looks further ahead', () async {
      settings.soundEnabled.value = true;
      sound.start();
      await flush();
      sound.begin(player);
      await flush();
      player
        ..cycleRate()
        ..cycleRate()
        ..play()
        ..seekTo(10);

      clock.advance(const Duration(milliseconds: 100));

      expect(hosts.last.rpm, closeTo(2000 + 20 * (10 + 0.9), 15));
    });

    test('when it ends the live voice is back', () async {
      settings.soundEnabled.value = true;
      sound.start();
      await flush();
      sound.begin(player);
      await flush();

      sound.end();
      await flush();

      expect(hosts.length, 2, reason: 'the live voice is reused');
      expect(hosts.first.running, isTrue);
      expect(hosts[1].running, isFalse, reason: 'the replay\'s has stopped');
    });

    test('with the sound turned off there is nothing to play', () async {
      sound.start();

      sound.begin(player);
      await flush();

      expect(hosts, isEmpty);
    });
  });

  group('the sources', () {
    test('load: an idle is none, and the foot is what counts', () {
      expect(EngineSoundSource.loadFrom(12, 28), 0, reason: 'an idle');
      expect(EngineSoundSource.loadFrom(100, 0), 1);
      expect(EngineSoundSource.loadFrom(56, 0), closeTo(0.5, 1e-9));
      // The engine load counts for a little less than the throttle.
      expect(EngineSoundSource.loadFrom(0, 100), closeTo(0.85, 1e-9));
      expect(EngineSoundSource.loadFrom(0, 0), 0);
      expect(
        EngineSoundSource.loadFrom(5, 10),
        0,
        reason: 'never below nothing',
      );
    });

    test(
      'a live drive: the revs and load as the needle has them, silent when stale or off',
      () {
        final motion = ManualMotionClock();
        final fake = FakeClock()..advance(const Duration(seconds: 100));
        final vehicle = VehicleState(clock: fake, scheduler: fake);
        final signals = DriveSignals(
          vehicle: vehicle,
          motion: motion,
          clock: fake,
          scheduler: fake,
          connection: ObservableValue(ConnectionStatus.connected),
        );
        final live = LiveSoundSource(signals);
        final c = EngineControls();
        void feed(Sensor s, double v) {
          final now = fake.monotonic();
          vehicle.ingest(s, v, at: now, receivedAt: now);
        }

        // Time goes on, and [feeds] says what the car keeps saying.
        void run(double seconds, {Map<Sensor, double> feeds = const {}}) {
          var sinceFeed = 1.0;
          for (var t = 0.0; t < seconds; t += 1 / 60) {
            sinceFeed += 1 / 60;
            if (sinceFeed >= 0.5) {
              sinceFeed = 0;
              feeds.forEach(feed);
            }
            motion.tick();
            fake.advance(const Duration(microseconds: 16667));
          }
        }

        expect(live.read(c), isFalse, reason: 'nothing yet');

        run(2, feeds: {Sensor.rpm: 2500, Sensor.throttle: 56});
        expect(live.read(c), isTrue);
        expect(c.rpm, closeTo(2500, 30));
        expect(c.load, closeTo(0.5, 0.05));

        run(3, feeds: {Sensor.rpm: 200});
        expect(live.read(c), isFalse, reason: 'turning over, or off');

        run(2, feeds: {Sensor.rpm: 2500, Sensor.throttle: 56});
        expect(live.read(c), isTrue);
        run(10);
        expect(live.read(c), isFalse, reason: 'the link went quiet');

        signals.dispose();
        motion.dispose();
      },
    );
  });
}

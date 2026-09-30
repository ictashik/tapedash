// What keeps the audio output fed (SynthVoiceHost) and the sound that follows the
// drive (EngineSound): on a fake clock and a sink in memory, so that it is all
// checked without a phone.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/sound/engine_profile.dart';
import 'package:tapedash/sound/engine_sound.dart';
import 'package:tapedash/sound/pcm_sink.dart';
import 'package:tapedash/sound/voice_host.dart';

const _rate = 32000;

/// A source that says what it is told.
class _Source implements EngineSoundSource {
  double rpm = 0;
  double load = 0;
  bool live = false;
  int reads = 0;

  @override
  bool read(EngineControls out) {
    reads++;
    out
      ..rpm = rpm
      ..load = load;
    return live;
  }
}

double rms(Int16List x, int from, int to) {
  var sum = 0.0;
  for (var i = from; i < to; i++) {
    final v = x[i] / 32767;
    sum += v * v;
  }
  return math.sqrt(sum / math.max(1, to - from));
}

void main() {
  late FakeClock clock;
  late MemorySink sink;
  late SynthVoiceHost host;

  setUp(() {
    clock = FakeClock();
    sink = MemorySink(clock);
    host = SynthVoiceHost(sink: sink, scheduler: clock, clock: clock);
  });

  tearDown(() async {
    await host.stop();
  });

  group('MemorySink', () {
    test('what is written plays away at the sample rate', () async {
      await sink.start(_rate);

      sink.write(Int16List(3200), 3200);
      expect(sink.queuedFrames, 3200);
      clock.advance(const Duration(milliseconds: 50));
      expect(sink.queuedFrames, 3200 - 1600);
      clock.advance(const Duration(milliseconds: 100));
      expect(sink.queuedFrames, 0);
    });

    test('running dry, having had sound to play, is an underrun', () async {
      await sink.start(_rate);
      sink.write(Int16List(320), 320); // 10 ms

      clock.advance(const Duration(milliseconds: 100));

      expect(sink.underruns, 1);
      clock.advance(const Duration(milliseconds: 100));
      expect(
        sink.underruns,
        1,
        reason: 'silence before there was sound is not one',
      );
    });

    test('with no car audio it will not start when asked for one', () async {
      sink.playable = false;

      expect(
        await sink.start(_rate, requireExternalOutput: true),
        SinkStart.noExternalOutput,
      );
      expect(await sink.start(_rate), SinkStart.started);
    });

    test('it keeps what was written', () async {
      await sink.start(_rate);
      final a = Int16List.fromList([1, 2, 3, 4]);
      sink.write(a, 4);
      a[0] = 99;
      sink.write(Int16List.fromList([5, 6]), 2);

      expect(sink.samples, [1, 2, 3, 4, 5, 6]);
      expect(sink.framesWritten, 6);
    });
  });

  group('SynthVoiceHost', () {
    test(
      'it keeps the sink about 120 ms ahead, and never lets it run dry',
      () async {
        await host.start(EngineProfile.inline4, volume: 1);
        host.setControls(rpm: 3000, load: 0.6, active: true);

        for (var i = 0; i < 300; i++) {
          clock.advance(const Duration(milliseconds: 20));
          expect(
            sink.queuedFrames,
            inInclusiveRange(_rate * 0.10, _rate * 0.16),
          );
        }

        expect(sink.underruns, 0);
        // Six seconds played, and the 120 ms ahead.
        expect(sink.framesWritten, closeTo(_rate * 6.12, _rate * 0.05));
      },
    );

    test('it makes the sound the controls say', () async {
      await host.start(EngineProfile.inline4, volume: 1);
      host.setControls(rpm: 3000, load: 0.6, active: true);
      clock.advance(const Duration(seconds: 2));

      final x = sink.samples;
      expect(rms(x, _rate, _rate * 2), greaterThan(0.05));
    });

    test('with no engine to hear it fades to silence', () async {
      await host.start(EngineProfile.inline4, volume: 1);
      host.setControls(rpm: 3000, load: 0.6, active: true);
      clock.advance(const Duration(seconds: 2));

      host.setControls(rpm: 3000, load: 0.6, active: false);
      clock.advance(const Duration(seconds: 5));

      final x = sink.samples;
      expect(rms(x, x.length - _rate, x.length), lessThan(1e-3));
    });

    test('the volume scales the sound', () async {
      Future<double> level(double volume) async {
        final s = MemorySink(clock);
        final h = SynthVoiceHost(sink: s, scheduler: clock, clock: clock);
        await h.start(EngineProfile.inline4, volume: volume);
        h.setControls(rpm: 3000, load: 0.6, active: true);
        clock.advance(const Duration(seconds: 2));
        await h.stop();
        return rms(s.samples, _rate, _rate * 2);
      }

      final full = await level(1);
      final half = await level(0.5);

      expect(half / full, closeTo(0.5, 0.03));
    });

    test('a change of profile crossfades, with no click', () async {
      await host.start(EngineProfile.inline4, volume: 1);
      host.setControls(rpm: 3000, load: 0.6, active: true);
      clock.advance(const Duration(seconds: 1));
      final before = sink.framesWritten;

      host.setProfile(EngineProfile.v8);
      clock.advance(const Duration(seconds: 1));

      final x = sink.samples;
      var worst = 0.0;
      for (var i = before - 200; i < x.length - 1; i++) {
        worst = math.max(worst, (x[i + 1] - x[i]).abs() / 32767);
      }
      expect(worst, lessThan(0.35));
      expect(rms(x, x.length - 4000, x.length), greaterThan(0.03));
    });

    test('when the output is taken away it says so and stops', () async {
      final events = <String>[];
      host.events.listen(events.add);
      await host.start(EngineProfile.inline4, volume: 1);
      host.setControls(rpm: 3000, load: 0.6, active: true);
      clock.advance(const Duration(seconds: 1));

      sink.lose();
      clock.advance(const Duration(milliseconds: 100));
      await Future<void>.delayed(Duration.zero);

      expect(events, contains('lost'));
      expect(host.isRunning, isFalse);
      final written = sink.framesWritten;
      clock.advance(const Duration(seconds: 1));
      expect(sink.framesWritten, written);
    });

    test('it says when the output ran dry', () async {
      // A host that ticks once a second cannot keep 120 ms ahead.
      final slow = SynthVoiceHost(
        sink: sink,
        scheduler: clock,
        clock: clock,
        tick: const Duration(seconds: 1),
      );
      final events = <String>[];
      slow.events.listen(events.add);
      await slow.start(EngineProfile.inline4, volume: 1);
      slow.setControls(rpm: 3000, load: 0.6, active: true);

      clock.advance(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);

      expect(events.where((e) => e.startsWith('underruns')), isNotEmpty);
      await slow.stop();
    });

    test('with no car audio it does not start, and runs nothing', () async {
      sink.playable = false;

      final result = await host.start(
        EngineProfile.inline4,
        volume: 1,
        requireExternalOutput: true,
      );

      expect(result, SinkStart.noExternalOutput);
      expect(host.isRunning, isFalse);
      expect(clock.pendingTasks, 0);
    });

    test('stop lets go of the clock and closes the sink', () async {
      await host.start(EngineProfile.inline4, volume: 1);
      expect(clock.pendingTasks, 1);

      await host.stop();

      expect(clock.pendingTasks, 0);
      expect(sink.isOpen, isFalse);
    });
  });

  group('EngineSound', () {
    late _Source source;
    late EngineSound sound;
    late List<String> notes;

    setUp(() {
      source = _Source();
      notes = [];
      sound = EngineSound(
        host: host,
        source: source,
        scheduler: clock,
        note: notes.add,
      );
    });

    tearDown(() async {
      await sound.dispose();
    });

    test('it starts, and says what it is in the session\'s notes', () async {
      await sound.start(profile: EngineProfile.v8, volume: 0.6);

      expect(sound.status.value, SoundStatus.playing);
      expect(notes, ['sound on v8 at 60 %']);
    });

    test(
      'it reads the source thirty times a second and passes it on',
      () async {
        await sound.start(profile: EngineProfile.inline4, volume: 1);
        source
          ..live = true
          ..rpm = 3000
          ..load = 0.5;
        final before = source.reads;

        clock.advance(const Duration(seconds: 1));

        expect(source.reads - before, closeTo(30, 2));
        final x = sink.samples;
        expect(rms(x, _rate ~/ 2, x.length), greaterThan(0.03));
      },
    );

    test('with nothing live it is silent', () async {
      await sound.start(profile: EngineProfile.inline4, volume: 1);
      source.live = false;

      clock.advance(const Duration(seconds: 3));

      final x = sink.samples;
      expect(rms(x, x.length - 1000, x.length), lessThan(1e-3));
    });

    test(
      'with no car audio and only that wanted, it says so and stays off',
      () async {
        sink.playable = false;

        await sound.start(profile: EngineProfile.inline4, volume: 1);

        expect(sound.status.value, SoundStatus.noOutput);
        expect(notes.single, contains('no car audio'));
        expect(clock.pendingTasks, 0);
      },
    );

    test('allowed on the speaker, it plays there', () async {
      sink.playable = false;

      await sound.start(
        profile: EngineProfile.inline4,
        volume: 1,
        requireExternalOutput: false,
      );

      expect(sound.status.value, SoundStatus.playing);
    });

    test('the output going away stops it, and it stays off', () async {
      await sound.start(profile: EngineProfile.inline4, volume: 1);
      source.live = true;
      clock.advance(const Duration(seconds: 1));

      sink.lose();
      clock.advance(const Duration(milliseconds: 100));
      await Future<void>.delayed(Duration.zero);

      expect(sound.status.value, SoundStatus.lost);
      expect(notes.last, contains('lost'));
      final reads = source.reads;
      clock.advance(const Duration(seconds: 1));
      expect(source.reads, reads, reason: 'it no longer reads anything');
    });

    test(
      'a profile and a volume chosen while it plays reach the host',
      () async {
        await sound.start(profile: EngineProfile.inline4, volume: 0.5);
        source
          ..live = true
          ..rpm = 3000
          ..load = 0.6;
        clock.advance(const Duration(seconds: 1));

        sound.setProfile(EngineProfile.electric);
        sound.setVolume(1);
        clock.advance(const Duration(seconds: 2));

        expect(sound.profile, EngineProfile.electric);
        expect(notes, contains('sound profile electric'));
        final x = sink.samples;
        expect(rms(x, x.length - _rate, x.length), greaterThan(0.06));
      },
    );

    test('stop ends it: no ticks, the sink closed, and it says so', () async {
      await sound.start(profile: EngineProfile.inline4, volume: 1);

      await sound.stop();

      expect(sound.status.value, SoundStatus.off);
      expect(clock.pendingTasks, 0);
      expect(sink.isOpen, isFalse);
      expect(notes.last, 'sound off');
    });

    test('it can be started again after a stop', () async {
      await sound.start(profile: EngineProfile.inline4, volume: 1);
      await sound.stop();

      await sound.start(profile: EngineProfile.v6, volume: 1);

      expect(sound.status.value, SoundStatus.playing);
      expect(sound.profile, EngineProfile.v6);
    });

    test('stopped while it was starting, it does not come up', () async {
      final starting = sound.start(profile: EngineProfile.inline4, volume: 1);
      await sound.stop();
      await starting;

      expect(sound.status.value, SoundStatus.off);
      expect(clock.pendingTasks, 0);
    });
  });

  group('ScriptedSoundSource', () {
    test('it follows its waypoints and is silent after the last', () {
      final source = ScriptedSoundSource(clock, const [
        (0, 1000, 0.0),
        (2, 3000, 1.0),
      ]);
      final c = EngineControls();

      expect(source.read(c), isTrue);
      expect(c.rpm, closeTo(1000, 1e-9));
      clock.advance(const Duration(seconds: 1));
      expect(source.read(c), isTrue);
      expect(c.rpm, closeTo(2000, 1e-9));
      expect(c.load, closeTo(0.5, 1e-9));
      clock.advance(const Duration(seconds: 2));
      expect(source.read(c), isFalse);
    });

    test(
      'the demonstration is ten and a half seconds and goes from an idle to 4800',
      () {
        final source = ScriptedSoundSource(
          clock,
          ScriptedSoundSource.demonstration,
        );

        expect(source.seconds, 10.5);
        final c = EngineControls();
        var top = 0.0;
        for (var i = 0; i < 105; i++) {
          source.read(c);
          top = math.max(top, c.rpm);
          clock.advance(const Duration(milliseconds: 100));
        }
        expect(top, closeTo(4800, 200));
      },
    );
  });
}

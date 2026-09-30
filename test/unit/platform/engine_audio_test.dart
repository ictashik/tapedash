// The Dart side of the engine audio output, against a mocked platform channel, and
// the isolate that runs the voice. The Android side (EngineAudioChannel.kt) is not
// exercised here; see docs/STATUS.md for what has and has not been verified on a
// device.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/platform/engine_audio.dart';
import 'package:tapedash/sound/engine_profile.dart';
import 'package:tapedash/sound/pcm_sink.dart';

const _channel = MethodChannel('tapedash/engine_audio');

/// A sink in the isolate that tells the test what it was given.
class _ReportingSink implements PcmSink {
  _ReportingSink(this._port);

  final SendPort _port;
  int _frames = 0;
  final Stopwatch _clock = Stopwatch()..start();
  bool _open = false;

  @override
  Future<SinkStart> start(
    int sampleRate, {
    bool requireExternalOutput = false,
  }) async {
    _port.send(['start', sampleRate, requireExternalOutput]);
    _open = true;
    return SinkStart.started;
  }

  @override
  void write(Int16List pcm, int frames) {
    _frames += frames;
    var peak = 0;
    for (var i = 0; i < frames; i++) {
      peak = pcm[i].abs() > peak ? pcm[i].abs() : peak;
    }
    _port.send(['write', frames, peak]);
  }

  @override
  int get queuedFrames {
    final played = (_clock.elapsedMicroseconds / 1e6 * 32000).round();
    return (_frames - played).clamp(0, 1 << 30);
  }

  @override
  bool get isLost => false;

  @override
  int get underruns => 0;

  @override
  Future<void> stop() async {
    if (_open) _port.send(['stop']);
    _open = false;
  }
}

PcmSink _reportingFactory(Object? config) =>
    _ReportingSink(config! as SendPort);

PcmSink _refusingFactory(Object? config) => _RefusingSink();

PcmSink _brokenFactory(Object? config) => throw StateError('no sink');

// Never comes back from being made: the isolate is stuck before it answers.
PcmSink _hangingFactory(Object? config) {
  while (true) {}
}

class _RefusingSink extends _ReportingSink {
  _RefusingSink() : super(ReceivePort().sendPort);

  @override
  Future<SinkStart> start(
    int sampleRate, {
    bool requireExternalOutput = false,
  }) async => SinkStart.noExternalOutput;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Object? Function(MethodCall call) reply;
  late FakeClock clock;

  setUp(() {
    calls = [];
    reply = (_) => null;
    clock = FakeClock();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return reply(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  });

  group('AudioTrackSink', () {
    test(
      'start sends the rate and whether a wire or car audio is required',
      () async {
        reply = (_) => 'started';
        final sink = AudioTrackSink(clock: clock);

        final result = await sink.start(32000, requireExternalOutput: true);

        expect(result, SinkStart.started);
        expect(calls.single.method, 'start');
        expect(calls.single.arguments, {
          'sampleRate': 32000,
          'requireExternal': true,
        });
      },
    );

    test('with no car audio it says so, and is not open', () async {
      reply = (_) => 'noExternalOutput';
      final sink = AudioTrackSink(clock: clock);

      expect(
        await sink.start(32000, requireExternalOutput: true),
        SinkStart.noExternalOutput,
      );
      sink.write(Int16List(64), 64);
      expect(calls.where((c) => c.method == 'write'), isEmpty);
    });

    test(
      'a platform error or a missing platform is a failed start, not a throw',
      () async {
        reply = (_) => throw PlatformException(code: 'boom');
        expect(
          await AudioTrackSink(clock: clock).start(32000),
          SinkStart.failed,
        );

        messenger.setMockMethodCallHandler(_channel, null);
        expect(
          await AudioTrackSink(clock: clock).start(32000),
          SinkStart.failed,
        );
      },
    );

    test(
      'a write sends the samples as little-endian bytes, and the caller may reuse them',
      () async {
        reply = (call) => call.method == 'start' ? 'started' : 512;
        final sink = AudioTrackSink(clock: clock);
        await sink.start(32000);
        final pcm = Int16List.fromList([1, -2, 0x1234, 4]);

        sink.write(pcm, 3);
        pcm[0] = 99;
        await Future<void>.delayed(Duration.zero);

        final write = calls.firstWhere((c) => c.method == 'write');
        expect(
          (write.arguments as Map)['pcm'],
          Uint8List.fromList([1, 0, 0xFE, 0xFF, 0x34, 0x12]),
        );
      },
    );

    test(
      'what is queued is the last answer, plus what is on its way, less what played',
      () async {
        final answers = <Completer<int>>[];
        reply = (call) {
          if (call.method == 'start') return 'started';
          final c = Completer<int>();
          answers.add(c);
          return c.future;
        };
        final sink = AudioTrackSink(clock: clock);
        await sink.start(32000);

        sink.write(Int16List(3200), 3200);
        expect(sink.queuedFrames, 3200, reason: 'in flight, not answered yet');
        answers.single.complete(3000);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(sink.queuedFrames, 3000);

        clock.advance(const Duration(milliseconds: 50));
        expect(sink.queuedFrames, 3000 - 1600);
        clock.advance(const Duration(seconds: 1));
        expect(sink.queuedFrames, 0);
      },
    );

    test('an answer of -1 is an output that was taken away', () async {
      reply = (call) => call.method == 'start' ? 'started' : -1;
      final sink = AudioTrackSink(clock: clock);
      await sink.start(32000);

      sink.write(Int16List(64), 64);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(sink.isLost, isTrue);
      calls.clear();
      sink.write(Int16List(64), 64);
      expect(calls, isEmpty, reason: 'it writes nothing more');
    });

    test('an error on a write is a lost output too', () async {
      reply = (call) {
        if (call.method == 'start') return 'started';
        throw PlatformException(code: 'gone');
      };
      final sink = AudioTrackSink(clock: clock);
      await sink.start(32000);

      sink.write(Int16List(64), 64);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(sink.isLost, isTrue);
    });

    test(
      'underruns are asked for about once a second, less the one at the start',
      () async {
        var count = 1; // one before there was any sound
        reply = (call) => switch (call.method) {
          'start' => 'started',
          'underruns' => count,
          _ => 100,
        };
        final sink = AudioTrackSink(clock: clock);
        await sink.start(32000);

        clock.advance(const Duration(seconds: 2));
        sink.write(Int16List(64), 64);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(sink.underruns, 0);

        count = 4;
        clock.advance(const Duration(seconds: 2));
        sink.write(Int16List(64), 64);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(sink.underruns, 3);
      },
    );

    test('stop tells the phone', () async {
      reply = (call) => call.method == 'start' ? 'started' : null;
      final sink = AudioTrackSink(clock: clock);
      await sink.start(32000);

      await sink.stop();

      expect(calls.last.method, 'stop');
    });

    test('whether car audio is there can be asked', () async {
      reply = (call) => call.method == 'externalOutput';

      expect(await AudioTrackSink.externalOutputAvailable(), isTrue);

      messenger.setMockMethodCallHandler(_channel, null);
      expect(await AudioTrackSink.externalOutputAvailable(), isFalse);
    });
  });

  group('IsolateVoiceHost', () {
    test('the voice runs in another isolate and feeds its sink', () async {
      final reports = ReceivePort();
      final log = <List<Object?>>[];
      reports.listen((m) => log.add(m as List<Object?>));
      final host = IsolateVoiceHost(
        sinkFactory: _reportingFactory,
        sinkConfig: reports.sendPort,
      );

      final result = await host.start(EngineProfile.v8, volume: 0.8);
      host.setControls(rpm: 3000, load: 0.6, active: true);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await host.stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      reports.close();

      expect(result, SinkStart.started);
      expect(log.first, ['start', 32000, false]);
      final frames = log
          .where((m) => m[0] == 'write')
          .fold<int>(0, (a, m) => a + (m[1] as int));
      final peak = log
          .where((m) => m[0] == 'write')
          .fold<int>(0, (a, m) => (m[2] as int) > a ? m[2] as int : a);
      // A little over 0.7 s played at 32 kHz, and the 120 ms ahead.
      expect(frames, inInclusiveRange(32000 * 0.5, 32000 * 1.2));
      expect(peak, greaterThan(500), reason: 'there is sound, at 80% volume');
      expect(log.last, ['stop']);
    });

    test(
      'a sink that cannot start is a start that says why, and nothing is left running',
      () async {
        final host = IsolateVoiceHost(sinkFactory: _refusingFactory);

        final result = await host.start(
          EngineProfile.inline4,
          volume: 1,
          requireExternalOutput: true,
        );

        expect(result, SinkStart.noExternalOutput);
        expect(host.isRunning, isFalse);
      },
    );

    test(
      'a sink that cannot be made is a failed start, not a dead isolate',
      () async {
        final host = IsolateVoiceHost(sinkFactory: _brokenFactory);

        final result = await host.start(EngineProfile.inline4, volume: 1);

        expect(result, SinkStart.failed);
        expect(host.isRunning, isFalse);
      },
    );

    test(
      'an isolate that never answers is a failed start, not a hang',
      () async {
        final host = IsolateVoiceHost(
          sinkFactory: _hangingFactory,
          startTimeout: const Duration(milliseconds: 300),
        );

        final result = await host.start(EngineProfile.inline4, volume: 1);

        expect(result, SinkStart.failed);
        expect(host.isRunning, isFalse);
      },
    );

    test('it can be started again after a stop', () async {
      final reports = ReceivePort();
      reports.listen((_) {});
      final host = IsolateVoiceHost(
        sinkFactory: _reportingFactory,
        sinkConfig: reports.sendPort,
      );

      await host.start(EngineProfile.inline4, volume: 1);
      await host.stop();
      final again = await host.start(EngineProfile.v6, volume: 1);
      await host.stop();
      reports.close();

      expect(again, SinkStart.started);
    });

    test('commands to a host that is not running do nothing', () async {
      final host = IsolateVoiceHost();

      expect(() {
        host.setControls(rpm: 3000, load: 0.5, active: true);
        host.setProfile(EngineProfile.v8);
        host.setVolume(0.5);
      }, returnsNormally);
      await host.stop();
    });
  });
}

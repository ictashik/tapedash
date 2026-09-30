import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../core/clock.dart';
import '../core/scheduler.dart';
import '../sound/engine_profile.dart';
import '../sound/pcm_sink.dart';
import '../sound/voice_host.dart';

/// [PcmSink] on the phone's audio output, through the channel that
/// `EngineAudioChannel.kt` implements: it plays on an `AudioTrack`, on car audio
/// (Bluetooth, a wire, USB) or, if allowed, the phone's speaker.
///
/// A write does not wait for the phone's answer: it sends the samples and goes on,
/// and the answers (how much is still waiting) arrive when they arrive. What the
/// sink reports as queued is the last answer, plus what has been written since,
/// less what has played in the time between.
///
/// Unverified on hardware until the handoff (CLAUDE.md 11). The tests here run
/// against mocked channels.
class AudioTrackSink implements PcmSink {
  AudioTrackSink({MethodChannel? channel, this._clock = const SystemClock()})
    : _channel = channel ?? const MethodChannel('tapedash/engine_audio');

  final MethodChannel _channel;
  final Clock _clock;

  int _rate = 32000;
  int _reported = 0;
  Duration _reportedAt = Duration.zero;
  final Queue<int> _inFlight = Queue<int>();
  bool _lost = false;
  bool _open = false;
  int _underruns = 0;
  int _baseline = -1;
  Duration _lastUnderrunCheck = Duration.zero;

  @override
  Future<SinkStart> start(
    int sampleRate, {
    bool requireExternalOutput = false,
  }) async {
    try {
      final answer = await _channel.invokeMethod<String>('start', {
        'sampleRate': sampleRate,
        'requireExternal': requireExternalOutput,
      });
      switch (answer) {
        case 'started':
          _rate = sampleRate;
          _open = true;
          _lost = false;
          _reported = 0;
          _reportedAt = _clock.monotonic();
          _inFlight.clear();
          _underruns = 0;
          _baseline = -1;
          _lastUnderrunCheck = _reportedAt;
          return SinkStart.started;
        case 'noExternalOutput':
          return SinkStart.noExternalOutput;
        default:
          return SinkStart.failed;
      }
    } on PlatformException {
      return SinkStart.failed;
    } on MissingPluginException {
      return SinkStart.failed;
    }
  }

  @override
  void write(Int16List pcm, int frames) {
    if (!_open || _lost) return;
    // The bytes are copied into the message here and now: the caller may reuse pcm.
    final bytes = Uint8List.sublistView(pcm, 0, frames);
    _inFlight.add(frames);
    unawaited(
      _channel
          .invokeMethod<int>('write', {'pcm': bytes})
          .then(_onAnswer, onError: (Object _) => _lost = true),
    );
    _checkUnderruns();
  }

  void _onAnswer(int? queued) {
    if (_inFlight.isNotEmpty) _inFlight.removeFirst();
    if (queued == null || queued < 0) {
      _lost = true;
      return;
    }
    _reported = queued;
    _reportedAt = _clock.monotonic();
  }

  // The count of times it ran dry is asked for about once a second.
  void _checkUnderruns() {
    final now = _clock.monotonic();
    if (now - _lastUnderrunCheck < const Duration(seconds: 1)) return;
    _lastUnderrunCheck = now;
    unawaited(
      _channel.invokeMethod<int>('underruns').then((n) {
        if (n == null) return;
        // The one at the start, before there was any sound, is not one.
        if (_baseline < 0) _baseline = n;
        _underruns = n - _baseline;
      }, onError: (Object _) {}),
    );
  }

  @override
  int get queuedFrames {
    var waiting = _reported;
    for (final f in _inFlight) {
      waiting += f;
    }
    final played =
        (_clock.monotonic() - _reportedAt).inMicroseconds / 1e6 * _rate;
    final left = waiting - played;
    return left < 0 ? 0 : left.round();
  }

  @override
  bool get isLost => _lost;

  @override
  int get underruns => _underruns;

  @override
  Future<void> stop() async {
    _open = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Already gone.
    } on MissingPluginException {
      // No platform, as in a test.
    }
  }

  /// Whether there is car audio (Bluetooth, a wire or USB) to play on now.
  static Future<bool> externalOutputAvailable({MethodChannel? channel}) async {
    try {
      return await (channel ?? const MethodChannel('tapedash/engine_audio'))
              .invokeMethod<bool>('externalOutput') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Makes the sink inside the isolate, from the [config] it was given. A top-level
/// function of this kind is what crosses to the isolate.
typedef SinkFactory = PcmSink Function(Object? config);

PcmSink audioTrackSinkFactory(Object? config) => AudioTrackSink();

/// A [VoiceHost] that runs the whole voice (the synth and the pacing of its sink) in
/// an isolate of its own, so that nothing in it can make a frame of the drive
/// late: the drive's UI isolate sends it the controls thirty times a second and
/// that is all.
///
/// In the isolate the platform channel is reached through
/// `BackgroundIsolateBinaryMessenger`.
class IsolateVoiceHost implements VoiceHost {
  IsolateVoiceHost({
    this.sinkFactory = audioTrackSinkFactory,
    this.sinkConfig,
    this.startTimeout = const Duration(seconds: 5),
  });

  /// How long to wait for the isolate to come up and open its output.
  final Duration startTimeout;

  final SinkFactory sinkFactory;

  /// Sent to [sinkFactory] in the isolate (it must be something an isolate can be
  /// sent).
  final Object? sinkConfig;

  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _replies;
  Completer<SinkStart>? _starting;
  Completer<void>? _stopping;
  final StreamController<String> _events = StreamController.broadcast();

  @override
  Stream<String> get events => _events.stream;

  bool get isRunning => _commands != null;

  @override
  Future<SinkStart> start(
    EngineProfile profile, {
    required double volume,
    bool requireExternalOutput = false,
  }) async {
    if (_commands != null) await stop();
    final replies = ReceivePort();
    _replies = replies;
    final ready = Completer<SendPort>();
    _starting = Completer<SinkStart>();
    replies.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is List && message.isNotEmpty) {
        switch (message[0]) {
          case 'started':
            _starting?.complete(SinkStart.values[message[1] as int]);
          case 'event':
            _events.add(message[1] as String);
          case 'stopped':
            _stopping?.complete();
        }
      }
    });
    try {
      _isolate = await Isolate.spawn(
        _voiceEntry,
        _VoiceInit(
          replies: replies.sendPort,
          token: RootIsolateToken.instance,
          sinkFactory: sinkFactory,
          sinkConfig: sinkConfig,
        ),
        debugName: 'tapedash-engine-voice',
      );
    } on Object {
      _cleanUp();
      return SinkStart.failed;
    }
    try {
      final commands = await ready.future.timeout(startTimeout);
      _commands = commands;
      commands.send(['start', profile.id, volume, requireExternalOutput]);
      final result = await _starting!.future.timeout(startTimeout);
      if (result != SinkStart.started) _cleanUp();
      return result;
    } on TimeoutException {
      // The isolate never answered (it died making its sink, say).
      _cleanUp();
      return SinkStart.failed;
    }
  }

  @override
  void setProfile(EngineProfile profile) =>
      _commands?.send(['profile', profile.id]);

  @override
  void setVolume(double volume) => _commands?.send(['volume', volume]);

  @override
  void setControls({
    required double rpm,
    required double load,
    required bool active,
  }) => _commands?.send(['controls', rpm, load, active]);

  @override
  Future<void> stop() async {
    final commands = _commands;
    if (commands == null) return;
    _stopping = Completer<void>();
    commands.send(['stop']);
    await _stopping!.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    _cleanUp();
  }

  void _cleanUp() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _replies?.close();
    _replies = null;
    _starting = null;
    _stopping = null;
  }
}

class _VoiceInit {
  const _VoiceInit({
    required this.replies,
    required this.token,
    required this.sinkFactory,
    required this.sinkConfig,
  });

  final SendPort replies;
  final RootIsolateToken? token;
  final SinkFactory sinkFactory;
  final Object? sinkConfig;
}

/// The isolate's whole life: it listens for commands and runs a [SynthVoiceHost]
/// on real time.
Future<void> _voiceEntry(_VoiceInit init) async {
  final token = init.token;
  if (token != null) BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final commands = ReceivePort();
  init.replies.send(commands.sendPort);
  // A sink that cannot be made is a start that fails, not an isolate that dies.
  SynthVoiceHost? host;
  try {
    host = SynthVoiceHost(
      sink: init.sinkFactory(init.sinkConfig),
      scheduler: const SystemScheduler(),
      clock: const SystemClock(),
    );
    host.events.listen((e) => init.replies.send(['event', e]));
  } on Object {
    host = null;
  }
  await for (final message in commands) {
    if (message is! List || message.isEmpty) continue;
    switch (message[0]) {
      case 'start':
        final result =
            await host?.start(
              EngineProfile.byId(message[1] as String),
              volume: message[2] as double,
              requireExternalOutput: message[3] as bool,
            ) ??
            SinkStart.failed;
        init.replies.send(['started', result.index]);
      case 'profile':
        host?.setProfile(EngineProfile.byId(message[1] as String));
      case 'volume':
        host?.setVolume(message[1] as double);
      case 'controls':
        host?.setControls(
          rpm: message[1] as double,
          load: message[2] as double,
          active: message[3] as bool,
        );
      case 'stop':
        await host?.stop();
        init.replies.send(['stopped']);
        commands.close();
    }
  }
}

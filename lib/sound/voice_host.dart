import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/clock.dart';
import '../core/scheduler.dart';
import 'engine_profile.dart';
import 'engine_synth.dart';
import 'pcm_sink.dart';

/// Whatever makes the engine's sound from the controls it is given: the synth
/// feeding a sink in this isolate ([SynthVoiceHost]), or the same in another one
/// (`IsolateVoiceHost`, so that the drive's frames never wait for audio).
abstract interface class VoiceHost {
  /// Brings the voice up with [profile] at [volume] (0 to 1). False answers say why
  /// it did not.
  Future<SinkStart> start(
    EngineProfile profile, {
    required double volume,
    bool requireExternalOutput = false,
  });

  void setProfile(EngineProfile profile);

  /// 0 to 1, of full scale.
  void setVolume(double volume);

  /// Where the sound is to go: the revs, the load (0 to 1), and whether there is an
  /// engine to hear (otherwise it fades out). Call it as often as there is news.
  void setControls({
    required double rpm,
    required double load,
    required bool active,
  });

  /// What the audio side has to say: `lost` (the output was taken away: it has
  /// stopped), `underruns N`, or a note.
  Stream<String> get events;

  Future<void> stop();
}

/// A [VoiceHost] that runs the synth here and keeps a [PcmSink] a little ahead of
/// its playing: every [tick] it asks how much is waiting, and renders what makes
/// up the difference to [ahead].
///
/// The sink is kept about [ahead] (120 ms) ahead: enough to ride out a late tick
/// and a slow frame, and little enough that the sound is not long behind the
/// controls (the Bluetooth link behind it is a good deal more).
///
/// Changing the profile crossfades: the old engine fades out over half a second
/// as the new one comes in, so that there is no click.
class SynthVoiceHost implements VoiceHost {
  SynthVoiceHost({
    required this.sink,
    required this.scheduler,
    required this.clock,
    this.sampleRate = 32000,
    this.tick = const Duration(milliseconds: 20),
    this.ahead = const Duration(milliseconds: 120),
  });

  final PcmSink sink;
  final Scheduler scheduler;
  final Clock clock;
  final int sampleRate;
  final Duration tick;
  final Duration ahead;

  static const int _chunk = 512;

  EngineSynth? _synth;
  EngineSynth? _outgoing;
  Duration? _outgoingUntil;
  ScheduledTask? _task;
  double _volume = 1;
  double _rpm = 0;
  double _load = 0;
  bool _active = false;
  int _reportedUnderruns = 0;
  bool _stopped = true;
  final StreamController<String> _events = StreamController.broadcast();

  final Int16List _pcm = Int16List(_chunk);
  final Float64List _mix = Float64List(_chunk);
  final Float64List _old = Float64List(_chunk);

  @override
  Stream<String> get events => _events.stream;

  /// Whether it is running.
  bool get isRunning => !_stopped;

  @override
  Future<SinkStart> start(
    EngineProfile profile, {
    required double volume,
    bool requireExternalOutput = false,
  }) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    final result = await sink.start(
      sampleRate,
      requireExternalOutput: requireExternalOutput,
    );
    if (result != SinkStart.started) return result;
    _stopped = false;
    _reportedUnderruns = 0;
    _synth = _make(profile);
    _pump();
    _task = scheduler.runEvery(tick, _pump);
    return SinkStart.started;
  }

  EngineSynth _make(EngineProfile profile) {
    final synth = EngineSynth(profile, sampleRate: sampleRate);
    synth.setTargets(rpm: _rpm, load: _load, active: _active);
    return synth;
  }

  @override
  void setProfile(EngineProfile profile) {
    final current = _synth;
    if (current == null || identical(current.profile, profile)) return;
    // The old one fades out while the new one comes in.
    _outgoing = current..setTargets(rpm: _rpm, load: _load, active: false);
    _outgoingUntil = clock.monotonic() + const Duration(milliseconds: 700);
    _synth = _make(profile);
  }

  @override
  void setVolume(double volume) => _volume = volume.clamp(0.0, 1.0).toDouble();

  @override
  void setControls({
    required double rpm,
    required double load,
    required bool active,
  }) {
    _rpm = rpm;
    _load = load;
    _active = active;
    _synth?.setTargets(rpm: rpm, load: load, active: active);
  }

  void _pump() {
    if (_stopped) return;
    if (sink.isLost) {
      _events.add('lost');
      _shutDown();
      return;
    }
    final target = (ahead.inMicroseconds / 1e6 * sampleRate).round();
    var queued = sink.queuedFrames;
    final synth = _synth;
    if (synth == null) return;
    final outgoing = _outgoing;
    if (outgoing != null && clock.monotonic() >= _outgoingUntil!) {
      _outgoing = null;
      _outgoingUntil = null;
    }
    while (queued < target) {
      final n = math.min(_chunk, math.max(64, target - queued));
      synth.renderFloat(_mix, n);
      final fading = _outgoing;
      if (fading != null) {
        fading.renderFloat(_old, n);
        for (var i = 0; i < n; i++) {
          _mix[i] += _old[i];
        }
      }
      EngineSynth.toPcm16(_mix, n, _pcm, 0, volume: _volume);
      sink.write(_pcm, n);
      queued += n;
    }
    final underruns = sink.underruns;
    if (underruns > _reportedUnderruns) {
      _reportedUnderruns = underruns;
      _events.add('underruns $underruns');
    }
  }

  void _shutDown() {
    _stopped = true;
    _task?.cancel();
    _task = null;
  }

  @override
  Future<void> stop() async {
    if (_stopped && _synth == null) return;
    _shutDown();
    _synth = null;
    _outgoing = null;
    await sink.stop();
  }
}

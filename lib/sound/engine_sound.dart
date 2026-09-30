import 'dart:async';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import 'engine_profile.dart';
import 'pcm_sink.dart';
import 'voice_host.dart';

/// What the engine sound is told, filled in place: the revs, and the load, 0 to 1.
class EngineControls {
  double rpm = 0;
  double load = 0;
}

/// Where the engine sound gets its controls: the drive's smoothed signals
/// (live), or a replayed trip.
abstract interface class EngineSoundSource {
  /// The load the engine is under, 0 to 1, from the throttle position and the
  /// engine load, both in percent (either may be missing: pass 0).
  ///
  /// An engine at an idle reports a throttle of about 12 % and a load of 25 to 30 %,
  /// and that is no load to the ear: each is measured from its idle, and the load is
  /// weighed a little below the throttle, which is what the driver's foot is doing.
  static double loadFrom(double throttlePercent, double loadPercent) {
    final foot = (throttlePercent - 12) / 88;
    final engine = (loadPercent - 28) / 72 * 0.85;
    return (foot > engine ? foot : engine).clamp(0.0, 1.0).toDouble();
  }

  /// The revs below which there is no engine to hear: off, or turning over.
  static const double minRpm = 350;

  /// Fills [out] with the revs and the load as they should sound now, and says
  /// whether there is an engine to hear: false with no data, a stale link, or the
  /// engine off, and the sound fades out.
  bool read(EngineControls out);
}

/// Where the engine sound is.
enum SoundStatus {
  off,
  starting,
  playing,

  /// There is no car audio to play on, and the phone's speaker is not wanted.
  noOutput,

  /// It was playing and the output was taken away (the Bluetooth link dropped, or
  /// the app left the screen): it stays off until started again.
  lost,

  failed,
}

/// The engine sound (see `EngineSynth`): it reads a [source] thirty times a second
/// and passes what it says to a [VoiceHost], which makes the sound.
///
/// It is passive by design (CLAUDE.md 1.5 and 9): nothing on the screen changes
/// and nothing is asked of the driver; there is no cue, no alert and no voice. It
/// only says what the engine is doing, and it goes quiet by itself when the data
/// does (the link lost, the engine off).
class EngineSound {
  EngineSound({
    required this.host,
    required this.source,
    required this.scheduler,
    this.clock,
    this.tick = const Duration(milliseconds: 33),
    this.note,
  });

  final VoiceHost host;
  final EngineSoundSource source;
  final Scheduler scheduler;
  final Clock? clock;
  final Duration tick;

  /// Where what happens is written down (the session recording), or null.
  final void Function(String line)? note;

  final ObservableValue<SoundStatus> status = ObservableValue(SoundStatus.off);

  final EngineControls _controls = EngineControls();
  ScheduledTask? _task;
  StreamSubscription<String>? _events;
  EngineProfile _profile = EngineProfile.inline4;
  double _volume = 0.7;

  EngineProfile get profile => _profile;
  double get volume => _volume;

  bool get isPlaying => status.value == SoundStatus.playing;

  /// Brings the sound up. With [requireExternalOutput] it stays off unless there is
  /// car audio (or a wire) to play on: [status] says `noOutput` then.
  Future<void> start({
    required EngineProfile profile,
    required double volume,
    bool requireExternalOutput = true,
  }) async {
    if (status.value == SoundStatus.starting || isPlaying) return;
    _profile = profile;
    _volume = volume;
    status.value = SoundStatus.starting;
    _events ??= host.events.listen(_onEvent);
    final result = await host.start(
      profile,
      volume: volume,
      requireExternalOutput: requireExternalOutput,
    );
    if (status.value != SoundStatus.starting) {
      // Stopped while it was starting.
      if (result == SinkStart.started) await host.stop();
      return;
    }
    switch (result) {
      case SinkStart.started:
        status.value = SoundStatus.playing;
        note?.call('sound on ${profile.id} at ${(volume * 100).round()} %');
        _task = scheduler.runEvery(tick, _tick);
        _tick();
      case SinkStart.noExternalOutput:
        status.value = SoundStatus.noOutput;
        note?.call('sound not started: no car audio to play on');
      case SinkStart.failed:
        status.value = SoundStatus.failed;
        note?.call('sound failed to start');
    }
  }

  void setProfile(EngineProfile profile) {
    _profile = profile;
    if (isPlaying) {
      host.setProfile(profile);
      note?.call('sound profile ${profile.id}');
    }
  }

  void setVolume(double volume) {
    _volume = volume;
    if (isPlaying) host.setVolume(volume);
  }

  void _tick() {
    if (!isPlaying) return;
    final live = source.read(_controls);
    host.setControls(rpm: _controls.rpm, load: _controls.load, active: live);
  }

  void _onEvent(String event) {
    if (event == 'lost') {
      _task?.cancel();
      _task = null;
      if (isPlaying || status.value == SoundStatus.starting) {
        status.value = SoundStatus.lost;
        note?.call('sound lost: the audio output went away');
      }
    } else {
      note?.call('sound $event');
    }
  }

  Future<void> stop() async {
    _task?.cancel();
    _task = null;
    final wasOn = status.value != SoundStatus.off;
    status.value = SoundStatus.off;
    await host.stop();
    if (wasOn) note?.call('sound off');
  }

  Future<void> dispose() async {
    await stop();
    await _events?.cancel();
    _events = null;
  }
}

/// A scripted source: the revs and the load along waypoints of (seconds, rpm,
/// load), joined by straight lines, from the moment it is made, and silent after
/// the last: the Garage's "Test sound".
class ScriptedSoundSource implements EngineSoundSource {
  ScriptedSoundSource(this._clock, this.script) : _from = _clock.monotonic();

  final Clock _clock;
  final List<(double, double, double)> script;
  final Duration _from;

  /// A short demonstration: an idle, a pull up through the revs, a lift, and back.
  static const List<(double, double, double)> demonstration = [
    (0, 800, 0.12),
    (1.5, 800, 0.12),
    (5, 4800, 0.85),
    (5.6, 3300, 0.0),
    (8, 1500, 0.0),
    (9.5, 800, 0.12),
    (10.5, 800, 0.12),
  ];

  /// How long the script runs.
  double get seconds => script.last.$1;

  @override
  bool read(EngineControls out) {
    final t = (_clock.monotonic() - _from).inMicroseconds / 1e6;
    if (t >= seconds) {
      out
        ..rpm = script.last.$2
        ..load = script.last.$3;
      return false;
    }
    var i = 0;
    while (i < script.length - 2 && script[i + 1].$1 <= t) {
      i++;
    }
    final a = script[i];
    final b = script[i + 1];
    final f = b.$1 == a.$1 ? 1.0 : ((t - a.$1) / (b.$1 - a.$1)).clamp(0.0, 1.0);
    out
      ..rpm = a.$2 + (b.$2 - a.$2) * f
      ..load = a.$3 + (b.$3 - a.$3) * f;
    return true;
  }
}

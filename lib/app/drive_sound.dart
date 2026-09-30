import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/scheduler.dart';
import '../platform/engine_audio.dart';
import '../sound/engine_profile.dart';
import '../sound/engine_sound.dart';
import '../sound/voice_host.dart';
import '../ui/design/motion/trip_player.dart';
import '../ui/pages/review/replay_sound.dart';
import 'app_settings.dart';
import 'engine_sound_sources.dart';

/// The engine sound of the running app (lib/sound): it follows the Garage's
/// settings, starts and stops with the screen, and keeps the three voices that can
/// want the speaker from sounding over each other:
///
///  * **Live:** the drive's signals, while the setting is on and the app is on
///    screen. It plays on car audio only (Bluetooth, a wire or USB) unless the
///    Garage allows the phone's speaker, and stops if that output goes away.
///  * **A replay** in Review: the replayed trip's revs, on whatever output there is
///    (it is parked, at a desk or in the car, and asked for).
///  * **The test** in Garage: a ten second demonstration, on whatever output there
///    is.
/// A replay or a test takes the speaker from the live voice for as long as it lasts.
///
/// There is no foreground service (no new permission): the sound belongs to the
/// screen that is showing, and stops when the app leaves it.
class DriveSound with WidgetsBindingObserver implements ReplaySound {
  DriveSound({
    required this.settings,
    required this.live,
    required this.scheduler,
    required this.clock,
    VoiceHost Function()? hostFactory,
    this.note,
  }) : _hostFactory = hostFactory ?? IsolateVoiceHost.new;

  final AppSettings settings;
  final EngineSoundSource live;
  final Scheduler scheduler;
  final Clock clock;
  final void Function(String line)? note;
  final VoiceHost Function() _hostFactory;

  /// Where the live voice is, for the Garage to say.
  final ValueNotifier<SoundStatus> status = ValueNotifier(SoundStatus.off);

  /// Whether the Garage's test is playing.
  final ValueNotifier<bool> testing = ValueNotifier(false);

  EngineSound? _live;
  EngineSound? _other; // the replay's, or the test's
  ScheduledTask? _testEnd;
  bool _foreground = true;
  bool _replaying = false;
  bool _started = false;
  bool _disposed = false;

  /// Starts following the settings and the screen. Call it once.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    settings.soundEnabled.addListener(_apply);
    settings.soundOnSpeaker.addListener(_restart);
    settings.soundProfile.addListener(_onProfile);
    settings.soundVolume.addListener(_onVolume);
    _apply();
  }

  bool get _free => !_replaying && !testing.value && !_disposed;

  EngineProfile get _profile => EngineProfile.byId(settings.soundProfile.value);

  /// Brings the live voice to what the settings want.
  void _apply() {
    if (!_free) return;
    if (settings.soundEnabled.value && _foreground) {
      unawaited(_startLive());
    } else {
      unawaited(_stopLive());
    }
  }

  Future<void> _startLive() async {
    var sound = _live;
    if (sound != null &&
        (sound.status.value == SoundStatus.playing ||
            sound.status.value == SoundStatus.starting)) {
      return;
    }
    sound ??= _live = EngineSound(
      host: _hostFactory(),
      source: live,
      scheduler: scheduler,
      note: note,
    )..status.addListener(_mirror);
    await sound.start(
      profile: _profile,
      volume: settings.soundVolume.value,
      requireExternalOutput: !settings.soundOnSpeaker.value,
    );
    _mirror();
  }

  Future<void> _stopLive() async {
    await _live?.stop();
    _mirror();
  }

  void _mirror() {
    if (_disposed) return;
    status.value = _live?.status.value ?? SoundStatus.off;
  }

  void _restart() {
    if (!_free) return;
    unawaited(() async {
      await _stopLive();
      _apply();
    }());
  }

  void _onProfile() {
    final profile = _profile;
    _live?.setProfile(profile);
    _other?.setProfile(profile);
  }

  void _onVolume() {
    final volume = settings.soundVolume.value;
    _live?.setVolume(volume);
    _other?.setVolume(volume);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        if (status.value == SoundStatus.lost) {
          // It was taken away when the screen went: coming back is asking again.
          unawaited(_live?.stop().then((_) => _apply()));
        } else {
          _apply();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _foreground = false;
        _apply();
        unawaited(_other?.stop());
      case AppLifecycleState.inactive:
        break;
    }
  }

  // ---- The Garage's test ----

  /// Plays the ten second demonstration of the chosen engine, on whatever output
  /// there is (Bluetooth, a wire, or the phone's speaker), and puts the live voice
  /// back when it is done. Pressed again while it plays, it stops.
  Future<void> test() async {
    if (testing.value) {
      await _endOther();
      return;
    }
    if (_replaying || _disposed) return;
    testing.value = true;
    await _stopLive();
    final script = ScriptedSoundSource(
      clock,
      ScriptedSoundSource.demonstration,
    );
    final sound = _other = EngineSound(
      host: _hostFactory(),
      source: script,
      scheduler: scheduler,
      note: note,
    );
    await sound.start(
      profile: _profile,
      volume: settings.soundVolume.value,
      requireExternalOutput: false,
    );
    if (sound.status.value != SoundStatus.playing) {
      await _endOther();
      return;
    }
    // Its own tail: the script ends, and the engine fades out over a moment.
    _testEnd = scheduler.runAfter(
      Duration(milliseconds: (script.seconds * 1000).round() + 1500),
      () => unawaited(_endOther()),
    );
  }

  Future<void> _endOther() async {
    _testEnd?.cancel();
    _testEnd = null;
    final sound = _other;
    _other = null;
    await sound?.dispose();
    final wasTesting = testing.value;
    testing.value = false;
    if (wasTesting) _apply();
  }

  // ---- A replay in Review ----

  @override
  void begin(TripPlayer player) {
    if (!settings.soundEnabled.value || _disposed) return;
    _replaying = true;
    unawaited(() async {
      await _stopLive();
      if (!_replaying) return;
      final sound = _other = EngineSound(
        host: _hostFactory(),
        source: ReplaySoundSource(player),
        scheduler: scheduler,
        note: note,
      );
      await sound.start(
        profile: _profile,
        volume: settings.soundVolume.value,
        requireExternalOutput: false,
      );
    }());
  }

  @override
  void end() {
    if (!_replaying) return;
    _replaying = false;
    unawaited(() async {
      await _endOther();
      _apply();
    }());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      settings.soundEnabled.removeListener(_apply);
      settings.soundOnSpeaker.removeListener(_restart);
      settings.soundProfile.removeListener(_onProfile);
      settings.soundVolume.removeListener(_onVolume);
    }
    _testEnd?.cancel();
    unawaited(_other?.dispose());
    _live?.status.removeListener(_mirror);
    unawaited(_live?.dispose());
    status.dispose();
    testing.dispose();
  }
}

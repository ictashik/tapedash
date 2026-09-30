import '../sound/engine_sound.dart';
import '../trips/trip_playback.dart';
import '../ui/design/motion/trip_player.dart';
import '../ui/pages/drive/drive_signals.dart';

/// The drive's own signals as the engine sound's source: the revs, the throttle and
/// the load as the tach shows them (the smoothed, played-out signals, so that the
/// sound is what the needle does), and silence when there is no engine to hear: the
/// data stale or never come (the link lost), or the revs below turning-over.
class LiveSoundSource implements EngineSoundSource {
  LiveSoundSource(this.signals);

  final DriveSignals signals;

  /// How stale a signal may be before the sound goes: it goes as the needle does.
  static const double maxStaleness = 0.5;

  @override
  bool read(EngineControls out) {
    final rpm = signals.rpm;
    if (!rpm.hasValue ||
        rpm.staleness > maxStaleness ||
        rpm.value < EngineSoundSource.minRpm) {
      return false;
    }
    final throttle = signals.throttle;
    final load = signals.load;
    out
      ..rpm = rpm.value
      ..load = EngineSoundSource.loadFrom(
        throttle.hasValue && throttle.staleness <= maxStaleness
            ? throttle.value
            : 0,
        load.hasValue && load.staleness <= maxStaleness ? load.value : 0,
      );
    return true;
  }
}

/// A replayed trip as the engine sound's source: what the car was doing a moment
/// from now, since the sound reaches the ear that much later than the picture does
/// ([lead]: the synth's look-ahead and the audio output's buffer), and silence when
/// the replay is paused or has ended.
class ReplaySoundSource implements EngineSoundSource {
  ReplaySoundSource(this.player, {this.lead = 0.3});

  final TripPlayer player;

  /// How far ahead of the picture the sound is taken, in seconds of the replay at
  /// 1 times (and more at 2 and 3 times: it is a stretch of real time).
  final double lead;

  final PlaybackFrame _frame = PlaybackFrame();

  @override
  bool read(EngineControls out) {
    if (!player.isPlaying) return false;
    player.playback.fill(_frame, player.seconds + lead * player.rate);
    if (_frame.rpm < EngineSoundSource.minRpm) return false;
    out
      ..rpm = _frame.rpm
      ..load = EngineSoundSource.loadFrom(
        _frame.throttle,
        _frame.load.isNaN ? 0 : _frame.load,
      );
    return true;
  }
}

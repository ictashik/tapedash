import 'package:flutter/foundation.dart';

import '../../../trips/trip_playback.dart';
import '../tokens/motion_tokens.dart';
import 'motion_clock.dart';

/// The transport of a trip replay (DESIGN.md 6.12): a play head on a
/// [TripPlayback], run by the [MotionClock] at 1, 2 or 3 times real time.
///
/// It notifies on every frame it moves, and [frame] is the moment it is at,
/// filled in place: listeners (painters and the camera) read it and draw, and
/// nothing rebuilds. It runs on the motion clock, so it slows with `timeDilation`
/// like everything else, and a stalled frame does not make it jump.
class TripPlayer extends ChangeNotifier implements MotionDriven {
  TripPlayer({required this.clock, required this.playback}) {
    playback.fill(frame, 0);
  }

  final MotionClock clock;
  final TripPlayback playback;

  /// Where the play head is: updated in place, never replaced.
  final PlaybackFrame frame = PlaybackFrame();

  double _seconds = 0;
  int _rate = 0;
  bool _playing = false;
  bool _disposed = false;

  /// How far into the replay, in seconds at 1 times.
  double get seconds => _seconds;

  double get duration => playback.duration;

  /// 0 to 1.
  double get progress =>
      duration <= 0 ? 0 : (_seconds / duration).clamp(0.0, 1.0);

  bool get isPlaying => _playing;

  /// Whether the play head is at the end.
  bool get isAtEnd => _seconds >= duration;

  /// The speed, a multiple of real time: one of [TapeReplay.rates].
  double get rate => TapeReplay.rates[_rate];

  /// Starts, or carries on; from the start again if it had reached the end.
  void play() {
    if (_playing || playback.duration <= 0) return;
    if (isAtEnd) _moveTo(0);
    _playing = true;
    clock.attach(this);
    notifyListeners();
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    clock.detach(this);
    notifyListeners();
  }

  void toggle() => _playing ? pause() : play();

  /// The next speed: 1, 2, 3 and round again.
  void cycleRate() {
    _rate = (_rate + 1) % TapeReplay.rates.length;
    notifyListeners();
  }

  /// Moves the play head to [seconds], playing or not (the scrubber, a tap on the
  /// route).
  void seekTo(double seconds) {
    _moveTo(seconds);
    notifyListeners();
  }

  /// Moves the play head to a fractional sample of the trip.
  void seekToSample(double sample) =>
      seekTo(playback.timeOfFractionalSample(sample));

  void _moveTo(double seconds) {
    _seconds = seconds.clamp(0.0, duration).toDouble();
    playback.fill(frame, _seconds);
  }

  @override
  bool advance(double dt, Duration time) {
    if (!_playing) return false;
    _moveTo(_seconds + dt * rate);
    if (isAtEnd) {
      _playing = false;
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clock.detach(this);
    super.dispose();
  }
}

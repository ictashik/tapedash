import '../../design/motion/trip_player.dart';

/// What Review asks of the engine sound while a trip replays (lib/app/drive_sound.dart
/// provides it): [begin] when the replay's instruments come up, [end] when they go.
/// The sound follows the play head by itself from then on (it is silent while the
/// replay is paused).
abstract interface class ReplaySound {
  void begin(TripPlayer player);

  void end();
}

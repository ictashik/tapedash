import '../fuel/fuel_estimator.dart';
import '../obd/obd_session.dart';
import '../obd/poller.dart';
import 'trip_recorder.dart';

/// Moves the fuel source's PID to the fast tier while a trip is being recorded
/// (CLAUDE.md 8.2): money accuracy depends on how often the air flow or the fuel
/// rate is read, and once a second is too slow to see a coast with the fuel cut.
///
/// Until a source has been chosen it asks for all three candidates; once one is
/// chosen it asks for that one only.
class RecordingDemand {
  RecordingDemand({
    required this.session,
    required this.recorder,
    required this.estimator,
  }) {
    recorder.phase.addListener(_update);
    estimator.source.addListener(_update);
    _update();
  }

  final ObdSession session;
  final TripRecorder recorder;
  final FuelEstimator estimator;

  SessionDemand? _demand;
  Set<int> _held = {};

  /// The PIDs each source reads its main value from.
  static Set<int> pidsFor(FuelSource source) => switch (source) {
    FuelSource.fuelRate => {0x5E},
    FuelSource.airFlow => {0x10},
    FuelSource.speedDensity => {0x0B},
    FuelSource.none => {0x5E, 0x10, 0x0B},
  };

  /// The PIDs held at the fast tier now.
  Set<int> get held => Set.unmodifiable(_held);

  void _update() {
    final want = recorder.recording ? pidsFor(estimator.source.value) : <int>{};
    if (want.length == _held.length && want.containsAll(_held)) return;
    _demand?.release();
    _demand = null;
    _held = want;
    if (want.isNotEmpty) {
      _demand = session.demand({for (final p in want) p: PollTier.fast});
    }
  }

  void dispose() {
    recorder.phase.removeListener(_update);
    estimator.source.removeListener(_update);
    _demand?.release();
    _demand = null;
  }
}

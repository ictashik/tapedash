import '../coach/coach_monitor.dart';
import '../coach/coach_thresholds.dart';
import '../coach/hard_event_detector.dart';
import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../fuel/fuel_estimator.dart';
import '../location/location_source.dart';
import '../money/trip_computer.dart';
import '../obd/obd_session.dart';
import '../trips/recording_demand.dart';
import '../trips/trip_recorder.dart';
import '../vehicle/vehicle_state.dart';
import 'app_services.dart';

/// Everything that turns a car's readings into a trip, its fuel and its money
/// (CLAUDE.md 6), for one source of readings: a demo drive now, a real adapter's
/// session later.
///
/// The chain is the one the end-to-end tests run: [VehicleState] to the fuel
/// estimator and the hard-event detector, to the [TripComputer], to the
/// [TripRecorder], with the fuel PID moved to the fast tier while a trip is
/// recorded.
class DriveServices {
  DriveServices({
    required this.vehicle,
    required this.connection,
    required this.app,
    required this.clock,
    required this.scheduler,
    this.sessions,
    this.isDemo = false,
    this.location,
    CoachThresholds thresholds = CoachThresholds.normal,
  }) {
    estimator = FuelEstimator(vehicle: vehicle, setup: app.setup.value);
    hardEvents = HardEventDetector(vehicle: vehicle, thresholds: thresholds);
    coach = CoachMonitor(vehicle: vehicle, thresholds: thresholds);
    computer = TripComputer(
      vehicle: vehicle,
      estimator: estimator,
      hardEvents: hardEvents,
      calibrationFactor: () => app.ledger.calibration.factor,
      price: app.money.price,
      setup: app.setup.value,
      thresholds: thresholds,
      location: location,
      onEstimate: app.ledger.addEstimate,
    );
    recorder = TripRecorder(
      vehicle: vehicle,
      connection: connection,
      computer: computer,
      hardEvents: hardEvents,
      estimator: estimator,
      repository: app.trips,
      clock: clock,
      scheduler: scheduler,
      calibrationFactor: () => app.ledger.calibration.factor,
      price: app.money.price,
      ledger: app.ledger,
      coach: coach,
      location: location,
      isDemo: isDemo,
    );
    if (sessions != null) {
      demand = RecordingDemand(
        sessions: sessions!,
        recorder: recorder,
        estimator: estimator,
      );
    }
    app.setup.addListener(_onSetup);
  }

  final VehicleState vehicle;
  final Observable<ConnectionStatus> connection;
  final AppServices app;
  final Clock clock;
  final Scheduler scheduler;

  /// The OBD session(s) to move the fuel PID to the fast tier on, if any.
  final Observable<ObdSession?>? sessions;
  final bool isDemo;
  final LocationSource? location;

  late final FuelEstimator estimator;
  late final HardEventDetector hardEvents;
  late final CoachMonitor coach;
  late final TripComputer computer;
  late final TripRecorder recorder;
  RecordingDemand? demand;

  void _onSetup() {
    estimator.setup = app.setup.value;
    computer.setup = app.setup.value;
  }

  /// Saves what there is and lets go of everything.
  Future<void> close() async {
    app.setup.removeListener(_onSetup);
    demand?.dispose();
    await recorder.close();
    computer.dispose();
    coach.dispose();
    hardEvents.dispose();
    estimator.dispose();
  }
}

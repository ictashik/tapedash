import '../coach/coach_monitor.dart';
import '../coach/coach_thresholds.dart';
import '../coach/hard_event_detector.dart';
import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../fuel/fuel_constants.dart' show FuelType;
import '../fuel/fuel_estimator.dart';
import '../location/location_source.dart';
import '../money/spend_bucket.dart';
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
    this.note,
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
      countedRemaining: () => app.ledger.litresLeft(app.setup.value.tankLitres),
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
    if (note != null) _startNotes(note!);
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

  /// Where the app writes what it is making of the car, for a recording of the
  /// drive to carry (`LiveDrive.note`). Null for a demo.
  final void Function(String)? note;

  late final FuelEstimator estimator;
  late final HardEventDetector hardEvents;
  late final CoachMonitor coach;
  late final TripComputer computer;
  late final TripRecorder recorder;
  RecordingDemand? demand;

  final List<void Function()> _noteUnbind = [];
  ScheduledTask? _vitals;

  /// Says, into the recording, the app's own view of the drive: the setup, each
  /// change of the connection, the engine, the mode and the trip, and every 5 s
  /// the numbers the money is made of. It is what a log needs to show why a trip
  /// ended, or why a figure is what it is; none of it is used by the app.
  void _startNotes(void Function(String) say) {
    String fixed(double? v, int n) => v == null ? '-' : v.toStringAsFixed(n);

    void watch(Observable<Object?> o, String Function() line) {
      void l() => say(line());
      o.addListener(l);
      _noteUnbind.add(() => o.removeListener(l));
    }

    final s = app.setup.value;
    say(
      'setup ${s.fuelType.name} ${s.fuelType == FuelType.petrol ? '${s.blend.label} ' : ''}'
      '${s.displacementLitres.toStringAsFixed(1)} L, tank ${s.tankLitres.round()} L, '
      'price ${fixed(app.money.price.value, 2)}, '
      'calibration ${app.ledger.calibration.factor.toStringAsFixed(3)}',
    );
    watch(connection, () => 'status ${connection.value.name}');
    watch(
      vehicle.engineRunning,
      () =>
          'engine ${vehicle.engineRunning.value ? 'on' : 'off'} '
          '(rpm ${fixed(vehicle.rpm.value?.value, 0)}, '
          'volts ${fixed(vehicle.voltage.value?.value, 1)})',
    );
    watch(vehicle.mode, () => 'mode ${vehicle.mode.value.name}');
    watch(recorder.phase, () => 'trip ${recorder.phase.value.name}');
    _vitals = scheduler.runEvery(const Duration(seconds: 5), () {
      final flow = estimator.flow.value;
      say(
        'vitals kmh=${fixed(vehicle.speed.value?.value, 0)} '
        'rpm=${fixed(vehicle.rpm.value?.value, 0)} '
        'volts=${fixed(vehicle.voltage.value?.value, 1)} '
        'maf=${fixed(vehicle.airFlow.value?.value, 2)} '
        'src=${estimator.source.value.label} '
        'lph=${fixed(flow?.litresPerHour, 2)} '
        'km=${fixed(computer.distanceKm.value, 2)} '
        'litres=${fixed(computer.litres.value, 3)} '
        'idle_s=${fixed(computer.idleSeconds.value, 0)} '
        'idle_l=${fixed(computer.bucketLitres[SpendBucket.idling], 3)}',
      );
    });
  }

  void _onSetup() {
    estimator.setup = app.setup.value;
    computer.setup = app.setup.value;
  }

  /// Saves what there is and lets go of everything.
  /// Applies new coach thresholds to everything that reads them, from the next
  /// sample on (Garage: the preset, the speed threshold).
  void setThresholds(CoachThresholds thresholds) {
    hardEvents.thresholds = thresholds;
    coach.thresholds = thresholds;
    computer.thresholds = thresholds;
  }

  Future<void> close() async {
    app.setup.removeListener(_onSetup);
    _vitals?.cancel();
    for (final unbind in _noteUnbind) {
      unbind();
    }
    demand?.dispose();
    await recorder.close();
    computer.dispose();
    coach.dispose();
    hardEvents.dispose();
    estimator.dispose();
  }
}

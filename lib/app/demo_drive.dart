import 'dart:async';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../obd/obd_session.dart';
import '../obd/transport/sim_transport.dart';
import '../sim/profiles.dart';
import '../sim/scenarios.dart';
import '../sim/simulated_car.dart';
import '../sim/vehicle_profile.dart';
import '../ui/dev/demo_control.dart';
import '../vehicle/vehicle_state.dart';

/// Demo Mode's data (CLAUDE.md 7.6): a simulated car on a simulated adapter, read
/// by the same OBD stack a real car is. The vehicle it fills is the one the whole UI
/// reads, so what is drawn in demo is what would be drawn with an adapter plugged
/// in.
///
/// The drive loops: when the scenario ends it starts again. Changing the scenario or
/// the car rebuilds the simulator and the session and keeps the [vehicle], so
/// whatever is reading it carries on.
class DemoDrive implements DemoControl {
  DemoDrive({
    required this.clock,
    required this.scheduler,
    String scenario = 'city_stop_go',
    String? profile,
    this.seed = 1,
  }) : _scenario = ObservableValue(scenario),
       _profile = ObservableValue(profile ?? ''),
       vehicle = VehicleState(clock: clock, scheduler: scheduler) {
    _description = ObservableValue(_describe());
  }

  final Clock clock;
  final Scheduler scheduler;
  final int seed;

  @override
  final VehicleState vehicle;

  final ObservableValue<String> _scenario;
  final ObservableValue<String> _profile;
  final ObservableValue<bool> _running = ObservableValue(false);
  final ObservableValue<ConnectionStatus> _connection = ObservableValue(
    ConnectionStatus.stopped,
  );
  final ObservableValue<double> _pollRate = ObservableValue(0);
  late final ObservableValue<String> _description;

  SimulatedCar? _car;
  SimTransport? _transport;
  ObdSession? _session;
  final ObservableValue<ObdSession?> _sessionValue = ObservableValue(null);
  final ObservableValue<SimulatedCar?> _carValue = ObservableValue(null);
  final ObservableValue<int> _loopValue = ObservableValue(0);
  ScheduledTask? _loop;
  void Function()? _statusListener;
  void Function()? _rateListener;

  @override
  bool get isDemo => true;

  @override
  List<String> get scenarios => [for (final s in DriveScenarios.all) s.name];

  @override
  List<String> get profiles => [for (final p in VehicleProfiles.all) p.name];

  @override
  Observable<String> get scenario => _scenario;

  @override
  Observable<String> get profile => _profile;

  @override
  Observable<bool> get running => _running;

  @override
  Observable<String> get description => _description;

  @override
  Observable<ConnectionStatus> get connection => _connection;

  @override
  Observable<double> get pollRate => _pollRate;

  /// The OBD session reading the simulated car: the trip recorder moves the fuel
  /// PID to the fast tier through it. Null before [start].
  ObdSession? get session => _session;

  /// The same, as something to listen to: the session is replaced whenever the
  /// drive starts over.
  Observable<ObdSession?> get sessions => _sessionValue;

  /// How long the finished car stands before the trip is ended, and before the
  /// drive starts over.
  static const Duration endTripAfter = Duration(seconds: 8);
  static const Duration restartAfter = Duration(seconds: 40);

  /// How many times the drive has come to its end and started over. Listeners run
  /// before it restarts, so a trip can be ended first.
  Observable<int> get loops => _loopValue;

  /// The simulated car, as something to listen to: it is replaced whenever the
  /// drive starts over, and the demo's GPS follows the new one.
  Observable<SimulatedCar?> get cars => _carValue;

  /// The car being driven, for the simulator's own ground truth.
  SimulatedCar? get car => _car;

  String _describe() {
    final profile = _profile.value.isEmpty ? 'default car' : _profile.value;
    return 'DEMO  ${_scenario.value}  ·  $profile';
  }

  @override
  void start() {
    if (_running.value) return;
    _build();
    _running.value = true;
  }

  @override
  void stop() {
    _teardown();
    _running.value = false;
    _connection.value = ConnectionStatus.stopped;
  }

  @override
  void restart() {
    _teardown();
    _build();
    _running.value = true;
  }

  @override
  void select({String? scenario, String? profile}) {
    if (scenario != null) _scenario.value = scenario;
    if (profile != null) _profile.value = profile;
    _description.value = _describe();
    restart();
  }

  void _build() {
    final scenario = DriveScenarios.byName(_scenario.value)!;
    final VehicleProfile? profile = _profile.value.isEmpty
        ? null
        : VehicleProfiles.all.firstWhere((p) => p.name == _profile.value);
    final car = SimulatedCar(
      scenario: scenario,
      profile: profile,
      seed: seed,
      scheduler: scheduler,
      stopWhenFinished: true,
    )..start();
    final transport = SimTransport(
      car: car,
      scheduler: scheduler,
      quirks: scenario.quirks,
      seed: seed,
    );
    final session = ObdSession(
      transport: transport,
      scheduler: scheduler,
      clock: clock,
      vehicle: vehicle,
    );
    _car = car;
    _carValue.value = car;
    _transport = transport;
    _session = session;
    _sessionValue.value = session;

    _statusListener = () => _connection.value = session.status.value;
    _rateListener = () => _pollRate.value = session.pollRate.value;
    session.status.addListener(_statusListener!);
    session.pollRate.addListener(_rateListener!);
    session.start();

    // The drive loops: when it ends, it starts again. The car stands a while
    // first, so it is parked, the trip ends and its Debrief can be seen
    // (DESIGN.md 7.5) before the next drive locks the parked pages away.
    Duration? finishedAt;
    var announced = false;
    _loop = scheduler.runEvery(const Duration(seconds: 2), () {
      // Finished and standing: a scenario cut off mid-drive brakes to a stop first.
      if (!car.isFinished || car.state.speedMs > 0.05) return;
      final now = clock.monotonic();
      finishedAt ??= now;
      final standing = now - finishedAt!;
      if (!announced && standing >= endTripAfter) {
        announced = true;
        _loopValue.value++;
      }
      if (standing >= restartAfter) restart();
    });
  }

  void _teardown() {
    _loop?.cancel();
    _loop = null;
    final session = _session;
    if (session != null) {
      if (_statusListener != null) {
        session.status.removeListener(_statusListener!);
      }
      if (_rateListener != null) {
        session.pollRate.removeListener(_rateListener!);
      }
      session.stop();
      session.dispose();
    }
    _car?.stop();
    final transport = _transport;
    if (transport != null) unawaited(transport.dispose());
    _session = null;
    _sessionValue.value = null;
    _car = null;
    _carValue.value = null;
    _transport = null;
  }

  /// Stops the drive and lets go of everything.
  void dispose() {
    _teardown();
    vehicle.dispose();
  }
}

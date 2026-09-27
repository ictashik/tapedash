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
    _transport = transport;
    _session = session;

    _statusListener = () => _connection.value = session.status.value;
    _rateListener = () => _pollRate.value = session.pollRate.value;
    session.status.addListener(_statusListener!);
    session.pollRate.addListener(_rateListener!);
    session.start();

    // The drive loops: when it ends, it starts again.
    _loop = scheduler.runEvery(const Duration(seconds: 2), () {
      if (car.isFinished) restart();
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
    _car = null;
    _transport = null;
  }

  /// Stops the drive and lets go of everything.
  void dispose() {
    _teardown();
    vehicle.dispose();
  }
}

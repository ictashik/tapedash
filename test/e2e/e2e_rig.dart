import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/transport/recording_transport.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/sim/vehicle_model.dart';
import 'package:tapedash/sim/vehicle_profile.dart';
import 'package:tapedash/vehicle/reading.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

/// The whole stack of CLAUDE.md 10, Layer 3: a simulated car, its adapter and
/// the link, the ELM327 layer, the poller and the session, and the vehicle
/// state, on a fake clock, with everything recorded that a test may want to
/// compare with the truth.
class E2eRig {
  E2eRig(
    DriveScenario scenario, {
    VehicleProfile? profile,
    AdapterQuirks? quirks,
    int seed = 1,
    SessionConfig config = const SessionConfig(),
  }) {
    car = SimulatedCar(
      scenario: scenario,
      profile: profile,
      seed: seed,
      scheduler: clock,
    )..start();
    // What the car was doing, every 50 ms, to compare readings with.
    clock.runEvery(
      const Duration(milliseconds: 50),
      () => truth.add(car.state),
    );
    final sim = SimTransport(
      car: car,
      scheduler: clock,
      quirks: quirks,
      seed: seed,
    );
    transport = sim;
    recorder = RecordingTransport(sim, clock: clock);
    vehicle = VehicleState(clock: clock, scheduler: clock);
    session = ObdSession(
      transport: recorder,
      scheduler: clock,
      clock: clock,
      vehicle: vehicle,
      config: config,
    );
    session.status.addListener(() {
      statuses.add((clock.monotonic(), session.status.value));
    });
    for (final sensor in Sensor.values) {
      final o = vehicle.reading(sensor);
      o.addListener(() => readings[sensor]!.add(o.value!));
    }
    vehicle.motion.addListener(() => motion.add(vehicle.motion.value!));
    vehicle.engineRunning.addListener(
      () => engine.add((clock.monotonic(), vehicle.engineRunning.value)),
    );
    session.start();
  }

  final clock = FakeClock();
  late final SimulatedCar car;
  late final SimTransport transport;
  late final RecordingTransport recorder;
  late final VehicleState vehicle;
  late final ObdSession session;

  /// What the car was doing, every 50 ms.
  final List<VehicleSnapshot> truth = [];

  final List<(Duration, ConnectionStatus)> statuses = [];
  final Map<Sensor, List<Reading>> readings = {
    for (final s in Sensor.values) s: [],
  };
  final List<MotionSample> motion = [];
  final List<(Duration, bool)> engine = [];

  List<ConnectionStatus> get sequence => [for (final s in statuses) s.$2];

  ConnectionStatus get status => session.status.value;

  double get seconds => clock.monotonic().inMicroseconds / 1e6;

  /// What the commands sent were, from the recording of the link.
  SessionLog get log => recorder.log;

  /// The car as it was at [at]: the nearest of the snapshots kept every 50 ms.
  VehicleSnapshot truthAt(Duration at) {
    final seconds = at.inMicroseconds / 1e6;
    var low = 0;
    var high = truth.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (truth[mid].timeSeconds < seconds) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0 &&
        (truth[low - 1].timeSeconds - seconds).abs() <
            (truth[low].timeSeconds - seconds).abs()) {
      low--;
    }
    return truth[low];
  }

  /// Runs to the end of the drive, and a few seconds more for the last answers.
  void runToEnd({Duration? limit}) {
    final end = limit ?? const Duration(hours: 2);
    while (!car.isFinished && clock.monotonic() < end) {
      clock.advance(const Duration(seconds: 1));
    }
    clock.advance(const Duration(seconds: 5));
  }

  void run(int seconds) => clock.advance(Duration(seconds: seconds));

  /// Runs until [condition], and says whether it was met within [limit].
  bool runUntil(
    bool Function() condition, {
    Duration limit = const Duration(minutes: 5),
  }) {
    final until = clock.monotonic() + limit;
    while (!condition() && clock.monotonic() < until) {
      clock.advance(const Duration(milliseconds: 100));
    }
    return condition();
  }

  void close() {
    session.dispose();
    vehicle.dispose();
    car.stop();
    recorder.dispose();
    transport.dispose();
  }
}

/// The hard accelerations and hard brakings the coach's rule (CLAUDE.md 8.8)
/// finds in a stream of smoothed acceleration: above 2.5 m/s2 for a second, and
/// below -3.5 m/s2 for half a second. The rule's throttle alternative is the
/// coach's own (phase 5).
({int accelerations, int brakings}) detectHardEvents(
  Iterable<MotionSample> motion,
) {
  var accelerationFor = 0.0;
  var brakingFor = 0.0;
  var accelerations = 0;
  var brakings = 0;
  var accelerationOpen = false;
  var brakingOpen = false;
  Duration? last;
  for (final m in motion) {
    final dt = last == null ? 0.0 : (m.at - last).inMicroseconds / 1e6;
    last = m.at;

    accelerationFor = m.accelerationMs2 > 2.5 ? accelerationFor + dt : 0;
    if (accelerationFor >= 1.0 && !accelerationOpen) {
      accelerations++;
      accelerationOpen = true;
    }
    if (m.accelerationMs2 <= 2.5) accelerationOpen = false;

    brakingFor = m.accelerationMs2 < -3.5 ? brakingFor + dt : 0;
    if (brakingFor >= 0.5 && !brakingOpen) {
      brakings++;
      brakingOpen = true;
    }
    if (m.accelerationMs2 >= -3.5) brakingOpen = false;
  }
  return (accelerations: accelerations, brakings: brakings);
}

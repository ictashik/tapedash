import 'package:tapedash/coach/coach_monitor.dart';
import 'package:tapedash/coach/hard_event_detector.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/fuel/fuel_constants.dart';
import 'package:tapedash/fuel/fuel_estimator.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/money/fuel_ledger.dart';
import 'package:tapedash/money/money_settings.dart';
import 'package:tapedash/money/trip_computer.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/drive_style.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/vehicle_profile.dart';
import 'package:tapedash/trips/recording_demand.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/trips/trip_recorder.dart';

import 'e2e_rig.dart';

/// The whole stack of CLAUDE.md 10, Layer 3, and everything phase 4 adds on top
/// of it: the fuel estimator, the trip computer, the fill-up ledger and the trip
/// recorder, on the same fake clock, with in-memory storage.
class TripRig {
  TripRig(
    DriveScenario scenario, {
    VehicleProfile? profile,
    AdapterQuirks? quirks,
    int seed = 1,
    double? price = 100,
    FuelLedger? sharedLedger,
    MemoryTripRepository? trips,
    bool isDemo = false,
  }) : rig = E2eRig(scenario, profile: profile, quirks: quirks, seed: seed) {
    final p = profile ?? scenario.profile;
    setup = VehicleSetup(
      fuelType: p.isDiesel ? FuelType.diesel : FuelType.petrol,
      displacementLitres: p.engine.displacementLitres,
      tankLitres: p.tankLitres,
    );
    this.trips = trips ?? MemoryTripRepository();
    fills = MemoryFillUpRepository();
    store = MemoryKeyValueStore();
    ledger = sharedLedger ?? FuelLedger(fills: fills, store: store);
    money = MoneySettings(store);
    if (price != null) money.setPrice(price);
    estimator = FuelEstimator(vehicle: rig.vehicle, setup: setup);
    hard = HardEventDetector(vehicle: rig.vehicle);
    coach = CoachMonitor(vehicle: rig.vehicle);
    computer = TripComputer(
      vehicle: rig.vehicle,
      estimator: estimator,
      hardEvents: hard,
      calibrationFactor: () => ledger.calibration.factor,
      price: money.price,
      setup: setup,
      onEstimate: ledger.addEstimate,
    );
    recorder = TripRecorder(
      vehicle: rig.vehicle,
      connection: rig.session.status,
      computer: computer,
      hardEvents: hard,
      estimator: estimator,
      repository: this.trips,
      clock: rig.clock,
      scheduler: rig.clock,
      calibrationFactor: () => ledger.calibration.factor,
      price: money.price,
      ledger: ledger,
      coach: coach,
      isDemo: isDemo,
    );
    demand = RecordingDemand(
      sessions: ObservableValue<ObdSession?>(rig.session),
      recorder: recorder,
      estimator: estimator,
    );
  }

  final E2eRig rig;
  late final VehicleSetup setup;
  late final MemoryTripRepository trips;
  late final MemoryFillUpRepository fills;
  late final MemoryKeyValueStore store;
  late final FuelLedger ledger;
  late final MoneySettings money;
  late final FuelEstimator estimator;
  late final HardEventDetector hard;
  late final CoachMonitor coach;
  late final TripComputer computer;
  late final TripRecorder recorder;
  late final RecordingDemand demand;

  void runToEnd() => rig.runToEnd();

  Future<void> close() async {
    demand.dispose();
    await recorder.close();
    computer.dispose();
    coach.dispose();
    hard.dispose();
    estimator.dispose();
    rig.close();
  }
}

/// The error of an estimate against the truth, as a fraction.
double relError(double estimate, double truth) => (estimate - truth) / truth;

/// A short drive that ends with the engine switched off for [offSeconds].
DriveScenario simpleTrip({double offSeconds = 240}) => DriveScenario(
  name: 'simple_trip',
  description: 'Idle, a minute at 50 km/h, stop, engine off',
  route: SimRoute([const Straight(5000)]),
  driverBuilder: () => ScriptedDriver([
    IdleFor(6),
    GoToSpeed(50, style: DriveStyle.gentle, holdSeconds: 90),
    StopFor(8, style: DriveStyle.gentle),
    IgnitionOffFor(offSeconds),
  ]),
);

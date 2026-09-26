import 'adapter_quirks.dart';
import 'driver.dart';
import 'profiles.dart';
import 'scenario_events.dart';
import 'sim_route.dart';
import 'vehicle_profile.dart';

/// A scripted drive (CLAUDE.md 7.3): a road, a driver, and what happens along
/// the way. A driver is stateful, so each run builds a fresh one.
class DriveScenario {
  const DriveScenario({
    required this.name,
    required this.description,
    required this.route,
    required this.driverBuilder,
    this.profile = VehicleProfiles.petrolCvtMaf,
    this.duration,
    this.dtcs = const [],
    this.adapterFaults = const [],
    this.quirks = AdapterQuirks.none,
    this.ambientC = 30,
    this.startCoolantC,
    this.fuelLevelFraction = 0.7,
    this.engineRunningAtStart = false,
  });

  /// The name used on the command line, such as `city_stop_go`.
  final String name;
  final String description;

  /// The road, for lateral acceleration and the simulated GPS.
  final SimRoute route;

  final Driver Function() driverBuilder;

  /// The profile the scenario is written for. Any profile can drive it.
  final VehicleProfile profile;

  /// How long the scenario runs, or null to run until the driver has finished.
  final Duration? duration;

  /// Fault codes that appear in the car's memory during the drive.
  final List<DtcInjection> dtcs;

  /// Faults with the adapter link at set times.
  final List<AdapterFault> adapterFaults;

  /// How the adapter misbehaves in this scenario.
  final AdapterQuirks quirks;

  final double ambientC;

  /// The coolant temperature at the start. Null means the engine is at ambient,
  /// which is a cold start.
  final double? startCoolantC;

  final double fuelLevelFraction;

  /// Whether the engine is already running when the scenario begins, as it is
  /// when a demo picks up a drive part way through.
  final bool engineRunningAtStart;

  Driver newDriver() => driverBuilder();

  @override
  String toString() => 'DriveScenario($name)';
}

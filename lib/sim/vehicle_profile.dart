import '../core/fuel_blend.dart';
import 'engine_spec.dart';

/// How the engine is connected to the wheels.
sealed class Transmission {
  const Transmission({required this.wheelRadiusM, required this.efficiency});

  /// Rolling radius of the tyres.
  final double wheelRadiusM;

  /// The share of engine power that reaches the wheels.
  final double efficiency;
}

/// A CVT, or any automatic that behaves like one: engine speed follows the
/// pedal more than road speed (CLAUDE.md 7.1). Gentle cruising sits between
/// [cruiseRpmBase] and [cruiseRpmMax], and the pedal pulls the revs up towards
/// [pullRpmMax].
final class CvtTransmission extends Transmission {
  const CvtTransmission({
    super.wheelRadiusM = 0.30,
    super.efficiency = 0.90,
    this.cruiseRpmBase = 1100,
    this.cruiseRpmPerKmh = 9.5,
    this.cruiseRpmMax = 2300,
    this.pullRpmMax = 5800,
    this.launchRpmMax = 3800,
    this.creepForceN = 350,
    this.standstillDragNm = 3.5,
  });

  /// Engine speed at a gentle cruise: base + perKmh * speed, up to the max.
  final double cruiseRpmBase;
  final double cruiseRpmPerKmh;
  final double cruiseRpmMax;

  /// Engine speed at full pedal at speed, and from a standstill, where the
  /// torque converter lets the revs run ahead of the wheels.
  final double pullRpmMax;
  final double launchRpmMax;

  /// With the pedal up and the brake off, an automatic in drive creeps.
  final double creepForceN;

  /// What the torque converter costs the engine when stopped in drive.
  final double standstillDragNm;
}

/// A manual gearbox. A virtual driver changes gear, so the revs rise and fall
/// like a real car's, which is what the shift horizon and fast needle work
/// need (CLAUDE.md 7.2).
final class ManualTransmission extends Transmission {
  const ManualTransmission({
    required this.gearRatios,
    required this.finalDrive,
    required this.upshiftRpmAtFullPedal,
    required this.upshiftRpmAtLightPedal,
    required this.downshiftRpm,
    super.wheelRadiusM = 0.30,
    super.efficiency = 0.92,
    this.shiftSeconds = 0.35,
    this.launchRpmMax = 4200,
  });

  /// Ratios of first gear up.
  final List<double> gearRatios;
  final double finalDrive;

  /// The engine speed at which the virtual driver changes up, with the pedal
  /// flat and with it barely pressed.
  final double upshiftRpmAtFullPedal;
  final double upshiftRpmAtLightPedal;

  /// The engine speed below which the driver changes down.
  final double downshiftRpm;

  /// How long the clutch is out while changing gear.
  final double shiftSeconds;

  /// The revs the driver launches from a standstill with the pedal flat.
  final double launchRpmMax;
}

/// A simulated car: an approximation, not real vehicle data (CLAUDE.md 7.2).
/// Real recordings replace or tune these after the hardware handoff.
class VehicleProfile {
  const VehicleProfile({
    required this.name,
    required this.description,
    required this.engine,
    required this.transmission,
    required this.massKg,
    required this.tankLitres,
    required this.idleRpm,
    required this.redlineRpm,
    required this.tachMaxRpm,
    required this.supportedPids,
    this.secondEcuPids = const {},
    this.canProtocol = 6,
    this.dragAreaM2 = 0.68,
    this.rollingResistance = 0.011,
    this.maxBrakeDecelMs2 = 7.5,
    this.tractionLimitG = 0.36,
  });

  /// The name used on the command line and in recordings, such as
  /// `petrol_cvt_map`.
  final String name;
  final String description;

  final EngineSpec engine;
  final Transmission transmission;

  final double massKg;
  final double tankLitres;

  /// Coefficient of drag times frontal area, in square metres.
  final double dragAreaM2;

  /// Rolling resistance as a fraction of weight.
  final double rollingResistance;

  /// The hardest the brakes alone can slow the car. With drag, rolling
  /// resistance and engine braking on top, the car decelerates at about 8 m/s2
  /// at most (CLAUDE.md 7.1).
  final double maxBrakeDecelMs2;

  /// The most force the driven wheels can put down, as a fraction of weight.
  final double tractionLimitG;

  /// Warm idle speed, and the speed where the limiter cuts in.
  final double idleRpm;
  final double redlineRpm;

  /// The top of the tachometer scale, above the redline.
  final double tachMaxRpm;

  /// The Mode 01 PIDs the ECU answers, apart from PID 01 (the MIL and code
  /// count), which every OBD-II ECU has and the simulator always adds.
  final Set<int> supportedPids;

  /// The PIDs of a second ECU on the same bus, if the car has one: many do (an
  /// engine and a transmission or body module answer the same request, each in
  /// its own frames). Empty means one ECU.
  final Set<int> secondEcuPids;

  /// The ELM327 protocol number the car speaks: 6 is 11-bit CAN at 500 kbaud,
  /// 7 is 29-bit CAN at 500 kbaud.
  final int canProtocol;

  /// The same car running on petrol with [blend] ethanol in it: the air makes
  /// more litres of fuel and less energy per litre, and the ground truth follows.
  /// Only a petrol car has a blend.
  VehicleProfile withBlend(PetrolBlend blend) {
    final e = engine;
    if (e is! PetrolSpec) throw StateError('$name is not a petrol car');
    return VehicleProfile(
      name: '${name}_${blend.name}',
      description: '$description, on ${blend.label}',
      engine: e.withFuel(FuelProperties.petrolBlend(blend)),
      transmission: transmission,
      massKg: massKg,
      tankLitres: tankLitres,
      idleRpm: idleRpm,
      redlineRpm: redlineRpm,
      tachMaxRpm: tachMaxRpm,
      supportedPids: supportedPids,
      secondEcuPids: secondEcuPids,
      canProtocol: canProtocol,
      dragAreaM2: dragAreaM2,
      rollingResistance: rollingResistance,
      maxBrakeDecelMs2: maxBrakeDecelMs2,
      tractionLimitG: tractionLimitG,
    );
  }

  bool get isDiesel => engine is DieselSpec;
  FuelProperties get fuel => engine.fuel;

  bool supports(int pid) => pid == 0x01 || supportedPids.contains(pid);

  @override
  String toString() => 'VehicleProfile($name)';
}

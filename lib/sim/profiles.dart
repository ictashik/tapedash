import 'engine_spec.dart';
import 'vehicle_profile.dart';

// Mode 01 PIDs, by what they read (CLAUDE.md 8.3).
const int pidLoad = 0x04;
const int pidCoolant = 0x05;
const int pidMap = 0x0B;
const int pidRpm = 0x0C;
const int pidSpeed = 0x0D;
const int pidIntakeAir = 0x0F;
const int pidMaf = 0x10;
const int pidThrottle = 0x11;
const int pidFuelLevel = 0x2F;
const int pidVoltage = 0x42;
const int pidFuelRate = 0x5E;

/// What a typical car with a MAF sensor answers (CLAUDE.md 7.2).
const Set<int> _withMaf = {
  pidLoad,
  pidCoolant,
  pidMap,
  pidRpm,
  pidSpeed,
  pidIntakeAir,
  pidMaf,
  pidThrottle,
  pidFuelLevel,
  pidVoltage,
};

/// The vehicle profiles the simulator ships with (CLAUDE.md 7.2). They are
/// approximations, not data from real cars.
abstract final class VehicleProfiles {
  /// A petrol CVT hatchback with a MAF sensor.
  static const VehicleProfile petrolCvtMaf = VehicleProfile(
    name: 'petrol_cvt_maf',
    description: 'Petrol CVT hatch with a MAF sensor',
    engine: PetrolSpec(displacementLitres: 1.5),
    transmission: CvtTransmission(),
    massKg: 1150,
    tankLitres: 40,
    idleRpm: 750,
    redlineRpm: 6500,
    tachMaxRpm: 7000,
    supportedPids: _withMaf,
  );

  /// The same car without a MAF sensor, so the app has to use speed-density.
  /// Many Honda petrol cars behave like this.
  static const VehicleProfile petrolCvtMap = VehicleProfile(
    name: 'petrol_cvt_map',
    description: 'Petrol CVT hatch with no MAF: speed-density only',
    engine: PetrolSpec(displacementLitres: 1.5),
    transmission: CvtTransmission(),
    massKg: 1150,
    tankLitres: 40,
    idleRpm: 750,
    redlineRpm: 6500,
    tachMaxRpm: 7000,
    supportedPids: {
      pidLoad,
      pidCoolant,
      pidMap,
      pidRpm,
      pidSpeed,
      pidIntakeAir,
      pidThrottle,
      pidFuelLevel,
      pidVoltage,
    },
  );

  /// The same car, and it also reports its own fuel rate (PID 5E).
  static const VehicleProfile petrolCvtFuelRate = VehicleProfile(
    name: 'petrol_cvt_fuelrate',
    description: 'Petrol CVT hatch that reports engine fuel rate (PID 5E)',
    engine: PetrolSpec(displacementLitres: 1.5),
    transmission: CvtTransmission(),
    massKg: 1150,
    tankLitres: 40,
    idleRpm: 750,
    redlineRpm: 6500,
    tachMaxRpm: 7000,
    supportedPids: {..._withMaf, pidFuelRate},
  );

  /// A high-revving petrol manual, for the shift horizon and fast needle work.
  static const VehicleProfile petrolManualSporty = VehicleProfile(
    name: 'petrol_manual_sporty',
    description: 'Petrol six-speed manual, 7,000 rpm redline',
    engine: PetrolSpec(
      displacementLitres: 1.6,
      volumetricEfficiency: VolumetricEfficiencyCurve([
        (500, 0.66),
        (1000, 0.75),
        (2000, 0.85),
        (3000, 0.92),
        (4500, 1.0),
        (6000, 1.02),
        (7000, 1.0),
        (8000, 0.9),
      ]),
      frictionBaseKpa: 85,
      frictionPerKrpm2Kpa: 2.2,
    ),
    transmission: ManualTransmission(
      gearRatios: [3.54, 2.06, 1.45, 1.10, 0.90, 0.75],
      finalDrive: 4.25,
      upshiftRpmAtFullPedal: 6600,
      upshiftRpmAtLightPedal: 2500,
      downshiftRpm: 1500,
    ),
    massKg: 1080,
    tankLitres: 45,
    idleRpm: 850,
    redlineRpm: 7000,
    tachMaxRpm: 8000,
    dragAreaM2: 0.66,
    supportedPids: _withMaf,
  );

  /// An old car that answers very little, to test graceful degradation: money
  /// is unavailable and the app has to say so plainly.
  static const VehicleProfile minimalOldCar = VehicleProfile(
    name: 'minimal_old_car',
    description: 'Old petrol car that only answers PIDs 04, 05, 0C, 0D and 11',
    engine: PetrolSpec(displacementLitres: 1.3, indicatedEfficiency: 0.40),
    transmission: CvtTransmission(pullRpmMax: 5400, launchRpmMax: 3400),
    massKg: 980,
    tankLitres: 38,
    idleRpm: 800,
    redlineRpm: 6000,
    tachMaxRpm: 7000,
    dragAreaM2: 0.70,
    supportedPids: {pidLoad, pidCoolant, pidRpm, pidSpeed, pidThrottle},
  );

  /// A small turbodiesel manual. It reports MAF, but a diesel's mixture varies
  /// with load, so the MAF method cannot turn air into fuel: money has to be
  /// flagged low-confidence until fill-up calibration exists (CLAUDE.md 8.4).
  static const VehicleProfile dieselManual = VehicleProfile(
    name: 'diesel_manual',
    description: 'Turbodiesel five-speed manual, MAF available',
    engine: DieselSpec(
      displacementLitres: 1.5,
      maximumTorqueCurve: [
        (1000, 130),
        (1500, 200),
        (2000, 240),
        (3000, 240),
        (4000, 205),
        (4500, 180),
        (5000, 150),
      ],
    ),
    transmission: ManualTransmission(
      gearRatios: [3.73, 2.05, 1.32, 0.98, 0.72],
      finalDrive: 3.4,
      upshiftRpmAtFullPedal: 4300,
      upshiftRpmAtLightPedal: 2400,
      downshiftRpm: 1150,
      launchRpmMax: 2600,
    ),
    massKg: 1250,
    tankLitres: 50,
    idleRpm: 800,
    redlineRpm: 5000,
    tachMaxRpm: 6000,
    dragAreaM2: 0.70,
    supportedPids: _withMaf,
  );

  static const List<VehicleProfile> all = [
    petrolCvtMaf,
    petrolCvtMap,
    petrolCvtFuelRate,
    petrolManualSporty,
    minimalOldCar,
    dieselManual,
  ];

  /// The profile called [name], or null.
  static VehicleProfile? byName(String name) {
    for (final profile in all) {
      if (profile.name == name) return profile;
    }
    return null;
  }
}

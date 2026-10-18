import '../core/fuel_blend.dart';

/// The physical constants behind the insight pages (Powerflow, the power curve):
/// the wheel power of a drive worked out from its speed and acceleration. Every
/// figure they give is an estimate, and is labelled one on screen (CLAUDE.md 1.6).
///
/// The defaults are a small petrol hatch or sedan (the first car TapeDash was
/// tested on: 1250 kg with its driver, a drag area of 0.65 m²). They are not
/// settings yet; a car with other numbers changes them here, in one place.
class InsightConstants {
  const InsightConstants({
    this.massKg = 1250,
    this.dragArea = 0.65,
    this.rollingResistance = 0.012,
    this.airDensity = 1.18,
    this.blend = PetrolBlend.e20,
  });

  /// The car and its load, in kilograms.
  final double massKg;

  /// Drag coefficient times frontal area, in square metres.
  final double dragArea;

  /// The rolling resistance coefficient of road tyres on tarmac.
  final double rollingResistance;

  /// Air at about 25 °C and Bangalore's height, in kg/m³.
  final double airDensity;

  final PetrolBlend blend;

  static const double gravity = 9.81;

  /// The lower heating value of petrol and of ethanol, in MJ a litre.
  static const double petrolMjPerLitre = 32.0;
  static const double ethanolMjPerLitre = 21.1;

  /// The energy in a litre of this petrol, in kWh: the two fuels mixed by volume.
  double get kwhPerLitre {
    final e = blend.ethanolVolumeShare;
    final mj = petrolMjPerLitre * (1 - e) + ethanolMjPerLitre * e;
    return mj / 3.6;
  }
}

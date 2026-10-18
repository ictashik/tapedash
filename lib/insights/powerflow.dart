import 'dart:math' as math;

import '../money/spend_bucket.dart';
import '../trips/trip.dart';
import 'insight_constants.dart';
import 'wheel_power.dart';

/// Where the energy in the fuel of one trip went (Powerflow): out of the engine as
/// heat, burnt standing still, or into the wheels, and from the wheels into the
/// tyres, the air and the brakes. The shares add up to 1 at each split.
///
/// An estimate from speed and fuel alone; the labels say so, and no figure is
/// shown to more than a whole percent.
class Powerflow {
  const Powerflow({
    required this.fuelKwh,
    required this.idleShare,
    required this.wheelShare,
    required this.heatShare,
    required this.tyreShare,
    required this.airShare,
    required this.brakeShare,
    this.cost,
  });

  /// The energy in the fuel the trip used.
  final double fuelKwh;

  /// Of the fuel's energy: burnt with the car still, delivered to the wheels,
  /// and given off as engine heat. They add up to 1.
  final double idleShare;
  final double wheelShare;
  final double heatShare;

  /// Of what reached the wheels: the tyres, the air and the brakes. They add up
  /// to 1 when anything reached the wheels, and are all 0 otherwise.
  final double tyreShare;
  final double airShare;
  final double brakeShare;

  /// The trip's cost, when it was priced, to turn a share into rupees.
  final double? cost;

  /// What a share of the fuel's energy cost: the trip's rupees by that share.
  double? rupees(double share) => cost == null ? null : cost! * share;

  /// What went to the brakes, as a share of all the fuel's energy.
  double get brakeOfFuel => wheelShare * brakeShare;
  double get tyreOfFuel => wheelShare * tyreShare;
  double get airOfFuel => wheelShare * airShare;

  /// The engine cannot give the wheels more than a third of the fuel's energy,
  /// so a share above that says the estimate has gone wrong, not the engine.
  static const double ceiling = 0.4;

  /// Null for a trip with no fuel or no samples worth the name.
  static Powerflow? of(
    Trip trip,
    List<TripSample> samples, {
    InsightConstants constants = const InsightConstants(),
  }) {
    if (trip.litres <= 0 || samples.length < 30) return null;
    final fuelKwh = trip.litres * constants.kwhPerLitre;
    final moments = WheelPower.moments(samples, constants: constants);
    if (moments.isEmpty) return null;
    var wheelsKwh = 0.0, tyres = 0.0, air = 0.0, brakes = 0.0;
    for (final m in moments) {
      final h = m.dt / 3600;
      wheelsKwh += m.tractionKw * h;
      tyres += m.rollingKw * h;
      air += m.airKw * h;
      brakes += m.brakingKw * h;
    }
    final sinks = tyres + air + brakes;
    if (sinks <= 0) return null;
    final idleKwh =
        (trip.bucketLitres[SpendBucket.idling] ?? 0) * constants.kwhPerLitre;
    final wheel = math.min(ceiling, wheelsKwh / fuelKwh);
    final idle = math.min(1 - wheel, idleKwh / fuelKwh);
    final heat = math.max(0.0, 1 - wheel - idle);
    return Powerflow(
      fuelKwh: fuelKwh,
      idleShare: idle,
      wheelShare: wheel,
      heatShare: heat,
      tyreShare: tyres / sinks,
      airShare: air / sinks,
      brakeShare: brakes / sinks,
      cost: trip.cost,
    );
  }
}

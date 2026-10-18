import '../money/calibration.dart';
import '../money/fuel_ledger.dart';
import '../trips/trip.dart';

/// The counted tank, for its page (Tank without a gauge): litres, range, and what
/// it is counted from.
class TankReading {
  const TankReading({
    required this.litres,
    required this.tankLitres,
    required this.usedLitres,
    required this.kmSinceFull,
    required this.rangeKm,
    required this.confidence,
    required this.fullAt,
  });

  /// The least distance a km/L is worked out over; under it the range is not
  /// shown, since a short drive's economy says little.
  static const double minKm = 20;

  /// The tank is in its reserve under this share.
  static const double reserveShare = 0.125;

  final double litres;
  final double tankLitres;

  /// Litres used, and kilometres driven, since the last full tank.
  final double usedLitres;
  final double kmSinceFull;

  /// Null until there is enough driving to know the economy.
  final double? rangeKm;
  final CalibrationConfidence confidence;
  final DateTime fullAt;

  double get level => (litres / tankLitres).clamp(0.0, 1.0);
  bool get inReserve => level < reserveShare;

  /// Null until a full tank has been logged.
  static TankReading? of({
    required FuelLedger ledger,
    required double tankLitres,
    required Iterable<Trip> trips,
  }) {
    final left = ledger.litresLeft(tankLitres);
    final fullAt = ledger.lastFullAt;
    if (left == null || fullAt == null) return null;
    var km = 0.0, litres = 0.0, allKm = 0.0, allLitres = 0.0;
    for (final t in trips) {
      if (t.isDemo || t.litres <= 0) continue;
      allKm += t.distanceKm;
      allLitres += t.litres;
      if (!t.startedAt.isBefore(fullAt)) {
        km += t.distanceKm;
        litres += t.litres;
      }
    }
    // The economy since the tank was filled if there is enough of it, else the
    // car's whole record.
    final kmPerLitre = km >= minKm && litres > 0
        ? km / litres
        : allKm >= minKm && allLitres > 0
        ? allKm / allLitres
        : null;
    return TankReading(
      litres: left,
      tankLitres: tankLitres,
      usedLitres: ledger.usedSinceFull,
      kmSinceFull: km,
      rangeKm: kmPerLitre == null ? null : left * kmPerLitre,
      confidence: ledger.confidence.value,
      fullAt: fullAt,
    );
  }
}

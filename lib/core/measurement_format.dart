import 'number_format.dart';
import 'units.dart';

// Every value comes in canonical units (see units.dart) and is converted only
// here. The number of decimals follows DESIGN.md 10 and CLAUDE.md 1.6: no false
// precision, so speed and RPM are whole numbers and economy has one decimal.
// The unit itself is a separate, smaller label, never part of the number
// (DESIGN.md 4.5).

/// Speed in whole units. [kmh] is km/h.
String formatSpeed(double? kmh, {SpeedUnit unit = SpeedUnit.kmh}) =>
    formatNumber(kmh == null ? null : unit.fromKmh(kmh));

/// Engine speed in whole revolutions per minute.
String formatRpm(double? rpm) => formatNumber(rpm);

/// Distance with one decimal below 100 and whole units from there on.
/// [km] is kilometres.
///
/// The choice is made on the rounded value, so 99.96 reads `100`, not `100.0`.
String formatDistance(double? km, {DistanceUnit unit = DistanceUnit.km}) {
  if (km == null) return noValue;
  final value = unit.fromKm(km);
  return formatNumber(value, decimals: value.abs() < 99.95 ? 1 : 0);
}

/// Fuel economy with one decimal. [kmPerLitre] is km/L, whichever [unit] it is
/// shown in.
String formatEconomy(
  double? kmPerLitre, {
  EconomyUnit unit = EconomyUnit.kmPerLitre,
}) => formatNumber(
  kmPerLitre == null ? null : unit.fromKmPerLitre(kmPerLitre),
  decimals: 1,
);

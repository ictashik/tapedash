import 'dart:math' as math;

import 'package:tapedash/trips/trip.dart';

/// One second of a made-up drive: the speed in km/h and what else is wanted. The
/// rest is filled in from the speed.
typedef Moment = ({
  double kmh,
  double? rpm,
  double? throttle,
  double? lph,
  double? coolant,
  double? volts,
  double? lat,
  double? lon,
});

/// A drive, one sample a second, from a function of the time.
List<TripSample> madeDrive(
  int seconds, {
  required double Function(int t) kmh,
  double Function(int t, double kmh)? rpm,
  double Function(int t, double kmh)? lph,
  double Function(int t)? throttle,
  double? Function(int t)? coolant,
  double? Function(int t)? volts,
  (double, double) Function(int t, double km)? position,
}) {
  final out = <TripSample>[];
  var km = 0.0;
  for (var t = 0; t <= seconds; t++) {
    final v = kmh(t);
    km += v / 3600;
    final pos = position?.call(t, km);
    out.add(
      TripSample(
        seconds: t.toDouble(),
        speedKmh: v,
        rpm: rpm?.call(t, v) ?? (v < 1 ? 800 : 1200 + v * 20),
        throttle: throttle?.call(t) ?? (v < 1 ? 0 : 15),
        litresPerHour: lph?.call(t, v) ?? (v < 1 ? 0.8 : 1.5 + v * 0.05),
        latitude: pos?.$1,
        longitude: pos?.$2,
        coolantC: coolant?.call(t),
        voltage: volts?.call(t),
      ),
    );
  }
  return out;
}

/// A point [km] along a line that heads east from ([lat], [lon]).
(double, double) eastward(double lat, double lon, double km) =>
    (lat, lon + km / (111.32 * math.cos(lat * math.pi / 180)));

import 'dart:math' as math;

import 'package:tapedash/insights/insight_data.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/trips/trip.dart';

/// A made-up commute, driven the way a city is: a cold engine, a few lights and
/// one long junction, a stretch at 60, the revs of a five-speed, the battery
/// dipping at the turns. Deterministic for a seed. For the insight pages' tests
/// and captures; no part of it is real data.
class MadeCommute {
  MadeCommute(this.trip, this.samples);
  final Trip trip;
  final List<TripSample> samples;
}

const double _kmPerDegLat = 111.32;
const double _price = 115;

/// Waypoints of the commute in km east and north of home.
const _route = <(double, double)>[
  (0, 0),
  (1.2, 0.3),
  (2.5, 1.6),
  (3.4, 1.8),
  (5.0, 3.8),
  (6.5, 4.1),
  (8.0, 6.4),
  (9.4, 7.0),
];

({double lat, double lon}) _at(
  double km,
  List<double> cum,
  double lat0,
  double lon0,
  bool outbound,
  List<(double, double)> route,
) {
  final total = cum.last;
  final d = (outbound ? km : total - km).clamp(0.0, total);
  var i = 1;
  while (i < cum.length - 1 && cum[i] < d) {
    i++;
  }
  final f = ((d - cum[i - 1]) / (cum[i] - cum[i - 1])).clamp(0.0, 1.0);
  final x = route[i - 1].$1 + (route[i].$1 - route[i - 1].$1) * f;
  final y = route[i - 1].$2 + (route[i].$2 - route[i - 1].$2) * f;
  return (
    lat: lat0 + y / _kmPerDegLat,
    lon: lon0 + x / (_kmPerDegLat * math.cos(lat0 * math.pi / 180)),
  );
}

/// One commute. [gentle] drives it softly; [start] is the clock time it begins at;
/// [manual] gives the revs of a five-speed, else a CVT's. [coldStart] starts the
/// coolant at 32 °C.
MadeCommute madeCommute({
  required int id,
  required DateTime start,
  int seed = 1,
  bool outbound = true,
  bool gentle = false,
  bool manual = true,
  bool coldStart = true,
  double lat0 = 12.9352,
  double lon0 = 77.6245,
  bool isDemo = false,
  bool detour = false,
}) {
  final rng = math.Random(seed);
  // A detour takes another way round the fifth waypoint.
  final route = [
    for (final (i, w) in _route.indexed)
      i == 4 && detour ? (w.$1 + 0.3, w.$2 - 0.3) : w,
  ];
  final cum = <double>[0];
  for (var i = 1; i < route.length; i++) {
    final dx = route[i].$1 - route[i - 1].$1;
    final dy = route[i].$2 - route[i - 1].$2;
    cum.add(cum.last + math.sqrt(dx * dx + dy * dy));
  }
  final totalKm = cum.last;
  // Stops by km along the way: a light, the big junction, another light.
  final stops = <(double km, double wait)>[
    (3.0, 18.0 + rng.nextInt(20)),
    (6.0, gentle ? 70.0 : 95.0 + rng.nextInt(55)),
    (8.5, 20.0 + rng.nextInt(20)),
  ];
  final aUp = gentle ? 0.9 : 2.0 + rng.nextDouble() * 0.6;
  const aDown = 1.6;

  final samples = <TripSample>[];
  var v = 0.0; // m/s
  var s = 0.0; // metres along
  var wait = 4.0; // a few seconds at the start
  var nextStop = 0;
  var coolant = coldStart ? 32.0 : 86.0;
  var t = 0;
  var prevV = 0.0;
  // Loads that dent the voltage: a start, a length and a depth, the gaps random.
  final dips = <(int, int, double)>[];
  for (var at = 30 + rng.nextInt(30); at < 1800; at += 40 + rng.nextInt(70)) {
    dips.add((at, 3 + rng.nextInt(10), 0.5 + rng.nextDouble() * 1.1));
  }
  var depth = 0.0;
  var dipLeft = 0;
  while (s / 1000 < totalKm - 0.02 && t < 3600) {
    final km0 = s / 1000;
    final limit =
        (km0 < 1.4
            ? 24.0
            : km0 < 3.6
            ? 36.0
            : km0 < 4.6
            ? 46.0
            : km0 < 5.9
            ? 62.0
            : km0 < 8.2
            ? 38.0
            : 28.0) /
        3.6;
    var target = limit;
    if (nextStop < stops.length) {
      final stopAt = stops[nextStop].$1 * 1000;
      final gap = stopAt - s;
      if (gap <= 1.5 && v <= 1.5) {
        // Arrived: stand for as long as this stop takes.
        v = 0;
        s = stopAt;
        wait = stops[nextStop].$2;
        nextStop++;
      } else {
        target = math.min(limit, math.sqrt(2 * aDown * math.max(gap - 1, 0)));
      }
    }
    if (wait > 0) {
      wait -= 1;
      v = 0;
    } else if (v < target) {
      v = math.min(target, v + aUp);
    } else {
      v = math.max(target, v - aDown);
    }
    s += v;
    final kmh = (v * 3.6).roundToDouble();
    final acc = v - prevV;
    prevV = v;
    coolant = math.min(90, coolant + (90 - coolant) * 0.0062 + 0.01);
    if (dipLeft > 0) dipLeft--;
    for (final d in dips) {
      if (d.$1 == t) {
        dipLeft = d.$2;
        depth = d.$3;
      }
    }

    // Revs: a five-speed's gear for the speed, a little more under load.
    double rpm;
    if (kmh < 1) {
      rpm = 780 + rng.nextDouble() * 20;
    } else if (manual) {
      const ratios = [128.0, 76.0, 52.0, 39.0, 32.0];
      var g = 0;
      const upshift = [19.0, 29.0, 40.0, 52.0];
      while (g < 4 && kmh > upshift[g]) {
        g++;
      }
      rpm = math.max(
        900,
        ratios[g] * kmh * (1 + (rng.nextDouble() - 0.5) * 0.02),
      );
    } else {
      rpm = 1100 + kmh * 17 + math.max(0, acc) * 900;
    }
    final throttle = kmh < 1
        ? 0.0
        : (14 + acc * 22 + kmh * 0.12).clamp(8.0, 95.0);
    final cold = 1 + math.max(0, 80 - coolant) / 80 * 0.45;
    // A hard pull runs the engine rich, which is what makes a hard drive cost more.
    final rich = 1 + math.max(0, throttle - 50) / 100 * 2.2;
    final lph =
        (kmh < 1
            ? 0.85
            : (1.1 + 0.052 * kmh + math.max(0, acc) * 3.2 * (kmh / 40)) *
                  rich) *
        cold;
    final pos = _at(s / 1000, cum, lat0, lon0, outbound, route);
    samples.add(
      TripSample(
        seconds: t.toDouble(),
        speedKmh: kmh,
        rpm: rpm,
        throttle: throttle,
        litresPerHour: lph,
        latitude: pos.lat,
        longitude: pos.lon,
        load: 25 + kmh * 0.4,
        coolantC: coolant,
        voltage:
            (dipLeft > 0 ? 14.0 - depth : 14.0) +
            (rng.nextDouble() - 0.5) * 0.06,
      ),
    );
    t++;
  }

  // The trip's own totals, worked from the samples the way the app would.
  var km = 0.0, litres = 0.0, idleS = 0.0;
  final bucketL = <SpendBucket, double>{
    for (final b in SpendBucket.values) b: 0,
  };
  var hard = 0;
  var inHard = 0;
  for (var i = 1; i < samples.length; i++) {
    final a = samples[i];
    final dKm = a.speedKmh / 3600;
    final dl = a.litresPerHour / 3600;
    km += dKm;
    litres += dl;
    final acc = (a.speedKmh - samples[i - 1].speedKmh) / 3.6;
    if (a.speedKmh < 2) {
      idleS += 1;
      bucketL[SpendBucket.idling] = bucketL[SpendBucket.idling]! + dl;
      inHard = 0;
    } else if (acc > 2.2) {
      inHard++;
      if (inHard == 1) hard++;
      bucketL[SpendBucket.hardAcceleration] =
          bucketL[SpendBucket.hardAcceleration]! + dl;
    } else {
      inHard = 0;
      bucketL[SpendBucket.normal] = bucketL[SpendBucket.normal]! + dl;
    }
  }
  final cost = litres * _price;
  final blocks = <SpendBucket>[];
  final order = [
    SpendBucket.normal,
    SpendBucket.idling,
    SpendBucket.hardAcceleration,
  ];
  for (final b in order) {
    for (var k = 0; k < (bucketL[b]! * _price).round(); k++) {
      blocks.add(b);
    }
  }
  blocks.shuffle(math.Random(seed));
  final trip = Trip(
    id: id,
    startedAt: start,
    endedAt: start.add(Duration(seconds: samples.length)),
    isDemo: isDemo,
    distanceKm: km,
    litres: litres,
    uncalibratedLitres: litres,
    cost: cost,
    pricePerLitre: _price,
    idleSeconds: idleS,
    engineSeconds: samples.length.toDouble(),
    bucketLitres: bucketL,
    blockBuckets: blocks,
    hardAccelerations: hard,
    longIdles: 1,
    longestIdleSeconds: stops[1].$2,
  );
  return MadeCommute(trip, samples);
}

/// A Sunday of pulls: second, third and fourth gear taken hard to 5,800 rpm, with
/// a lift between, on a road with no route to speak of.
MadeCommute madePulls({
  required int id,
  required DateTime start,
  int seed = 3,
}) {
  final rng = math.Random(seed);
  const ratios = [76.0, 52.0, 39.0];
  const from = [20.0, 28.0, 38.0];
  final samples = <TripSample>[];
  var t = 0;
  void add(double kmh, double rpm, double throttle, double lph) {
    samples.add(
      TripSample(
        seconds: (t++).toDouble(),
        speedKmh: kmh.roundToDouble(),
        rpm: rpm,
        throttle: throttle,
        litresPerHour: lph,
        coolantC: 90,
        voltage: 14.0 + (rng.nextDouble() - 0.5) * 0.06,
      ),
    );
  }

  for (var k = 0; k < 12; k++) {
    final g = k % 3;
    var v = from[g];
    while (ratios[g] * v < 5800 && v < 120) {
      add(
        v,
        ratios[g] * v * (1 + (rng.nextDouble() - 0.5) * 0.01),
        78 + rng.nextDouble() * 22,
        11 + rng.nextDouble() * 5,
      );
      v += 4;
    }
    // A lift to the next pull.
    for (var j = 0; j < 8; j++) {
      add(v - j * 6, ratios[g] * (v - j * 6), 0, 0.5);
    }
  }
  final trip = Trip(
    id: id,
    startedAt: start,
    endedAt: start.add(Duration(seconds: samples.length)),
    distanceKm: 4,
    litres: 0.7,
    cost: 0.7 * _price,
    pricePerLitre: _price,
    engineSeconds: samples.length.toDouble(),
  );
  return MadeCommute(trip, samples);
}

/// A trip with only its totals, for a year's bars.
Trip summaryTrip(int id, DateTime at, math.Random rng, {bool highway = false}) {
  final km = highway ? 60 + rng.nextDouble() * 140 : 8 + rng.nextDouble() * 14;
  final kmpl = highway ? 17 + rng.nextDouble() * 3 : 11 + rng.nextDouble() * 4;
  final litres = km / kmpl;
  final idle = highway ? 0.03 : 0.12 + rng.nextDouble() * 0.2;
  final hard = highway ? 0.02 : 0.01 + rng.nextDouble() * 0.05;
  final fast = highway ? 0.3 : 0.0;
  final normal = 1 - idle - hard - fast;
  return Trip(
    id: id,
    startedAt: at,
    endedAt: at.add(const Duration(minutes: 40)),
    distanceKm: km,
    litres: litres,
    cost: litres * _price,
    pricePerLitre: _price,
    bucketLitres: {
      SpendBucket.normal: litres * normal,
      SpendBucket.idling: litres * idle,
      SpendBucket.hardAcceleration: litres * hard,
      SpendBucket.highSpeed: litres * fast,
    },
  );
}

/// What a month or three of one person's driving looks like to the insight
/// pages: [days] days of commutes (the earlier ones summary-only), a cold start
/// on most mornings, and a year of bars behind them when [year] is set.
InsightData madeInsightData({
  DateTime? now,
  int days = 14,
  bool manual = true,
  bool year = false,
  bool pulls = false,
}) {
  final today = now ?? DateTime(2026, 10, 17, 9);
  final rows = <(Trip, List<TripSample>)>[];
  var id = 1;
  final rng = math.Random(5);
  if (year) {
    var d = DateTime(2026, 1, 1, 8);
    while (d.isBefore(today.subtract(Duration(days: days + 1)))) {
      final wk = d.weekday < 6;
      if (wk) {
        for (var k = 0; k < (rng.nextDouble() < 0.6 ? 2 : 1); k++) {
          rows.add((
            summaryTrip(id++, d.add(Duration(hours: 9 * k)), rng),
            const [],
          ));
        }
      } else if (rng.nextDouble() < 0.14) {
        rows.add((summaryTrip(id++, d, rng, highway: true), const []));
      } else if (rng.nextDouble() < 0.5) {
        rows.add((summaryTrip(id++, d, rng), const []));
      }
      d = d.add(const Duration(days: 1));
    }
  }
  for (var k = days; k >= 0; k--) {
    final day = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: k));
    if (day.weekday >= 6) continue;
    for (final out in [true, false]) {
      final c = madeCommute(
        id: id++,
        start: day.add(Duration(hours: out ? 8 : 18, minutes: out ? 10 : 20)),
        seed: id,
        outbound: out,
        gentle: k == 1 || k == 4 || k == 8,
        detour: day.day.isOdd,
        manual: manual,
        coldStart: out,
      );
      rows.add((c.trip, c.samples));
    }
  }
  if (pulls) {
    final p = madePulls(
      id: id++,
      start: today.subtract(const Duration(days: 4)),
    );
    rows.add((p.trip, p.samples));
  }
  rows.sort((a, b) => b.$1.startedAt.compareTo(a.$1.startedAt));
  return InsightData.of(rows, fallbackPrice: _price);
}

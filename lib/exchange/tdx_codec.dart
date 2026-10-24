import '../fuel/fuel_estimator.dart' show FuelSource;
import '../insights/rest_voltage_log.dart' show RestReading;
import '../money/fill_up.dart';
import '../money/spend_bucket.dart';
import '../trips/trip.dart';
import 'tdx_format.dart';

/// A value read out of a line, or the plain reason it was not good.
class Parsed<T> {
  const Parsed.ok(T this.value) : problem = null;
  const Parsed.bad(String this.problem) : value = null;

  final T? value;
  final String? problem;

  bool get isOk => problem == null;
}

/// How the trip, its samples, the fill-ups and the resting readings are written to
/// and read from a line (docs/EXCHANGE.md 1). Reading **validates**: a record with
/// an impossible value is refused on its own and never reaches the log, since a
/// file is something that was carried and may have been edited, made by another
/// version, or damaged in a way a checksum cannot tell from a real number.
abstract final class TdxCodec {
  // What a trip's times and figures may be, wide enough for any real drive and
  // narrow enough to refuse a wrong one.
  static final int _earliestMs = DateTime.utc(2000).millisecondsSinceEpoch;
  static final int _latestMs = DateTime.utc(2100).millisecondsSinceEpoch;
  static const int _longestTripMs = 3 * 24 * 3600 * 1000;

  /// The letters of the Money Tape's `blocks` string, by bucket.
  static const Map<SpendBucket, String> _blockLetter = {
    SpendBucket.normal: 'n',
    SpendBucket.idling: 'i',
    SpendBucket.hardAcceleration: 'h',
    SpendBucket.highSpeed: 's',
  };

  static const Map<FuelSource, String> _sourceName = {
    FuelSource.fuelRate: '5e',
    FuelSource.airFlow: 'maf',
    FuelSource.speedDensity: 'map',
    FuelSource.none: 'none',
  };

  /// A finite number, or null: JSON has no NaN or infinity.
  static num? finite(num? v) => v == null || !v.isFinite ? null : v;

  // ---- trips ----

  static Map<String, Object?> tripToJson(Trip t) => {
    't': 'trip',
    'k': t.startedAt.millisecondsSinceEpoch,
    'startedMs': t.startedAt.millisecondsSinceEpoch,
    'endedMs': t.endedAt?.millisecondsSinceEpoch,
    'distanceKm': finite(t.distanceKm),
    'litres': finite(t.litres),
    'uncalibratedLitres': finite(t.uncalibratedLitres),
    'cost': finite(t.cost),
    'pricePerLitre': finite(t.pricePerLitre),
    'idleSeconds': finite(t.idleSeconds),
    'engineSeconds': finite(t.engineSeconds),
    'bucketLitres': {
      for (final b in SpendBucket.values)
        b.name: finite(t.bucketLitres[b] ?? 0),
    },
    'blocks': t.blockBuckets.map((b) => _blockLetter[b]!).join(),
    'fuelSource': _sourceName[t.fuelSource],
    'lowConfidence': t.lowConfidence,
    'calibrationFactor': finite(t.calibrationFactor),
    'hardAccelerations': t.hardAccelerations,
    'hardBrakings': t.hardBrakings,
    'longIdles': t.longIdles,
    'longestIdleSeconds': finite(t.longestIdleSeconds),
    'highRpmSeconds': finite(t.highRpmSeconds),
    'speedingSeconds': finite(t.speedingSeconds),
  };

  /// The finished trip a `trip` line holds, or why it is not one.
  static Parsed<Trip> tripFromJson(Map<String, Object?> j) {
    final started = _int(j['startedMs'] ?? j['k']);
    if (started == null || started < _earliestMs || started > _latestMs) {
      return const Parsed.bad('the trip has no sensible start time');
    }
    final ended = _int(j['endedMs']);
    if (ended == null) {
      return const Parsed.bad('the trip is not finished');
    }
    if (ended < started || ended - started > _longestTripMs) {
      return const Parsed.bad('the trip ends before it starts, or lasts days');
    }
    final distance = _range(j['distanceKm'], 0, 5000);
    final litres = _range(j['litres'], 0, 1000);
    final raw = _range(j['uncalibratedLitres'] ?? j['litres'], 0, 1000);
    final engine = _range(j['engineSeconds'], 0, _longestTripMs / 1000);
    final idle = _range(j['idleSeconds'], 0, _longestTripMs / 1000);
    if (distance == null ||
        litres == null ||
        raw == null ||
        engine == null ||
        idle == null) {
      return const Parsed.bad('a distance, fuel or time is out of range');
    }
    final costRaw = j['cost'];
    final cost = costRaw == null ? null : _range(costRaw, 0, 1e7);
    if (costRaw != null && cost == null) {
      return const Parsed.bad('the cost is out of range');
    }
    final priceRaw = j['pricePerLitre'];
    final price = priceRaw == null ? null : _range(priceRaw, 0, 1e4);
    if (priceRaw != null && price == null) {
      return const Parsed.bad('the price is out of range');
    }
    final factor = _range(j['calibrationFactor'] ?? 1, 0.1, 10);
    if (factor == null) {
      return const Parsed.bad('the calibration factor is out of range');
    }

    final buckets = <SpendBucket, double>{};
    final b = j['bucketLitres'];
    for (final bucket in SpendBucket.values) {
      final v = b is Map ? _range(b[bucket.name] ?? 0, 0, 1000) : 0.0;
      if (v == null) return const Parsed.bad('a bucket is out of range');
      buckets[bucket] = v.toDouble();
    }

    final blocks = <SpendBucket>[];
    final letters = j['blocks'];
    if (letters is String) {
      if (letters.length > 200000) {
        return const Parsed.bad('the Money Tape is too long');
      }
      for (final c in letters.split('')) {
        final bucket = _blockLetter.entries
            .where((e) => e.value == c)
            .map((e) => e.key)
            .firstOrNull;
        if (bucket == null) {
          return const Parsed.bad(
            'the Money Tape has a block it does not know',
          );
        }
        blocks.add(bucket);
      }
    }

    final counts = <String, int>{};
    for (final key in const [
      'hardAccelerations',
      'hardBrakings',
      'longIdles',
    ]) {
      final n = _int(j[key] ?? 0);
      if (n == null || n < 0 || n > 100000) {
        return Parsed.bad('$key is out of range');
      }
      counts[key] = n;
    }
    final longest = _range(j['longestIdleSeconds'] ?? 0, 0, 259200);
    final highRpm = _range(j['highRpmSeconds'] ?? 0, 0, 259200);
    final speeding = _range(j['speedingSeconds'] ?? 0, 0, 259200);
    if (longest == null || highRpm == null || speeding == null) {
      return const Parsed.bad('a coach duration is out of range');
    }

    final source = _sourceName.entries
        .where((e) => e.value == j['fuelSource'])
        .map((e) => e.key)
        .firstOrNull;

    return Parsed.ok(
      Trip(
        startedAt: DateTime.fromMillisecondsSinceEpoch(started),
        endedAt: DateTime.fromMillisecondsSinceEpoch(ended),
        distanceKm: distance.toDouble(),
        litres: litres.toDouble(),
        uncalibratedLitres: raw.toDouble(),
        cost: cost?.toDouble(),
        pricePerLitre: price?.toDouble(),
        idleSeconds: idle.toDouble(),
        engineSeconds: engine.toDouble(),
        bucketLitres: buckets,
        blockBuckets: blocks,
        fuelSource: source ?? FuelSource.none,
        lowConfidence: j['lowConfidence'] == true,
        calibrationFactor: factor.toDouble(),
        hardAccelerations: counts['hardAccelerations']!,
        hardBrakings: counts['hardBrakings']!,
        longIdles: counts['longIdles']!,
        longestIdleSeconds: longest.toDouble(),
        highRpmSeconds: highRpm.toDouble(),
        speedingSeconds: speeding.toDouble(),
      ),
    );
  }

  // ---- samples ----

  static Map<String, Object?> samplesToJson(
    int tripKey,
    List<TripSample> samples,
  ) => {
    't': 'samples',
    'trip': tripKey,
    'cols': Tdx.sampleColumns,
    'rows': [
      for (final s in samples)
        [
          finite(s.seconds),
          finite(s.speedKmh),
          finite(s.rpm),
          finite(s.throttle),
          finite(s.litresPerHour),
          finite(s.latitude),
          finite(s.longitude),
          finite(s.load),
          finite(s.coolantC),
          finite(s.voltage),
        ],
    ],
  };

  /// The samples of a `samples` line. A row with an impossible value is dropped
  /// and counted, and the rest of the line is kept.
  static Parsed<({List<TripSample> samples, int dropped})> samplesFromJson(
    Map<String, Object?> j,
  ) {
    final cols = j['cols'];
    final rows = j['rows'];
    if (cols is! List || rows is! List) {
      return const Parsed.bad('the samples have no columns or no rows');
    }
    final at = <String, int>{
      for (var i = 0; i < cols.length; i++)
        if (cols[i] is String) cols[i] as String: i,
    };
    for (final need in Tdx.requiredColumns) {
      if (!at.containsKey(need)) {
        return Parsed.bad('the samples have no "$need" column');
      }
    }
    final out = <TripSample>[];
    var dropped = 0;
    for (final row in rows) {
      if (row is! List || row.length != cols.length) {
        dropped++;
        continue;
      }
      num? col(String name) {
        final i = at[name];
        if (i == null) return null;
        final v = row[i];
        return v is num && v.isFinite ? v : null;
      }

      final s = col('s');
      final kmh = col('kmh');
      final rpm = col('rpm');
      final thr = col('thr');
      final lph = col('lph');
      final lat = col('lat');
      final lon = col('lon');
      final load = col('load');
      final clt = col('clt');
      final v = col('v');
      bool within(num? x, num lo, num hi) => x == null || (x >= lo && x <= hi);
      if (s == null ||
          kmh == null ||
          rpm == null ||
          thr == null ||
          lph == null ||
          !within(s, 0, 259200) ||
          !within(kmh, 0, 400) ||
          !within(rpm, 0, 20000) ||
          !within(thr, 0, 101) ||
          !within(lph, 0, 2000) ||
          !within(lat, -90, 90) ||
          !within(lon, -180, 180) ||
          !within(load, 0, 101) ||
          !within(clt, -60, 260) ||
          !within(v, 0, 60)) {
        dropped++;
        continue;
      }
      out.add(
        TripSample(
          seconds: s.toDouble(),
          speedKmh: kmh.toDouble(),
          rpm: rpm.toDouble(),
          throttle: thr.toDouble(),
          litresPerHour: lph.toDouble(),
          latitude: lat?.toDouble(),
          longitude: lon?.toDouble(),
          load: load?.toDouble(),
          coolantC: clt?.toDouble(),
          voltage: v?.toDouble(),
        ),
      );
    }
    return Parsed.ok((samples: out, dropped: dropped));
  }

  // ---- fill-ups ----

  static Map<String, Object?> fillUpToJson(FillUp f) => {
    't': 'fillup',
    'k': f.at.millisecondsSinceEpoch,
    'atMs': f.at.millisecondsSinceEpoch,
    'litres': finite(f.litres),
    'amount': finite(f.amount),
    'full': f.fullTank,
    'factor': finite(f.factor),
  };

  static Parsed<FillUp> fillUpFromJson(Map<String, Object?> j) {
    final at = _int(j['atMs'] ?? j['k']);
    if (at == null || at < _earliestMs || at > _latestMs) {
      return const Parsed.bad('the fill-up has no sensible date');
    }
    final litres = _range(j['litres'], 0.1, 2000);
    final amount = _range(j['amount'], 0, 1e7);
    if (litres == null || amount == null) {
      return const Parsed.bad('the litres or the amount are out of range');
    }
    final factorRaw = j['factor'];
    final factor = factorRaw == null ? null : _range(factorRaw, 0.3, 3);
    if (factorRaw != null && factor == null) {
      return const Parsed.bad('the calibration factor is out of range');
    }
    return Parsed.ok(
      FillUp(
        at: DateTime.fromMillisecondsSinceEpoch(at),
        litres: litres.toDouble(),
        amount: amount.toDouble(),
        fullTank: j['full'] == true,
        factor: factor?.toDouble(),
      ),
    );
  }

  // ---- the battery at rest ----

  static Map<String, Object?> restToJson(List<RestReading> readings) => {
    't': 'rest',
    'readings': [
      for (final r in readings) [r.at.millisecondsSinceEpoch, r.volts],
    ],
  };

  static Parsed<List<RestReading>> restFromJson(Map<String, Object?> j) {
    final list = j['readings'];
    if (list is! List) return const Parsed.bad('the readings are not a list');
    final out = <RestReading>[];
    for (final e in list) {
      if (e is! List || e.length != 2) continue;
      final ms = _int(e[0]);
      final v = e[1];
      if (ms == null ||
          ms < _earliestMs ||
          ms > _latestMs ||
          v is! num ||
          !v.isFinite ||
          v < 5 ||
          v > 20) {
        continue;
      }
      out.add(
        RestReading(DateTime.fromMillisecondsSinceEpoch(ms), v.toDouble()),
      );
    }
    return Parsed.ok(out);
  }

  // ---- helpers ----

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is double && v.isFinite && v == v.roundToDouble()) return v.toInt();
    return null;
  }

  static num? _range(Object? v, num lo, num hi) {
    if (v is! num || !v.isFinite) return null;
    return v >= lo && v <= hi ? v : null;
  }
}

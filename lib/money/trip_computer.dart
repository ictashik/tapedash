import 'dart:async';
import 'dart:math' as math;

import '../coach/coach_thresholds.dart';
import '../coach/hard_event_detector.dart';
import '../core/observable.dart';
import '../fuel/fuel_constants.dart';
import '../fuel/fuel_estimator.dart';
import '../fuel/fuel_integrator.dart';
import '../location/location_source.dart';
import '../vehicle/sensor.dart';
import '../vehicle/vehicle_state.dart';
import 'spend_bucket.dart';

/// One rupee of spend, as it fell (CLAUDE.md 8.6): which bucket the fuel that
/// took the running total past a whole unit was burnt in. The Money Tape prints
/// one block for each.
class MoneyEvent {
  const MoneyEvent({
    required this.bucket,
    required this.index,
    required this.at,
  });

  final SpendBucket bucket;

  /// 1 for the first rupee, 2 for the second, and so on.
  final int index;

  /// When, on the monotonic clock.
  final Duration at;
}

/// A sample of fuel burnt, waiting to be put in a bucket.
class _Piece {
  _Piece({
    required this.uncalibrated,
    required this.calibrated,
    required this.at,
    required this.idle,
    required this.highSpeed,
  });

  final double uncalibrated;
  final double calibrated;
  final Duration at;
  final bool idle;
  final bool highSpeed;
  SpendBucket? bucket;
}

/// The live trip computer (CLAUDE.md 8.6 and 8.7): distance, fuel, cost, idling
/// and where the money went, kept up to date as the car drives.
///
/// **Distance** is the OBD speed integrated over time, with the phone's GPS as a
/// fallback while the car's speed has gone quiet. **Fuel** is the estimator's
/// flow, integrated, times the calibration factor. **Cost** is the fuel times
/// the price, and while there is no price the fuel is still counted and there is
/// no cost.
///
/// **Where it went:** each sample of fuel goes into exactly one bucket, so the
/// buckets always add up to the total. Idling comes first (speed below 2 km/h);
/// then a hard acceleration; then above the speed threshold; then everything
/// else. A hard acceleration is only known to be one after a second or two, so
/// the fuel from its first moments waits, in order, until the detector says
/// which it was.
class TripComputer {
  TripComputer({
    required this.vehicle,
    required this.estimator,
    required this.hardEvents,
    required this.calibrationFactor,
    required this.price,
    this.setup = const VehicleSetup(),
    this.thresholds = CoachThresholds.normal,
    this.location,
    this.onEstimate,
    FuelIntegrator? integrator,
  }) : _integrator = integrator ?? FuelIntegrator() {
    estimator.flow.addListener(_onFlow);
    vehicle.speed.addListener(_onSpeed);
    vehicle.fuelLevel.addListener(_publishRemaining);
    hardEvents.accelerationPhase.addListener(_onPhase);
    price.addListener(_onPrice);
    _sub = location?.fixes.listen(_onFix);
  }

  final VehicleState vehicle;
  final FuelEstimator estimator;
  final HardEventDetector hardEvents;

  /// The correction to apply to the raw estimate now (`Calibration.factor`).
  final double Function() calibrationFactor;

  /// The price of a litre, or null while none is set.
  final Observable<double?> price;

  VehicleSetup setup;
  final CoachThresholds thresholds;
  final LocationSource? location;

  /// Told the raw litres of each stretch, for the fill-up ledger.
  final void Function(double uncalibratedLitres)? onEstimate;

  final FuelIntegrator _integrator;

  /// The most speed readings apart that still count as one stretch of driving.
  static const Duration speedGap = Duration(seconds: 3);

  /// Below this an instant km/L means nothing (CLAUDE.md 8.6), and above it the
  /// figure is capped, as a coast with the fuel cut would give an endless one.
  static const double minInstantKmh = 5;
  static const double maxInstantKmPerLitre = 99.9;

  static const double idleBelowKmh = 2;

  // Distance and time.
  final ObservableValue<double> _distance = ObservableValue(0);
  final ObservableValue<double> _idleSeconds = ObservableValue(0);
  double _distanceKm = 0;
  double _gpsKm = 0;
  double _idleS = 0;
  ({double kmh, Duration at})? _lastSpeed;
  LocationFix? _lastFix;
  StreamSubscription<LocationFix>? _sub;

  // Fuel and money.
  final ObservableValue<double> _litres = ObservableValue(0);
  final ObservableValue<double?> _cost = ObservableValue(null);
  final ObservableValue<double?> _costPerKm = ObservableValue(null);
  final ObservableValue<double?> _kmPerLitre = ObservableValue(null);
  final ObservableValue<double?> _instantKmPerLitre = ObservableValue(null);
  final ObservableValue<double?> _idleCost = ObservableValue(null);
  final ObservableValue<double?> _remainingLitres = ObservableValue(null);
  final ObservableValue<double?> _remainingKm = ObservableValue(null);
  final ObservableValue<int> _blockCount = ObservableValue(0);
  final ObservableValue<bool> _fuelKnown = ObservableValue(false);

  double _uncalibratedL = 0;
  double _calibratedL = 0;
  final Map<SpendBucket, double> _bucketLitres = {
    for (final b in SpendBucket.values) b: 0,
  };
  final List<_Piece> _resolved = [];
  final List<_Piece> _pending = [];
  List<MoneyEvent> _blocks = [];
  double _blockCost = 0;
  final Map<SpendBucket, double> _blockBucketCost = {
    for (final b in SpendBucket.values) b: 0,
  };
  final Map<SpendBucket, int> _blockBucketCount = {
    for (final b in SpendBucket.values) b: 0,
  };
  final List<void Function(MoneyEvent)> _blockListeners = [];
  final List<void Function()> _resetListeners = [];

  double? _speedEma;
  double? _flowEma;
  Duration? _emaAt;

  Duration? startedAt;

  // -------------------------------------------------------------- outputs

  /// Kilometres driven, from the car's speed.
  Observable<double> get distanceKm => _distance;

  /// Kilometres by GPS, kept as a check on [distanceKm] (CLAUDE.md 8.6).
  double get gpsDistanceKm => _gpsKm;

  /// Seconds stopped with the engine running.
  Observable<double> get idleSeconds => _idleSeconds;

  /// Litres burnt, calibrated.
  Observable<double> get litres => _litres;

  /// The raw litres, before calibration.
  double get uncalibratedLitres => _uncalibratedL;

  /// Cost so far, or null while no price is set.
  Observable<double?> get cost => _cost;

  /// Cost per kilometre, or null with no price or under a hundred metres.
  Observable<double?> get costPerKm => _costPerKm;

  /// Kilometres a litre over the whole trip, or null under a hundred metres or
  /// with no fuel used yet.
  Observable<double?> get kmPerLitre => _kmPerLitre;

  /// Kilometres a litre right now, smoothed over a few seconds, or null below
  /// 5 km/h.
  Observable<double?> get instantKmPerLitre => _instantKmPerLitre;

  /// What idling has cost.
  Observable<double?> get idleCost => _idleCost;

  /// Fuel left in the tank, in litres, if the car reports its level.
  Observable<double?> get remainingLitres => _remainingLitres;

  /// The distance that fuel should take, at this trip's economy.
  Observable<double?> get remainingKm => _remainingKm;

  /// How many rupee blocks there are.
  Observable<int> get blockCount => _blockCount;

  /// Whether the car has given any fuel figure this trip. A car that gives none
  /// (an old one with no air flow, manifold or fuel-rate PID) has no fuel and no
  /// cost, and the UI says money is unavailable (CLAUDE.md 8.4).
  Observable<bool> get fuelKnown => _fuelKnown;

  bool get _hasFuel => _integrator.last != null;

  /// Which fuel source the estimate is from.
  Observable<FuelSource> get source => estimator.source;

  /// Whether the estimate is one to be wary of: a diesel's from air flow.
  bool get lowConfidence => _integrator.last?.lowConfidence ?? false;

  /// Calibrated litres in each bucket. They add up to [litres] less whatever is
  /// still waiting to be put in one.
  Map<SpendBucket, double> get bucketLitres => Map.of(_bucketLitres);

  /// What each bucket cost, or null with no price.
  Map<SpendBucket, double>? get bucketCosts {
    final p = price.value;
    if (p == null) return null;
    return {for (final e in _bucketLitres.entries) e.key: e.value * p};
  }

  /// Litres burnt but not yet put in a bucket: a hard acceleration is not
  /// known to be one for a second or two.
  double get pendingLitres =>
      _pending.fold<double>(0, (a, p) => a + p.calibrated);

  /// The rupee blocks so far, in order.
  List<MoneyEvent> get blocks => List.unmodifiable(_blocks);

  /// Calls [listener] with each new rupee block.
  void onBlock(void Function(MoneyEvent) listener) =>
      _blockListeners.add(listener);

  /// Calls [listener] when the blocks are worked out again from the start,
  /// because the price changed.
  void onBlocksReset(void Function() listener) => _resetListeners.add(listener);

  // ----------------------------------------------------------------- input

  void _onSpeed() {
    final r = vehicle.speed.value;
    if (r == null) return;
    startedAt ??= r.at;
    final last = _lastSpeed;
    _lastSpeed = (kmh: r.value, at: r.at);
    if (last == null) return;
    final dt = r.at - last.at;
    if (dt <= Duration.zero || dt > speedGap) return;
    final seconds = dt.inMicroseconds / 1e6;
    _distanceKm += (last.kmh + r.value) / 2 * seconds / 3600;
    if (vehicle.engineRunning.value &&
        last.kmh < idleBelowKmh &&
        r.value < idleBelowKmh) {
      _idleS += seconds;
    }
    _distance.value = _distanceKm;
    _idleSeconds.value = _idleS;
    _updateEma(speed: r.value, at: r.at);
    _publishDerived();
  }

  void _onFix(LocationFix fix) {
    final last = _lastFix;
    _lastFix = fix;
    if (last == null) return;
    final dt = fix.time.difference(last.time).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 5) return;
    final km = (last.speedMs + fix.speedMs) / 2 * dt / 1000;
    _gpsKm += km;
    // The phone's speed takes over while the car's has gone quiet, so a trip
    // is not left short by an adapter that dropped.
    if (vehicle.engineRunning.value && vehicle.isStale(Sensor.speed)) {
      _distanceKm += km;
      _distance.value = _distanceKm;
      _publishDerived();
    }
  }

  void _onFlow() {
    final flow = estimator.flow.value;
    if (flow == null) return;
    startedAt ??= flow.at;
    final inc = _integrator.add(flow);
    if (inc == null) {
      _updateEma(
        flowLph: flow.litresPerHour * calibrationFactor(),
        at: flow.at,
      );
      return;
    }
    _uncalibratedL += inc.litres;
    onEstimate?.call(inc.litres);
    final calibrated = inc.litres * calibrationFactor();
    _calibratedL += calibrated;
    final speed = vehicle.speed.value;
    final speedKmh = speed?.value;
    final piece = _Piece(
      uncalibrated: inc.litres,
      calibrated: calibrated,
      at: inc.to,
      idle: speedKmh != null && speedKmh < idleBelowKmh,
      highSpeed: speedKmh != null && speedKmh > thresholds.speedLimitKmh,
    );
    _litres.value = _calibratedL;
    _updateEma(flowLph: flow.litresPerHour * calibrationFactor(), at: flow.at);
    _place(piece);
    _publishDerived();
  }

  void _onPhase() {
    switch (hardEvents.accelerationPhase.value) {
      case HardPhase.active:
        _resolvePending(hard: true);
      case HardPhase.none:
        _resolvePending(hard: false);
      case HardPhase.candidate:
        break;
    }
    _publishDerived();
  }

  void _onPrice() {
    _rebuildBlocks(notifyReset: true);
    _publishDerived();
  }

  // ------------------------------------------------------------ attribution

  void _place(_Piece piece) {
    final phase = hardEvents.accelerationPhase.value;
    if (phase == HardPhase.candidate || _pending.isNotEmpty) {
      // Order matters for the blocks, so nothing passes a piece that is waiting.
      _pending.add(piece);
      return;
    }
    piece.bucket = _bucketFor(piece, hard: phase == HardPhase.active);
    _commit(piece);
  }

  SpendBucket _bucketFor(_Piece p, {required bool hard}) {
    if (p.idle) return SpendBucket.idling;
    if (hard) return SpendBucket.hardAcceleration;
    if (p.highSpeed) return SpendBucket.highSpeed;
    return SpendBucket.normal;
  }

  void _resolvePending({required bool hard}) {
    if (_pending.isEmpty) return;
    final waiting = List.of(_pending);
    _pending.clear();
    for (final p in waiting) {
      p.bucket = _bucketFor(p, hard: hard);
      _commit(p);
    }
  }

  void _commit(_Piece p) {
    _resolved.add(p);
    _bucketLitres[p.bucket!] = _bucketLitres[p.bucket!]! + p.calibrated;
    final pr = price.value;
    if (pr == null) return;
    final events = _accrue(p, pr);
    for (final event in events) {
      _blocks.add(event);
      _blockCount.value = _blocks.length;
      for (final l in List.of(_blockListeners)) {
        l(event);
      }
    }
  }

  /// Adds a piece's cost, and returns the blocks it completes. A block goes to
  /// the bucket with the most spend not yet in a block, so that each bucket has
  /// its own cost's worth of blocks to within one, however the pieces of
  /// different buckets are interleaved. (Giving it to the bucket of the piece
  /// that crossed the line would favour whichever bucket happened to be
  /// burning when the total was near a whole rupee.)
  List<MoneyEvent> _accrue(_Piece p, double pricePerLitre) {
    final out = <MoneyEvent>[];
    _blockBucketCost[p.bucket!] =
        _blockBucketCost[p.bucket!]! + p.calibrated * pricePerLitre;
    _blockCost += p.calibrated * pricePerLitre;
    var index = _blocks.length + out.length;
    while (_blockCost >= index + 1) {
      SpendBucket best = SpendBucket.normal;
      var deficit = double.negativeInfinity;
      for (final b in SpendBucket.values) {
        final d = _blockBucketCost[b]! - _blockBucketCount[b]!;
        if (d > deficit) {
          deficit = d;
          best = b;
        }
      }
      _blockBucketCount[best] = _blockBucketCount[best]! + 1;
      index++;
      out.add(MoneyEvent(bucket: best, index: index, at: p.at));
    }
    return out;
  }

  /// Works the blocks out again, from every resolved piece, at the current
  /// price: when the price is set or changed after some fuel is already
  /// burnt.
  void _rebuildBlocks({required bool notifyReset}) {
    _blocks = [];
    _blockCost = 0;
    for (final b in SpendBucket.values) {
      _blockBucketCost[b] = 0;
      _blockBucketCount[b] = 0;
    }
    final pr = price.value;
    if (pr != null) {
      for (final p in _resolved) {
        _blocks.addAll(_accrue(p, pr));
      }
    }
    _blockCount.value = _blocks.length;
    if (notifyReset) {
      for (final l in List.of(_resetListeners)) {
        l();
      }
    }
  }

  // --------------------------------------------------------------- derived

  void _updateEma({double? speed, double? flowLph, required Duration at}) {
    const tau = 3.0;
    final last = _emaAt;
    final dt = last == null ? 0.0 : (at - last).inMicroseconds / 1e6;
    final a = dt <= 0 ? 1.0 : 1 - math.exp(-dt / tau);
    if (speed != null) {
      _speedEma = _speedEma == null
          ? speed
          : _speedEma! + a * (speed - _speedEma!);
    }
    if (flowLph != null) {
      _flowEma = _flowEma == null
          ? flowLph
          : _flowEma! + a * (flowLph - _flowEma!);
    }
    if (dt > 0 || last == null) _emaAt = at;
  }

  void _publishDerived() {
    final pr = _hasFuel ? price.value : null;
    _fuelKnown.value = _hasFuel;
    final l = _litres.value;
    _cost.value = pr == null ? null : l * pr;
    _costPerKm.value = pr == null || _distanceKm < 0.1
        ? null
        : l * pr / _distanceKm;
    final kmPerL = _distanceKm < 0.1 || l <= 0 ? null : _distanceKm / l;
    _kmPerLitre.value = kmPerL;
    _idleCost.value = pr == null
        ? null
        : _bucketLitres[SpendBucket.idling]! * pr;
    final s = _speedEma;
    final f = _flowEma;
    if (s == null || f == null || s < minInstantKmh) {
      _instantKmPerLitre.value = null;
    } else if (f < 0.05) {
      _instantKmPerLitre.value = maxInstantKmPerLitre;
    } else {
      _instantKmPerLitre.value = math.min(maxInstantKmPerLitre, s / f);
    }
    _publishRemaining();
  }

  void _publishRemaining() {
    final level = vehicle.fuelLevel.value;
    if (level == null) {
      _remainingLitres.value = null;
      _remainingKm.value = null;
      return;
    }
    final litres = level.value / 100 * setup.tankLitres;
    _remainingLitres.value = litres;
    final kmPerL = _kmPerLitre.value;
    _remainingKm.value = kmPerL == null ? null : litres * kmPerL;
  }

  /// Puts the last of the waiting fuel in the buckets, at the end of a trip.
  void finish() {
    _resolvePending(hard: false);
    _publishDerived();
  }

  /// Starts a new trip: everything back to nothing.
  void reset() {
    _integrator.reset();
    _distanceKm = 0;
    _gpsKm = 0;
    _idleS = 0;
    _uncalibratedL = 0;
    _calibratedL = 0;
    _lastSpeed = null;
    _lastFix = null;
    _speedEma = null;
    _flowEma = null;
    _emaAt = null;
    startedAt = null;
    for (final b in SpendBucket.values) {
      _bucketLitres[b] = 0;
    }
    _resolved.clear();
    _pending.clear();
    _blocks = [];
    _blockCost = 0;
    for (final b in SpendBucket.values) {
      _blockBucketCost[b] = 0;
      _blockBucketCount[b] = 0;
    }
    _distance.value = 0;
    _idleSeconds.value = 0;
    _litres.value = 0;
    _blockCount.value = 0;
    _publishDerived();
    for (final l in List.of(_resetListeners)) {
      l();
    }
  }

  /// The engine went off: the time until it is next on is not counted.
  void engineOff() {
    _integrator.breakStretch();
    _lastSpeed = null;
    _lastFix = null;
  }

  void dispose() {
    estimator.flow.removeListener(_onFlow);
    vehicle.speed.removeListener(_onSpeed);
    vehicle.fuelLevel.removeListener(_publishRemaining);
    hardEvents.accelerationPhase.removeListener(_onPhase);
    price.removeListener(_onPrice);
    _sub?.cancel();
  }
}

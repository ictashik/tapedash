import 'package:flutter/foundation.dart';

import '../../../core/clock.dart';
import '../../../core/observable.dart';
import '../../../money/calibration.dart';
import '../../../money/fill_up.dart';
import '../../../money/fuel_ledger.dart';
import '../../../money/money_settings.dart';
import '../../../money/spend_bucket.dart';
import '../../../money/trip_computer.dart';
import '../../../trips/trip.dart';
import '../../../trips/trip_recorder.dart';
import '../../../vehicle/reading.dart';
import '../../design/components/money.dart';
import '../../design/motion/motion_clock.dart';
import '../../design/motion/smoothing_pipeline.dart';
import '../../design/tokens/motion_tokens.dart';

/// What a money readout can show (CLAUDE.md 8.5, DESIGN.md 7.4).
enum MoneyView {
  /// The car gives no fuel figure at all: money is unavailable, and the screen
  /// says so in plain words.
  unavailable,

  /// There is fuel and no price yet: litres, with a prompt to set the price.
  litres,

  /// There is fuel and a price: rupees.
  rupees,
}

/// The trip computer, as the smoothed signals the money screens read (CLAUDE.md
/// 6: `ui/` reads `ValueListenable`s and never the services). Like
/// `DriveSignals` for the vehicle, it is bound once and shared by every screen
/// that shows money, so the ₹ you were watching keeps its momentum when you swipe
/// from Drive to Money.
///
/// Values that are not there (no price, no distance yet) simply hold their last
/// value; [view] and the other flags say when to show them.
class MoneySignals {
  MoneySignals({
    required this.trip,
    required this.settings,
    required this.ledger,
    required this.motion,
    required this.clock,
    this.recorder,
  }) {
    _bind(cost, trip.cost);
    _bind(costPerKm, trip.costPerKm);
    _bind(kmPerLitre, trip.kmPerLitre);
    _bind(instantKmPerLitre, trip.instantKmPerLitre);
    _bind(idleCost, trip.idleCost);
    _bind(litres, trip.litres);
    _bind(distanceKm, trip.distanceKm);
    trip.kmPerLitre.addListener(_onAverage);
    trip.distanceKm.addListener(_onAverage);
    trip.litres.addListener(_onSpend);
    refreshFills();
    trip.instantKmPerLitre.addListener(_onAvailability);
    trip.costPerKm.addListener(_onAvailability);
    _bind(remainingKm, trip.remainingKm);
    trip.remainingLitres.addListener(_onRemaining);
    trip.blockCount.addListener(_onBlocks);
    trip.onBlocksReset(_onBlocks);
    settings.price.addListener(_onPrice);
    trip.fuelKnown.addListener(_onView);
    ledger.confidence.addListener(_onConfidence);
    recorder?.current.addListener(_onTrip);
    // A signal that has no reading yet shows 0, so give each its first.
    _onRemaining();
    _onBlocks();
    _onPrice();
    _onConfidence();
    _onTrip();
  }

  final TripComputer trip;
  final MoneySettings settings;
  final FuelLedger ledger;
  final MotionClock motion;
  final Clock clock;
  final TripRecorder? recorder;

  SmoothedSignal _signal(SpringSpec spring) => SmoothedSignal(
    motion: motion,
    clock: clock,
    spring: spring,
    // Money moves with the fuel, once a second or so, and a trip that has
    // stopped answering is not "stale" in the sense of a needle: the values hold.
    staleAfter: TapeDurations.moneyStale,
    precision: 0.0005,
  );

  /// ₹ this trip (or litres, when there is no price: see [view]).
  late final SmoothedSignal cost = _signal(TapeSprings.gauge);
  late final SmoothedSignal costPerKm = _signal(TapeSprings.gauge);
  late final SmoothedSignal kmPerLitre = _signal(TapeSprings.gauge);
  late final SmoothedSignal instantKmPerLitre = _signal(TapeSprings.gauge);
  late final SmoothedSignal idleCost = _signal(TapeSprings.gauge);
  late final SmoothedSignal litres = _signal(TapeSprings.gauge);
  late final SmoothedSignal distanceKm = _signal(TapeSprings.gauge);
  late final SmoothedSignal remainingKm = _signal(TapeSprings.gauge);

  /// What each bucket has cost this trip, and its share of the fuel, in percent
  /// (CLAUDE.md 8.7). They are read by the parked breakdown (DESIGN.md 7.4).
  late final Map<SpendBucket, SmoothedSignal> bucketCost = {
    for (final b in SpendBucket.values) b: _signal(TapeSprings.gauge),
  };
  late final Map<SpendBucket, SmoothedSignal> bucketPercent = {
    for (final b in SpendBucket.values) b: _signal(TapeSprings.gauge),
  };

  /// The fuel left, in rupees (litres left times the price).
  late final SmoothedSignal remainingCost = _signal(TapeSprings.gauge);

  final ValueNotifier<MoneyView> _view = ValueNotifier(MoneyView.unavailable);
  final ValueNotifier<MoneyConfidence> _confidence = ValueNotifier(
    MoneyConfidence.uncalibrated,
  );
  final ValueNotifier<bool> _hasRemaining = ValueNotifier(false);
  final ValueNotifier<List<MoneyBlock>> _blocks = ValueNotifier(const []);
  final ValueNotifier<Duration> _tripTime = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _lowConfidence = ValueNotifier(false);
  final ValueNotifier<double?> _ecoAverage = ValueNotifier(null);
  late final _PriceListenable _price = _PriceListenable(settings.price);
  final ValueNotifier<FillUp?> _lastFill = ValueNotifier(null);
  final ValueNotifier<bool> _instantAvailable = ValueNotifier(false);
  final ValueNotifier<bool> _costPerKmAvailable = ValueNotifier(false);
  final ValueNotifier<bool> _kmPerLitreAvailable = ValueNotifier(false);

  /// Rupees, litres or nothing (see [MoneyView]).
  ValueListenable<MoneyView> get view => _view;

  /// The three pips beside a money figure (DESIGN.md 6.8).
  ValueListenable<MoneyConfidence> get confidence => _confidence;

  /// Whether the car reports its fuel level, so the fuel left can be shown.
  ValueListenable<bool> get hasRemaining => _hasRemaining;

  /// The Money Tape's blocks, in order (DESIGN.md 6.8).
  ValueListenable<List<MoneyBlock>> get blocks => _blocks;

  /// How long the engine has run this trip.
  ValueListenable<Duration> get tripTime => _tripTime;

  /// The estimate is one to be wary of: a diesel's, from air flow.
  ValueListenable<bool> get lowConfidence => _lowConfidence;

  /// The latest fill-up, for "last filled" beside the price (DESIGN.md 7.4).
  ValueListenable<FillUp?> get lastFill => _lastFill;

  /// The price of a litre, or null while none is set.
  ValueListenable<double?> get pricePerLitre => _price;

  /// Reads the fill-up log again, after a fill-up is saved.
  Future<void> refreshFills() async {
    final all = await ledger.fills.all();
    _lastFill.value = all.isEmpty ? null : all.last;
  }

  /// Whether there is an instant km/L to show (not below 5 km/h, CLAUDE.md 8.6),
  /// a ₹/km (100 m in, with a price) and a trip km/L: the numerals are drawn as a
  /// dash when not.
  ValueListenable<bool> get instantAvailable => _instantAvailable;
  ValueListenable<bool> get costPerKmAvailable => _costPerKmAvailable;
  ValueListenable<bool> get kmPerLitreAvailable => _kmPerLitreAvailable;

  /// The car's own average km/L, for the eco bar's notch; null until there is
  /// enough of the trip to have one.
  ValueListenable<double?> get ecoAverage => _ecoAverage;

  // ------------------------------------------------------------------ feeds

  final List<void Function()> _unbind = [];

  void _bind(SmoothedSignal signal, Observable<double?> source) => _feed(
    signal,
    () => source.value,
    source.addListener,
    source.removeListener,
  );

  void _feed(
    SmoothedSignal signal,
    double? Function() read,
    void Function(void Function()) add,
    void Function(void Function()) remove,
  ) {
    void listener() {
      final v = read();
      if (v == null) return;
      final now = clock.monotonic();
      signal.ingest(Reading(value: v, at: now, receivedAt: now));
    }

    add(listener);
    _unbind.add(() => remove(listener));
    listener();
  }

  void _onRemaining() {
    final litres = trip.remainingLitres.value;
    _hasRemaining.value = litres != null;
    final price = settings.price.value;
    if (litres != null && price != null) {
      final now = clock.monotonic();
      remainingCost.ingest(
        Reading(value: litres * price, at: now, receivedAt: now),
      );
    }
  }

  void _onSpend() {
    final litres = trip.bucketLitres;
    final total = litres.values.fold<double>(0, (a, b) => a + b);
    final price = settings.price.value;
    final now = clock.monotonic();
    for (final b in SpendBucket.values) {
      final l = litres[b] ?? 0;
      if (price != null) {
        bucketCost[b]!.ingest(
          Reading(value: l * price, at: now, receivedAt: now),
        );
      }
      bucketPercent[b]!.ingest(
        Reading(
          value: total <= 0 ? 0 : 100 * l / total,
          at: now,
          receivedAt: now,
        ),
      );
    }
  }

  void _onAvailability() {
    _instantAvailable.value = trip.instantKmPerLitre.value != null;
    _costPerKmAvailable.value = trip.costPerKm.value != null;
    _kmPerLitreAvailable.value = trip.kmPerLitre.value != null;
  }

  void _onAverage() {
    _onAvailability();
    _ecoAverage.value = trip.distanceKm.value >= 1
        ? trip.kmPerLitre.value
        : null;
  }

  void _onBlocks() {
    _blocks.value = [
      for (final b in trip.blocks) MoneyBlock(_bucket(b.bucket)),
    ];
  }

  static MoneyBucket _bucket(SpendBucket b) => switch (b) {
    SpendBucket.normal => MoneyBucket.normal,
    SpendBucket.idling => MoneyBucket.idling,
    SpendBucket.hardAcceleration => MoneyBucket.hardAcceleration,
    SpendBucket.highSpeed => MoneyBucket.highSpeed,
  };

  void _onPrice() {
    _onView();
    _onRemaining();
    _onSpend();
  }

  void _onView() {
    _view.value = !trip.fuelKnown.value
        ? MoneyView.unavailable
        : settings.price.value == null
        ? MoneyView.litres
        : MoneyView.rupees;
  }

  void _onConfidence() {
    _confidence.value = switch (ledger.confidence.value) {
      CalibrationConfidence.uncalibrated => MoneyConfidence.uncalibrated,
      CalibrationConfidence.calibrating => MoneyConfidence.calibrating,
      CalibrationConfidence.calibrated => MoneyConfidence.calibrated,
    };
  }

  void _onTrip() {
    final Trip? t = recorder?.current.value;
    if (t == null) return;
    _tripTime.value = Duration(milliseconds: (t.engineSeconds * 1000).round());
    _lowConfidence.value = t.lowConfidence;
  }

  void dispose() {
    for (final u in _unbind) {
      u();
    }
    trip.litres.removeListener(_onSpend);
    trip.instantKmPerLitre.removeListener(_onAvailability);
    trip.costPerKm.removeListener(_onAvailability);
    trip.kmPerLitre.removeListener(_onAverage);
    trip.distanceKm.removeListener(_onAverage);
    trip.remainingLitres.removeListener(_onRemaining);
    trip.blockCount.removeListener(_onBlocks);
    settings.price.removeListener(_onPrice);
    trip.fuelKnown.removeListener(_onView);
    ledger.confidence.removeListener(_onConfidence);
    recorder?.current.removeListener(_onTrip);
    for (final s in [
      ...bucketCost.values,
      ...bucketPercent.values,
      cost,
      costPerKm,
      kmPerLitre,
      instantKmPerLitre,
      idleCost,
      litres,
      distanceKm,
      remainingKm,
      remainingCost,
    ]) {
      s.dispose();
    }
    _blocks.dispose();
    _view.dispose();
    _confidence.dispose();
    _hasRemaining.dispose();
    _tripTime.dispose();
    _lowConfidence.dispose();
    _ecoAverage.dispose();
    _lastFill.dispose();
    _price.dispose();
    _instantAvailable.dispose();
    _costPerKmAvailable.dispose();
    _kmPerLitreAvailable.dispose();
  }
}

/// The settings' price as a [ValueListenable].
class _PriceListenable extends ChangeNotifier
    implements ValueListenable<double?> {
  _PriceListenable(this._source) {
    _source.addListener(notifyListeners);
  }

  final Observable<double?> _source;

  @override
  double? get value => _source.value;

  @override
  void dispose() {
    _source.removeListener(notifyListeners);
    super.dispose();
  }
}

import '../core/key_value_store.dart';
import '../core/observable.dart';
import 'calibration.dart';
import 'fill_up.dart';

/// Keeps count of the fuel the app has estimated since the last full tank, and
/// turns each new full-tank fill-up into a calibration factor (CLAUDE.md 8.5).
///
/// The estimate counted is the raw one, before any correction, since the
/// correction is what is being worked out. Only real driving is counted; demo
/// trips never reach here.
class FuelLedger {
  FuelLedger({
    required this.fills,
    required this.store,
    Calibration? calibration,
  }) : calibration = calibration ?? Calibration();

  static const _estimateKey = 'fuel_ledger_estimated_since_full';

  /// A factor further out than this is put down to trips the app missed (it was
  /// off, or its adapter was out), and not used.
  static const double plausibleMin = 0.4;
  static const double plausibleMax = 2.5;

  /// Less than this much fuel, filled or estimated, says too little.
  static const double minLitres = 1;

  final FillUpRepository fills;
  final KeyValueStore store;
  final Calibration calibration;

  double _estimatedSinceFull = 0;
  double _unsaved = 0;

  // The tank count (see [litresLeft]): whether a full tank has ever been logged,
  // and the litres put in by part-fills since the last one.
  bool _hasFullTank = false;
  double _topUpSinceFull = 0;
  DateTime? _lastFullAt;
  late final ObservableValue<CalibrationConfidence> _confidence =
      ObservableValue(calibration.confidence);

  /// How far the estimate has been checked, kept current as fill-ups come in.
  Observable<CalibrationConfidence> get confidence => _confidence;

  /// Litres the app has estimated, raw, since the last full-tank fill-up.
  double get estimatedSinceFull => _estimatedSinceFull;

  /// Reads the log and the counter back after a start.
  Future<void> load() async {
    _estimatedSinceFull = await store.getDouble(_estimateKey) ?? 0;
    final rebuilt = Calibration();
    final all = await fills.all();
    _countTank(all);
    for (final f in all) {
      if (f.factor != null) rebuilt.add(f.factor!);
    }
    for (final f in rebuilt.factors) {
      calibration.add(f);
    }
    _confidence.value = calibration.confidence;
  }

  /// Forgets everything it holds: the fill-ups, the calibration and the count
  /// (Garage → Data → delete all).
  Future<void> clear() async {
    for (final f in await fills.all()) {
      if (f.id != null) await fills.delete(f.id!);
    }
    calibration.clear();
    _confidence.value = calibration.confidence;
    _estimatedSinceFull = 0;
    _unsaved = 0;
    _hasFullTank = false;
    _lastFullAt = null;
    _topUpSinceFull = 0;
    await store.setDouble(_estimateKey, 0);
  }

  void _countTank(List<FillUp> all) {
    final lastFull = all.where((f) => f.fullTank).toList();
    _hasFullTank = lastFull.isNotEmpty;
    _lastFullAt = _hasFullTank ? lastFull.last.at : null;
    _topUpSinceFull = _hasFullTank
        ? all
              .where((f) => !f.fullTank && f.at.isAfter(lastFull.last.at))
              .fold<double>(0, (a, f) => a + f.litres)
        : 0;
  }

  /// The litres in a tank of [tankLitres], counted and not sensed: the tank as it
  /// was at the last full fill-up, less what the app has estimated since (with the
  /// calibration), plus any part-fills since. Null until a full tank has been
  /// logged, since there is nothing to count from. An estimate, and it drifts as
  /// trips are missed; every full tank sets it right again.
  double? litresLeft(double tankLitres) {
    if (!_hasFullTank) return null;
    final used = _estimatedSinceFull * calibration.factor;
    return (tankLitres - used + _topUpSinceFull).clamp(0.0, tankLitres);
  }

  /// When the tank was last filled to the top, or null if never.
  DateTime? get lastFullAt => _lastFullAt;

  /// The litres the app has used since the last full tank, calibrated.
  double get usedSinceFull => _estimatedSinceFull * calibration.factor;

  /// Counts [litres] of raw estimate.
  void addEstimate(double litres) {
    _estimatedSinceFull += litres;
    _unsaved += litres;
  }

  /// Saves the counter, at the end of a trip and when parking.
  Future<void> flush() async {
    if (_unsaved == 0) return;
    _unsaved = 0;
    await store.setDouble(_estimateKey, _estimatedSinceFull);
  }

  /// Logs a fill-up. A full tank, with an earlier full tank behind it, works
  /// out a factor: the litres put in since that one (this fill-up and any
  /// part-fills between) over the litres the app estimated in that time.
  Future<FillUp> recordFillUp({
    required DateTime at,
    required double litres,
    required double amount,
    required bool fullTank,
  }) async {
    double? factor;
    if (fullTank) {
      final all = await fills.all();
      final lastFull = all.where((f) => f.fullTank).toList();
      if (lastFull.isNotEmpty) {
        final since = all.where((f) => f.at.isAfter(lastFull.last.at));
        final filled = litres + since.fold<double>(0, (a, f) => a + f.litres);
        if (filled >= minLitres && _estimatedSinceFull >= minLitres) {
          final candidate = filled / _estimatedSinceFull;
          if (candidate >= plausibleMin && candidate <= plausibleMax) {
            factor = candidate;
            calibration.add(candidate);
            _confidence.value = calibration.confidence;
          }
        }
      }
      // A full tank starts the count again, whether or not it made a factor.
      _estimatedSinceFull = 0;
      _unsaved = 0;
      _hasFullTank = true;
      _lastFullAt = at;
      _topUpSinceFull = 0;
      await store.setDouble(_estimateKey, 0);
    } else if (_hasFullTank) {
      _topUpSinceFull += litres;
    }
    return fills.add(
      FillUp(
        at: at,
        litres: litres,
        amount: amount,
        fullTank: fullTank,
        factor: factor,
      ),
    );
  }
}

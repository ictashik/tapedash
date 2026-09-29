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
    for (final f in await fills.all()) {
      if (f.factor != null) rebuilt.add(f.factor!);
    }
    for (final f in rebuilt.factors) {
      calibration.add(f);
    }
    _confidence.value = calibration.confidence;
  }

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
      await store.setDouble(_estimateKey, 0);
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

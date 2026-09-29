import 'dart:async';

import '../core/observable.dart';
import '../core/scheduler.dart';
import 'location_source.dart';

/// Whether the phone has a usable GPS fix right now, for the status strip's glyph
/// (DESIGN.md 6.9): a fix in the last few seconds, and an accuracy good enough to
/// place the car on a road. Fixes stop and the answer falls to no after
/// [staleAfter], without waiting for anything else to happen.
class LocationStatus {
  LocationStatus({
    required this.source,
    required this.scheduler,
    this.staleAfter = const Duration(seconds: 4),
    this.usableAccuracyM = 50,
  }) {
    _sub = source.fixes.listen(_onFix);
  }

  final LocationSource source;
  final Scheduler scheduler;
  final Duration staleAfter;
  final double usableAccuracyM;

  final ObservableValue<bool> _hasFix = ObservableValue(false);
  final ObservableValue<LocationFix?> _last = ObservableValue(null);
  StreamSubscription<LocationFix>? _sub;
  ScheduledTask? _expiry;

  Observable<bool> get hasFix => _hasFix;

  /// The latest fix, of any accuracy.
  Observable<LocationFix?> get last => _last;

  void _onFix(LocationFix fix) {
    _last.value = fix;
    _expiry?.cancel();
    if (fix.accuracyM <= usableAccuracyM) {
      _hasFix.value = true;
      _expiry = scheduler.runAfter(staleAfter, () => _hasFix.value = false);
    } else {
      _hasFix.value = false;
    }
  }

  Future<void> dispose() async {
    _expiry?.cancel();
    await _sub?.cancel();
  }
}

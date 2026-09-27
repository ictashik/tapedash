import 'package:flutter/foundation.dart';

/// A number that changes and can say when (DESIGN.md 5.2): what a readout reads.
///
/// A `SmoothedSignal` is one. Painters listen to it and repaint, so the widget that
/// holds them never rebuilds for data (DESIGN.md 9.3).
abstract interface class NumeralSource implements Listenable {
  /// The value to show, already smoothed.
  double get value;

  /// 0 for a fresh value, up to 1 for a fully stale one.
  double get staleness;

  /// Whether there is anything to show yet.
  bool get hasValue;
}

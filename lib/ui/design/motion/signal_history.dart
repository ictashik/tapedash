import 'dart:typed_data';

import 'smoothing_pipeline.dart';

/// The last stretch of a signal, kept whether or not anything is drawing it.
///
/// A telemetry tile used to keep its own sparkline, so the line began when the
/// tile was mounted: open the Telemetry cluster after ten minutes of driving and
/// it began empty. The history belongs to the drive instead (`DriveSignals`), is
/// sampled on the scheduler at a fixed rate, and a tile only reads it.
///
/// A ring of floats: nothing is allocated once it exists.
class SignalHistory {
  SignalHistory(this.source, {required this.capacity})
    : _samples = Float32List(capacity);

  /// The signal it follows; the smoothed value is what is kept, the same one a
  /// numeral shows.
  final SmoothedSignal source;

  /// How many samples it keeps.
  final int capacity;

  final Float32List _samples;
  int _head = 0;
  int _filled = 0;

  /// How many samples there are, up to [capacity].
  int get length => _filled;

  /// Takes a sample now, if the signal has a value yet.
  void sample() {
    if (!source.hasValue) return;
    _samples[_head] = source.value;
    _head = (_head + 1) % capacity;
    if (_filled < capacity) _filled++;
  }

  /// The [i]th sample counting from the oldest, 0 to `length - 1`.
  double at(int i) => _samples[(_head - _filled + i + capacity) % capacity];

  /// The samples, oldest first (for tests; the painter uses [at]).
  List<double> get oldestFirst => [for (var i = 0; i < _filled; i++) at(i)];
}

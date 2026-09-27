import 'dart:math' as math;
import 'package:flutter/scheduler.dart';

/// Reads how long frames take, from the engine's own timings (DESIGN.md 9.2): the
/// input of the tier detector and the governor.
///
/// A frame costs its build time or its raster time, whichever is longer, since the
/// two run one after the other on separate threads and the slower sets the pace.
class FrameProbe {
  FrameProbe(this.onFrames, {SchedulerBinding? binding})
    : _binding = binding ?? SchedulerBinding.instance;

  /// Called with the cost of each frame in a batch, in milliseconds.
  final void Function(List<double> milliseconds) onFrames;

  final SchedulerBinding _binding;
  bool _running = false;

  /// The cost of one frame, in milliseconds.
  static double costOf(FrameTiming timing) =>
      math.max(
        timing.buildDuration.inMicroseconds,
        timing.rasterDuration.inMicroseconds,
      ) /
      1000;

  void start() {
    if (_running) return;
    _running = true;
    _binding.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _binding.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) =>
      onFrames([for (final t in timings) costOf(t)]);
}

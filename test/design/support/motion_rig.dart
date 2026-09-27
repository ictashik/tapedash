import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/vehicle/reading.dart';

/// The two clocks of a drive, moved together: the domain clock that readings are
/// stamped on, and the motion clock that springs run on. A frame is 1/60 s.
class MotionRig {
  MotionRig() {
    // Start well after zero, so that a reading can be older than the clock.
    clock.advance(const Duration(seconds: 100));
  }

  final FakeClock clock = FakeClock();
  final ManualMotionClock motion = ManualMotionClock();

  /// Runs [duration], a frame at a time, on both clocks.
  void run(Duration duration) {
    var left = duration.inMicroseconds;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
      clock.advance(Duration(microseconds: step));
      motion.tick(step / 1e6);
      left -= step;
    }
  }

  /// A reading of [value] that arrives now, having been measured [latency] ago.
  Reading reading(double value, {Duration latency = Duration.zero}) {
    final now = clock.monotonic();
    return Reading(value: value, at: now - latency, receivedAt: now);
  }

  void dispose() => motion.dispose();
}

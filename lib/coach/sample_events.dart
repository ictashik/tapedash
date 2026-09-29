import '../trips/trip.dart';
import 'coach_thresholds.dart';

/// What kind of moment a trip's timeline is marked with (DESIGN.md 6.12).
enum SampleEventType { hardAcceleration, hardBraking, longIdle }

/// A marked moment, at sample [index] of a trip.
class SampleEvent {
  const SampleEvent(this.type, this.index);

  final SampleEventType type;
  final int index;
}

/// Finds the moments to mark on a saved trip's route and timeline, from its
/// one-second samples (CLAUDE.md 8.8's rules, at the resolution the samples
/// have). The live detectors decide what is counted and costed while driving;
/// this only says where to put a marker afterwards, so a marker can be a second
/// or so off where the live rule confirmed it.
abstract final class SampleEvents {
  static List<SampleEvent> find(
    List<TripSample> samples, {
    CoachThresholds thresholds = CoachThresholds.normal,
  }) {
    final out = <SampleEvent>[];
    var accelOpen = false;
    var brakeOpen = false;
    int? idleFrom;
    var idleMarked = false;
    for (var i = 1; i < samples.length; i++) {
      final a = samples[i - 1];
      final b = samples[i];
      final dt = b.seconds - a.seconds;
      if (dt <= 0 || dt > 2.5) {
        accelOpen = false;
        brakeOpen = false;
        idleFrom = null;
        continue;
      }
      final accel = (b.speedKmh - a.speedKmh) / 3.6 / dt;
      final hardAccel =
          accel > thresholds.hardAccelerationMs2 ||
          (b.throttle > thresholds.hardAccelerationThrottlePercent &&
              b.speedKmh > thresholds.hardAccelerationMinSpeedKmh);
      if (hardAccel && !accelOpen) {
        out.add(SampleEvent(SampleEventType.hardAcceleration, i));
      }
      accelOpen = hardAccel;
      final hardBrake = accel < -thresholds.hardBrakingMs2;
      if (hardBrake && !brakeOpen) {
        out.add(SampleEvent(SampleEventType.hardBraking, i));
      }
      brakeOpen = hardBrake;

      final idle = b.speedKmh < 2 && b.rpm > 400;
      if (idle) {
        idleFrom ??= i;
        if (!idleMarked &&
            b.seconds - samples[idleFrom].seconds >=
                thresholds.longIdleSeconds) {
          out.add(SampleEvent(SampleEventType.longIdle, idleFrom));
          idleMarked = true;
        }
      } else {
        idleFrom = null;
        idleMarked = false;
      }
    }
    out.sort((x, y) => x.index.compareTo(y.index));
    return out;
  }
}

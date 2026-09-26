/// The source of time for everything in TapeDash that is not a widget.
///
/// Domain code never calls `DateTime.now()` or creates a `Stopwatch`; it takes
/// a [Clock]. That keeps simulated drives deterministic and fast: tests hand in
/// a `FakeClock`, and a 30-minute drive runs in seconds. See
/// `test/unit/architecture_test.dart`.
abstract interface class Clock {
  /// Wall-clock time, for timestamps that are shown or stored.
  ///
  /// It can jump when the phone's time or time zone changes, so never measure
  /// an interval with it.
  DateTime now();

  /// Time on a monotonic timer with an arbitrary starting point, for measuring
  /// intervals. It never jumps and never runs backwards.
  Duration monotonic();
}

/// The real clock.
class SystemClock implements Clock {
  const SystemClock();

  // One origin for every instance, so values from different instances compare.
  static final Stopwatch _origin = Stopwatch()..start();

  @override
  DateTime now() => DateTime.now();

  @override
  Duration monotonic() => _origin.elapsed;
}

import 'package:flutter/foundation.dart';

import '../../../core/clock.dart';
import '../../../core/scheduler.dart';
import '../tokens/motion_tokens.dart';

/// A [ValueListenable] of the wall-clock time (DESIGN.md 6.9's status strip
/// clock), ticking on the injected [Clock] and [Scheduler] rather than
/// `DateTime.now()`/`Timer` directly (CLAUDE.md 5), so a `FakeClock` and a
/// fake `Scheduler` can drive it deterministically in a test.
class WallClockTicker extends ChangeNotifier
    implements ValueListenable<DateTime> {
  WallClockTicker({
    required Clock clock,
    required Scheduler scheduler,
    Duration period = TapeMotion.wallClockTick,
  }) : _clock = clock,
       _value = clock.now() {
    _task = scheduler.runEvery(period, _tick);
  }

  final Clock _clock;
  DateTime _value;
  late final ScheduledTask _task;

  @override
  DateTime get value => _value;

  void _tick() {
    _value = _clock.now();
    notifyListeners();
  }

  @override
  void dispose() {
    _task.cancel();
    super.dispose();
  }
}

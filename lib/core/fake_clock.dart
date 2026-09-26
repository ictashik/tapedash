import 'clock.dart';
import 'scheduler.dart';

/// A [Clock] and [Scheduler] on simulated time, for tests, the simulator tools
/// and anything else that has to be deterministic.
///
/// Time only moves when [advance] is called. It lives in `lib/` rather than
/// `test/` because `tool/` programs such as the recorder run simulated drives
/// too.
class FakeClock implements Clock, Scheduler {
  /// Starts at [start], which defaults to a fixed instant so runs are
  /// reproducible whatever the machine's date or time zone.
  FakeClock({DateTime? start}) : _wallStart = start ?? DateTime.utc(2026);

  final DateTime _wallStart;
  Duration _monotonic = Duration.zero;
  Duration _wallOffset = Duration.zero;
  bool _advancing = false;

  // Sorted by due time. Tasks due at the same time keep the order in which they
  // were scheduled, and a periodic task goes to the back when it re-arms.
  final List<_FakeTask> _tasks = [];

  @override
  DateTime now() => _wallStart.add(_monotonic + _wallOffset);

  @override
  Duration monotonic() => _monotonic;

  /// How many tasks are scheduled and have neither run nor been cancelled.
  /// Tests use this to check that nothing is left running.
  int get pendingTasks => _tasks.length;

  /// Moves time on by [duration], running every task that falls due on the way,
  /// in order.
  ///
  /// While a task runs, [now] and [monotonic] read exactly its due time, so it
  /// sees the same time it would have on a real device. Tasks scheduled by a
  /// task run in the same call if they fall inside the window. If a task throws,
  /// the error propagates, time stays at that task's due time and the remaining
  /// tasks stay scheduled.
  void advance(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    if (_advancing) {
      throw StateError('FakeClock.advance called from inside a scheduled task');
    }
    final target = _monotonic + duration;
    _advancing = true;
    try {
      while (_tasks.isNotEmpty && _tasks.first.due <= target) {
        final task = _tasks.removeAt(0);
        _monotonic = task.due;
        final period = task.period;
        if (period == null) {
          task._active = false;
        } else {
          task.due += period;
          _insert(task);
        }
        task.callback();
      }
      _monotonic = target;
    } finally {
      _advancing = false;
    }
  }

  /// Changes the wall clock only, as when the user or the network sets the
  /// phone's time. [monotonic] and the scheduled tasks are unaffected.
  void adjustWallClock(Duration delta) => _wallOffset += delta;

  @override
  ScheduledTask runAfter(Duration delay, void Function() task) =>
      _schedule(delay, null, task);

  @override
  ScheduledTask runEvery(Duration period, void Function() task) {
    if (period <= Duration.zero) {
      throw ArgumentError.value(period, 'period', 'must be positive');
    }
    return _schedule(period, period, task);
  }

  ScheduledTask _schedule(
    Duration delay,
    Duration? period,
    void Function() callback,
  ) {
    final due = _monotonic + (delay.isNegative ? Duration.zero : delay);
    final task = _FakeTask(this, due, period, callback);
    _insert(task);
    return task;
  }

  void _insert(_FakeTask task) {
    var index = _tasks.length;
    while (index > 0 && _tasks[index - 1].due > task.due) {
      index--;
    }
    _tasks.insert(index, task);
  }
}

class _FakeTask implements ScheduledTask {
  _FakeTask(this._clock, this.due, this.period, this.callback);

  final FakeClock _clock;
  final Duration? period;
  final void Function() callback;
  Duration due;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    if (!_active) return;
    _active = false;
    _clock._tasks.remove(this);
  }
}

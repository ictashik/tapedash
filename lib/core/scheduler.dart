import 'dart:async';

/// Runs work later, on a timeline the caller controls.
///
/// Domain code never creates a `Timer`; it takes a [Scheduler]. [SystemScheduler]
/// uses real timers, and `FakeClock` runs tasks as simulated time is advanced.
abstract interface class Scheduler {
  /// Runs [task] once, [delay] from now.
  ///
  /// A zero or negative delay means as soon as possible, but never
  /// synchronously inside this call.
  ScheduledTask runAfter(Duration delay, void Function() task);

  /// Runs [task] every [period], first after one period, until cancelled.
  ///
  /// [period] must be positive.
  ScheduledTask runEvery(Duration period, void Function() task);
}

/// A handle to work given to a [Scheduler].
abstract interface class ScheduledTask {
  /// True until a one-shot task has started running or the task is cancelled.
  bool get isActive;

  /// Stops the task from running again. Safe to call more than once, and from
  /// inside the task itself.
  void cancel();
}

/// The real scheduler, backed by `dart:async` timers.
class SystemScheduler implements Scheduler {
  const SystemScheduler();

  @override
  ScheduledTask runAfter(Duration delay, void Function() task) =>
      _TimerTask(Timer(delay, task));

  @override
  ScheduledTask runEvery(Duration period, void Function() task) {
    if (period <= Duration.zero) {
      throw ArgumentError.value(period, 'period', 'must be positive');
    }
    return _TimerTask(Timer.periodic(period, (_) => task()));
  }
}

class _TimerTask implements ScheduledTask {
  _TimerTask(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}

import 'package:flutter/scheduler.dart';

import '../tokens/motion_tokens.dart';

/// Something a [MotionClock] drives a frame at a time: a spring, a phosphor bank,
/// a smoothed signal.
abstract interface class MotionDriven {
  /// Moves on by [dt] seconds, to [time] on the clock. Returns true while it
  /// still needs frames, and false when it has come to rest, at which point the
  /// clock lets go of it. Attach it again to wake it.
  bool advance(double dt, Duration time);
}

/// The one clock all motion runs on (DESIGN.md 5.9).
///
/// It ticks once a frame, on the vsync, and hands every attached [MotionDriven]
/// the frame's time. It ticks only while something needs it, so a screen that is
/// at rest costs no frames.
///
/// Time on this clock is virtual: it advances by each frame's delta, clamped to
/// 50 ms, so that after a stall the motion carries on from where it was and does
/// not jump. It follows `timeDilation`, which is how the Design Lab slows motion
/// down to tune it.
abstract class MotionClock {
  /// The clock's time. It starts at zero and only moves forward.
  Duration get now;

  /// How many things are attached.
  int get attachedCount;

  /// Whether the clock is ticking.
  bool get isTicking;

  /// Starts driving [driven] on every frame until it says it has come to rest or
  /// is [detach]ed. Attaching one that is already attached does nothing.
  void attach(MotionDriven driven);

  void detach(MotionDriven driven);

  /// Holds the clock to at most [fps] frames a second, or lifts the limit with
  /// null. The fidelity governor uses it for the 30 fps fallback (DESIGN.md 9.1).
  /// Motion carries on at its true speed, in coarser steps.
  set maxFps(int? fps);
  int? get maxFps;

  /// Stops ticking and lets go of everything.
  void dispose();
}

/// The shared bookkeeping of a clock: the attached list and the stepping.
abstract class _SteppedClock extends MotionClock {
  final List<MotionDriven> _driven = [];
  Duration _now = Duration.zero;
  bool _stepping = false;
  int? _maxFps;

  @override
  int? get maxFps => _maxFps;

  @override
  set maxFps(int? fps) {
    assert(fps == null || fps > 0);
    _maxFps = fps;
  }

  @override
  Duration get now => _now;

  @override
  int get attachedCount => _driven.length;

  @override
  void attach(MotionDriven driven) {
    if (_driven.contains(driven)) return;
    _driven.add(driven);
    onAttached();
  }

  @override
  void detach(MotionDriven driven) {
    _driven.remove(driven);
    if (_driven.isEmpty) onEmpty();
  }

  /// Called when the first thing is attached to an idle clock.
  void onAttached();

  /// Called when nothing is attached any more.
  void onEmpty();

  /// Runs one frame of [seconds], clamped to 50 ms.
  void step(double seconds) {
    if (_stepping) return;
    _stepping = true;
    try {
      final dt = seconds.isNaN
          ? 0.0
          : seconds.clamp(0.0, TapeMotion.maxFrameSeconds).toDouble();
      _now += Duration(microseconds: (dt * 1e6).round());
      // Backwards, so that a driven that comes to rest can be removed as it is
      // visited, and one attached during the frame waits for the next.
      final count = _driven.length;
      for (var i = count - 1; i >= 0; i--) {
        if (i >= _driven.length) continue;
        final driven = _driven[i];
        if (!driven.advance(dt, _now)) {
          _driven.remove(driven);
        }
      }
      if (_driven.isEmpty) onEmpty();
    } finally {
      _stepping = false;
    }
  }
}

/// The clock of the running app: one vsync [Ticker].
class VsyncMotionClock extends _SteppedClock {
  VsyncMotionClock() {
    _ticker = Ticker(_onTick, debugLabel: 'MotionClock');
  }

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  bool get isTicking => _ticker.isActive;

  @override
  void onAttached() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void onEmpty() {
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final seconds = (elapsed - _last).inMicroseconds / 1e6;
    final cap = _maxFps;
    if (cap != null) {
      // Wait until enough time has passed for a frame at the cap, then step by
      // all of it. A tick a little early is let through, since vsync ticks are
      // never exactly a frame apart.
      if (seconds < (1 / cap) * 0.9) return;
    }
    _last = elapsed;
    step(seconds);
  }

  @override
  void dispose() {
    _driven.clear();
    _ticker.dispose();
  }
}

/// A clock that only moves when it is told to, for tests and for the Design Lab's
/// captures, which need frames at exact times.
class ManualMotionClock extends _SteppedClock {
  /// One frame at 60 Hz, in seconds.
  static const double frame = 1 / 60;

  @override
  bool get isTicking => _driven.isNotEmpty;

  @override
  void onAttached() {}

  @override
  void onEmpty() {}

  /// Runs one frame of [seconds] (at most 50 ms of it counts).
  void tick([double seconds = frame]) => step(seconds);

  /// Runs frames of [step] seconds until [duration] has passed.
  void advance(Duration duration, {double step = frame}) {
    var remaining = duration.inMicroseconds / 1e6;
    while (remaining > 1e-9) {
      final dt = remaining < step ? remaining : step;
      this.step(dt);
      remaining -= dt;
    }
  }

  @override
  void dispose() => _driven.clear();
}

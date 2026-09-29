import 'package:flutter/foundation.dart';

import '../tokens/motion_tokens.dart';
import 'motion_clock.dart';
import 'smoothing_pipeline.dart';
import 'timeline.dart';

/// How much of the ignition sequence plays (DESIGN.md 7.13, Garage's
/// Off / Subtle / Full).
enum IgnitionMode { off, subtle, full }

/// The ignition sequence (DESIGN.md 7.13): what plays on the first valid rpm
/// above 400 after connecting.
///
/// 1. 0-450 ms: the tach segments light in a wave, 0 to maximum (expo-out).
/// 2. 150-900 ms: the needle sweeps to redline and back to the live rpm.
/// 3. 300-900 ms: the numerals roll up from 0 to the live value.
/// 4. 600-1,200 ms: the horizon draws outwards from the centre and the
///    flanks fade in.
///
/// Subtle plays steps 3 and 4 only; Off plays nothing; reduced motion swaps
/// the sweep for a 200 ms fade of the horizon and flanks.
///
/// **It never delays live data.** The needle and the numerals are moved with
/// [SmoothedSignal.hold] and let go again on the timeline, and [release]
/// retargets to whatever the newest reading is, so a value arriving
/// mid-sequence simply retargets (spring.needle, spring.gauge).
class IgnitionSequence extends ChangeNotifier {
  IgnitionSequence({
    required this.clock,
    required this.rpm,
    required this.speed,
    this.redlineRpm = 6500,
    this.mode = IgnitionMode.full,
    this.reduceMotion = false,
  });

  final MotionClock clock;

  /// The needle, held at redline for the sweep.
  final SmoothedSignal rpm;

  /// The hero numerals' signal, held at 0 for the roll-up.
  final SmoothedSignal speed;

  final double redlineRpm;
  IgnitionMode mode;
  bool reduceMotion;

  Timeline? _timeline;
  bool _sweepHeld = false;
  bool _rollHeld = false;
  bool _played = false;

  /// Whether the sequence has run since the last [reset]: it plays once per
  /// connection.
  bool get hasPlayed => _played;

  bool get isRunning => _timeline?.isRunning ?? false;

  double get _seconds => _timeline?.seconds ?? double.infinity;

  double _ms(int ms) => ms / 1000.0;

  bool get _plays => mode != IgnitionMode.off;
  bool get _full => mode == IgnitionMode.full && !reduceMotion;

  /// Step 1: the share of the arc's segments the wave has lit, 0 to 1.
  /// 1 when nothing is playing.
  double get arcWave {
    if (!isRunning || !_full) return 1;
    return Timeline.interval(
      _seconds,
      _ms(TapeMotion.ignitionWaveFromMs),
      _ms(TapeMotion.ignitionWaveToMs),
      TapeMotion.ignitionWaveCurve,
    );
  }

  /// Step 4, first half: how far the horizon has drawn out from its centre.
  /// 1 when nothing is playing.
  double get horizonDraw => _tail(0);

  /// Step 4, second half: flank [index]'s presence, staggered
  /// (DESIGN.md 5.7). 1 when nothing is playing.
  double flank(int index) => _tail(index);

  double _tail(int index) {
    if (!isRunning || !_plays) return 1;
    if (reduceMotion) {
      return Timeline.interval(_seconds, 0, _ms(TapeMotion.ignitionReducedMs));
    }
    final from = _ms(TapeMotion.ignitionHorizonFromMs);
    final to = _ms(TapeMotion.ignitionHorizonToMs);
    final start =
        index.clamp(0, TapeMotion.maxStaggered - 1) *
        TapeMotion.stagger.inMicroseconds /
        1e6;
    final share = Timeline.interval(
      _seconds,
      from + start,
      to,
      TapeMotion.ignitionRevealCurve,
    );
    return share;
  }

  /// Plays the sequence, from the start. A running one restarts.
  void play() {
    _finish(notify: false);
    if (!_plays) return;
    _played = true;
    _timeline = Timeline(
      clock: clock,
      length: Duration(
        milliseconds: reduceMotion
            ? TapeMotion.ignitionReducedMs
            : TapeMotion.ignitionLengthMs,
      ),
      onDone: () => _finish(),
    )..addListener(_onTick);
    if (_full) {
      _sweepHeld = true;
      rpm.hold(redlineRpm);
    }
    if (!reduceMotion) {
      _rollHeld = true;
      speed.hold(0, jump: true);
    }
    _timeline!.start();
  }

  /// Lets the next connection play it again.
  void reset() {
    _finish(notify: false);
    _played = false;
  }

  void _onTick() {
    final t = _seconds;
    if (_sweepHeld && t >= _ms(TapeMotion.ignitionNeedleTurnMs)) {
      _sweepHeld = false;
      rpm.release();
    }
    if (_rollHeld && t >= _ms(TapeMotion.ignitionNumeralsFromMs)) {
      _rollHeld = false;
      speed.release();
    }
    notifyListeners();
  }

  void _finish({bool notify = true}) {
    final timeline = _timeline;
    _timeline = null;
    if (_sweepHeld) rpm.release();
    if (_rollHeld) speed.release();
    _sweepHeld = false;
    _rollHeld = false;
    timeline?.removeListener(_onTick);
    timeline?.dispose();
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _finish(notify: false);
    super.dispose();
  }
}

/// One of the [IgnitionSequence]'s shares as a plain [ValueListenable], for a
/// painter to take as its `repaint:` and read fresh in paint (DESIGN.md 9.3).
/// A component takes this, never the sequence itself, so `ui/design/`
/// components stay ignorant of who is playing what.
class IgnitionShare extends ChangeNotifier implements ValueListenable<double> {
  IgnitionShare(this._sequence, this._read) {
    _sequence.addListener(notifyListeners);
  }

  final IgnitionSequence _sequence;
  final double Function(IgnitionSequence) _read;

  @override
  double get value => _read(_sequence);

  @override
  void dispose() {
    _sequence.removeListener(notifyListeners);
    super.dispose();
  }
}

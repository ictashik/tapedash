import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../tokens/connection.dart';
import '../tokens/motion_tokens.dart';
import 'motion_clock.dart';
import 'spring_value.dart';
import 'timeline.dart';

/// What the link to the car is doing, in the vocabulary of DESIGN.md 7.12.
/// `ui/design/` stays ignorant of the OBD layer; the page maps its own
/// connection status onto this.
enum LinkPhase { searching, waitingForIgnition, connected, lost }

/// The connection states' shares (DESIGN.md 7.12), read fresh in paint:
///
/// - [standby]: 1 while searching or waiting for the ignition, 0 once
///   connected. Rises on `spring.reveal`; the fall (the ignition sequence
///   takes over) is `spring.snap`, so live data is never held back.
/// - [sweep]: the beam's turn while searching, in turns (0 to 1, wrapping),
///   one revolution per [TapeConnection.sweepSeconds].
/// - [breath]: the waiting dot's alpha share, 0.25 Hz.
/// - [lost]: 1 while the link is down (the caution line, the status line).
/// - [relight]: 0 to 1 over 300 ms on a reconnection after a loss; 1 when
///   idle. The full ignition sweep does not play again (that is
///   `DriveSignals`' own once-per-connection rule).
///
/// It asks the clock for frames only while something is moving (the beam,
/// the breath, a spring, the re-light), so a connected cluster costs nothing.
class ConnectionPresentation extends ChangeNotifier implements MotionDriven {
  ConnectionPresentation({required this.clock, required LinkPhase initial})
    : _phase = initial,
      _standby = SpringValue(
        clock: clock,
        spec: TapeSprings.reveal,
        initial: _isStandby(initial) ? 1 : 0,
      ),
      _lost = SpringValue(
        clock: clock,
        spec: TapeSprings.reveal,
        initial: initial == LinkPhase.lost ? 1 : 0,
      ) {
    _standby.addListener(notifyListeners);
    _lost.addListener(notifyListeners);
    _syncClock();
  }

  final MotionClock clock;

  final SpringValue _standby;
  final SpringValue _lost;
  LinkPhase _phase;
  bool _wasLost = false;
  bool _attached = false;
  double _seconds = 0;
  Timeline? _relight;

  static bool _isStandby(LinkPhase p) =>
      p == LinkPhase.searching || p == LinkPhase.waitingForIgnition;

  LinkPhase get phase => _phase;

  double get standby => _standby.value;
  double get lost => _lost.value;

  /// The beam's turn, in turns: 0 to 1, wrapping.
  double get sweep => (_seconds / TapeConnection.sweepSeconds) % 1.0;

  /// The dot's alpha, breathing between the token's two ends.
  double get breath {
    final wave =
        0.5 - 0.5 * math.cos(2 * math.pi * TapeConnection.breathHz * _seconds);
    return TapeConnection.breathAlphaMin +
        (TapeConnection.breathAlphaMax - TapeConnection.breathAlphaMin) * wave;
  }

  /// The re-light's own progress, 0 to 1, and 1 when none is playing.
  double get relight => _relight?.progress ?? 1;
  bool get isRelighting => _relight?.isRunning ?? false;

  /// The ring's brightness through the re-light: up to its peak, then away.
  double get relightGlow {
    if (!isRelighting) return 0;
    final t = relight;
    final peak = TapeConnection.relightPeak;
    return t < peak ? t / peak : 1 - (t - peak) / (1 - peak);
  }

  /// Moves to [next]. A move to the same phase does nothing.
  void update(LinkPhase next) {
    if (next == _phase) return;
    _phase = next;
    if (next == LinkPhase.lost) {
      _wasLost = true;
    } else {
      // Only a reconnection after a loss re-lights; a first connection
      // plays the ignition sequence instead.
      if (next == LinkPhase.connected && _wasLost) _startRelight();
      _wasLost = false;
    }

    _standby
      ..setSpec(_isStandby(next) ? TapeSprings.reveal : TapeSprings.snap)
      ..retarget(_isStandby(next) ? 1 : 0);
    _lost
      ..setSpec(next == LinkPhase.lost ? TapeSprings.reveal : TapeSprings.snap)
      ..retarget(next == LinkPhase.lost ? 1 : 0);
    _syncClock();
    notifyListeners();
  }

  void _startRelight() {
    _relight?.dispose();
    _relight = Timeline(clock: clock, length: TapeConnection.relight)
      ..addListener(notifyListeners)
      ..start();
  }

  bool get _needsFrames =>
      _phase == LinkPhase.searching || _phase == LinkPhase.waitingForIgnition;

  void _syncClock() {
    if (_needsFrames && !_attached) {
      _attached = true;
      clock.attach(this);
    } else if (!_needsFrames && _attached) {
      _attached = false;
      clock.detach(this);
    }
  }

  @override
  bool advance(double dt, Duration time) {
    _seconds += dt;
    notifyListeners();
    return _needsFrames;
  }

  @override
  void dispose() {
    clock.detach(this);
    _relight?.dispose();
    _standby.removeListener(notifyListeners);
    _lost.removeListener(notifyListeners);
    _standby.dispose();
    _lost.dispose();
    super.dispose();
  }
}

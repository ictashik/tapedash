import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../icons/icons.dart';
import '../motion/motion_clock.dart';
import '../motion/motion_scope.dart';
import '../render/chamfer.dart';
import '../theme/tape_theme.dart';
import '../tokens/alerts.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/strokes.dart';

/// An alert's severity (DESIGN.md 6.10), in ascending order -- code that
/// compares levels (raising or falling in [AlertHysteresis]) relies on this
/// declaration order, so do not reorder these without checking there.
enum AlertLevel { none, caution, critical }

/// Debounces a raw, possibly noisy [AlertLevel] into a stable one that only
/// changes once the new reading has held for a minimum duration (DESIGN.md
/// 6.10: "alerts have hysteresis and minimum durations so they never
/// flicker"). Pure Dart, no Flutter: unit-tested directly, and driven by
/// whatever clock the caller is already on.
///
/// [raiseAfter] and [fallAfter] are asymmetric on purpose: quicker to warn,
/// slower to relax, so a reading bouncing right at its threshold settles on
/// the safer (alerted) state rather than flickering between the two.
class AlertHysteresis {
  AlertHysteresis({
    this.raiseAfter = TapeAlerts.raiseAfter,
    this.fallAfter = TapeAlerts.fallAfter,
  });

  final Duration raiseAfter;
  final Duration fallAfter;

  AlertLevel _stable = AlertLevel.none;
  AlertLevel? _pending;
  Duration? _pendingSince;

  /// The current stable level.
  AlertLevel get level => _stable;

  /// Feeds the raw, instantaneous level at [now] (the caller's own clock,
  /// not necessarily wall time). Returns the stable level, which only
  /// changes once [raw] has been the input continuously for [raiseAfter]
  /// (moving to a higher level) or [fallAfter] (a lower one).
  AlertLevel update(AlertLevel raw, Duration now) {
    if (raw == _stable) {
      _pending = null;
      _pendingSince = null;
      return _stable;
    }
    if (raw != _pending) {
      _pending = raw;
      _pendingSince = now;
      return _stable;
    }
    final since = _pendingSince!;
    final threshold = raw.index > _stable.index ? raiseAfter : fallAfter;
    if (now - since >= threshold) {
      _stable = raw;
      _pending = null;
      _pendingSince = null;
    }
    return _stable;
  }
}

/// The glyph in the alert slot (DESIGN.md 6.10: centre-bottom of the hero
/// zone, a position this standalone component leaves to whatever composes
/// it): small for caution, large for critical, nothing for none. Its own
/// colour is the level's, matching the affected value's own recolouring
/// elsewhere on the cluster.
class AlertSlot extends StatelessWidget {
  const AlertSlot({super.key, required this.level, required this.icon});

  final AlertLevel level;
  final TapeIcon icon;

  @override
  Widget build(BuildContext context) {
    if (level == AlertLevel.none) return const SizedBox.shrink();
    final palette = TapeTheme.of(context).palette;
    final size = level == AlertLevel.critical
        ? TapeAlerts.slotGlyphSizeCritical
        : TapeAlerts.slotGlyphSizeCaution;
    final color = level == AlertLevel.critical
        ? palette.critical
        : palette.caution;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _AlertSlotPainter(icon: icon, color: color),
      ),
    );
  }
}

class _AlertSlotPainter extends CustomPainter {
  _AlertSlotPainter({required this.icon, required this.color});

  final TapeIcon icon;
  final ui.Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      paintTapeIcon(canvas, icon, Offset.zero, size.shortestSide, color);

  @override
  bool shouldRepaint(_AlertSlotPainter old) =>
      old.icon != icon || old.color != color;
}

/// A chamfered bracket frame around [child] that pulses `critical` at
/// 1 Hz while [active] (DESIGN.md 6.10's critical presentation); otherwise
/// [child] is drawn with no frame at all, and nothing is animated. Wrap any
/// component in this rather than teaching each one to draw its own alert
/// bracket.
class CriticalAlertFrame extends StatefulWidget {
  const CriticalAlertFrame({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<CriticalAlertFrame> createState() => CriticalAlertFrameState();
}

class CriticalAlertFrameState extends State<CriticalAlertFrame>
    implements MotionDriven {
  late MotionClock _motion;
  bool _attached = false;
  double _phase = 0;
  final AlertRepaintPing repaint = AlertRepaintPing();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionScope.of(context);
    _sync();
  }

  @override
  void didUpdateWidget(CriticalAlertFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active && !_attached) {
      _attached = true;
      _phase = 0;
      _motion.attach(this);
    } else if (!widget.active && _attached) {
      _attached = false;
      _motion.detach(this);
      repaint.ping(); // one more frame, to clear the frame entirely.
    }
  }

  @override
  bool advance(double dt, Duration time) {
    _phase += dt;
    repaint.ping();
    return true;
  }

  /// The bracket's current stroke alpha, exposed for a direct test rather
  /// than sampling it back out of rendered pixels.
  double pulseAlpha() => pulseAlphaAt(_phase);

  static double pulseAlphaAt(double phaseSeconds) {
    final t = TapeMotion.pulseShare(phaseSeconds, TapeAlerts.criticalPulseHz);
    return TapeAlerts.criticalPulseAlphaMin +
        (TapeAlerts.criticalPulseAlphaMax - TapeAlerts.criticalPulseAlphaMin) *
            t;
  }

  @override
  void dispose() {
    if (_attached) _motion.detach(this);
    repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return CustomPaint(
      foregroundPainter: widget.active
          ? _CriticalFramePainter(
              listenable: repaint,
              state: this,
              color: palette.critical,
              strokeScale: palette.strokeScale,
            )
          : null,
      child: widget.child,
    );
  }
}

class AlertRepaintPing extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _CriticalFramePainter extends CustomPainter {
  _CriticalFramePainter({
    required Listenable listenable,
    required this.state,
    required this.color,
    required this.strokeScale,
  }) : super(repaint: listenable);

  final CriticalAlertFrameState state;
  final ui.Color color;
  final double strokeScale;

  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    Chamfer.bracketsInto(
      _path,
      Offset.zero & size,
      TapeAlerts.criticalBracketArm,
    );
    canvas.drawPath(
      _path,
      Paint()
        ..color = color.withValues(alpha: state.pulseAlpha())
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = TapeStroke.regular * strokeScale,
    );
  }

  @override
  bool shouldRepaint(_CriticalFramePainter old) =>
      old.color != color || old.strokeScale != strokeScale;
}

/// A thin `caution` line on the Horizon zone (DESIGN.md 6.10), shown
/// whenever any alert is caution or above. Static -- only the critical
/// bracket pulses -- so this needs no clock at all.
class CautionHorizonLine extends StatelessWidget {
  const CautionHorizonLine({
    super.key,
    required this.active,
    required this.width,
  });

  final bool active;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (!active) return SizedBox(width: width);
    final palette = TapeTheme.of(context).palette;
    return SizedBox(
      width: width,
      height: TapeAlerts.horizonLineThickness,
      child: DecoratedBox(decoration: BoxDecoration(color: palette.caution)),
    );
  }
}

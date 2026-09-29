import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../motion/connection_presentation.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/connection.dart';
import '../tokens/spacing.dart';
import '../tokens/tach.dart';
import 'presence.dart';
import 'tape_label.dart';

/// The connection states' presentation over a cluster (DESIGN.md 7.12):
///
/// - **Searching:** the cluster in standby (etch only, at 15%), a sweep beam
///   turning around the arc's ring once per 1.6 s, "Looking for your
///   adapter".
/// - **Waiting for ignition:** the same standby, one accent dot breathing at
///   0.25 Hz in the hero position, "Turn on the ignition" at full label
///   colour.
/// - **Lost:** the values freeze and fade to `stale` on their own (the
///   smoothing pipeline, DESIGN.md 5.2); this adds the `caution` line on the
///   horizon and "Reconnecting…". On reconnection, a 300 ms ring re-lights
///   at the arc's radius instead of the full sweep.
/// - Connected: nothing at all. It paints no layer, asks for no frames.
///
/// It is one layer over whichever cluster is showing, so all five get the
/// states without each knowing them. Never a blank screen, never a spinner:
/// the scrim leaves the status strip's band alone, and the only motion is
/// the beam and the breath.
///
/// The ring sits at the Apex/Minimal tach arc's radius, centred; the other
/// clusters have no arc, and the ring stands in for it there.
class ConnectionLayer extends StatefulWidget {
  const ConnectionLayer({
    super.key,
    required this.presentation,
    required this.width,
    required this.height,
  });

  final ConnectionPresentation presentation;
  final double width;
  final double height;

  @override
  State<ConnectionLayer> createState() => _ConnectionLayerState();
}

class _ConnectionLayerState extends State<ConnectionLayer> {
  late _PhaseShare _searching;
  late _PhaseShare _waiting;
  late _PhaseShare _lost;

  @override
  void initState() {
    super.initState();
    _makeShares();
  }

  void _makeShares() {
    _searching = _PhaseShare(widget.presentation, LinkPhase.searching);
    _waiting = _PhaseShare(widget.presentation, LinkPhase.waitingForIgnition);
    _lost = _PhaseShare(widget.presentation, LinkPhase.lost);
  }

  void _disposeShares() {
    _searching.dispose();
    _waiting.dispose();
    _lost.dispose();
  }

  @override
  void didUpdateWidget(ConnectionLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.presentation, widget.presentation)) {
      _disposeShares();
      _makeShares();
    }
  }

  @override
  void dispose() {
    _disposeShares();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final lineTop =
        widget.height / 2 +
        widget.height * TapeConnection.lineOffsetShareOfHeight;
    return IgnorePointer(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ConnectionPainter(
                  presentation: widget.presentation,
                  palette: palette,
                ),
              ),
            ),
            _line(
              'Looking for your adapter',
              lineTop,
              _searching,
              palette.label,
            ),
            _line(
              'Turn on the ignition',
              lineTop,
              _waiting,
              // Full label colour, not the dim one (DESIGN.md 7.12).
              palette.inkBright,
            ),
            _line('Reconnecting…', lineTop, _lost, palette.caution),
          ],
        ),
      ),
    );
  }

  Widget _line(
    String text,
    double top,
    ValueListenable<double> share,
    Color color,
  ) => Positioned(
    top: top,
    left: 0,
    right: 0,
    child: Presence(
      share: share,
      child: Center(
        child: TapeLabel(text, size: TapeConnection.lineSize, color: color),
      ),
    ),
  );
}

/// A phase's line: visible while that phase is the current one and the
/// matching share has risen. Swapping between searching and waiting swaps
/// the words at once; the scrim behind them stays.
class _PhaseShare extends ChangeNotifier implements ValueListenable<double> {
  _PhaseShare(this._presentation, this._phase) {
    _presentation.addListener(notifyListeners);
  }

  final ConnectionPresentation _presentation;
  final LinkPhase _phase;

  @override
  double get value {
    if (_presentation.phase != _phase) return 0;
    return _phase == LinkPhase.lost
        ? _presentation.lost
        : _presentation.standby;
  }

  @override
  void dispose() {
    _presentation.removeListener(notifyListeners);
    super.dispose();
  }
}

class _ConnectionPainter extends CustomPainter {
  _ConnectionPainter({required this.presentation, required this.palette})
    : super(repaint: presentation);

  final ConnectionPresentation presentation;
  final TapePalette palette;

  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final p = presentation;
    final standby = p.standby.clamp(0.0, 1.0);
    final lost = p.lost.clamp(0.0, 1.0);
    final glow = p.relightGlow;
    if (standby <= 0 && lost <= 0 && glow <= 0) return;

    final centre = Offset(size.width / 2, size.height / 2);
    final radius = TapeTach.radiusShareOfHeight * size.height;

    if (standby > 0) {
      // Etch only at 15%: the void over everything below the strip.
      final band = TapeConnection.stripBandHeight;
      _paint
        ..style = PaintingStyle.fill
        ..color = palette.canvas.withValues(
          alpha: (1 - TapeConnection.standbyBrightness) * standby,
        );
      canvas
        ..drawRect(
          Rect.fromLTWH(0, band, size.width, size.height - band),
          _paint,
        )
        ..drawRect(
          Rect.fromLTRB(
            TapeConnection.stripLeftWidth,
            0,
            size.width - TapeConnection.stripRightWidth,
            band,
          ),
          _paint,
        );

      if (p.phase == LinkPhase.searching) {
        _sweep(canvas, centre, radius, size.height, standby, p.sweep);
      } else if (p.phase == LinkPhase.waitingForIgnition) {
        _dot(canvas, centre, size.height, standby * p.breath);
      }
    }

    if (lost > 0) {
      final w = size.width * TapeConnection.cautionLineWidthShare;
      final h = size.height * TapeConnection.cautionLineShareOfHeight;
      _paint
        ..style = PaintingStyle.fill
        ..color = palette.caution.withValues(alpha: lost);
      canvas.drawRect(
        Rect.fromLTWH((size.width - w) / 2, TapeSpace.s2, w, h),
        _paint,
      );
    }

    if (glow > 0) {
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * TapeConnection.relightStrokeShareOfHeight
        ..color = palette.accentCore.withValues(alpha: glow);
      canvas.drawCircle(centre, radius, _paint);
    }
  }

  /// The beam: a lit head and a trail batched into a few fading arcs.
  void _sweep(
    Canvas canvas,
    Offset centre,
    double radius,
    double height,
    double standby,
    double turn,
  ) {
    const steps = TapeConnection.sweepTrailSteps;
    final stepRad = TapeConnection.sweepTrailDegrees * math.pi / 180 / steps;
    final head = -math.pi / 2 + turn * 2 * math.pi;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = height * TapeConnection.sweepStrokeShareOfHeight;
    for (var i = 0; i < steps; i++) {
      final fade = 1 - i / steps;
      _paint.color = palette.accentCore.withValues(
        alpha: standby * fade * fade,
      );
      canvas.drawArc(rect, head - (i + 1) * stepRad, stepRad, false, _paint);
    }
  }

  void _dot(Canvas canvas, Offset centre, double height, double alpha) {
    final r = height * TapeConnection.dotRadiusShareOfHeight;
    _paint
      ..style = PaintingStyle.fill
      ..color = palette.accentGlow.withValues(alpha: alpha * 0.35);
    canvas.drawCircle(centre, r * 2.2, _paint);
    _paint.color = palette.accentCore.withValues(alpha: alpha);
    canvas.drawCircle(centre, r, _paint);
  }

  @override
  bool shouldRepaint(_ConnectionPainter old) =>
      old.presentation != presentation || old.palette != palette;
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../motion/connection_presentation.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/connection.dart';
import '../presence.dart';
import '../tape_label.dart';
import 'watch_face.dart';

/// The connection states on the round face (DESIGN.md 7.12, 16.8): the same states
/// as the phone's `ConnectionLayer`, drawn for a circle.
///
/// - **Searching:** the face in standby (the veil over everything but the crown),
///   a beam turning round the rim once in 1.6 s, and "Looking for / your adapter"
///   in two short lines, since one would not fit the chord.
/// - **Waiting for ignition:** the same, one dot breathing at the hero's place and
///   "Turn on / the ignition".
/// - **Lost:** a `caution` arc along the top of the rim and "Reconnecting…".
/// - Connected: nothing at all, no layer and no frames.
class WatchConnectionLayer extends StatefulWidget {
  const WatchConnectionLayer({
    super.key,
    required this.presentation,
    required this.face,
  });

  final ConnectionPresentation presentation;
  final WatchFace face;

  @override
  State<WatchConnectionLayer> createState() => _WatchConnectionLayerState();
}

class _WatchConnectionLayerState extends State<WatchConnectionLayer> {
  late _Phase _searching = _Phase(widget.presentation, LinkPhase.searching);
  late _Phase _waiting = _Phase(
    widget.presentation,
    LinkPhase.waitingForIgnition,
  );
  late _Phase _lost = _Phase(widget.presentation, LinkPhase.lost);

  @override
  void didUpdateWidget(WatchConnectionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.presentation, widget.presentation)) {
      _searching.dispose();
      _waiting.dispose();
      _lost.dispose();
      _searching = _Phase(widget.presentation, LinkPhase.searching);
      _waiting = _Phase(widget.presentation, LinkPhase.waitingForIgnition);
      _lost = _Phase(widget.presentation, LinkPhase.lost);
    }
  }

  @override
  void dispose() {
    _searching.dispose();
    _waiting.dispose();
    _lost.dispose();
    super.dispose();
  }

  Widget _lines(
    List<String> words,
    ValueListenable<double> share,
    Color color,
  ) {
    final face = widget.face;
    return Positioned(
      top: face.heroY - face.type.label * 1.3,
      left: 0,
      right: 0,
      child: Presence(
        share: share,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in words)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: TapeLabel(line, size: face.type.label, color: color),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final face = widget.face;
    return IgnorePointer(
      child: SizedBox.square(
        dimension: face.diameter,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _Painter(
                  presentation: widget.presentation,
                  palette: palette,
                  face: face,
                ),
              ),
            ),
            // A waiting dot is the hero's, so its words go lower.
            _lines(
              const ['Looking for', 'your adapter'],
              _searching,
              palette.label,
            ),
            _lines(
              const ['Turn on', 'the ignition'],
              _waiting,
              palette.inkBright,
            ),
            _lines(const ['Reconnecting…'], _lost, palette.caution),
          ],
        ),
      ),
    );
  }
}

class _Phase extends ChangeNotifier implements ValueListenable<double> {
  _Phase(this._presentation, this._phase) {
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

class _Painter extends CustomPainter {
  _Painter({
    required this.presentation,
    required this.palette,
    required this.face,
  }) : super(repaint: presentation);

  final ConnectionPresentation presentation;
  final TapePalette palette;
  final WatchFace face;

  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final p = presentation;
    final standby = p.standby.clamp(0.0, 1.0);
    final lost = p.lost.clamp(0.0, 1.0);
    final glow = p.relightGlow;
    if (standby <= 0 && lost <= 0 && glow <= 0) return;
    final centre = face.centre;

    if (standby > 0) {
      // The veil: the face's etch only, at 15%. The crown is drawn over it.
      _paint
        ..style = PaintingStyle.fill
        ..color = palette.canvas.withValues(
          alpha: (1 - TapeConnection.standbyBrightness) * standby,
        );
      canvas.drawCircle(centre, face.radius, _paint);
      if (p.phase == LinkPhase.searching) {
        _sweep(canvas, centre, standby, p.sweep);
      } else if (p.phase == LinkPhase.waitingForIgnition) {
        _dot(canvas, Offset(centre.dx, face.heroY), standby * p.breath);
      }
    }

    if (lost > 0) {
      // A caution arc along the top of the rim, 60 degrees of it.
      _paint
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..strokeWidth = face.rimDepth * 0.3
        ..color = palette.caution.withValues(alpha: lost);
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: face.rimOuter),
        -math.pi / 2 - math.pi / 6,
        math.pi / 3,
        false,
        _paint,
      );
    }

    if (glow > 0) {
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = face.rimDepth * 0.4
        ..color = palette.accentCore.withValues(alpha: glow);
      canvas.drawCircle(centre, face.rimRadius, _paint);
    }
  }

  void _sweep(Canvas canvas, Offset centre, double standby, double turn) {
    const steps = TapeConnection.sweepTrailSteps;
    final stepRad = TapeConnection.sweepTrailDegrees * math.pi / 180 / steps;
    final head = -math.pi / 2 + turn * 2 * math.pi;
    final rect = Rect.fromCircle(center: centre, radius: face.rimRadius);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = face.rimDepth * 0.8;
    for (var i = 0; i < steps; i++) {
      final fade = 1 - i / steps;
      _paint.color = palette.accentCore.withValues(
        alpha: standby * fade * fade,
      );
      canvas.drawArc(rect, head - (i + 1) * stepRad, stepRad, false, _paint);
    }
  }

  void _dot(Canvas canvas, Offset at, double alpha) {
    final r = face.diameter * TapeConnection.dotRadiusShareOfHeight;
    _paint
      ..style = PaintingStyle.fill
      ..color = palette.accentGlow.withValues(alpha: alpha * 0.35);
    canvas.drawCircle(at, r * 2.2, _paint);
    _paint.color = palette.accentCore.withValues(alpha: alpha);
    canvas.drawCircle(at, r, _paint);
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.presentation != presentation ||
      old.palette != palette ||
      old.face != face;
}

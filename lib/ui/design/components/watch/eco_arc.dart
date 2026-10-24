import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../motion/smoothing_pipeline.dart';
import '../../render/arc_geometry.dart';
import '../../render/glow_cache.dart';
import '../../render/render_kit.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/eco_bar.dart';
import '../../tokens/glow.dart';
import '../../tokens/watch.dart';
import '../eco_bar.dart';
import 'watch_face.dart';

/// The eco bar (DESIGN.md 6.7) bent into the gap at the bottom of the rim
/// (DESIGN.md 16.5): a short arc round 6 o'clock with a notch for this car's own
/// average and a puck that rides towards the right while the car is more
/// efficient than it usually is and towards the left while it is thirstier, in the
/// eco ramp's colours. It says nothing in words.
///
/// Where it sits is the opening of the rim's 240° tach arc, so it costs the face
/// no room of its own.
class EcoArc extends StatelessWidget {
  const EcoArc({
    super.key,
    required this.instantValue,
    required this.average,
    required this.face,
  });

  /// The live km/L, smoothed with `spring.gauge`.
  final SmoothedSignal instantValue;

  /// The car's own average: the centre notch. Null while there is no history, and
  /// then the puck stays centred and dim, as on the phone.
  final double? average;

  final WatchFace face;

  /// The puck's position, -1 (thirstier) to 1 (more efficient).
  double shareFor(double value) {
    final avg = average;
    if (avg == null || avg <= 0) return 0;
    final travel = avg * TapeEcoBar.travelShareOfAverage;
    return ((value - avg) / travel).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final kit = TapeRenderScope.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final puck = TapeWatch.ecoPuckShare * face.diameter;
    final glow = kit.glows.get(
      GlowSpec(
        shape: GlowShape.disc,
        width: puck,
        height: puck,
        sigma: puck * 0.5,
        devicePixelRatio: dpr,
        resolution: theme.profile.halosAtHalfResolution
            ? TapeGlow.liteResolution
            : 1,
      ),
    );
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: face.diameter,
        child: CustomPaint(
          painter: EcoArcPainter(
            arc: this,
            palette: theme.palette,
            glow: glow,
            repaint: instantValue,
          ),
        ),
      ),
    );
  }
}

class EcoArcPainter extends CustomPainter {
  EcoArcPainter({
    required this.arc,
    required this.palette,
    required this.glow,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final EcoArc arc;
  final TapePalette palette;
  final GlowSprite glow;

  /// Straight down, in maths degrees.
  static const double bottom = 270;

  @override
  void paint(Canvas canvas, Size size) {
    final face = arc.face;
    final c = face.centre;
    final r = face.rimRadius;
    final track = TapeWatch.ecoTrackShare * face.diameter;
    final span = TapeWatch.ecoSpanDegrees;

    // The track: a short arc of the ring's own band.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -(bottom + span) * math.pi / 180,
      2 * span * math.pi / 180,
      false,
      Paint()
        ..color = palette.track
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = track
        ..strokeCap = ui.StrokeCap.butt,
    );
    // The notch at the average.
    canvas.drawLine(
      ArcGeometry.pointAt(c, r - track * 1.6, bottom),
      ArcGeometry.pointAt(c, r + track * 1.6, bottom),
      Paint()
        ..color = palette.etchStrong
        ..strokeWidth = 1.5,
    );

    if (!arc.instantValue.hasValue) return;
    final share = arc.shareFor(arc.instantValue.value);
    final colour = EcoBarPainter.colorFor(share, palette);
    // Right is the maths angle rising from straight down.
    final at = ArcGeometry.pointAt(c, r, bottom + share * span);
    final haloStrength = TapeGlow.needleHalo * palette.haloScale;
    if (haloStrength > 0.01) {
      glow.drawCentered(
        canvas,
        at,
        palette.accentGlow.withValues(alpha: haloStrength),
        Paint()..blendMode = ui.BlendMode.plus,
      );
    }
    canvas.drawCircle(
      at,
      TapeWatch.ecoPuckShare * face.diameter / 2,
      Paint()..color = colour,
    );
  }

  @override
  bool shouldRepaint(EcoArcPainter old) =>
      old.palette != palette ||
      old.glow != glow ||
      old.arc.average != arc.average ||
      !identical(old.arc.instantValue, arc.instantValue);
}

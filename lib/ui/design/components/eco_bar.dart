import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../motion/smoothing_pipeline.dart';
import '../render/glow_cache.dart';
import '../render/render_kit.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/eco_bar.dart';
import '../tokens/glow.dart';

/// The eco bar (DESIGN.md 6.7): a live cue for how efficient the drive is right
/// now, with no text. A glowing puck moves right (more efficient than the car's
/// own average) or left (thirstier), over ±50% of that average, coloured along a
/// ramp from critical (far left) through caution and `ink.bright` at the centre
/// to `accent.core` (right).
///
/// [instantValue] should be smoothed with `spring.gauge` (DESIGN.md 5.3): the
/// puck's position is a pure function of it (DESIGN.md 5.1). Showing or hiding it
/// when parked, or when there is no fuel data, is the caller's (DESIGN.md 6.7
/// says where: hidden then).
class EcoBar extends StatelessWidget {
  const EcoBar({
    super.key,
    required this.instantValue,
    required this.average,
    required this.width,
    required this.heightReference,
  });

  /// The live km/L (or equivalent), smoothed with `spring.gauge`.
  final SmoothedSignal instantValue;

  /// The car's own average, marked by the centre notch. Null while there is
  /// not enough history yet, in which case the bar shows the puck centred and
  /// dim rather than guessing an average.
  final double? average;

  /// The full width available; the bar itself is 0.36 of it.
  final double width;

  /// H, for the bar's height (DESIGN.md 6.7's 0.03H).
  final double heightReference;

  double get barWidth => TapeEcoBar.widthShareOfWidth * width;
  double get barHeight => TapeEcoBar.heightShareOfHeight * heightReference;

  /// The puck's position, -1 (far left) to 1 (far right), or 0 with no average.
  double shareFor(double value) {
    final avg = average;
    if (avg == null || avg <= 0) return 0;
    final travel = avg * TapeEcoBar.travelShareOfAverage;
    if (travel <= 0) return 0;
    return ((value - avg) / travel).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final kit = TapeRenderScope.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final glow = kit.glows.get(
      GlowSpec(
        shape: GlowShape.disc,
        width: barHeight * TapeEcoBar.puckDiameterShareOfHeight,
        height: barHeight * TapeEcoBar.puckDiameterShareOfHeight,
        sigma: barHeight * 0.5,
        devicePixelRatio: dpr,
        resolution: theme.profile.halosAtHalfResolution
            ? TapeGlow.liteResolution
            : 1,
      ),
    );
    return SizedBox(
      width: barWidth,
      height: barHeight * TapeEcoBar.puckDiameterShareOfHeight,
      child: CustomPaint(
        painter: EcoBarPainter(
          listenable: instantValue,
          bar: this,
          palette: theme.palette,
          glow: glow,
        ),
      ),
    );
  }
}

class EcoBarPainter extends CustomPainter {
  EcoBarPainter({
    required Listenable listenable,
    required this.bar,
    required this.palette,
    required this.glow,
  }) : super(repaint: listenable);

  final EcoBar bar;
  final TapePalette palette;
  final GlowSprite glow;

  @override
  void paint(Canvas canvas, Size size) {
    final barTop = (size.height - bar.barHeight) / 2;
    final trackRect = Rect.fromLTWH(0, barTop, size.width, bar.barHeight);
    canvas.drawRect(trackRect, Paint()..color = palette.track);

    final centreX = size.width / 2;
    canvas.drawLine(
      Offset(centreX, barTop - 2),
      Offset(centreX, barTop + bar.barHeight + 2),
      Paint()
        ..color = palette.etchStrong
        ..strokeWidth = 1.5,
    );

    if (!bar.instantValue.hasValue) return;
    final share = bar.shareFor(bar.instantValue.value);
    final color = _colorFor(share);
    final puckX = centreX + share * (size.width / 2);
    final puckCenter = Offset(puckX, size.height / 2);
    final radius = bar.barHeight * TapeEcoBar.puckDiameterShareOfHeight / 2;

    final haloStrength = 0.6 * palette.haloScale;
    if (haloStrength > 0.01) {
      glow.drawCentered(
        canvas,
        puckCenter,
        palette.accentGlow.withValues(alpha: haloStrength),
        Paint()..blendMode = ui.BlendMode.plus,
      );
    }
    canvas.drawCircle(puckCenter, radius, Paint()..color = color);
  }

  Color _colorFor(double share) => colorFor(share, palette);

  /// The puck's colour for [share] (-1 far left/thirstier to 1 far
  /// right/efficient), a 4-stop ramp through `TapeEcoBar`'s named stops.
  /// Exposed so the ramp has a direct test, since sampling it back out of
  /// rendered pixels is the fragile way to check it.
  static Color colorFor(double share, TapePalette palette) {
    if (share >= TapeEcoBar.accentStop) return palette.accentCore;
    if (share >= TapeEcoBar.centreStop) {
      final t = share / TapeEcoBar.accentStop;
      return Color.lerp(palette.inkBright, palette.accentCore, t)!;
    }
    if (share >= TapeEcoBar.cautionStop) {
      final t =
          (share - TapeEcoBar.centreStop) /
          (TapeEcoBar.cautionStop - TapeEcoBar.centreStop);
      return Color.lerp(palette.inkBright, palette.caution, t)!;
    }
    final t =
        (share - TapeEcoBar.cautionStop) /
        (TapeEcoBar.criticalStop - TapeEcoBar.cautionStop);
    return Color.lerp(palette.caution, palette.critical, t.clamp(0.0, 1.0))!;
  }

  @override
  bool shouldRepaint(EcoBarPainter old) =>
      old.palette != palette ||
      old.glow != glow ||
      old.bar.average != bar.average ||
      !identical(old.bar.instantValue, bar.instantValue);
}

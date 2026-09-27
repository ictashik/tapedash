import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../render/render_kit.dart';
import '../render/static_layer.dart';
import '../theme/tape_theme.dart';

/// The canvas behind everything (DESIGN.md 4.1 and 4.2, layer L0): the `void`, a
/// static radial vignette from `carbon.900` at the centre to `void` at the edges,
/// and grain over it to keep the gradient from banding on a 6-bit panel. The VFD
/// livery adds its fine hex mesh.
///
/// It is drawn once into a cached layer, and does not repaint while driving.
class TapeBackdrop extends StatelessWidget {
  const TapeBackdrop({super.key, this.child});

  /// What is drawn over the canvas.
  final Widget? child;

  /// How far the vignette reaches, as a multiple of half the screen's diagonal.
  static const double vignetteReach = 0.95;

  /// The colour that, with white noise of average strength [grain] over it, is
  /// [target] on average: `base + grain * (1 - base) = target`.
  static Color _beneathGrain(Color target, double grain) {
    double channel(double c) => math.max(0, (c - grain) / (1 - grain));
    return Color.from(
      alpha: 1,
      red: channel(target.r),
      green: channel(target.g),
      blue: channel(target.b),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final kit = TapeRenderScope.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final palette = theme.palette;
    final mesh = theme.livery.mesh;

    return StaticLayer(
      cacheKey: (theme.livery.id, theme.mode, dpr, mesh, kit),
      paint: (canvas, size) {
        final rect = Offset.zero & size;
        // The grain is white speckle, so it lifts the black by its average. The
        // canvas underneath is darkened by that much, so that the average colour
        // of the canvas is the token colour and the black is not hazy.
        final grain = kit.grain.opacity;
        final canvasColour = _beneathGrain(palette.canvas, grain);
        final centreColour = _beneathGrain(palette.vignetteCentre, grain);
        canvas.drawRect(rect, Paint()..color = canvasColour);

        final centre = rect.center;
        final radius =
            vignetteReach *
            0.5 *
            math.sqrt(size.width * size.width + size.height * size.height);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.radial(centre, radius, [
              centreColour,
              canvasColour,
            ]),
        );

        canvas.drawRect(rect, kit.grain.paint());
        if (mesh) canvas.drawRect(rect, kit.mesh(dpr).paint(dpr));
      },
      child: child,
    );
  }
}

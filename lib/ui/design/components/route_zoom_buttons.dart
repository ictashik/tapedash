import 'package:flutter/widgets.dart';

import '../icons/icons.dart';
import '../render/chamfer.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/shapes.dart';
import '../tokens/strokes.dart';
import 'controls/touch_bloom.dart';
import 'route_view.dart';

/// Zoom in, zoom out and fit, for the route panel (DESIGN.md 6.12): three small
/// chamfered buttons for someone who would rather tap than pinch. Each is dimmed
/// when it can do nothing (in at the furthest, out and fit at the whole route).
class RouteZoomButtons extends StatelessWidget {
  const RouteZoomButtons({super.key, required this.view});

  final RouteViewController view;

  /// One button: a glyph in a chamfered frame, [size] lp square.
  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return ListenableBuilder(
      listenable: view,
      builder: (context, _) {
        final zoomed = view.isZoomed || view.targetScale > 1.001;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Button(
              icon: TapeIcon.zoomOut,
              enabled: zoomed,
              palette: palette,
              onTap: view.zoomOut,
            ),
            const SizedBox(width: 4),
            _Button(
              icon: TapeIcon.zoomIn,
              enabled: view.targetScale < RouteViewController.maxScale - 0.01,
              palette: palette,
              onTap: view.zoomIn,
            ),
            const SizedBox(width: 4),
            _Button(
              icon: TapeIcon.fit,
              enabled: zoomed,
              palette: palette,
              onTap: view.reset,
            ),
          ],
        );
      },
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.icon,
    required this.enabled,
    required this.palette,
    required this.onTap,
  });

  final TapeIcon icon;
  final bool enabled;
  final TapePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? palette.accentCore : palette.inkDim;
    return TouchBloom(
      enabled: enabled,
      onTap: onTap,
      color: enabled ? palette.accentCore : null,
      builder: (context, pressed) => CustomPaint(
        painter: _FramePainter(color: color, palette: palette),
        child: SizedBox(
          width: RouteZoomButtons.size,
          height: RouteZoomButtons.size,
          child: Center(child: TapeIconView(icon, size: 18, color: color)),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({required this.color, required this.palette});

  final Color color;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = TapeStroke.fine * palette.strokeScale;
    canvas.drawPath(
      Chamfer.all(
        (Offset.zero & size).deflate(stroke / 2),
        TapeShape.cellChamfer,
      ),
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.color != color || old.palette != palette;
}

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
///
/// In a replay two more come first: FOLLOW, which puts the camera back on the car
/// (lit while it is there), and, while it is, the map's turn: an arrow up when the
/// map turns with the car (heading up), an N when it stays north up. Zoom in and
/// out then bring the camera closer or further from the car, and fit lets go of it.
class RouteZoomButtons extends StatelessWidget {
  const RouteZoomButtons({
    super.key,
    required this.view,
    this.onFollow,
    this.headingUp = true,
    this.onHeading,
  });

  final RouteViewController view;

  /// Shown only in a replay (when given).
  final VoidCallback? onFollow;
  final VoidCallback? onHeading;

  /// Whether the map turns with the car while following.
  final bool headingUp;

  /// One button: a glyph in a chamfered frame, [size] lp square.
  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    // It listens to the flags, which change when the buttons' states do, and not
    // to the view, which moves on every frame of a replay.
    return ValueListenableBuilder<int>(
      valueListenable: view.flags,
      builder: (context, flags, _) {
        final chasing = flags & 4 != 0;
        final zoomed = flags & 1 != 0 || chasing;
        final canIn = chasing ? flags & 8 == 0 : flags & 2 == 0;
        final canOut = chasing ? flags & 16 == 0 : zoomed;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onFollow != null) ...[
              if (chasing && onHeading != null) ...[
                _Button(
                  icon: headingUp ? TapeIcon.heading : TapeIcon.north,
                  enabled: true,
                  palette: palette,
                  onTap: onHeading!,
                ),
                const SizedBox(width: 4),
              ],
              _Button(
                icon: TapeIcon.gps,
                enabled: true,
                lit: chasing,
                palette: palette,
                onTap: onFollow!,
              ),
              const SizedBox(width: 4),
            ],
            _Button(
              icon: TapeIcon.zoomOut,
              enabled: canOut,
              palette: palette,
              onTap: view.zoomOut,
            ),
            const SizedBox(width: 4),
            _Button(
              icon: TapeIcon.zoomIn,
              enabled: canIn,
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
    this.lit = false,
  });

  final TapeIcon icon;
  final bool enabled;

  /// Filled with its colour: a toggle that is on.
  final bool lit;
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
        painter: _FramePainter(color: color, palette: palette, lit: lit),
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
  _FramePainter({
    required this.color,
    required this.palette,
    required this.lit,
  });

  final Color color;
  final TapePalette palette;
  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = TapeStroke.fine * palette.strokeScale;
    final frame = Chamfer.all(
      (Offset.zero & size).deflate(stroke / 2),
      TapeShape.cellChamfer,
    );
    if (lit) {
      canvas.drawPath(frame, Paint()..color = color.withValues(alpha: 0.16));
    }
    canvas.drawPath(
      frame,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.color != color || old.palette != palette || old.lit != lit;
}

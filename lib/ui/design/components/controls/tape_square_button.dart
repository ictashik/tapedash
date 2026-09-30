import 'package:flutter/widgets.dart';

import '../../icons/icons.dart';
import '../../render/chamfer.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/shapes.dart';
import '../../tokens/strokes.dart';
import '../../tokens/typography.dart';
import 'touch_bloom.dart';

/// A small chamfered button with a glyph or a few characters in it (DESIGN.md
/// 6.12's zoom buttons, and the replay's transport): an outline in the accent, a
/// bloom where it is touched, and dimmed when it can do nothing. A toggle that is
/// on is [lit]: filled a little with its colour.
///
/// It is for parked screens (Review), so a touch target of 48 lp is the norm for
/// the main ones; the zoom buttons sit on the map at 36.
class TapeSquareButton extends StatelessWidget {
  const TapeSquareButton({
    super.key,
    required this.onTap,
    this.icon,
    this.label,
    this.size = 36,
    this.enabled = true,
    this.lit = false,
  }) : assert(icon != null || label != null);

  final TapeIcon? icon;

  /// A few characters instead of a glyph: the replay's "2×".
  final String? label;

  /// The button's width and height, in logical pixels.
  final double size;

  final bool enabled;
  final bool lit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final color = enabled ? palette.accentCore : palette.inkDim;
    return TouchBloom(
      enabled: enabled,
      onTap: onTap,
      color: enabled ? palette.accentCore : null,
      builder: (context, pressed) => CustomPaint(
        painter: _FramePainter(
          color: color,
          palette: palette,
          lit: lit || pressed,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: icon != null
                ? TapeIconView(icon!, size: size >= 44 ? 22 : 18, color: color)
                : Text(
                    label!,
                    maxLines: 1,
                    softWrap: false,
                    style: TapeType.button(
                      size: size >= 44 ? 17 : 13,
                      color: color,
                    ),
                  ),
          ),
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

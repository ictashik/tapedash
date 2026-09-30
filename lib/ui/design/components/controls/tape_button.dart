import 'package:flutter/widgets.dart';

import '../../icons/icons.dart';
import '../../render/chamfer.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/opacity.dart';
import '../../tokens/shapes.dart';
import '../../tokens/spacing.dart';
import '../../tokens/strokes.dart';
import '../../tokens/typography.dart';
import 'touch_bloom.dart';

/// What a button is tinted with.
enum ButtonTone {
  /// The livery's accent.
  accent,

  /// Champagne, for the one thing that is about money: SET FUEL PRICE.
  money,

  /// For what cannot be undone.
  critical;

  Color colorIn(TapePalette palette) => switch (this) {
    accent => palette.accentCore,
    money => palette.money,
    critical => palette.critical,
  };
}

/// The chamfer button (DESIGN.md 6.14): 56 lp tall, an asymmetric 8 lp chamfer
/// (top-left and bottom-right), a 1.5 lp outline and a label in Barlow Semi
/// Condensed SemiBold, UPPERCASE and tracked out. Pressed, it fills with 12% of its
/// colour and blooms. The rare primary call to action is filled, with a `void`
/// label.
///
/// It is for parked screens only: nothing here is reachable while driving.
class TapeButton extends StatelessWidget {
  const TapeButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.primary = false,
    this.tone = ButtonTone.accent,
    this.compact = false,
    this.dense = false,
  });

  /// Tighter still than [compact], for a row of five on the narrowest screens
  /// (the parked dock at 640 lp): a 12 lp label, a 16 lp glyph, 6 lp of padding.
  /// It keeps the 56 lp height.
  final bool dense;

  /// A tighter button for a row of several that must fit a narrow screen (the
  /// parked dock): less padding, a smaller label and glyph. It keeps the 56 lp
  /// height, so the touch target does not shrink.
  final bool compact;

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;

  final TapeIcon? icon;

  /// A filled button: the one main action of a screen.
  final bool primary;

  final ButtonTone tone;

  bool get enabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    final color = enabled ? tone.colorIn(palette) : palette.trackInactive;
    final labelColor = !enabled
        ? palette.inkDim
        : primary
        ? palette.canvas
        : color;

    return TouchBloom(
      enabled: enabled,
      onTap: onPressed,
      color: enabled ? tone.colorIn(palette) : null,
      builder: (context, pressed) => CustomPaint(
        painter: _ButtonPainter(
          color: color,
          primary: primary && enabled,
          pressed: pressed,
          strokeScale: palette.strokeScale,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: TapeShape.buttonHeight,
            minWidth: TapeSpace.touchTarget,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense
                  ? 6
                  : compact
                  ? TapeSpace.s2
                  : TapeSpace.s6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  TapeIconView(
                    icon!,
                    size: dense
                        ? 16
                        : compact
                        ? 18
                        : 20,
                    color: labelColor,
                  ),
                  SizedBox(
                    width: compact || dense ? TapeSpace.s1 : TapeSpace.s2,
                  ),
                ],
                Text(
                  label.toUpperCase(),
                  style: TapeType.button(
                    size: dense
                        ? 12
                        : compact
                        ? 14
                        : 16,
                    color: labelColor,
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonPainter extends CustomPainter {
  _ButtonPainter({
    required this.color,
    required this.primary,
    required this.pressed,
    required this.strokeScale,
  });

  final Color color;
  final bool primary;
  final bool pressed;
  final double strokeScale;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = TapeStroke.fine * strokeScale;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final path = Chamfer.button(rect, TapeShape.buttonChamfer);
    if (primary) {
      canvas.drawPath(path, Paint()..color = color);
    } else if (pressed) {
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: TapeOpacity.pressedFill),
      );
    }
    if (!primary) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.miter,
      );
    }
  }

  @override
  bool shouldRepaint(_ButtonPainter old) =>
      old.color != color ||
      old.primary != primary ||
      old.pressed != pressed ||
      old.strokeScale != strokeScale;
}

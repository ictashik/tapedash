import 'package:flutter/widgets.dart';

import '../../icons/icons.dart';
import '../../render/chamfer.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/opacity.dart';
import '../../tokens/shapes.dart';
import '../../tokens/spacing.dart';
import '../../tokens/strokes.dart';
import '../../tokens/typography.dart';
import 'touch_bloom.dart';

/// The numpad (DESIGN.md 6.14): a 3 by 4 grid of chamfer-outlined keys 72 lp
/// square, Saira digits, a decimal point and a backspace, every press with a
/// touch bloom. Parked screens only.
///
/// [onKey] gets '0' to '9', '.' or 'back'.
class TapeNumpad extends StatelessWidget {
  const TapeNumpad({super.key, required this.onKey, this.keySize = 72});

  final ValueChanged<String> onKey;

  /// The side of a key: 72 lp (DESIGN.md 6.14), less only where the screen is too
  /// short for four of them (never under the 48 lp touch target).
  final double keySize;

  static const List<String> keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '.',
    '0',
    'back',
  ];

  /// The height of the whole pad for [keySize].
  static double heightFor(double keySize) => 4 * keySize + 3 * TapeSpace.s2;

  /// The width of the whole pad for [keySize].
  static double widthFor(double keySize) => 3 * keySize + 2 * TapeSpace.s2;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widthFor(keySize),
      height: heightFor(keySize),
      child: Column(
        children: [
          for (var row = 0; row < 4; row++) ...[
            if (row > 0) const SizedBox(height: TapeSpace.s2),
            Row(
              children: [
                for (var col = 0; col < 3; col++) ...[
                  if (col > 0) const SizedBox(width: TapeSpace.s2),
                  _Key(
                    label: keys[row * 3 + col],
                    size: keySize,
                    onTap: () => onKey(keys[row * 3 + col]),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.size, required this.onTap});

  final String label;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    return SizedBox(
      width: size,
      height: size,
      child: TouchBloom(
        onTap: onTap,
        builder: (context, pressed) => CustomPaint(
          painter: _KeyPainter(
            color: palette.accentCore,
            pressed: pressed,
            strokeScale: palette.strokeScale,
          ),
          child: Center(
            child: label == 'back'
                ? TapeIconView(
                    TapeIcon.back,
                    size: 28,
                    color: palette.inkBright,
                  )
                : Text(
                    label,
                    style: TapeType.numeral(
                      size: size * 0.42,
                      weight: theme.livery.numeralWeight,
                      color: palette.inkBright,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _KeyPainter extends CustomPainter {
  _KeyPainter({
    required this.color,
    required this.pressed,
    required this.strokeScale,
  });

  final Color color;
  final bool pressed;
  final double strokeScale;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = TapeStroke.fine * strokeScale;
    final path = Chamfer.button(
      (Offset.zero & size).deflate(stroke / 2),
      TapeShape.buttonChamfer,
    );
    if (pressed) {
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: TapeOpacity.pressedFill),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(_KeyPainter old) =>
      old.color != color ||
      old.pressed != pressed ||
      old.strokeScale != strokeScale;
}

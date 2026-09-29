import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../design/components/presence.dart';
import '../design/theme/tape_theme.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/strokes.dart';
import '../design/tokens/typography.dart';

/// The wordmark (DESIGN.md 12): TAPEDASH in wide Saira SemiBold, tracked +6%,
/// with a single thin line of light -- the tape -- beneath it, extending past
/// both ends and fading out. Inside the app it takes the livery's accent.
///
/// [lineShare] is how much of the line is drawn, from the centre outwards, and
/// [textShare] how present the letters are; both default to fully drawn. They
/// are what the cold open (DESIGN.md 7.11) drives, and repaint without a
/// rebuild.
class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    required this.size,
    this.lineShare,
    this.textShare,
  });

  /// The letters' font size.
  final double size;

  final ValueListenable<double>? lineShare;
  final ValueListenable<double>? textShare;

  /// How far the line reaches past each end of the letters, as a share of the
  /// letters' own width.
  static const double overhang = 0.25;

  @override
  Widget build(BuildContext context) {
    final color = TapeTheme.of(context).palette.accentCore;
    final style = TapeType.wordmark(size: size, color: color);
    final letters = Text(
      'TAPEDASH',
      style: style,
      maxLines: 1,
      softWrap: false,
    );
    final measured = TextPainter(
      text: TextSpan(text: 'TAPEDASH', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final lettersWidth = measured.width;
    final lineWidth = lettersWidth * (1 + 2 * overhang);
    measured.dispose();
    final gap = TapeSpace.s2 + size * 0.1;

    return SizedBox(
      width: lineWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          textShare == null
              ? letters
              : Presence(share: textShare!, child: letters),
          SizedBox(height: gap),
          SizedBox(
            width: lineWidth,
            height: TapeStroke.fine,
            child: CustomPaint(
              painter: TapeLinePainter(color: color, share: lineShare),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tape: a fine line, brightest in the middle and fading out to both ends,
/// drawn from the centre outwards as far as [share].
class TapeLinePainter extends CustomPainter {
  TapeLinePainter({required this.color, this.share}) : super(repaint: share);

  final Color color;
  final ValueListenable<double>? share;

  Shader? _shader;
  double _shaderWidth = -1;

  /// The line's alpha at [t], 0 at one end to 1 at the other: 0 at both ends,
  /// full over the middle half. Exposed for a direct test.
  static double alphaAt(double t) {
    final d = (t - 0.5).abs() * 2; // 0 centre, 1 end
    if (d <= 0.5) return 1;
    return ((1 - d) / 0.5).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = (share?.value ?? 1).clamp(0.0, 1.0);
    if (s <= 0) return;
    if (_shader == null || _shaderWidth != size.width) {
      _shaderWidth = size.width;
      final clear = color.withValues(alpha: 0);
      _shader = LinearGradient(
        colors: [clear, color, color, clear],
        stops: const [0, 0.25, 0.75, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    }
    final half = size.width * s / 2;
    final cx = size.width / 2;
    canvas.drawRect(
      Rect.fromLTRB(cx - half, 0, cx + half, size.height),
      Paint()..shader = _shader,
    );
  }

  @override
  bool shouldRepaint(TapeLinePainter old) =>
      old.color != color || !identical(old.share, share);
}

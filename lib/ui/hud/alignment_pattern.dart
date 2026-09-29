import 'package:flutter/widgets.dart';

import '../design/tokens/hud.dart';
import '../design/tokens/strokes.dart';
import '../design/tokens/typography.dart';

/// The HUD's alignment pattern (DESIGN.md 8; Garage → HUD, parked only): a
/// full-screen test pattern with a crosshair grid, the wordmark, a large "F"
/// and an "↑ UP" marker, so the user can confirm the orientation and the
/// position in the windshield before driving.
///
/// It draws unflipped, in the HUD's own space: the [HudView]'s mirror covers
/// it exactly as it covers a layout, so what the driver sees is what the HUD
/// will show. The "F" and the arrow are what make a wrong flip obvious: an F
/// is not symmetric either way. Every stroke is at least the windshield's 5 lp
/// ([TapeStroke.hud]).
class AlignmentPattern extends StatelessWidget {
  const AlignmentPattern({
    super.key,
    required this.color,
    required this.width,
    required this.height,
  });

  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final label = height * TapeHud.labelShare;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: AlignmentGridPainter(color: color)),
          ),
          // The large F, to the left of the crosshair so the centre stays
          // clear for the lines to cross.
          Positioned(
            left: width * 0.16,
            top: height * 0.22,
            child: Text(
              'F',
              style: TapeType.numeral(
                size: height * 0.5,
                weight: TapeHud.numeralWeight,
                color: color,
                height: 1.0,
              ),
            ),
          ),
          // The up marker: an arrow, and UP beside it, at the top right.
          Positioned(
            right: width * 0.1,
            top: height * 0.2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: height * 0.14,
                  height: height * 0.2,
                  child: CustomPaint(painter: UpArrowPainter(color: color)),
                ),
                SizedBox(width: height * 0.03),
                Text(
                  'UP',
                  style: TapeType.numeral(
                    size: height * 0.12,
                    weight: TapeHud.numeralWeight,
                    color: color,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: height * 0.08,
            child: Center(
              child: Text(
                'TAPEDASH',
                style: TapeType.wordmark(size: label * 1.2, color: color),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The frame, the crosshair through the centre and a grid at the thirds, all
/// at the windshield's stroke.
class AlignmentGridPainter extends CustomPainter {
  AlignmentGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.hud;
    final inset = TapeStroke.hud / 2;
    canvas.drawRect(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - 2 * inset,
        size.height - 2 * inset,
      ),
      paint,
    );
    final cx = size.width / 2;
    final cy = size.height / 2;
    // The crosshair, through the centre.
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
    // The thirds, in the same stroke: the grid that shows a slant.
    for (final f in const [1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(size.width * f, 0),
        Offset(size.width * f, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height * f),
        Offset(size.width, size.height * f),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(AlignmentGridPainter old) => old.color != color;
}

/// The "↑" of the up marker, drawn as a path: an arrow is not in the bundled
/// subset (DESIGN.md 4.5's glyph list), and a path can be a bold 5 lp stroke.
class UpArrowPainter extends CustomPainter {
  UpArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.hud
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;
    final cx = size.width / 2;
    final head = size.width * 0.45;
    final path = Path()
      ..moveTo(cx, size.height)
      ..lineTo(cx, TapeStroke.hud)
      ..moveTo(cx - head, head + TapeStroke.hud)
      ..lineTo(cx, TapeStroke.hud)
      ..lineTo(cx + head, head + TapeStroke.hud);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(UpArrowPainter old) => old.color != color;
}

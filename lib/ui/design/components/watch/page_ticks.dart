import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../theme/tape_theme.dart';

/// The page tape of the watch (DESIGN.md 7.1, 16.5): a short row of ticks above
/// the rim's opening, one for each face the reel can reach, the one on screen lit.
/// It follows the reel's own position, so the lit tick slides between two ticks
/// as the faces do.
class PageTicks extends StatelessWidget {
  const PageTicks({
    super.key,
    required this.position,
    required this.count,
    this.tickWidth = 14,
    this.tickHeight = 3,
    this.gap = 6,
  });

  /// Where the reel is, in faces: 0 at the first.
  final ValueListenable<double> position;

  /// How many faces can be reached now: two in Motion, four parked.
  final ValueListenable<int> count;

  final double tickWidth;
  final double tickHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return ListenableBuilder(
      listenable: count,
      builder: (context, _) {
        final n = count.value;
        return SizedBox(
          width: n * tickWidth + (n - 1) * gap,
          height: tickHeight,
          child: CustomPaint(
            painter: _TicksPainter(
              position: position,
              count: n,
              lit: palette.accentCore,
              unlit: palette.etchStrong,
              tickWidth: tickWidth,
              gap: gap,
            ),
          ),
        );
      },
    );
  }
}

class _TicksPainter extends CustomPainter {
  _TicksPainter({
    required this.position,
    required this.count,
    required this.lit,
    required this.unlit,
    required this.tickWidth,
    required this.gap,
  }) : super(repaint: position);

  final ValueListenable<double> position;
  final int count;
  final Color lit;
  final Color unlit;
  final double tickWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final at = position.value;
    for (var i = 0; i < count; i++) {
      // 1 on its own face, falling to 0 a face away.
      final near = (1 - (at - i).abs()).clamp(0.0, 1.0);
      final rect = Rect.fromLTWH(
        i * (tickWidth + gap),
        0,
        tickWidth,
        size.height,
      );
      canvas.drawRect(rect, Paint()..color = Color.lerp(unlit, lit, near)!);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) =>
      old.count != count ||
      old.lit != lit ||
      old.unlit != unlit ||
      !identical(old.position, position);
}

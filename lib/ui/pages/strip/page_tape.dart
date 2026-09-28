import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/icons/icons.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';

/// The page tape (DESIGN.md 7.1): a thin row of five ticks in the bottom
/// 8 lp of the floor, the current page lit. While the car is moving, the
/// ticks of pages the motion lock keeps out show the lock in place of
/// their dash, so the rule is visible before it is met.
///
/// It is painter-led on purpose: it reads the strip's own [offset] and
/// [mode] fresh on every repaint (the telemetry tile's rule -- never a
/// colour or a state cached at build time), and repaints from their
/// merge, so a page move repaints five dashes and nothing else.
class PageTape extends StatelessWidget {
  const PageTape({
    super.key,
    required this.offset,
    required this.mode,
    required this.width,
  });

  /// The strip's page position, settled or mid-flight.
  final ValueListenable<double> offset;

  /// Parked or motion (DESIGN.md 7.2): the lock's state.
  final ValueListenable<DrivingMode> mode;

  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return CustomPaint(
      painter: PageTapePainter(offset: offset, mode: mode, palette: palette),
      size: Size(width, TapeSpace.pageTapeHeight),
    );
  }
}

class PageTapePainter extends CustomPainter {
  PageTapePainter({
    required this.offset,
    required this.mode,
    required this.palette,
  }) : super(repaint: Listenable.merge([offset, mode]));

  final ValueListenable<double> offset;
  final ValueListenable<DrivingMode> mode;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final current = offset.value.round().clamp(0, 4);
    final locked = mode.value == DrivingMode.motion;
    final dash = Paint()..style = PaintingStyle.fill;

    var x = (size.width - TapePageTape.span) / 2;
    for (var i = 0; i < 5; i++) {
      if (locked && i != 1 && i != 2) {
        paintTapeIcon(
          canvas,
          TapeIcon.lock,
          Offset(x, 0),
          TapePageTape.lockSize,
          palette.inkMid,
        );
      } else {
        dash.color = i == current ? palette.accentCore : palette.etchFaint;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 3, TapePageTape.tickWidth, 2),
            const Radius.circular(1),
          ),
          dash,
        );
      }
      x += TapePageTape.tickWidth + TapePageTape.gap;
    }
  }

  @override
  bool shouldRepaint(PageTapePainter old) =>
      old.palette != palette ||
      !identical(old.offset, offset) ||
      !identical(old.mode, mode);
}

/// The tape's geometry (DESIGN.md 7.1): five ticks in the floor's bottom
/// 8 lp.
abstract final class TapePageTape {
  static const double tickWidth = 10;
  static const double gap = 12;
  static const double span = 5 * tickWidth + 4 * gap;
  static const double lockSize = 8;
}

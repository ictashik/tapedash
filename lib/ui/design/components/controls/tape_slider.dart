import 'package:flutter/widgets.dart';

import '../../render/chamfer.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/shapes.dart';
import '../../tokens/spacing.dart';
import '../../tokens/strokes.dart';
import '../tape_label.dart';

/// A slider in the design's language: an etched track, an accent fill and a
/// chamfered thumb. It sets a value by drag or tap, one to one with the finger.
///
/// It is for the Design Lab and the developer deck, where every input of a component
/// has one (DESIGN.md 13.2), and for parked screens.
class TapeSlider extends StatelessWidget {
  const TapeSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.format,
  });

  final String label;
  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  /// How the value is written; two decimals by default.
  final String Function(double value)? format;

  /// The height of the whole control: a touch target.
  static const double height = TapeSpace.touchTarget;

  static const double _thumbWidth = 14;

  void _set(double dx, double width) {
    final track = width - _thumbWidth;
    final share = ((dx - _thumbWidth / 2) / track).clamp(0.0, 1.0);
    onChanged?.call(min + (max - min) * share);
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final text = (format ?? (v) => v.toStringAsFixed(2))(value);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _set(d.localPosition.dx, box.maxWidth),
          onPanUpdate: (d) => _set(d.localPosition.dx, box.maxWidth),
          onTapDown: (d) => _set(d.localPosition.dx, box.maxWidth),
          child: Stack(
            children: [
              Positioned(left: 0, top: 4, child: TapeLabel(label, size: 11)),
              Positioned(
                right: 0,
                top: 4,
                child: TapeLabel(text, size: 11, color: palette.accentCore),
              ),
              Positioned.fill(
                top: 20,
                child: CustomPaint(
                  painter: _SliderPainter(
                    share: max == min
                        ? 0
                        : ((value - min) / (max - min)).clamp(0.0, 1.0),
                    palette: palette,
                    enabled: onChanged != null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({
    required this.share,
    required this.palette,
    required this.enabled,
  });

  final double share;
  final TapePalette palette;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final left = TapeSlider._thumbWidth / 2;
    final right = size.width - TapeSlider._thumbWidth / 2;
    final x = left + (right - left) * share;
    final width = TapeStroke.regular * palette.strokeScale;

    canvas.drawLine(
      Offset(left, y),
      Offset(right, y),
      Paint()
        ..color = palette.track
        ..strokeWidth = width,
    );
    canvas.drawLine(
      Offset(left, y),
      Offset(x, y),
      Paint()
        ..color = enabled ? palette.accentDeep : palette.trackInactive
        ..strokeWidth = width,
    );
    final thumb = Rect.fromCenter(
      center: Offset(x, y),
      width: TapeSlider._thumbWidth,
      height: 20,
    );
    canvas.drawPath(
      Chamfer.all(thumb, TapeShape.cellChamfer),
      Paint()..color = enabled ? palette.accentCore : palette.trackInactive,
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.share != share || old.palette != palette || old.enabled != enabled;
}

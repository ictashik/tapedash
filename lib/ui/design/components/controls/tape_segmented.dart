import 'package:flutter/widgets.dart';

import '../../motion/motion_scope.dart';
import '../../motion/spring_value.dart';
import '../../render/chamfer.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/motion_tokens.dart';
import '../../tokens/opacity.dart';
import '../../tokens/shapes.dart';
import '../../tokens/spacing.dart';
import '../../tokens/strokes.dart';
import '../../tokens/typography.dart';
import 'touch_bloom.dart';

/// One choice of a [TapeSegmented].
class TapeSegment<T> {
  const TapeSegment(this.value, this.label);

  final T value;
  final String label;
}

/// The segmented selector (DESIGN.md 6.14): a row of chamfered cells, of which the
/// selected one lights. The light moves from cell to cell on `spring.snap`.
class TapeSegmented<T> extends StatefulWidget {
  const TapeSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = TapeSpace.touchTarget,
  });

  final List<TapeSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  final double height;

  @override
  State<TapeSegmented<T>> createState() => _TapeSegmentedState<T>();
}

class _TapeSegmentedState<T> extends State<TapeSegmented<T>> {
  SpringValue? _index;

  int get _selected {
    final i = widget.segments.indexWhere((s) => s.value == widget.value);
    return i < 0 ? 0 : i;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final spec = TapeTheme.of(context).spring(TapeSprings.snap);
    if (_index == null) {
      _index = SpringValue(
        clock: MotionScope.of(context),
        spec: spec,
        initial: _selected.toDouble(),
      );
    } else {
      _index!.setSpec(spec);
    }
  }

  @override
  void didUpdateWidget(TapeSegmented<T> old) {
    super.didUpdateWidget(old);
    _index!.retarget(_selected.toDouble());
  }

  @override
  void dispose() {
    _index?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final count = widget.segments.length;
    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        painter: _SegmentedPainter(
          index: _index!,
          count: count,
          palette: palette,
        ),
        child: Row(
          children: [
            for (var i = 0; i < count; i++)
              Expanded(
                child: TouchBloom(
                  enabled: widget.onChanged != null,
                  onTap: () => widget.onChanged?.call(widget.segments[i].value),
                  builder: (context, pressed) => Center(
                    child: Text(
                      widget.segments[i].label.toUpperCase(),
                      style: TapeType.button(
                        size: 14,
                        color: i == _selected
                            ? palette.accentCore
                            : palette.inkDim,
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedPainter extends CustomPainter {
  _SegmentedPainter({
    required this.index,
    required this.count,
    required this.palette,
  }) : super(repaint: index);

  final SpringValue index;
  final int count;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = TapeStroke.fine * palette.strokeScale;
    final cell = size.width / count;
    final outer = Offset.zero & size;

    // The frame, and the hairlines between the cells.
    canvas.drawPath(
      Chamfer.all(outer.deflate(stroke / 2), TapeShape.cellChamfer),
      Paint()
        ..color = palette.etchStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    for (var i = 1; i < count; i++) {
      canvas.drawLine(
        Offset(i * cell, size.height * 0.25),
        Offset(i * cell, size.height * 0.75),
        Paint()
          ..color = palette.etch
          ..strokeWidth = TapeStroke.fine,
      );
    }

    // The lit cell.
    final left = index.value * cell;
    final lit = Rect.fromLTWH(left, 0, cell, size.height).deflate(stroke / 2);
    final path = Chamfer.all(lit, TapeShape.cellChamfer);
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.accentCore.withValues(
          alpha: TapeOpacity.selectedFill,
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.accentCore
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_SegmentedPainter old) =>
      old.count != count || old.palette != palette;
}

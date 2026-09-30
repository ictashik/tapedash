import 'package:flutter/widgets.dart';

import '../../icons/icons.dart';
import '../../render/chamfer.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/motion_tokens.dart';
import '../../tokens/opacity.dart';
import '../../tokens/shapes.dart';
import '../../tokens/spacing.dart';
import '../../tokens/strokes.dart';
import '../../tokens/typography.dart';
import 'tape_segmented.dart';
import 'touch_bloom.dart';

/// The segmented selector for more choices than fit side by side (DESIGN.md
/// 6.14): the same chamfered frame and lit cell as [TapeSegmented], but each cell
/// is as wide as its label and the row scrolls sideways. The selected cell is
/// brought into view, and a chevron at an edge says there is more that way.
///
/// Review's metric selector is one: SPEED, RPM, THROTTLE, LOAD, COOLANT, VOLTS and
/// ₹/KM do not fit a 640 lp screen at 14 lp a label in equal cells.
class TapeScrollSegmented<T> extends StatefulWidget {
  const TapeScrollSegmented({
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
  State<TapeScrollSegmented<T>> createState() => _TapeScrollSegmentedState<T>();
}

class _TapeScrollSegmentedState<T> extends State<TapeScrollSegmented<T>> {
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _keys = [];
  bool _more = false;
  bool _less = false;

  int get _selected {
    final i = widget.segments.indexWhere((s) => s.value == widget.value);
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onScroll();
      _reveal();
    });
  }

  @override
  void didUpdateWidget(TapeScrollSegmented<T> old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final more = _scroll.position.pixels < _scroll.position.maxScrollExtent - 1;
    final less = _scroll.position.pixels > 1;
    if (more != _more || less != _less) {
      setState(() {
        _more = more;
        _less = less;
      });
    }
  }

  /// Scrolls the selected cell into view.
  void _reveal() {
    if (!mounted || _keys.length <= _selected) return;
    final context = _keys[_selected].currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: TapeDurations.quick,
      curve: TapeCurves.enter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    while (_keys.length < widget.segments.length) {
      _keys.add(GlobalKey());
    }
    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        painter: _FramePainter(palette: palette),
        child: Stack(
          children: [
            NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _onScroll(),
                );
                return false;
              },
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: Row(
                  children: [
                    for (var i = 0; i < widget.segments.length; i++)
                      KeyedSubtree(
                        key: _keys[i],
                        child: _Cell(
                          label: widget.segments[i].label,
                          selected: i == _selected,
                          last: i == widget.segments.length - 1,
                          height: widget.height,
                          palette: palette,
                          onTap: widget.onChanged == null
                              ? null
                              : () =>
                                    widget.onChanged!(widget.segments[i].value),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_less)
              Positioned(
                left: 2,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Transform.flip(
                      flipX: true,
                      child: TapeIconView(
                        TapeIcon.chevron,
                        size: 14,
                        color: palette.accentCore,
                      ),
                    ),
                  ),
                ),
              ),
            if (_more)
              Positioned(
                right: 2,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Center(
                    child: TapeIconView(
                      TapeIcon.chevron,
                      size: 14,
                      color: palette.accentCore,
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

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.selected,
    required this.last,
    required this.height,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool last;
  final double height;
  final TapePalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TouchBloom(
      enabled: onTap != null,
      onTap: onTap,
      builder: (context, pressed) => CustomPaint(
        painter: _CellPainter(selected: selected, last: last, palette: palette),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: TapeSpace.s3),
            child: Center(
              child: Text(
                label.toUpperCase(),
                style: TapeType.button(
                  size: 14,
                  color: selected ? palette.accentCore : palette.inkDim,
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({required this.palette});

  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = TapeStroke.fine * palette.strokeScale;
    canvas.drawPath(
      Chamfer.all(
        (Offset.zero & size).deflate(stroke / 2),
        TapeShape.cellChamfer,
      ),
      Paint()
        ..color = palette.etchStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.palette != palette;
}

class _CellPainter extends CustomPainter {
  _CellPainter({
    required this.selected,
    required this.last,
    required this.palette,
  });

  final bool selected;
  final bool last;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = TapeStroke.fine * palette.strokeScale;
    if (!selected && !last) {
      canvas.drawLine(
        Offset(size.width, size.height * 0.25),
        Offset(size.width, size.height * 0.75),
        Paint()
          ..color = palette.etch
          ..strokeWidth = TapeStroke.fine,
      );
    }
    if (!selected) return;
    final path = Chamfer.all(
      (Offset.zero & size).deflate(stroke / 2),
      TapeShape.cellChamfer,
    );
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
  bool shouldRepaint(_CellPainter old) =>
      old.selected != selected || old.last != last || old.palette != palette;
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../motion/motion_clock.dart';
import '../../motion/spring_value.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/motion_tokens.dart';
import '../../tokens/shapes.dart';
import '../../tokens/typography.dart';
import '../../tokens/watch.dart';
import 'watch_face.dart';

/// One row of a [WatchWheel].
@immutable
class WheelRow {
  const WheelRow({
    required this.label,
    this.value,
    this.lit = false,
    this.critical = false,
    this.chevron = false,
  });

  /// The row's name, set in UPPERCASE.
  final String label;

  /// A second, smaller line: what the row is set to.
  final String? value;

  /// The row is the chosen one of a choice: a small lit cell before it.
  final bool lit;

  /// The row cannot be undone: it is tinted `critical`.
  final bool critical;

  /// The row opens another screen.
  final bool chevron;
}

/// The watch's list, choice and dial in one (DESIGN.md 16.7): a column of rows with
/// the chosen one at the centre, full size and in the accent between two brackets,
/// the ones above and below at 70% and dimmer. The bezel, a vertical swipe or a tap
/// on a neighbour moves the choice one row on `spring.gauge`; a tap on the centre
/// row chooses it.
///
/// It has [itemCount] rows and builds only those on screen, so a dial of a
/// thousand values costs no more than a menu of four. A turn of the bezel in
/// quick succession steps [fastStride] rows a detent instead of one, which is how a
/// price is dialled from ₹60 to ₹110 without a hundred clicks.
class WatchWheel extends StatefulWidget {
  const WatchWheel({
    super.key,
    required this.itemCount,
    required this.rowAt,
    required this.face,
    required this.motion,
    required this.onChoose,
    this.initial = 0,
    this.title,
    this.rotary,
    this.fastStride = 1,
    this.onMoved,
  });

  final int itemCount;
  final WheelRow Function(int index) rowAt;
  final WatchFace face;
  final MotionClock motion;

  /// Called with the row the centre was tapped on.
  final ValueChanged<int> onChoose;

  /// Called with the row the wheel has come to rest on (a dial's value).
  final ValueChanged<int>? onMoved;

  final int initial;

  /// A label in the crown: where this wheel is.
  final String? title;

  final Stream<int>? rotary;
  final int fastStride;

  @override
  State<WatchWheel> createState() => WatchWheelState();
}

class WatchWheelState extends State<WatchWheel> {
  late SpringValue _at;
  late double _raw = widget.initial.toDouble();
  StreamSubscription<int>? _bezel;
  Duration _lastTurn = Duration.zero;
  int _reported = -1;

  @override
  void initState() {
    super.initState();
    _at = SpringValue(
      clock: widget.motion,
      spec: TapeSprings.gauge,
      initial: widget.initial.toDouble(),
    )..addListener(_onMove);
    _reported = widget.initial;
    _listen();
  }

  @override
  void didUpdateWidget(WatchWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rotary, widget.rotary)) _listen();
  }

  @override
  void dispose() {
    _bezel?.cancel();
    _at
      ..removeListener(_onMove)
      ..dispose();
    super.dispose();
  }

  void _listen() {
    _bezel?.cancel();
    _bezel = widget.rotary?.listen(_onBezel);
  }

  /// The row at the centre, once settled.
  int get selected => _at.value.round().clamp(0, widget.itemCount - 1);

  void _move(double to) {
    _raw = to.clamp(0.0, (widget.itemCount - 1).toDouble());
    _at
      ..setSpec(TapeSprings.gauge)
      ..retarget(_raw.roundToDouble());
  }

  void _onBezel(int detents) {
    final now = widget.motion.now;
    final quick =
        now - _lastTurn < TapeWatch.quickTurn && _lastTurn != Duration.zero;
    _lastTurn = now;
    final stride = quick ? widget.fastStride : 1;
    _move(_raw.roundToDouble() + (detents > 0 ? stride : -stride));
  }

  void _onMove() {
    if (_at.isSettled) {
      final i = selected;
      if (i != _reported) {
        _reported = i;
        widget.onMoved?.call(i);
      }
    }
  }

  void _onDragStart(DragStartDetails details) {
    _at.setSpec(TapeSprings.gauge);
    _raw = _at.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _raw -= details.primaryDelta! / TapeWatch.wheelRow;
    _raw = _raw.clamp(0.0, (widget.itemCount - 1).toDouble());
    _at.retarget(_raw);
  }

  void _onDragEnd(DragEndDetails details) {
    final carry = -details.velocity.pixelsPerSecond.dy / TapeWatch.wheelRow;
    // A fling carries it on a little, in rows, and never past an end.
    _move(_raw + carry * 0.18);
  }

  void _onTap(TapUpDetails details) {
    final dy = details.localPosition.dy - widget.face.radius;
    final rows = (dy / TapeWatch.wheelRow).round();
    if (rows == 0) {
      widget.onChoose(selected);
    } else {
      _move(_at.value.roundToDouble() + rows);
    }
  }

  @override
  Widget build(BuildContext context) {
    final face = widget.face;
    final palette = TapeTheme.of(context).palette;
    final type = face.type;
    return SizedBox.square(
      dimension: face.diameter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onTapUp: _onTap,
        child: Stack(
          children: [
            if (widget.title != null)
              Positioned(
                top: face.crownY - type.label / 2,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    widget.title!.toUpperCase(),
                    style: TapeType.label(
                      size: type.label,
                      color: palette.label,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _at,
                builder: (context, _) => _rows(context),
              ),
            ),
            // The brackets round the chosen row.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _BracketPainter(
                    face: face,
                    colour: palette.accentCore,
                    width: face.roomAt(face.radius, TapeWatch.wheelRow) * 0.92,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rows(BuildContext context) {
    final face = widget.face;
    final palette = TapeTheme.of(context).palette;
    final type = face.type;
    final at = _at.value;
    final first = math.max(0, (at - 1.6).ceil());
    final last = math.min(widget.itemCount - 1, (at + 1.6).floor());
    final children = <Widget>[];
    for (var i = first; i <= last; i++) {
      final d = i - at;
      final near = (1 - d.abs()).clamp(0.0, 1.0);
      final scale =
          TapeWatch.wheelNeighbourScale +
          (1 - TapeWatch.wheelNeighbourScale) * near;
      final fade = (1 - (d.abs() / 1.6)).clamp(0.0, 1.0);
      final row = widget.rowAt(i);
      final base = row.critical
          ? palette.critical
          : Color.lerp(palette.inkDim, palette.accentCore, near)!;
      final colour = base.withValues(alpha: base.a * (0.25 + 0.75 * fade));
      children.add(
        Positioned(
          left: 0,
          right: 0,
          top: face.radius + d * TapeWatch.wheelRow - TapeWatch.wheelRow / 2,
          height: TapeWatch.wheelRow,
          child: Transform.scale(
            scale: scale,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (row.lit) ...[
                        _LitCell(
                          colour: palette.accentCore,
                          size: type.label * 0.7,
                        ),
                        SizedBox(width: type.label * 0.5),
                      ],
                      Text(
                        row.label.toUpperCase(),
                        style: TapeType.button(
                          size: type.secondary,
                          color: colour,
                        ),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ],
                  ),
                  if (row.value != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        row.value!.toUpperCase(),
                        style: TapeType.label(
                          size: type.label,
                          color: palette.inkMid.withValues(
                            alpha: palette.inkMid.a * (0.25 + 0.75 * fade),
                          ),
                        ),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Stack(children: children);
  }
}

class _LitCell extends StatelessWidget {
  const _LitCell({required this.colour, required this.size});

  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(decoration: BoxDecoration(color: colour)),
  );
}

class _BracketPainter extends CustomPainter {
  _BracketPainter({
    required this.face,
    required this.colour,
    required this.width,
  });

  final WatchFace face;
  final Color colour;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final arm = TapeShape.bracketArm;
    final h = TapeWatch.wheelRow;
    final rect = Rect.fromCenter(center: face.centre, width: width, height: h);
    final paint = Paint()
      ..color = colour.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.miter;
    final path = Path()
      ..moveTo(rect.left, rect.top + arm)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.left + arm, rect.top)
      ..moveTo(rect.right - arm, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + arm)
      ..moveTo(rect.right, rect.bottom - arm)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right - arm, rect.bottom)
      ..moveTo(rect.left + arm, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.bottom - arm);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BracketPainter old) =>
      old.colour != colour || old.width != width || old.face != face;
}

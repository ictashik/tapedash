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
import '../tape_label.dart';
import 'tape_button.dart' show ButtonTone;

/// Slide to confirm (DESIGN.md 6.14, 7.8, 7.10): for what cannot be undone. A
/// chamfered thumb rides a track under the label; it takes a deliberate drag all
/// the way across, and a release short of the end springs back and does nothing,
/// so a stray touch never clears a fault code or deletes the trip log.
///
/// Parked screens only. With [onConfirmed] null it is disabled: it does not move.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.tone = ButtonTone.critical,
  });

  final String label;

  /// Called once the thumb is dragged home and let go. Null disables the control.
  final VoidCallback? onConfirmed;
  final ButtonTone tone;

  /// How far across counts as home, as a share of the track.
  static const double threshold = 0.92;

  @override
  State<SlideToConfirm> createState() => SlideToConfirmState();
}

class SlideToConfirmState extends State<SlideToConfirm> {
  SpringValue? _position;
  double _travel = 1;

  /// How far the thumb is, 0 to 1.
  double get position => _position?.value ?? 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final spec = TapeTheme.of(context).spring(TapeSprings.snap);
    if (_position == null) {
      _position = SpringValue(
        clock: MotionScope.of(context),
        spec: spec,
        initial: 0,
      );
    } else {
      _position!.setSpec(spec);
    }
  }

  @override
  void dispose() {
    _position?.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onConfirmed != null;

  void _onUpdate(DragUpdateDetails d) {
    if (!_enabled) return;
    final at = (_position!.value + d.delta.dx / _travel).clamp(0.0, 1.0);
    _position!.jumpTo(at);
  }

  void _onEnd([DragEndDetails? _]) {
    if (!_enabled) return;
    final home = _position!.value >= SlideToConfirm.threshold;
    // Home or not, the thumb goes back to the start; home first says so.
    _position!.retarget(0);
    if (home) widget.onConfirmed!();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final color = _enabled
        ? widget.tone.colorIn(palette)
        : palette.trackInactive;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.isFinite ? box.maxWidth : 320.0;
        _travel = (width - _thumbWidth).clamp(1.0, double.infinity);
        return Semantics(
          button: true,
          enabled: _enabled,
          label: widget.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: _onEnd,
            onHorizontalDragCancel: _onEnd,
            child: SizedBox(
              width: width,
              height: TapeShape.buttonHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TrackPainter(
                        position: _position!,
                        color: color,
                        thumbWidth: _thumbWidth,
                        strokeScale: palette.strokeScale,
                      ),
                    ),
                  ),
                  Center(
                    child: TapeLabel(
                      widget.label,
                      size: 13,
                      color: _enabled ? palette.inkMid : palette.inkDim,
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ThumbPainter(
                        position: _position!,
                        color: color,
                        palette: palette,
                        thumbWidth: _thumbWidth,
                        travel: _travel,
                        enabled: _enabled,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static const double _thumbWidth = TapeSpace.touchTarget + TapeSpace.s4;
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.position,
    required this.color,
    required this.thumbWidth,
    required this.strokeScale,
  }) : super(repaint: position);

  final SpringValue position;
  final Color color;
  final double thumbWidth;
  final double strokeScale;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = TapeStroke.fine * strokeScale;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final path = Chamfer.button(rect, TapeShape.buttonChamfer);
    // What the thumb has covered so far, as a wash of the tone (its right end is
    // under the thumb, so it is not shaped).
    final reach = thumbWidth + (size.width - thumbWidth) * position.value;
    canvas.drawPath(
      Chamfer.button(
        Rect.fromLTWH(0, 0, reach, size.height).deflate(stroke / 2),
        TapeShape.buttonChamfer,
      ),
      Paint()..color = color.withValues(alpha: TapeOpacity.pressedFill),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.color != color || old.strokeScale != strokeScale;
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter({
    required this.position,
    required this.color,
    required this.palette,
    required this.thumbWidth,
    required this.travel,
    required this.enabled,
  }) : super(repaint: position);

  final SpringValue position;
  final Color color;
  final TapePalette palette;
  final double thumbWidth;
  final double travel;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final left = travel * position.value;
    final rect = Rect.fromLTWH(left, 0, thumbWidth, size.height).deflate(2);
    canvas.drawPath(
      Chamfer.button(rect, TapeShape.buttonChamfer),
      Paint()..color = color,
    );
    // Two chevrons, pointing the way it goes, in the canvas colour.
    final mid = rect.center;
    final chevron = Paint()
      ..color = palette.canvas
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.regular * palette.strokeScale
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;
    for (final dx in const [-6.0, 6.0]) {
      final path = Path()
        ..moveTo(mid.dx + dx - 4, mid.dy - 8)
        ..lineTo(mid.dx + dx + 4, mid.dy)
        ..lineTo(mid.dx + dx - 4, mid.dy + 8);
      canvas.drawPath(path, chevron);
    }
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.color != color ||
      old.travel != travel ||
      old.enabled != enabled ||
      old.palette != palette;
}

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../motion/motion_scope.dart';
import '../../motion/spring_value.dart';
import '../../render/chamfer.dart';
import '../../render/glow_cache.dart';
import '../../render/render_kit.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/motion_tokens.dart';
import '../../tokens/opacity.dart';
import '../../tokens/shapes.dart';
import '../../tokens/spacing.dart';
import '../../tokens/strokes.dart';
import 'touch_bloom.dart';

/// The light-switch toggle (DESIGN.md 6.14): a 48 by 26 lp track whose "on" cell
/// lights with a halo, moving on `spring.snap`. It is not a Material Switch.
class TapeToggle extends StatefulWidget {
  const TapeToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;

  /// Null disables the toggle.
  final ValueChanged<bool>? onChanged;

  final String? semanticLabel;

  @override
  State<TapeToggle> createState() => _TapeToggleState();
}

class _TapeToggleState extends State<TapeToggle> {
  SpringValue? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = TapeTheme.of(context);
    final spec = theme.spring(TapeSprings.snap);
    if (_position == null) {
      _position = SpringValue(
        clock: MotionScope.of(context),
        spec: spec,
        initial: widget.value ? 1 : 0,
      );
    } else {
      _position!.setSpec(spec);
    }
  }

  @override
  void didUpdateWidget(TapeToggle old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _position!.retarget(widget.value ? 1 : 0);
  }

  @override
  void dispose() {
    _position?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final kit = TapeRenderScope.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final enabled = widget.onChanged != null;
    final halo = kit.glows.get(
      GlowSpec(
        shape: GlowShape.bar,
        width: _cellWidth,
        height: _cellHeight,
        sigma: 5,
        devicePixelRatio: dpr,
      ),
    );

    // The touch target is 48 tall, and the track sits in the middle of it.
    // One node for the switch: its label and state, and the tap that turns it.
    return MergeSemantics(
      child: Semantics(
        toggled: widget.value,
        label: widget.semanticLabel,
        enabled: enabled,
        child: TouchBloom(
          enabled: enabled,
          onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
          builder: (context, pressed) => SizedBox(
            width: TapeShape.toggleWidth + TapeSpace.s2 * 2,
            height: TapeSpace.touchTarget,
            child: CustomPaint(
              painter: _TogglePainter(
                position: _position!,
                palette: theme.palette,
                halo: halo,
                enabled: enabled,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const double _cellWidth = 20;
  static const double _cellHeight = 18;
}

class _TogglePainter extends CustomPainter {
  _TogglePainter({
    required this.position,
    required this.palette,
    required this.halo,
    required this.enabled,
  }) : super(repaint: position);

  final SpringValue position;
  final TapePalette palette;
  final GlowSprite halo;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final t = position.value.clamp(0.0, 1.0);
    final track = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: TapeShape.toggleWidth,
      height: TapeShape.toggleHeight,
    );
    final stroke = TapeStroke.fine * palette.strokeScale;
    final on = enabled ? palette.accentCore : palette.trackInactive;
    final outline = Color.lerp(palette.etchStrong, on, t)!;

    final trackPath = Chamfer.all(
      track.deflate(stroke / 2),
      TapeShape.cellChamfer,
    );
    canvas.drawPath(
      trackPath,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    const inset = 4.0;
    final travel =
        TapeShape.toggleWidth - 2 * inset - _TapeToggleState._cellWidth;
    final cell = Rect.fromLTWH(
      track.left + inset + travel * t,
      track.top + (TapeShape.toggleHeight - _TapeToggleState._cellHeight) / 2,
      _TapeToggleState._cellWidth,
      _TapeToggleState._cellHeight,
    );
    final lit = Color.lerp(palette.trackInactive, on, t)!;

    final strength = t * TapeOpacity.toggleHalo * palette.haloScale;
    if (strength > 0.01 && enabled) {
      halo.draw(
        canvas,
        cell.left,
        cell.top,
        palette.accentGlow.withValues(alpha: strength),
        Paint()..blendMode = ui.BlendMode.plus,
      );
    }
    canvas.drawPath(
      Chamfer.all(cell, TapeShape.cellChamfer),
      Paint()
        ..color = enabled ? lit : lit.withValues(alpha: TapeOpacity.disabled),
    );
  }

  @override
  bool shouldRepaint(_TogglePainter old) =>
      old.palette != palette || old.enabled != enabled || old.halo != halo;
}

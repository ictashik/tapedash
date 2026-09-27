import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../motion/motion_clock.dart';
import '../../motion/motion_scope.dart';
import '../../render/glow_cache.dart';
import '../../render/render_kit.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/motion_tokens.dart';
import '../../tokens/opacity.dart';
import '../../tokens/shapes.dart';

/// Touch feedback (DESIGN.md 6.16): a cached radial glow at the touch point that
/// grows from 0.6 to 1.4 of its size while fading from 35% to nothing, over
/// `dur.quick`, on the expo-out curve. It replaces every ripple.
///
/// It wraps a widget, calls [onTap], and tells its [builder] whether the touch is
/// down, so the child can draw its pressed state.
class TouchBloom extends StatefulWidget {
  const TouchBloom({
    super.key,
    required this.builder,
    this.onTap,
    this.enabled = true,
    this.color,
  });

  final Widget Function(BuildContext context, bool pressed) builder;
  final VoidCallback? onTap;
  final bool enabled;

  /// The colour of the glow: the accent's by default.
  final Color? color;

  @override
  State<TouchBloom> createState() => _TouchBloomState();
}

/// One bloom in flight.
class _Bloom {
  Offset position = Offset.zero;
  double age = 0;
  bool active = false;
}

class _TouchBloomState extends State<TouchBloom> implements MotionDriven {
  final _Notifier _repaint = _Notifier();
  final List<_Bloom> _blooms = List.generate(4, (_) => _Bloom());
  bool _pressed = false;
  MotionClock? _clock;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock = MotionScope.of(context);
  }

  void _down(TapDownDetails details) {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
    final bloom = _blooms.firstWhere(
      (b) => !b.active,
      orElse: () => _blooms[0],
    );
    bloom
      ..position = details.localPosition
      ..age = 0
      ..active = true;
    _clock?.attach(this);
    _repaint.ping();
  }

  void _up() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  bool advance(double dt, Duration time) {
    var any = false;
    final total = TapeDurations.quick.inMicroseconds / 1e6;
    for (final bloom in _blooms) {
      if (!bloom.active) continue;
      bloom.age += dt;
      if (bloom.age >= total) {
        bloom.active = false;
      } else {
        any = true;
      }
    }
    _repaint.ping();
    return any;
  }

  @override
  void dispose() {
    _clock?.detach(this);
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final kit = TapeRenderScope.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final color = widget.color ?? theme.palette.accentGlow;
    final sprite = kit.glows.get(
      GlowSpec(
        shape: GlowShape.disc,
        width: TapeShape.touchBloomRadius * 0.3,
        height: TapeShape.touchBloomRadius * 0.3,
        sigma: TapeShape.touchBloomRadius * 0.3,
        devicePixelRatio: dpr,
      ),
    );
    final live = widget.enabled && widget.onTap != null;
    return Semantics(
      button: true,
      enabled: live,
      onTap: live ? widget.onTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _down,
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        onTap: widget.enabled ? widget.onTap : null,
        child: CustomPaint(
          foregroundPainter: _BloomPainter(_repaint, _blooms, sprite, color),
          child: widget.builder(context, _pressed),
        ),
      ),
    );
  }
}

class _Notifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _BloomPainter extends CustomPainter {
  _BloomPainter(Listenable repaint, this.blooms, this.sprite, this.color)
    : super(repaint: repaint);

  final List<_Bloom> blooms;
  final GlowSprite sprite;
  final Color color;
  final ui.Paint _paint = ui.Paint()
    ..blendMode = ui.BlendMode.plus
    ..filterQuality = ui.FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    final total = TapeDurations.quick.inMicroseconds / 1e6;
    for (final bloom in blooms) {
      if (!bloom.active) continue;
      final t = TapeCurves.enter.transform((bloom.age / total).clamp(0.0, 1.0));
      final scale =
          TapeMotion.bloomScaleFrom +
          (TapeMotion.bloomScaleTo - TapeMotion.bloomScaleFrom) * t;
      final alpha = TapeOpacity.bloomStart * (1 - t);
      canvas.save();
      canvas.translate(bloom.position.dx, bloom.position.dy);
      canvas.scale(scale);
      sprite.drawCentered(
        canvas,
        Offset.zero,
        color.withValues(alpha: alpha),
        _paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BloomPainter old) =>
      old.sprite != sprite || old.color != color;
}

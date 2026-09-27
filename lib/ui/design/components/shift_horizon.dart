import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../motion/motion_clock.dart';
import '../motion/motion_scope.dart';
import '../motion/phosphor.dart';
import '../motion/smoothing_pipeline.dart';
import '../render/chamfer.dart';
import '../render/glow_cache.dart';
import '../render/render_kit.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/glow.dart';
import '../tokens/tach.dart';

/// The shift horizon (DESIGN.md 6.4, signature moment 4): a thin light band
/// across the top edge. On a manual profile it is a shift-light bar, 24
/// chamfered segments per side that fill from the outer edges inward as rpm
/// approaches the shift point, stepping accent → caution → critical by
/// position, and flashing critical at 3 Hz at or above the shift point.
///
/// On a CVT or automatic profile the shift light is off by default; instead
/// the horizon shows a faint accent glow whose width follows rpm, "like the
/// engine breathing".
class ShiftHorizon extends StatefulWidget {
  const ShiftHorizon({
    super.key,
    required this.rpm,
    required this.width,
    required this.heightReference,
    this.shiftRpm = TapeTach.defaultRedlineRpm,
    this.maxRpm = TapeTach.defaultMaxRpm,
    this.shiftLightEnabled = true,
  });

  /// The rpm signal, smoothed with `spring.needle` (DESIGN.md 5.3), the same
  /// as the tach arc's.
  final SmoothedSignal rpm;

  /// How wide the band is, in logical pixels: normally the full screen width.
  final double width;

  /// H, for the band's height (DESIGN.md 6.4's 0.018H).
  final double heightReference;

  final double shiftRpm;
  final double maxRpm;

  /// False for a CVT or automatic profile (DESIGN.md 6.4): the segments never
  /// light, and the horizon breathes instead.
  final bool shiftLightEnabled;

  double get height => TapeShiftHorizon.heightShareOfHeight * heightReference;

  @override
  State<ShiftHorizon> createState() => ShiftHorizonState();
}

class ShiftHorizonState extends State<ShiftHorizon> implements MotionDriven {
  late MotionClock _motion;
  PhosphorBank? bank;
  int? _lastLitCount;
  bool _attached = false;
  final ShiftRepaintPing repaint = ShiftRepaintPing();

  static int get _totalSegments => TapeShiftHorizon.segmentsPerSide * 2;

  @override
  void initState() {
    super.initState();
    widget.rpm.addListener(_onRpm);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionScope.of(context);
    if (widget.shiftLightEnabled) {
      bank ??= PhosphorBank(clock: _motion, count: _totalSegments);
    }
    _onRpm();
  }

  @override
  void didUpdateWidget(ShiftHorizon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rpm, widget.rpm)) {
      oldWidget.rpm.removeListener(_onRpm);
      widget.rpm.addListener(_onRpm);
    }
    _onRpm();
  }

  void _onRpm() {
    if (!widget.shiftLightEnabled) return;
    if (widget.rpm.hasValue && !_attached) {
      _attached = true;
      _motion.attach(this);
    }
  }

  /// The fraction of the way from "starts filling" to the shift point, 0 to 1.
  double fillProgress() {
    final start = widget.shiftRpm - TapeShiftHorizon.fillsOverRpm;
    final value = widget.rpm.value;
    return ((value - start) / TapeShiftHorizon.fillsOverRpm).clamp(0.0, 1.0);
  }

  bool get atOrAboveShift => widget.rpm.value >= widget.shiftRpm;

  @override
  bool advance(double dt, Duration time) {
    final bank = this.bank;
    if (bank == null || !widget.shiftLightEnabled) return false;
    final progress = fillProgress();
    final litFloat = progress * TapeShiftHorizon.segmentsPerSide;
    final litCount = litFloat.floor().clamp(
      0,
      TapeShiftHorizon.segmentsPerSide,
    );
    if (_lastLitCount != litCount) {
      final last = _lastLitCount ?? 0;
      final lo = math.min(last, litCount);
      final hi = math.max(last, litCount);
      for (var i = lo; i < hi; i++) {
        final target = i < litCount ? 1.0 : 0.0;
        bank.setTarget(TapeShiftHorizon.segmentsPerSide - 1 - i, target);
        bank.setTarget(TapeShiftHorizon.segmentsPerSide + i, target);
      }
      _lastLitCount = litCount;
    }
    final fraction = (litFloat - litFloat.floorToDouble()).clamp(0.0, 1.0);
    final edgeIndex = litCount.clamp(0, TapeShiftHorizon.segmentsPerSide - 1);
    if (litCount < TapeShiftHorizon.segmentsPerSide) {
      bank.setTarget(
        TapeShiftHorizon.segmentsPerSide - 1 - edgeIndex,
        fraction,
      );
      bank.setTarget(TapeShiftHorizon.segmentsPerSide + edgeIndex, fraction);
    }
    repaint.ping();
    return true;
  }

  @override
  void dispose() {
    widget.rpm.removeListener(_onRpm);
    if (_attached) _motion.detach(this);
    bank?.dispose();
    repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final kit = TapeRenderScope.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final glow = kit.glows.get(
      GlowSpec(
        shape: GlowShape.bar,
        width: widget.width * 0.5,
        height: widget.height,
        sigma: widget.height * 0.4,
        devicePixelRatio: dpr,
        resolution: theme.profile.halosAtHalfResolution
            ? TapeGlow.liteResolution
            : 1,
      ),
    );
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: CustomPaint(
          painter: ShiftHorizonPainter(
            listenable: widget.shiftLightEnabled
                ? Listenable.merge([bank!, repaint])
                : widget.rpm,
            state: this,
            palette: theme.palette,
            motion: _motion,
            glow: glow,
          ),
        ),
      ),
    );
  }
}

/// A ping with no value attached, for a repaint trigger that isn't a value
/// change (the flash, and the segment sync loop).
class ShiftRepaintPing extends ChangeNotifier {
  void ping() => notifyListeners();
}

class ShiftHorizonPainter extends CustomPainter {
  ShiftHorizonPainter({
    required Listenable listenable,
    required this.state,
    required this.palette,
    required this.motion,
    required this.glow,
  }) : super(repaint: listenable);

  final ShiftHorizonState state;
  final TapePalette palette;
  final MotionClock motion;
  final GlowSprite glow;

  final Paint _fillPaint = Paint()..style = ui.PaintingStyle.fill;
  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    if (!state.widget.shiftLightEnabled) {
      _paintBreathing(canvas, size);
      return;
    }

    final bank = state.bank;
    if (bank == null) return;
    final perSide = TapeShiftHorizon.segmentsPerSide;
    final slotWidth = (size.width / 2) / perSide;
    final segWidth = slotWidth * 0.8;
    final gap = slotWidth - segWidth;
    final flashOn = state.atOrAboveShift ? _flashOn() : true;

    for (var side = 0; side < 2; side++) {
      for (var i = 0; i < perSide; i++) {
        final index = side == 0 ? perSide - 1 - i : perSide + i;
        final level = bank.levels[index];
        if (level <= 0.001) continue;
        // i counts outer (0) to inner (perSide-1) regardless of side.
        final positionShare = i / perSide;
        final color = _colorFor(positionShare);
        final left = side == 0
            ? i * slotWidth + gap / 2
            : size.width - (i + 1) * slotWidth + gap / 2;
        final rect = Rect.fromLTWH(left, 0, segWidth, size.height);
        final alpha = state.atOrAboveShift ? (flashOn ? 1.0 : 0.0) : level;
        if (alpha <= 0.001) continue;
        _fillPaint.color = color.withValues(alpha: alpha);
        Chamfer.polygonInto(_path, [
          rect.topLeft,
          rect.topRight,
          rect.bottomRight,
          rect.bottomLeft,
        ], math.min(segWidth, size.height) * 0.22);
        canvas.drawPath(_path, _fillPaint);
      }
    }
  }

  Color _colorFor(double positionShare) {
    if (positionShare < TapeShiftHorizon.accentShare) return palette.accentCore;
    if (positionShare <
        TapeShiftHorizon.accentShare + TapeShiftHorizon.cautionShare) {
      return palette.caution;
    }
    return palette.critical;
  }

  bool _flashOn() {
    final seconds = motion.now.inMicroseconds / 1e6;
    final phase = seconds * TapeShiftHorizon.flashHz * 2;
    return phase.floor().isEven;
  }

  /// How wide the breathing glow is drawn, as a share of its full reference
  /// width, for [rpm] out of [maxRpm] (DESIGN.md 6.4). Exposed so the mapping
  /// itself has a direct test, since sampling it back out of rendered pixels
  /// is the fragile way to check it.
  static double widthShareFor(double rpm, double maxRpm) {
    final share = maxRpm <= 0 ? 0.0 : (rpm / maxRpm).clamp(0.0, 1.0);
    return TapeShiftHorizon.breathingMinShare +
        (TapeShiftHorizon.breathingMaxShare -
                TapeShiftHorizon.breathingMinShare) *
            share;
  }

  void _paintBreathing(Canvas canvas, Size size) {
    final rpm = state.widget.rpm;
    if (!rpm.hasValue) return;
    final widthShare = widthShareFor(rpm.value, state.widget.maxRpm);
    // The sprite is a fixed reference size (built for the full half-width);
    // "breathing" scales it horizontally by canvas transform, the same way
    // touch bloom scales its own cached glow, rather than baking a new sprite
    // every frame (DESIGN.md 9.3: never blur at runtime).
    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(widthShare, 1);
    glow.drawCentered(
      canvas,
      Offset.zero,
      palette.accentGlow.withValues(alpha: 0.5 * palette.haloScale),
      Paint()..blendMode = ui.BlendMode.plus,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(ShiftHorizonPainter old) =>
      old.palette != palette ||
      old.glow != glow ||
      // As TachArc's painter: catch a swapped rpm signal even before its own
      // `repaint:` listenable next notifies.
      !identical(old.state.widget.rpm, state.widget.rpm);
}

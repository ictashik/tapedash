import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../fidelity/fidelity_tier.dart';
import '../motion/motion_clock.dart';
import '../motion/motion_scope.dart';
import '../motion/phosphor.dart';
import '../motion/smoothing_pipeline.dart';
import '../render/arc_geometry.dart';
import '../render/chamfer.dart';
import '../render/glow_cache.dart';
import '../render/render_kit.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/colors.dart';
import '../tokens/glow.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/tach.dart';
import '../tokens/typography.dart';

/// The tach arc (DESIGN.md 6.2, signature moments 2 and 4's needle half): a
/// 240° sweep of chamfered segments that light up to the current rpm, a light
/// blade needle with a fading trail, a redline zone, and a peak-hold tick.
///
/// It draws two layers, as DESIGN.md 4.2 asks: the scale (ticks and labels) is
/// static, recorded once into a `Picture` and replayed every frame; the
/// segments, needle, trail and peak hold repaint whenever they move, through
/// one `RepaintBoundary`.
///
/// It draws only the ring: the hero speed readout in the middle is the caller's,
/// composed on top (DESIGN.md 7.3, Apex cluster).
class TachArc extends StatefulWidget {
  const TachArc({
    super.key,
    required this.rpm,
    required this.heightReference,
    this.parkedShare,
    this.litShare,
    this.maxRpm = TapeTach.defaultMaxRpm,
    this.redlineRpm = TapeTach.defaultRedlineRpm,
  });

  /// The rpm signal, already smoothed with `spring.needle` (DESIGN.md 5.3):
  /// the needle's position is a pure function of its value (DESIGN.md 5.1).
  final SmoothedSignal rpm;

  /// The landscape screen's height, H: every size here is a share of it
  /// (DESIGN.md 4.5, 6.2).
  final double heightReference;

  /// The parked share (DESIGN.md 7.2), when the caller composes this arc
  /// into a screen that has one: the arc thins and dims to 60% as it goes to
  /// 1, and repaints with it as it moves. Null (the default) leaves the arc
  /// always at full strength, the way a Lab drive of the arc alone does.
  final ValueListenable<double>? parkedShare;

  /// How much of the ring the ignition wave has lit, 0 to 1 (DESIGN.md
  /// 7.13's step 1): every segment up to that share of the sweep shows lit,
  /// whatever the rpm is. Null, or 1, leaves the ring following the rpm alone.
  final ValueListenable<double>? litShare;

  final double maxRpm;
  final double redlineRpm;

  /// The radius the needle and segments are drawn around, for a screen of
  /// [heightReference].
  static double radiusOf(double heightReference) =>
      TapeTach.radiusShareOfHeight * heightReference;

  /// The side of the square box the arc and its ticks need, for a screen of
  /// [heightReference].
  static double boxSideOf(double heightReference) {
    final r = radiusOf(heightReference);
    final depth = TapeTach.segmentDepthShareOfHeight * heightReference;
    final tick = TapeTach.majorTickLengthShareOfHeight * heightReference;
    final label = 0.09 * heightReference;
    return 2 * (r + depth / 2 + tick + label);
  }

  @override
  State<TachArc> createState() => TachArcState();
}

/// The [TachArc]'s state, exposed (not private) so its painter and tests can
/// read the trail, peak and phosphor state it owns.
class TachArcState extends State<TachArc> implements MotionDriven {
  late MotionClock _motion;
  PhosphorBank? bank;
  int _rpmPerSegment = 100;
  final TachRepaintPing repaint = TachRepaintPing();

  /// Trail: a ring buffer of the last needle angles (degrees), one per
  /// [TapeMotion.trailInterval]. Sized for the largest tier so a tier change
  /// never reallocates it; only the tier's own `trailLength` is read back.
  final Float32List trailAngles = Float32List(16);
  int trailHead = 0;
  int trailFilled = 0;
  Duration? _lastTrailSample;

  int? _lastFloorIndex;
  double peakValue = 0;
  Duration peakAt = Duration.zero;
  bool _attached = false;

  /// How long ago the peak was set, on the motion clock.
  Duration peakAge() => _motion.now - peakAt;

  @override
  void initState() {
    super.initState();
    widget.rpm.addListener(_onRpm);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionScope.of(context);
    _onRpm();
  }

  @override
  void didUpdateWidget(TachArc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rpm, widget.rpm)) {
      oldWidget.rpm.removeListener(_onRpm);
      widget.rpm.addListener(_onRpm);
    }
    _onRpm();
  }

  void _onRpm() {
    if (widget.rpm.hasValue && !_attached) {
      _attached = true;
      _motion.attach(this);
    }
  }

  void _ensureBank(int perSegment) {
    final count = (widget.maxRpm / perSegment).ceil();
    if (bank != null && _rpmPerSegment == perSegment && bank!.count == count) {
      return;
    }
    bank?.dispose();
    _rpmPerSegment = perSegment;
    bank = PhosphorBank(clock: _motion, count: count);
    _lastFloorIndex = null;
  }

  @override
  bool advance(double dt, Duration time) {
    final bank = this.bank;
    if (bank == null) return true;
    final value = widget.rpm.value.clamp(0.0, widget.maxRpm);
    final step = _rpmPerSegment.toDouble();
    final count = bank.count;
    final floor = (value / step).floor().clamp(0, count - 1);
    // The first sync after a fresh bank (or a tier change, which rebuilds one)
    // has no previous floor to diff against; treating it as if the previous
    // floor were 0 back-fills every segment below the current one, which is
    // exactly what "nothing was lit before" should do.
    final effectiveLast = _lastFloorIndex ?? 0;
    if (_lastFloorIndex == null || effectiveLast != floor) {
      final lo = math.min(effectiveLast, floor);
      final hi = math.max(effectiveLast, floor);
      for (var i = lo; i <= hi; i++) {
        if (i == floor) continue;
        bank.setTarget(i, i < floor ? 1.0 : 0.0);
      }
    }
    _lastFloorIndex = floor;
    final fraction = ((value - floor * step) / step).clamp(0.0, 1.0);
    bank.setTarget(floor, fraction);

    final lastSample = _lastTrailSample;
    if (lastSample == null || time - lastSample >= TapeMotion.trailInterval) {
      _lastTrailSample = time;
      trailAngles[trailHead] = angleForRpm(value);
      trailHead = (trailHead + 1) % trailAngles.length;
      if (trailFilled < trailAngles.length) trailFilled++;
    }

    if (value >= peakValue ||
        time - peakAt > TapeMotion.peakHold + TapeMotion.peakFade) {
      peakValue = value;
      peakAt = time;
    }

    repaint.ping();
    // Always active while the rpm signal has a value: a live tach keeps
    // ticking, the same as the data it follows.
    return true;
  }

  double angleForRpm(double rpm) =>
      TapeTach.startDegrees -
      TapeTach.sweepDegrees * (rpm.clamp(0, widget.maxRpm) / widget.maxRpm);

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
    _ensureBank(theme.profile.rpmPerSegment);
    final side = TachArc.boxSideOf(widget.heightReference);
    final r = TachArc.radiusOf(widget.heightReference);
    final bandWidth = r * (TapeTach.needleOuter - TapeTach.needleInner);
    final glow = kit.glows.get(
      GlowSpec(
        shape: GlowShape.bar,
        width: bandWidth,
        height: widget.heightReference * 0.01,
        sigma: widget.heightReference * 0.015,
        devicePixelRatio: dpr,
        resolution: theme.profile.halosAtHalfResolution
            ? TapeGlow.liteResolution
            : 1,
      ),
    );

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: side,
        child: CustomPaint(
          painter: TachPainter(
            listenable: Listenable.merge([
              widget.rpm,
              bank!,
              repaint,
              ?widget.parkedShare,
              ?widget.litShare,
            ]),
            state: this,
            palette: theme.palette,
            profile: theme.profile,
            glow: glow,
            devicePixelRatio: dpr,
            parkedShare: widget.parkedShare,
            litShare: widget.litShare,
          ),
        ),
      ),
    );
  }
}

/// Fires its listeners on demand: a ping with no value attached to it. Public
/// because [TachArcState.repaint] is (tests read it to force a repaint check).
class TachRepaintPing extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// The paint code for [TachArc], exposed so `test/design` can drive it without
/// a full widget tree where that is cheaper than a widget test.
class TachPainter extends CustomPainter {
  TachPainter({
    required Listenable listenable,
    required this.state,
    required this.palette,
    required this.profile,
    required this.glow,
    required this.devicePixelRatio,
    this.parkedShare,
    this.litShare,
  }) : super(repaint: listenable);

  final TachArcState state;
  final TapePalette palette;
  final TierProfile profile;
  final GlowSprite glow;
  final double devicePixelRatio;

  /// The parked share, when the caller composes this arc into a screen that
  /// has one (DESIGN.md 7.2): the arc thins and dims to 60% as it goes to 1.
  final ValueListenable<double>? parkedShare;

  /// The ignition wave's lit share (see [TachArc.litShare]).
  final ValueListenable<double>? litShare;

  final Paint _fillPaint = Paint()..style = ui.PaintingStyle.fill;
  final Paint _strokePaint = Paint()..style = ui.PaintingStyle.stroke;
  final Path _path = Path();
  ui.Picture? _staticPicture;
  Object? _staticKey;

  /// The parked share, 0 in Motion and 1 parked, clamped to its own band:
  /// the one number every parked rule here reads.
  double get parked {
    final value = parkedShare?.value ?? 0.0;
    return value.clamp(0.0, 1.0);
  }

  /// The share of a colour's own alpha to draw with, `1` in Motion falling
  /// to [TapeTach.parkedBrightness] parked (DESIGN.md 7.2's "dims to 60%").
  double get dim => 1.0 + (TapeTach.parkedBrightness - 1.0) * parked;

  /// The segment depth's own share, thinned by the same parked rule.
  double get depthShare => 1.0 + (TapeTach.parkedDepthShare - 1.0) * parked;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final h = state.widget.heightReference;
    final r = TachArc.radiusOf(h);
    final depth = TapeTach.segmentDepthShareOfHeight * h * depthShare;
    final outer = r + depth / 2;
    final inner = r - depth / 2;
    final bank = state.bank!;
    final count = bank.count;
    final step = state.widget.maxRpm / count;
    final redlineIndex = (state.widget.redlineRpm / step).floor();
    final slot = TapeTach.sweepDegrees / count;
    final wave = (litShare?.value ?? 1.0).clamp(0.0, 1.0);

    final key = (
      palette.livery,
      palette.mode,
      state.widget.maxRpm,
      state.widget.redlineRpm,
      size.width,
      size.height,
      devicePixelRatio,
    );
    if (_staticPicture == null || _staticKey != key) {
      _staticPicture?.dispose();
      _staticPicture = _recordStatic(center, r, outer, h);
      _staticKey = key;
    }
    canvas.drawPicture(_staticPicture!);

    // Segments, one draw call each but batched by nothing more exotic than a
    // shared Paint and Path reused every iteration (DESIGN.md 9.3): no new
    // object is created per segment.
    final fillSpan = slot * TapeTachFill.share;
    final gap = (slot - fillSpan) / 2;
    for (var i = 0; i < count; i++) {
      var level = bank.levels[i];
      if (wave < 1) {
        // The wave's own front, a segment wide and soft at its leading edge.
        final front = ((wave * count - i) / 1.0).clamp(0.0, 1.0);
        if (front > level) level = front;
      }
      final slotStart = TapeTach.startDegrees - i * slot;
      final segStart = slotStart - gap;
      final segEnd = segStart - fillSpan;
      final inRedline = i >= redlineIndex;
      final unlitColor = inRedline
          ? Color.lerp(
              palette.track,
              palette.critical,
              TapeTach.redlineGhostTint,
            )!
          : palette.track;
      final litColor = inRedline ? palette.critical : palette.accentCore;
      final lerped = Color.lerp(unlitColor, litColor, level)!;
      _fillPaint.color = lerped.withValues(alpha: lerped.a * dim);
      Chamfer.polygonInto(
        _path,
        ArcGeometry.trapezoid(center, inner, outer, segStart, segEnd),
        depth * 0.18,
      );
      canvas.drawPath(_path, _fillPaint);
    }

    _paintPeak(canvas, center, inner, outer);
    _paintTrail(canvas, center, r);
    _paintNeedle(canvas, center, r);
  }

  void _paintPeak(Canvas canvas, Offset center, double inner, double outer) {
    if (state.peakValue <= 0) return;
    final age = state.peakAge();
    if (age >= TapeMotion.peakHold + TapeMotion.peakFade) return;
    final alpha =
        (age <= TapeMotion.peakHold
            ? 1.0
            : 1.0 -
                  (age - TapeMotion.peakHold).inMicroseconds /
                      TapeMotion.peakFade.inMicroseconds.toDouble()) *
        dim;
    if (alpha <= 0) return;
    final angle = state.angleForRpm(state.peakValue);
    _strokePaint
      ..color = palette.inkBright.withValues(alpha: alpha.clamp(0.0, 1.0))
      ..strokeWidth = 1.5
      ..strokeCap = ui.StrokeCap.butt;
    canvas.drawLine(
      ArcGeometry.pointAt(center, inner - 2, angle),
      ArcGeometry.pointAt(center, outer + 2, angle),
      _strokePaint,
    );
  }

  void _paintTrail(Canvas canvas, Offset center, double r) {
    final trailLen = math.min(profile.trailLength, state.trailFilled);
    for (var k = 0; k < trailLen; k++) {
      final idx =
          (state.trailHead - 1 - k + state.trailAngles.length) %
          state.trailAngles.length;
      final angle = state.trailAngles[idx];
      final alpha = math.pow(0.5, k + 1).toDouble() * 0.8 * dim;
      if (alpha <= 0) continue;
      _drawBlade(
        canvas,
        center,
        r,
        angle,
        palette.accentCore.withValues(alpha: alpha),
        1.5,
      );
    }
  }

  void _paintNeedle(Canvas canvas, Offset center, double r) {
    final needleAngle = state.angleForRpm(state.widget.rpm.value);
    final haloStrength = TapeTach.needleHaloStrength * palette.haloScale * dim;
    if (haloStrength > 0.01) {
      final mid = ArcGeometry.pointAt(center, r, needleAngle);
      canvas.save();
      canvas.translate(mid.dx, mid.dy);
      canvas.rotate(-needleAngle * math.pi / 180 + math.pi / 2);
      glow.drawCentered(
        canvas,
        Offset.zero,
        palette.accentGlow.withValues(alpha: haloStrength),
        Paint()..blendMode = ui.BlendMode.plus,
      );
      canvas.restore();
    }
    final bladeColor = palette.inkHotEverywhere
        ? TapeColors.inkHot
        : palette.accentCore;
    _drawBlade(
      canvas,
      center,
      r,
      needleAngle,
      bladeColor.withValues(alpha: bladeColor.a * dim),
      TapeTach.needleCoreStroke,
    );
  }

  void _drawBlade(
    Canvas canvas,
    Offset center,
    double r,
    double angleDeg,
    Color color,
    double width,
  ) {
    final inner = ArcGeometry.pointAt(
      center,
      r * TapeTach.needleInner,
      angleDeg,
    );
    final outer = ArcGeometry.pointAt(
      center,
      r * TapeTach.needleOuter,
      angleDeg,
    );
    _strokePaint
      ..color = color
      ..strokeWidth = width
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawLine(inner, outer, _strokePaint);
  }

  ui.Picture _recordStatic(Offset center, double r, double outer, double h) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final depth = TapeTach.segmentDepthShareOfHeight * h;
    final inner = r - depth / 2;
    final trackPaint = Paint()
      ..color = palette.track
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: (inner + outer) / 2),
      -TapeTach.startDegrees * math.pi / 180,
      -TapeTach.sweepDegrees * math.pi / 180,
      false,
      trackPaint,
    );

    final tickPaint = Paint()
      ..color = palette.etchStrong
      ..strokeWidth = 1.5;
    final tickLen = TapeTach.majorTickLengthShareOfHeight * h;
    for (
      var rpm = 0.0;
      rpm <= state.widget.maxRpm + 1;
      rpm += TapeTach.majorTickEveryRpm
    ) {
      final angle = state.angleForRpm(rpm);
      final from = ArcGeometry.pointAt(center, outer, angle);
      final to = ArcGeometry.pointAt(center, outer + tickLen, angle);
      canvas.drawLine(from, to, tickPaint);

      final labelPainter = TextPainter(
        text: TextSpan(
          text: (rpm / 1000).round().toString(),
          style: TapeType.label(size: 12, color: palette.inkDim),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelPoint = ArcGeometry.pointAt(
        center,
        outer + tickLen + 10,
        angle,
      );
      labelPainter.paint(
        canvas,
        labelPoint - Offset(labelPainter.width / 2, labelPainter.height / 2),
      );
      labelPainter.dispose();
    }

    final unitPainter = TextPainter(
      text: TextSpan(
        text: 'RPM ×1000',
        style: TapeType.label(size: 11, color: palette.inkDim),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitPainter.paint(
      canvas,
      center + Offset(-unitPainter.width / 2, outer + tickLen + 22),
    );
    unitPainter.dispose();

    return recorder.endRecording();
  }

  @override
  bool shouldRepaint(TachPainter old) =>
      old.palette != palette ||
      old.glow != glow ||
      old.devicePixelRatio != devicePixelRatio ||
      !identical(old.parkedShare, parkedShare) ||
      // A caller that swaps in a new rpm signal (a rebuild recreating its
      // inputs, or a test) needs a repaint even before that object's own
      // `repaint:` listenable next notifies.
      !identical(old.state.widget.rpm, state.widget.rpm);
}

/// How much of a segment's angular slot is filled (DESIGN.md 6.2): kept as its
/// own tiny token rather than in `TapeShape.segmentFill` a second time, since
/// that token already exists from phase 3a and this just names it for the arc.
abstract final class TapeTachFill {
  static const double share = 0.70;
}

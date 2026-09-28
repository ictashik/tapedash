import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../motion/motion_clock.dart';
import '../motion/motion_scope.dart';
import '../motion/smoothing_pipeline.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/road_view.dart';
import '../tokens/typography.dart';
import 'centered_numeral.dart';
import 'rolling_numerals.dart';

/// The road view (DESIGN.md 6.11): the "car moving" cluster. A stylised,
/// non-photorealistic driving scene, not a simulation of real camera optics
/// -- every depth cue here (the perspective ease, the dash spacing, the
/// visible road length) is a deliberate abstraction DESIGN.md leaves to this
/// component, not a literal projection.
///
/// [moneySlot] is the money readout DESIGN.md 6.11 places on the driver-side
/// flank; it is left null until Phase 4 builds the money engine that would
/// feed it (CLAUDE.md 13) rather than faked here. The layout reserves its
/// place regardless, so Phase 4 only has to pass a widget in.
class RoadView extends StatefulWidget {
  const RoadView({
    super.key,
    required this.speed,
    required this.rpm,
    required this.maxRpm,
    required this.longitudinalAcceleration,
    required this.lateralAcceleration,
    required this.width,
    required this.height,
    this.moneySlot,
  });

  /// km/h, smoothed (`spring.gauge`, DESIGN.md 5.3): drives the dash phase,
  /// the streaks and the hero speed overlay.
  final SmoothedSignal speed;

  /// rpm, smoothed: drives the horizon RPM bar.
  final SmoothedSignal rpm;
  final double maxRpm;

  /// m/s^2, smoothed (`spring.needle`): positive is accelerating, negative
  /// is braking. Drives body pitch and the tail-light brake halo.
  final SmoothedSignal longitudinalAcceleration;

  /// m/s^2, smoothed (`spring.needle`), positive to the right: drives body
  /// roll. The accelerometer, low-pass filtered (DESIGN.md 6.11) -- the
  /// filtering is the caller's, this just reads the already-smoothed value.
  final SmoothedSignal lateralAcceleration;

  final double width;
  final double height;
  final Widget? moneySlot;

  @override
  State<RoadView> createState() => RoadViewState();
}

class RoadViewState extends State<RoadView> implements MotionDriven {
  late MotionClock _motion;
  double _distanceMetres = 0;
  bool _attached = false;
  final RoadRepaintPing repaint = RoadRepaintPing();

  /// A fixed per-slot lateral jitter for the speed streaks, drawn once (not
  /// reallocated every frame, DESIGN.md 9.3) and just subset by the current
  /// density.
  late final List<double> _streakJitter = List.generate(
    120, // the largest a tier ever asks for (TierProfile.full.maxStreaks).
    (i) => _pseudoRandom(i),
  );

  static double _pseudoRandom(int seed) {
    // A tiny deterministic hash, not a Random(): the same seed must draw
    // the same streak on every frame and every run.
    final x = math.sin(seed * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void initState() {
    super.initState();
    widget.speed.addListener(_onSpeed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionScope.of(context);
    _onSpeed();
  }

  @override
  void didUpdateWidget(RoadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.speed, widget.speed)) {
      oldWidget.speed.removeListener(_onSpeed);
      widget.speed.addListener(_onSpeed);
    }
    _onSpeed();
  }

  void _onSpeed() {
    // Attach once and keep ticking, unlike a search pulse or an alert: the
    // scene must keep integrating distance even at a standstill (so the
    // dash phase is exactly where it should be the instant speed resumes),
    // and it is the main thing on screen throughout Motion mode, not an
    // intermittent effect with nothing to show when idle.
    if (widget.speed.hasValue && !_attached) {
      _attached = true;
      _motion.attach(this);
    }
  }

  @override
  bool advance(double dt, Duration time) {
    final kmh = widget.speed.hasValue
        ? widget.speed.value.clamp(0.0, 400.0)
        : 0.0;
    _distanceMetres += (kmh / 3.6) * dt;
    repaint.ping();
    return true;
  }

  /// 0 to 1: how far through one dash period the car has travelled.
  /// Exposed so "truthful motion" (DESIGN.md 6.11) has a direct test: pure
  /// distance-in, phase-out, rather than inferred from drawn dash pixels.
  double get dashPhase =>
      (_distanceMetres / TapeRoadView.dashPeriodMetres) % 1.0;

  @override
  void dispose() {
    widget.speed.removeListener(_onSpeed);
    if (_attached) _motion.detach(this);
    repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: RoadViewPainter(
                listenable: Listenable.merge([
                  widget.speed,
                  widget.longitudinalAcceleration,
                  widget.lateralAcceleration,
                  repaint,
                ]),
                state: this,
                palette: palette,
                maxStreaks: theme.profile.maxStreaks,
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: CenteredNumeral(
                source: widget.speed,
                format: const NumeralFormat(integerDigits: 3),
                typicalIntegerDigits: 2,
                size: TypeScale.forHeight(widget.height).hero,
                role: NumeralRole.bright,
              ),
            ),
          ),
          if (widget.moneySlot != null)
            Positioned(
              left: 8,
              top: widget.height * TapeRoadView.horizonShare,
              child: widget.moneySlot!,
            ),
        ],
      ),
    );
  }
}

/// A ping with no value attached, for the road's own per-frame distance tick.
class RoadRepaintPing extends ChangeNotifier {
  void ping() => notifyListeners();
}

class RoadViewPainter extends CustomPainter {
  RoadViewPainter({
    required Listenable listenable,
    required this.state,
    required this.palette,
    required this.maxStreaks,
  }) : super(repaint: listenable);

  final RoadViewState state;
  final TapePalette palette;
  final int maxStreaks;

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * TapeRoadView.horizonShare;
    final bottomY = size.height;
    final centerX = size.width / 2;

    double halfWidthAt(double y) {
      final t = ((y - horizonY) / (bottomY - horizonY)).clamp(0.0, 1.0);
      return (TapeRoadView.roadHalfWidthAtHorizon +
              (TapeRoadView.roadHalfWidthAtBottom -
                      TapeRoadView.roadHalfWidthAtHorizon) *
                  t) *
          size.width;
    }

    // Perspective ease: rungs and dashes bunch up near the horizon, the way
    // evenly spaced real-world distances do at a distance.
    double easedY(double t) => horizonY + (bottomY - horizonY) * t * t;

    _paintLaneGrid(canvas, horizonY, bottomY, centerX, halfWidthAt, easedY);
    _paintEdges(canvas, horizonY, bottomY, centerX, halfWidthAt);
    _paintDashes(canvas, centerX, easedY);
    _paintStreaks(canvas, size, horizonY, bottomY, centerX, halfWidthAt);

    final speed = state.widget.speed.hasValue ? state.widget.speed.value : 0.0;
    final longAccel = state.widget.longitudinalAcceleration.hasValue
        ? state.widget.longitudinalAcceleration.value
        : 0.0;
    final latAccel = state.widget.lateralAcceleration.hasValue
        ? state.widget.lateralAcceleration.value
        : 0.0;

    if (palette.isNight) {
      _paintHeadlightCones(canvas, size, horizonY, bottomY, centerX);
    }
    _paintCar(
      canvas,
      size,
      horizonY,
      bottomY,
      centerX,
      longAccel,
      latAccel,
      speed,
    );
    _paintRpmBar(canvas, size, horizonY);
  }

  void _paintLaneGrid(
    Canvas canvas,
    double horizonY,
    double bottomY,
    double centerX,
    double Function(double) halfWidthAt,
    double Function(double) easedY,
  ) {
    final paint = Paint()
      ..color = palette.etchFaint
      ..strokeWidth = 1;
    for (var i = 1; i <= TapeRoadView.laneGridRungs; i++) {
      final t = i / (TapeRoadView.laneGridRungs + 1);
      final y = easedY(t);
      final half = halfWidthAt(y);
      canvas.drawLine(
        Offset(centerX - half, y),
        Offset(centerX + half, y),
        paint,
      );
    }
  }

  void _paintEdges(
    Canvas canvas,
    double horizonY,
    double bottomY,
    double centerX,
    double Function(double) halfWidthAt,
  ) {
    final paint = Paint()
      ..color = palette.etchStrong
      ..strokeWidth = 2
      ..style = ui.PaintingStyle.stroke;
    final topHalf = halfWidthAt(horizonY);
    final bottomHalf = halfWidthAt(bottomY);
    canvas.drawLine(
      Offset(centerX - topHalf, horizonY),
      Offset(centerX - bottomHalf, bottomY),
      paint,
    );
    canvas.drawLine(
      Offset(centerX + topHalf, horizonY),
      Offset(centerX + bottomHalf, bottomY),
      paint,
    );
  }

  static const int _dashSlots = 10;

  void _paintDashes(
    Canvas canvas,
    double centerX,
    double Function(double) easedY,
  ) {
    final paint = Paint()
      ..color = palette.accentDeep
      ..strokeWidth = 3;
    final phase = state.dashPhase;
    for (var i = 0; i < _dashSlots; i++) {
      final t = i / _dashSlots;
      final slotPhase = (t + phase) % 1.0;
      if (slotPhase >= TapeRoadView.dashOnShare) continue;
      final y0 = easedY(t);
      final y1 = easedY(t + 1 / _dashSlots * TapeRoadView.dashOnShare);
      canvas.drawLine(Offset(centerX, y0), Offset(centerX, y1), paint);
    }
  }

  void _paintStreaks(
    Canvas canvas,
    Size size,
    double horizonY,
    double bottomY,
    double centerX,
    double Function(double) halfWidthAt,
  ) {
    final speed = state.widget.speed.hasValue ? state.widget.speed.value : 0.0;
    final count = streakCountFor(speed, maxStreaks);
    if (count == 0) return;

    final phase = state.dashPhase;
    final paint = Paint()
      ..color = palette.inkBright
      ..strokeWidth = 2.5;
    for (var i = 0; i < count; i++) {
      final jitter = state._streakJitter[i];
      final t = (jitter + phase) % 1.0;
      final y = horizonY + (bottomY - horizonY) * t * t;
      final half = halfWidthAt(y);
      // A small, proportional hug just outside the road's own edge at this
      // y, rather than a large additive offset: that kept landing well past
      // the viewport at high t, where half is already most of the width.
      final side = i.isEven ? -1 : 1;
      final x = centerX + side * (half * 1.08 + 3 + jitter * 4);
      final length =
          TapeRoadView.streakMinLength +
          (bottomY - horizonY) * TapeRoadView.streakLengthShare * t;
      canvas.drawLine(Offset(x, y), Offset(x, y + length), paint);
    }
  }

  void _paintHeadlightCones(
    Canvas canvas,
    Size size,
    double horizonY,
    double bottomY,
    double centerX,
  ) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(centerX, bottomY),
        (bottomY - horizonY) * 0.7,
        [
          palette.inkBright.withValues(alpha: 0.08),
          palette.inkBright.withValues(alpha: 0),
        ],
      );
    canvas.drawRect(Rect.fromLTRB(0, horizonY, size.width, bottomY), paint);
  }

  void _paintCar(
    Canvas canvas,
    Size size,
    double horizonY,
    double bottomY,
    double centerX,
    double longAccel,
    double latAccel,
    double speed,
  ) {
    final carWidth = TapeRoadView.carWidthShare * size.width;
    final carHeight = TapeRoadView.carHeightShareOfWidth * carWidth;
    final baseY = horizonY + (bottomY - horizonY) * TapeRoadView.carBaseShare;

    final pitchDeg = pitchDegreesFor(longAccel);
    final rollDeg = rollDegreesFor(latAccel);

    canvas.save();
    canvas.translate(centerX, baseY - carHeight / 2);
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0012) // a touch of perspective for the pitch tilt.
      ..rotateX(pitchDeg * math.pi / 180)
      ..rotateZ(rollDeg * math.pi / 180);
    canvas.transform(transform.storage);
    canvas.translate(-carWidth / 2, -carHeight / 2);

    final body = Rect.fromLTWH(0, carHeight * 0.32, carWidth, carHeight * 0.68);
    final bodyRRect = RRect.fromRectAndRadius(
      body,
      Radius.circular(carHeight * 0.1),
    );
    final roof = Rect.fromLTWH(
      carWidth * 0.16,
      0,
      carWidth * 0.68,
      carHeight * 0.4,
    );
    final roofRRect = RRect.fromRectAndRadius(
      roof,
      Radius.circular(carHeight * 0.08),
    );

    canvas.drawRRect(bodyRRect, Paint()..color = palette.track);
    canvas.drawRRect(roofRRect, Paint()..color = palette.track);
    final outline = Paint()
      ..color = palette.etchStrong
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(bodyRRect, outline);
    canvas.drawRRect(roofRRect, outline);

    // A rim-light hint along the roof's top edge.
    canvas.drawLine(
      Offset(roof.left + 4, roof.top + 1),
      Offset(roof.right - 4, roof.top + 1),
      Paint()
        ..color = palette.accentCore.withValues(alpha: 0.8)
        ..strokeWidth = 1.5,
    );

    final braking = isBraking(longAccel);
    final tailColor = braking
        ? palette.critical
        : palette.track.withValues(alpha: 0.9);
    final tailWidth = carWidth * 0.14;
    final tailHeight = carHeight * 0.08;
    final leftTail = Rect.fromLTWH(
      body.left + carWidth * 0.06,
      body.bottom - tailHeight * 1.6,
      tailWidth,
      tailHeight,
    );
    final rightTail = Rect.fromLTWH(
      body.right - carWidth * 0.06 - tailWidth,
      body.bottom - tailHeight * 1.6,
      tailWidth,
      tailHeight,
    );
    final tailPaint = Paint()..color = tailColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(leftTail, Radius.circular(2)),
      tailPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rightTail, Radius.circular(2)),
      tailPaint,
    );
    if (braking) {
      final haloPaint = Paint()
        ..color = palette.critical.withValues(alpha: 0.35)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(leftTail.inflate(3), Radius.circular(4)),
        haloPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rightTail.inflate(3), Radius.circular(4)),
        haloPaint,
      );
    }

    canvas.restore();
  }

  void _paintRpmBar(Canvas canvas, Size size, double horizonY) {
    if (!state.widget.rpm.hasValue) return;
    final share = (state.widget.rpm.value / state.widget.maxRpm).clamp(
      0.0,
      1.0,
    );
    final thickness = size.height * TapeRoadView.rpmBarThicknessShare;
    final track = Rect.fromLTWH(
      0,
      horizonY - thickness / 2,
      size.width,
      thickness,
    );
    canvas.drawRect(track, Paint()..color = palette.etchFaint);
    canvas.drawRect(
      Rect.fromLTWH(0, horizonY - thickness / 2, size.width * share, thickness),
      Paint()..color = palette.accentCore,
    );
  }

  static const double _g = 9.81;

  /// Body pitch in degrees for [longAccel] (m/s^2, positive accelerating,
  /// DESIGN.md 6.11): linear up to 1g, capped at [TapeRoadView.pitchMaxDegrees].
  /// A pure function, exposed for a direct test.
  static double pitchDegreesFor(double longAccel) =>
      (longAccel / _g).clamp(-1.0, 1.0) * TapeRoadView.pitchMaxDegrees;

  /// Body roll in degrees for [latAccel] (m/s^2, positive to the right),
  /// the same shape as [pitchDegreesFor] but capped at
  /// [TapeRoadView.rollMaxDegrees].
  static double rollDegreesFor(double latAccel) =>
      (latAccel / _g).clamp(-1.0, 1.0) * TapeRoadView.rollMaxDegrees;

  /// Whether deceleration is past the brake-light threshold (DESIGN.md
  /// 6.11): [longAccel] negative and beyond [TapeRoadView.brakeThreshold]
  /// in magnitude.
  static bool isBraking(double longAccel) =>
      -longAccel > TapeRoadView.brakeThreshold;

  /// How many speed streaks to draw for [speedKmh] out of [maxStreaks]
  /// (DESIGN.md 6.11): 0 at and below [TapeRoadView.streakThresholdKmh],
  /// rising to [maxStreaks] at [TapeRoadView.streakFullDensityKmh].
  static int streakCountFor(double speedKmh, int maxStreaks) {
    if (speedKmh <= TapeRoadView.streakThresholdKmh) return 0;
    final density =
        ((speedKmh - TapeRoadView.streakThresholdKmh) /
                (TapeRoadView.streakFullDensityKmh -
                    TapeRoadView.streakThresholdKmh))
            .clamp(0.0, 1.0);
    return (density * maxStreaks).round();
  }

  @override
  bool shouldRepaint(RoadViewPainter old) =>
      old.palette != palette ||
      old.maxStreaks != maxStreaks ||
      !identical(old.state.widget.speed, state.widget.speed) ||
      !identical(
        old.state.widget.longitudinalAcceleration,
        state.widget.longitudinalAcceleration,
      ) ||
      !identical(
        old.state.widget.lateralAcceleration,
        state.widget.lateralAcceleration,
      ) ||
      !identical(old.state.widget.rpm, state.widget.rpm);
}

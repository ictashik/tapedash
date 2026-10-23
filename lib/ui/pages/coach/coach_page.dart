import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../coach/efficiency_curve.dart';
import '../../../coach/tips.dart';
import '../../../coach/trip_statistics.dart';
import '../../../core/clock.dart';
import '../../../trips/trip.dart';
import '../../../trips/trip_library.dart';
import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/efficiency_curve.dart';
import '../../design/components/tape_label.dart';
import '../../design/motion/motion_scope.dart';
import '../../design/motion/timeline.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/motion_tokens.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/strokes.dart';
import '../review/review_page.dart' show BracketFramePainter, ReviewPageState;

/// Coach (DESIGN.md 7.6): what the car and the driving add up to over time.
///
/// On the left the car's own efficiency curve with its sweet spot; on the right
/// the sweet spot in words, THIS WEEK ₹ against LAST WEEK ₹ with a delta glyph, an
/// eight-week ₹/km trend, and the last three tips as bracketed panels. With no
/// steady driving yet the curve is drawn as a ghost, and the page says what fills
/// it in.
///
/// Everything is from real trips (CLAUDE.md 8.9).
/// Parked only, and the tips show nothing while the car moves.
class CoachPage extends StatefulWidget {
  const CoachPage({
    super.key,
    required this.library,
    required this.clock,
    required this.mode,
    required this.width,
    required this.height,
    this.tips = const TipEngine(),
    this.reduceMotion = false,
  });

  final TripLibrary library;
  final Clock clock;
  final ValueListenable<DrivingMode> mode;
  final double width;
  final double height;
  final TipEngine tips;
  final bool reduceMotion;

  @override
  State<CoachPage> createState() => CoachPageState();
}

class CoachPageState extends State<CoachPage> {
  SweetSpot _curve = const SweetSpot([]);
  List<WeekTotal> _weeks = const [];
  final ValueNotifier<double> _draw = ValueNotifier(0);
  Timeline? _drawOn;
  int _load = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.library.trips.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.library.trips.removeListener(_reload);
    _drawOn?.dispose();
    _draw.dispose();
    super.dispose();
  }

  /// The curve now shown.
  SweetSpot get curve => _curve;

  /// Whether the first load has finished.
  bool get loaded => _loaded;

  Future<void> _reload() async {
    final ticket = ++_load;
    final curve = await sweetSpotFrom(widget.library.repository);
    if (!mounted || ticket != _load) return;
    setState(() {
      _curve = curve;
      _weeks = TripStatistics.weekly(
        widget.library.trips.value,
        widget.clock.now(),
      );
      _loaded = true;
    });
    _startDrawOn();
  }

  void _startDrawOn() {
    _drawOn?.dispose();
    if (widget.reduceMotion) {
      _draw.value = 1;
      return;
    }
    _draw.value = 0;
    final t = Timeline(
      clock: MotionScope.of(context),
      length: TapeDurations.scene,
    );
    t.addListener(() => _draw.value = TapeCurves.enter.transform(t.progress));
    _drawOn = t;
    t.start();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final margin = TapeSpace.margin(widget.height);
    final leftW = widget.width * 0.6 - margin;
    const captionH = 34.0;
    final range = _curve.range;
    final thisWeek = _weeks.isEmpty ? null : _weeks.last;
    final lastWeek = _weeks.length < 2 ? null : _weeks[_weeks.length - 2];
    final recent = [for (final t in widget.library.trips.value.take(3)) t];

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          // What the curve is (or what fills it in) sits above it, and the curve
          // stops at the parked dock's clear line, so nothing is under the dock.
          Positioned(
            left: margin,
            top: TapeSpace.s3,
            width: leftW,
            height: captionH,
            child: TapeText(
              _curve.reported.isEmpty
                  ? 'Your curve fills in as you drive. Around 50 km of steady driving is enough.'
                  : 'Kilometres a litre at each steady speed, from your own drives.',
              style: TapeTextStyle.small,
              color: palette.inkMid,
            ),
          ),
          Positioned(
            left: margin,
            top: TapeSpace.s3 + captionH,
            width: leftW,
            bottom: widget.height * TapeSpace.clearOfDockShare,
            child: EfficiencyCurveView(curve: _curve, draw: _draw),
          ),
          Positioned(
            left: widget.width * 0.62,
            right: margin,
            top: TapeSpace.s4,
            bottom: TapeSpace.s3,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TapeLabel('Sweet spot', size: 11),
                  const SizedBox(height: TapeSpace.s1),
                  TapeText(
                    range == null
                        ? 'Not enough steady driving yet.'
                        : '${range.from}–${range.to} km/h',
                    style: TapeTextStyle.title,
                    color: range == null ? palette.inkMid : palette.accentCore,
                  ),
                  const SizedBox(height: TapeSpace.s3),
                  _WeekRow(current: thisWeek, last: lastWeek, palette: palette),
                  const SizedBox(height: TapeSpace.s3),
                  TapeLabel('₹/km, last 8 weeks', size: 11),
                  const SizedBox(height: TapeSpace.s1),
                  SizedBox(
                    height: 36,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: TrendPainter(
                        values: [for (final w in _weeks) w.costPerKm],
                        palette: palette,
                      ),
                    ),
                  ),
                  const SizedBox(height: TapeSpace.s3),
                  ValueListenableBuilder<DrivingMode>(
                    valueListenable: widget.mode,
                    builder: (context, m, _) => m != DrivingMode.parked
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final t in recent)
                                for (final tip
                                    in widget.tips.tipsFor(t).take(1))
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: TapeSpace.s2,
                                    ),
                                    child: _TipCard(
                                      trip: t,
                                      tip: tip,
                                      palette: palette,
                                    ),
                                  ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.current,
    required this.last,
    required this.palette,
  });

  final WeekTotal? current;
  final WeekTotal? last;
  final TapePalette palette;

  @override
  Widget build(BuildContext context) {
    final a = current?.cost ?? 0;
    final b = last?.cost ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Cell(
          label: 'This week',
          value: '₹${a.round()}',
          palette: palette,
          strong: true,
        ),
        const SizedBox(width: TapeSpace.s4),
        _Cell(label: 'Last week', value: '₹${b.round()}', palette: palette),
        const SizedBox(width: TapeSpace.s2),
        if (b > 0 || a > 0)
          CustomPaint(
            size: const Size(14, 14),
            painter: DeltaGlyphPainter(
              up: a > b,
              color: a > b ? palette.caution : palette.accentCore,
            ),
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.value,
    required this.palette,
    this.strong = false,
  });

  final String label;
  final String value;
  final TapePalette palette;
  final bool strong;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TapeLabel(label, size: 10),
      TapeText(
        value,
        style: strong ? TapeTextStyle.title : TapeTextStyle.body,
        color: strong ? palette.money : palette.inkMid,
      ),
    ],
  );
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.trip,
    required this.tip,
    required this.palette,
  });

  final Trip trip;
  final Tip tip;
  final TapePalette palette;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: BracketFramePainter(color: palette.etchStrong),
    child: Padding(
      padding: const EdgeInsets.all(TapeSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TapeText(
            ReviewPageState.formatWhen(trip.startedAt),
            style: TapeTextStyle.caption,
            color: palette.inkDim,
          ),
          TapeText(
            tip.text,
            style: TapeTextStyle.small,
            color: palette.inkBright,
          ),
        ],
      ),
    ),
  );
}

/// The eight-week ₹/km trend as a sparkline: a line through the weeks that have a
/// figure, and a dot on the last.
class TrendPainter extends CustomPainter {
  TrendPainter({required this.values, required this.palette});

  final List<double?> values;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final have = [
      for (var i = 0; i < values.length; i++)
        if (values[i] != null) (i, values[i]!),
    ];
    final base = Paint()
      ..color = palette.etch
      ..strokeWidth = TapeStroke.fine;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      base,
    );
    if (have.length < 2) return;
    var lo = have.first.$2, hi = have.first.$2;
    for (final (_, v) in have) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = hi - lo < 0.01 ? 1 : hi - lo;
    Offset at((int, double) p) => Offset(
      size.width * p.$1 / (values.length - 1),
      size.height - 4 - (size.height - 8) * (p.$2 - lo) / span,
    );
    final path = Path()..moveTo(at(have.first).dx, at(have.first).dy);
    for (final p in have.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = TapeStroke.regular
        ..color = palette.moneyDeep,
    );
    canvas.drawCircle(at(have.last), 3, Paint()..color = palette.money);
  }

  @override
  bool shouldRepaint(TrendPainter old) =>
      !listEquals(old.values, values) || old.palette != palette;
}

/// A small triangle, up or down: this week against last.
class DeltaGlyphPainter extends CustomPainter {
  DeltaGlyphPainter({required this.up, required this.color});

  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = up
        ? (Path()
            ..moveTo(size.width / 2, 1)
            ..lineTo(size.width - 1, size.height - 1)
            ..lineTo(1, size.height - 1)
            ..close())
        : (Path()
            ..moveTo(1, 1)
            ..lineTo(size.width - 1, 1)
            ..lineTo(size.width / 2, size.height - 1)
            ..close());
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(DeltaGlyphPainter old) =>
      old.up != up || old.color != color;
}

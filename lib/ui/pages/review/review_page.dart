import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../coach/sample_events.dart';
import '../../../coach/tips.dart';
import '../../../money/spend_bucket.dart';
import '../../../trips/route_geometry.dart';
import '../../../trips/trip.dart';
import '../../../trips/trip_library.dart';
import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/controls/tape_segmented.dart';
import '../../design/components/presence.dart';
import '../../design/components/rolling_numerals.dart';
import '../../design/components/route_trail.dart';
import '../../design/components/tape_label.dart';
import '../../design/components/telemetry_scrubber.dart';
import '../../design/motion/motion_scope.dart';
import '../../design/motion/numeral_source.dart';
import '../../design/motion/timeline.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/motion_tokens.dart';
import '../../design/tokens/shapes.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/strokes.dart';
import '../../design/tokens/typography.dart';
import '../money/bucket_breakdown.dart';
import '../money/money_figure.dart';
import 'roll_up_source.dart';

/// A request for the Debrief to play (DESIGN.md 7.5): the shell makes one when a
/// trip ends, and Review takes it as soon as it is on screen, which may be a moment
/// later, since the Strip only builds the pages near the one it is showing.
class DebriefRequest extends ChangeNotifier {
  bool _pending = false;

  bool get pending => _pending;

  /// Asks for the Debrief.
  void request() {
    _pending = true;
    notifyListeners();
  }

  /// Takes the request: true once for each [request].
  bool take() {
    final was = _pending;
    _pending = false;
    return was;
  }

  /// Withdraws it (the engine came back).
  void clear() => _pending = false;
}

/// Which metric colours the route.
enum ReviewMetric {
  speed('Speed'),
  throttle('Throttle'),
  costPerKm('₹/km');

  const ReviewMetric(this.label);

  final String label;
}

/// Review (DESIGN.md 7.5): a trip laid out. On the left the route trail, with a
/// SPEED, THROTTLE or ₹/KM selector; on the right the receipt (₹ total at display
/// size, then distance, time, km/L, ₹/km and idle time), where it went, and one
/// tip; along the bottom the telemetry scrubber.
///
/// **The Debrief** ([playDebrief]) is this page playing itself when a trip ends:
/// the where-it-went bar fills, the route draws itself with a comet head, the
/// receipt's figures roll up, and the tip fades in, 4.5 s at most; a tap anywhere
/// skips to the end. It never plays while the car moves, since the page is not
/// reachable then.
///
/// Parked only: tips are shown only when the car is not moving ([mode]).
class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.library,
    required this.mode,
    required this.width,
    required this.height,
    this.tips = const TipEngine(),
    this.reduceMotion = false,
    this.debrief,
  });

  /// Asks the page to play the Debrief, when it is on screen.
  final DebriefRequest? debrief;

  final TripLibrary library;
  final ValueListenable<DrivingMode> mode;
  final double width;
  final double height;
  final TipEngine tips;

  /// With reduce motion the Debrief shows its end state at once (DESIGN.md 5.8).
  final bool reduceMotion;

  @override
  State<ReviewPage> createState() => ReviewPageState();
}

class ReviewPageState extends State<ReviewPage> {
  Trip? _trip;
  List<TripSample> _samples = const [];
  List<SampleEvent> _events = const [];
  ReviewMetric _metric = ReviewMetric.speed;
  final ValueNotifier<int?> _cursor = ValueNotifier(null);
  final ValueNotifier<double> _seconds = ValueNotifier(double.infinity);
  Timeline? _debrief;
  late final ValueNotifier<double> _full = ValueNotifier(1);
  RouteGeometry? _geometry;
  Size? _geometrySize;
  int _load = 0;

  @override
  void initState() {
    super.initState();
    widget.library.selected.addListener(_onSelected);
    widget.debrief?.addListener(_onDebriefRequest);
    _onSelected();
    _onDebriefRequest();
  }

  void _onDebriefRequest() {
    final request = widget.debrief;
    if (request == null || !request.pending) return;
    // The page may still be building: play once this frame is done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && request.take()) playDebrief();
    });
  }

  @override
  void dispose() {
    widget.library.selected.removeListener(_onSelected);
    widget.debrief?.removeListener(_onDebriefRequest);
    _debrief?.dispose();
    _cursor.dispose();
    _barShare.dispose();
    _routeShare.dispose();
    _receiptShare.dispose();
    _tipShare.dispose();
    _seconds.dispose();
    _full.dispose();
    super.dispose();
  }

  /// Whether the Debrief is playing.
  bool get isDebriefing => _debrief != null && !_debrief!.isDone;

  void _onSelected() {
    final trip = widget.library.selected.value;
    final ticket = ++_load;
    if (trip == null) {
      setState(() {
        _trip = null;
        _samples = const [];
      });
      return;
    }
    widget.library.samples(trip).then((samples) {
      if (!mounted || ticket != _load) return;
      setState(() {
        _trip = trip;
        _samples = samples;
        _events = SampleEvents.find(samples);
        _geometry = null;
        _cursor.value = null;
      });
    });
  }

  /// Plays the Debrief (DESIGN.md 7.5): call it when a trip ends.
  void playDebrief() {
    _debrief?.dispose();
    if (widget.reduceMotion) {
      _seconds.value = double.infinity;
      _debrief = null;
      setState(() {});
      return;
    }
    _seconds.value = 0;
    final t = Timeline(
      clock: MotionScope.of(context),
      length: TapeDebrief.length,
    );
    t.addListener(() => _seconds.value = t.seconds);
    _debrief = t;
    t.start();
    setState(() {});
  }

  /// Puts the Debrief away without playing the rest (the engine came back).
  void cancelDebrief() {
    _debrief?.dispose();
    _debrief = null;
    _seconds.value = double.infinity;
  }

  void _skip() {
    if (isDebriefing) {
      _debrief!.skip();
      _seconds.value = double.infinity;
    }
  }

  // The shares of the Debrief's steps (all 1 when it is not playing).
  SliceShare _slice(double from, double to) =>
      SliceShare(_seconds, from, to, TapeCurves.enter.transform);

  late final SliceShare _barShare = _slice(
    TapeDebrief.barFrom,
    TapeDebrief.barTo,
  );
  late final SliceShare _routeShare = _slice(
    TapeDebrief.routeFrom,
    TapeDebrief.routeTo,
  );
  late final SliceShare _receiptShare = _slice(
    TapeDebrief.receiptFrom,
    TapeDebrief.receiptTo,
  );
  late final SliceShare _tipShare = _slice(
    TapeDebrief.tipFrom,
    TapeDebrief.tipTo,
  );

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    final palette = TapeTheme.of(context).palette;
    final margin = TapeSpace.margin(widget.height);
    if (trip == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Center(
          child: TapeText(
            'No trips yet. Drive, and the trip lands here.',
            color: palette.inkMid,
          ),
        ),
      );
    }
    final leftW = widget.width * 0.58 - margin;
    // The scrubber stands on the parked dock's clear line (it is over the dock's
    // floor otherwise), the tip sits on the scrubber, and the route takes what is
    // left between the metric selector and the tip.
    final scrubberH = widget.height * 0.13;
    final scrubberBottom = widget.height * TapeSpace.clearOfDockShare;
    const tipH = 52.0;
    final shares = (
      bar: _barShare,
      route: _routeShare,
      receipt: _receiptShare,
      tip: _tipShare,
    );
    final tip = widget.tips.tipsFor(trip).firstOrNull;
    const headingH = 20.0;
    const selectorH = 34.0;
    final selectorTop = TapeSpace.s2 + headingH;
    final routeTop = selectorTop + selectorH + TapeSpace.s1;
    final tipTop =
        widget.height - scrubberBottom - scrubberH - TapeSpace.s1 - tipH;
    final routeH = tipTop - TapeSpace.s1 - routeTop;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _skip,
        child: Stack(
          children: [
            // The heading: when, and the DEMO badge for a demo trip; the readouts
            // at the cursor take its right-hand side while scrubbing.
            Positioned(
              left: margin,
              top: TapeSpace.s2,
              width: leftW,
              height: headingH,
              child: Row(
                children: [
                  TapeText(
                    formatWhen(trip.startedAt),
                    style: TapeTextStyle.small,
                    color: palette.inkMid,
                  ),
                  if (trip.isDemo) ...[
                    const SizedBox(width: TapeSpace.s2),
                    const TapeLabel('Demo', size: 11),
                  ],
                  const Spacer(),
                  _CursorReadout(
                    cursor: _cursor,
                    samples: _samples,
                    price: trip.pricePerLitre,
                  ),
                ],
              ),
            ),
            Positioned(
              left: margin,
              top: selectorTop,
              width: leftW,
              child: TapeSegmented<ReviewMetric>(
                height: selectorH,
                value: _metric,
                onChanged: (m) => setState(() => _metric = m),
                segments: [
                  for (final m in ReviewMetric.values) TapeSegment(m, m.label),
                ],
              ),
            ),
            Positioned(
              left: margin,
              top: routeTop,
              width: leftW,
              height: routeH,
              child: _route(trip, palette, shares.route),
            ),
            // One tip, in a bracket frame, only while the car is not moving.
            Positioned(
              left: margin,
              top: tipTop,
              width: leftW,
              child: ValueListenableBuilder<DrivingMode>(
                valueListenable: widget.mode,
                builder: (context, m, _) =>
                    m == DrivingMode.parked && tip != null
                    ? TipPanel(tip: tip, share: shares.tip)
                    : const SizedBox.shrink(),
              ),
            ),
            Positioned(
              left: widget.width * 0.62,
              right: margin,
              top: TapeSpace.s2,
              bottom: scrubberBottom + scrubberH + TapeSpace.s2,
              child: _Receipt(
                key: ValueKey(trip.id),
                trip: trip,
                palette: palette,
                receiptShare: shares.receipt,
                barShare: shares.bar,
                height: widget.height,
              ),
            ),
            Positioned(
              left: margin,
              right: margin,
              bottom: scrubberBottom,
              height: scrubberH,
              child: _samples.length < 2
                  ? const SizedBox.shrink()
                  : TelemetryScrubber(
                      samples: _samples,
                      cursor: _cursor,
                      events: _events,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _route(
    Trip trip,
    TapePalette palette,
    ValueListenable<double> reveal,
  ) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        if (_geometry == null || _geometrySize != size) {
          _geometry = RouteGeometry.build(_samples, size.width, size.height);
          _geometrySize = size;
        }
        final g = _geometry;
        if (g == null) {
          return Center(
            child: TapeText(
              _samples.isEmpty
                  ? 'This trip has no samples.'
                  : 'No route: this trip had no GPS.',
              style: TapeTextStyle.small,
              color: palette.inkMid,
            ),
          );
        }
        final values = [
          for (final i in g.sampleIndex) _metricValue(_samples[i], trip),
        ];
        final normalised = normalise(
          values,
          fixedMax: _metric == ReviewMetric.throttle ? 100 : null,
        );
        final markers = <RouteMarker>[
          RouteMarker(null, 0),
          RouteMarker(null, g.length - 1),
          for (final e in _events) RouteMarker(e.type, g.nearestPoint(e.index)),
        ];
        return ValueListenableBuilder<int?>(
          valueListenable: _cursor,
          builder: (context, c, _) => RouteTrail(
            geometry: g,
            metric: normalised,
            ramp: _ramp(palette),
            reveal: reveal,
            cursor: ValueNotifier(c == null ? null : g.nearestPoint(c)),
            markers: markers,
          ),
        );
      },
    );
  }

  double _metricValue(TripSample s, Trip trip) => switch (_metric) {
    ReviewMetric.speed => s.speedKmh,
    ReviewMetric.throttle => s.throttle,
    ReviewMetric.costPerKm =>
      trip.pricePerLitre == null || s.speedKmh < 5
          ? 0
          : s.litresPerHour * trip.pricePerLitre! / s.speedKmh,
  };

  List<Color> _ramp(TapePalette p) => switch (_metric) {
    ReviewMetric.costPerKm => [p.moneyDeep, p.moneyGlow, p.critical],
    _ => [p.accentDeep, p.accentCore, p.inkBright],
  };

  /// "Wed 4 Mar · 8:15 am": the heading of a trip.
  static String formatWhen(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} · '
        '$h:$m ${d.hour < 12 ? 'am' : 'pm'}';
  }
}

class _CursorReadout extends StatelessWidget {
  const _CursorReadout({
    required this.cursor,
    required this.samples,
    required this.price,
  });

  final ValueListenable<int?> cursor;
  final List<TripSample> samples;
  final double? price;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return ValueListenableBuilder<int?>(
      valueListenable: cursor,
      builder: (context, c, _) {
        if (c == null || samples.isEmpty) return const SizedBox.shrink();
        final r = ScrubReadout.at(samples, c, price);
        final style = TapeType.label(size: 12, color: palette.inkBright);
        return Row(
          children: [
            Text('${r.speedKmh.round()} KM/H', style: style),
            const SizedBox(width: TapeSpace.s4),
            Text('${r.rpm.round()} RPM', style: style),
            const SizedBox(width: TapeSpace.s4),
            Text('${r.throttle.round()} % THROTTLE', style: style),
            if (r.costPerKm != null) ...[
              const SizedBox(width: TapeSpace.s4),
              Text('₹${r.costPerKm!.toStringAsFixed(1)}/KM', style: style),
            ],
          ],
        );
      },
    );
  }
}

class _Receipt extends StatefulWidget {
  const _Receipt({
    super.key,
    required this.trip,
    required this.palette,
    required this.receiptShare,
    required this.barShare,
    required this.height,
  });

  final Trip trip;
  final TapePalette palette;
  final ValueListenable<double> receiptShare;
  final ValueListenable<double> barShare;
  final double height;

  @override
  State<_Receipt> createState() => _ReceiptState();
}

/// The receipt's roll-up sources are made once for the trip (the page keys it by
/// trip) and let go with it, however often the page rebuilds.
class _ReceiptState extends State<_Receipt> {
  final Map<String, RollUpSource> _sources = {};

  RollUpSource _source(
    String key,
    double target,
    ValueListenable<double> share,
    int decimals,
  ) => _sources.putIfAbsent(
    key,
    () => RollUpSource(target, share, decimals: decimals),
  );

  @override
  void dispose() {
    for (final s in _sources.values) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final palette = widget.palette;
    final type = TypeScale.forHeight(widget.height);
    final total = trip.bucketLitres.values.fold<double>(0, (a, b) => a + b);
    final price = trip.pricePerLitre;
    NumeralSource roll(String key, double v, {int decimals = 1}) =>
        _source(key, v, widget.receiptShare, decimals);
    NumeralSource bar(String key, double v) =>
        _source(key, v, widget.barShare, 0);
    final size = type.display * 0.6;

    Widget stat(
      String label,
      double value,
      NumeralFormat f,
      String unit, {
      int decimals = 1,
    }) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TapeLabel(label, size: 10),
          SizedBox(
            height: 18,
            child: OverflowBox(
              maxHeight: NumeralMetrics(15).boxHeight,
              alignment: Alignment.centerLeft,
              child: LabeledNumeral(
                source: roll(label, value, decimals: decimals),
                format: f,
                size: 15,
                unit: unit,
                role: NumeralRole.bright,
              ),
            ),
          ),
        ],
      ),
    );

    const minutes = NumeralFormat(integerDigits: 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The total, at display size (a step down on a 360 lp screen).
        SizedBox(
          height: size * 0.9,
          child: OverflowBox(
            maxHeight: size * 2.2,
            alignment: Alignment.centerLeft,
            child: price == null
                ? LabeledNumeral(
                    source: roll('litres', trip.litres),
                    format: rateFormat,
                    size: size,
                    unit: 'L',
                    role: NumeralRole.money,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '≈₹',
                        style: TapeType.numeral(
                          size: size * 0.5,
                          weight: TapeTheme.of(context).livery.numeralWeight,
                          color: palette.rupee,
                        ),
                      ),
                      FittedNumerals(
                        source: roll(
                          'total',
                          trip.cost ?? trip.litres * price,
                          decimals: 0,
                        ),
                        maxDigits: 6,
                        builder: (context, digits) => RollingNumerals(
                          source: roll(
                            'total',
                            trip.cost ?? trip.litres * price,
                            decimals: 0,
                          ),
                          format: NumeralFormat(
                            integerDigits: digits,
                            grouping: DigitGrouping.indian,
                          ),
                          size: size,
                          role: NumeralRole.money,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: TapeSpace.s1),
        Row(
          children: [
            stat('Distance', trip.distanceKm, rateFormat, 'KM'),
            stat('Time', trip.engineSeconds / 60, minutes, 'MIN', decimals: 0),
          ],
        ),
        const SizedBox(height: TapeSpace.s1),
        Row(
          children: [
            if (trip.kmPerLitre != null)
              stat('Economy', trip.kmPerLitre!, rateFormat, 'KM/L')
            else
              const Spacer(),
            if (trip.costPerKm != null)
              stat('Cost', trip.costPerKm!, rateFormat, '₹/KM')
            else
              const Spacer(),
          ],
        ),
        const SizedBox(height: TapeSpace.s1),
        Row(
          children: [
            stat('Idling', trip.idleSeconds / 60, minutes, 'MIN', decimals: 0),
            const Spacer(),
          ],
        ),
        const Spacer(),
        if (price != null && total > 0)
          BucketBreakdown(
            compact: true,
            cost: {
              for (final b in SpendBucket.values)
                b: bar('cost:${b.name}', (trip.bucketLitres[b] ?? 0) * price),
            },
            percent: {
              for (final b in SpendBucket.values)
                b: bar(
                  'pct:${b.name}',
                  100 * (trip.bucketLitres[b] ?? 0) / total,
                ),
            },
            width: double.infinity,
            labelSize: 10,
            numeralSize: 13,
          ),
      ],
    );
  }
}

/// A tip in a bracket frame (DESIGN.md 7.5): the sentence, and its cost's brackets.
class TipPanel extends StatelessWidget {
  const TipPanel({super.key, required this.tip, this.share});

  final Tip tip;
  final ValueListenable<double>? share;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final child = CustomPaint(
      painter: BracketFramePainter(color: palette.accentCore),
      child: Padding(
        padding: const EdgeInsets.all(TapeSpace.s3),
        child: TapeText(
          tip.text,
          style: TapeTextStyle.small,
          color: palette.inkBright,
        ),
      ),
    );
    if (share == null) return child;
    // Fades in once, at the end of the Debrief: Presence, the design's one
    // transient-reveal layer, and nothing while it is hidden.
    return Presence(share: share!, child: child);
  }
}

/// Four corner brackets round a box, in [color] (DESIGN.md 4.6's bracket frame).
class BracketFramePainter extends CustomPainter {
  BracketFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final arm = TapeShape.bracketArm;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.fine;
    for (final (cx, cy, sx, sy) in [
      (0.0, 0.0, 1.0, 1.0),
      (size.width, 0.0, -1.0, 1.0),
      (0.0, size.height, 1.0, -1.0),
      (size.width, size.height, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx + sx * arm, cy)
          ..lineTo(cx, cy)
          ..lineTo(cx, cy + sy * arm),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(BracketFramePainter old) => old.color != color;
}

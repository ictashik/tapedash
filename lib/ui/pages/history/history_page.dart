import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../coach/trip_statistics.dart';
import '../../../core/clock.dart';
import '../../../money/spend_bucket.dart';
import '../../../trips/route_geometry.dart';
import '../../../trips/trip.dart';
import '../../../trips/trip_library.dart';
import '../../design/components/controls/tape_segmented.dart';
import '../../design/components/tape_label.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../money/bucket_breakdown.dart' show paintBucketBlock;
import '../review/review_page.dart' show ReviewPageState;

/// How far back History reaches.
enum HistoryRange {
  week('Week'),
  month('Month'),
  all('All');

  const HistoryRange(this.label);

  final String label;

  /// Whether a trip that started at [at] is in the range at [now].
  bool includes(DateTime at, DateTime now) => switch (this) {
    week => !at.isBefore(TripStatistics.weekStart(now)),
    month => at.year == now.year && at.month == now.month,
    all => true,
  };
}

/// History (DESIGN.md 7.7): every trip, newest first. A header with THIS MONTH ₹,
/// distance and average km/L, and a week / month / all selector; rows of 88 lp
/// with the date, a small route, the distance, the ₹, km/L and a thin barcode of
/// where the money went. Tapping a row opens its Review.
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.library,
    required this.clock,
    required this.width,
    required this.height,
    this.onOpen,
  });

  final TripLibrary library;
  final Clock clock;
  final double width;
  final double height;

  /// Called with the trip whose row was tapped (after it is selected in the
  /// library): the shell moves to Review.
  final ValueChanged<Trip>? onOpen;

  /// A row's height (DESIGN.md 7.7).
  static const double rowHeight = 88;

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  HistoryRange _range = HistoryRange.month;

  @override
  void initState() {
    super.initState();
    widget.library.trips.addListener(_changed);
  }

  @override
  void dispose() {
    widget.library.trips.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  /// The trips in the chosen range, newest first.
  List<Trip> get shown {
    final now = widget.clock.now();
    return [
      for (final t in widget.library.trips.value)
        if (_range.includes(t.startedAt, now)) t,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final margin = TapeSpace.margin(widget.height);
    final now = widget.clock.now();
    final month = TripStatistics.month(widget.library.trips.value, now);
    final trips = shown;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(margin, TapeSpace.s3, margin, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TapeLabel('This month', size: 11),
                    TapeText(
                      '₹${month.cost.round()}',
                      style: TapeTextStyle.title,
                      color: palette.money,
                    ),
                  ],
                ),
                const SizedBox(width: TapeSpace.s6),
                _Stat('Distance', '${month.km.toStringAsFixed(1)} km', palette),
                const SizedBox(width: TapeSpace.s6),
                _Stat(
                  'Economy',
                  month.litres > 0 && month.km >= 0.5
                      ? '${(month.km / month.litres).toStringAsFixed(1)} km/L'
                      : '—',
                  palette,
                ),
                const Spacer(),
                SizedBox(
                  width: 210,
                  child: TapeSegmented<HistoryRange>(
                    height: 40,
                    value: _range,
                    onChanged: (r) => setState(() => _range = r),
                    segments: [
                      for (final r in HistoryRange.values)
                        TapeSegment(r, r.label),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: TapeSpace.s2),
            Expanded(
              child: trips.isEmpty
                  ? Center(
                      child: TapeText(
                        'No trips in this range yet.',
                        color: palette.inkMid,
                      ),
                    )
                  : ListView.builder(
                      itemCount: trips.length,
                      itemExtent: HistoryPage.rowHeight,
                      physics: const ClampingScrollPhysics(),
                      itemBuilder: (context, i) => TripRow(
                        key: ValueKey(trips[i].id),
                        trip: trips[i],
                        library: widget.library,
                        onTap: () {
                          widget.library.select(trips[i]);
                          widget.onOpen?.call(trips[i]);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.palette);

  final String label;
  final String value;
  final TapePalette palette;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TapeLabel(label, size: 10),
      TapeText(value, style: TapeTextStyle.body, color: palette.inkMid),
    ],
  );
}

/// One row of History (88 lp).
class TripRow extends StatefulWidget {
  const TripRow({
    super.key,
    required this.trip,
    required this.library,
    required this.onTap,
  });

  final Trip trip;
  final TripLibrary library;
  final VoidCallback onTap;

  @override
  State<TripRow> createState() => _TripRowState();
}

class _TripRowState extends State<TripRow> {
  RouteGeometry? _route;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.library.samples(widget.trip).then((samples) {
      if (!mounted) return;
      setState(() {
        _route = RouteGeometry.build(samples, 48, 48);
        _loaded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final t = widget.trip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.etch)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TapeText(
                    ReviewPageState.formatWhen(t.startedAt),
                    style: TapeTextStyle.small,
                    color: palette.inkBright,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 48,
              height: 48,
              child: _loaded && _route != null
                  ? CustomPaint(painter: MiniRoutePainter(_route!, palette))
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: TapeSpace.s4),
            _Cell(
              '${t.distanceKm.toStringAsFixed(1)} km',
              84,
              palette.inkBright,
            ),
            _Cell(
              t.cost == null ? '—' : '₹${t.cost!.round()}',
              70,
              palette.money,
            ),
            _Cell(
              t.kmPerLitre == null
                  ? '—'
                  : '${t.kmPerLitre!.toStringAsFixed(1)} km/L',
              84,
              palette.inkMid,
            ),
            Expanded(
              child: SizedBox(
                height: 14,
                child: CustomPaint(
                  painter: BarcodePainter(t.blockBuckets, palette),
                  size: Size.infinite,
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
  const _Cell(this.text, this.width, this.color);

  final String text;
  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: TapeText(text, style: TapeTextStyle.body, color: color),
  );
}

/// A trip's route as a small line, north up, 48 lp square.
class MiniRoutePainter extends CustomPainter {
  MiniRoutePainter(this.route, this.palette);

  final RouteGeometry route;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(route.xs.first, route.ys.first);
    for (var i = 1; i < route.length; i++) {
      path.lineTo(route.xs[i], route.ys[i]);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = palette.accentCore,
    );
    canvas.drawCircle(
      Offset(route.xs.last, route.ys.last),
      2.5,
      Paint()..color = palette.inkBright,
    );
  }

  @override
  bool shouldRepaint(MiniRoutePainter old) => old.route != route;
}

/// A thin barcode of where the money went: one small block for each rupee, in its
/// bucket's style, thinned to fit (DESIGN.md 6.8: the same barcode as the Money
/// Tape, "in Review and History").
class BarcodePainter extends CustomPainter {
  BarcodePainter(this.blocks, this.palette);

  final List<SpendBucket> blocks;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (blocks.isEmpty) return;
    const pitch = 4.0;
    final fit = (size.width / pitch).floor().clamp(1, 1 << 20);
    final n = blocks.length;
    final count = n < fit ? n : fit;
    for (var k = 0; k < count; k++) {
      // Thinned evenly when there are more blocks than room.
      final b = blocks[n <= fit ? k : (k * n ~/ fit)];
      paintBucketBlock(
        canvas,
        Rect.fromLTWH(k * pitch, 0, 3, size.height),
        b,
        palette,
      );
    }
  }

  @override
  bool shouldRepaint(BarcodePainter old) =>
      !listEquals(old.blocks, blocks) || old.palette != palette;
}

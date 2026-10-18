import 'package:flutter/widgets.dart';

import '../../../insights/ghost_commute.dart';
import '../../../trips/trip.dart';
import '../../design/components/insights/ghost_route_chart.dart';
import '../../design/components/tape_label.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../history/history_page.dart' show BarcodePainter;
import '../review/review_page.dart' show ReviewPageState;
import 'insight_layout.dart';

/// Ghost commute (DESIGN.md 7.14): the same route driven twice, the two routes
/// laid over each other and the two Money Tapes one above the other, with what
/// separates them in rupees. Never in minutes: a commute is not a race.
class GhostPanel extends StatelessWidget {
  const GhostPanel({super.key, required this.match});

  /// Null when the trip has no earlier drive of its route.
  final GhostMatch? match;

  static String _when(DateTime t) => ReviewPageState.formatWhen(t);

  /// "9 min less", "3 min more" or null when it is under a minute either way.
  static String? idleWords(double secondsSaved) {
    final m = (secondsSaved.abs() / 60).round();
    if (m == 0) return null;
    return '$m min ${secondsSaved > 0 ? 'less' : 'more'} standing still';
  }

  /// "5 fewer hard starts", "2 more hard starts" or null for the same.
  static String? hardWords(int saved) {
    if (saved == 0) return null;
    final n = saved.abs();
    return '$n ${saved > 0 ? 'fewer' : 'more'} hard ${n == 1 ? 'start' : 'starts'}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final m = match;
    final saved = m?.rupeesSaved;
    final rounded = saved?.round();
    return InsightPanel(
      chart: m == null
          ? const InsightEmpty(
              title: 'No earlier drive of this route',
              how:
                  'Drive the same route twice, with the GPS on, and the two line up here, rupee by rupee.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GhostRouteChart(
                    now: m.nowRoute,
                    before: m.beforeRoute,
                  ),
                ),
                const SizedBox(height: TapeSpace.s2),
                _TapeRow(
                  label: _when(m.now.startedAt),
                  bright: true,
                  trip: m.now,
                ),
                const SizedBox(height: TapeSpace.s2),
                _TapeRow(
                  label: _when(m.before.startedAt),
                  bright: false,
                  trip: m.before,
                ),
              ],
            ),
      facts: [
        if (m != null) ...[
          const TapeLabel('Same route, two days', size: 10),
          const SizedBox(height: 2),
          if (rounded == null)
            TapeText(
              'Set a fuel price to compare in rupees.',
              style: TapeTextStyle.small,
              color: palette.inkMid,
            )
          else
            Text(
              rounded == 0
                  ? '₹0'
                  : '₹${rounded.abs()} ${rounded > 0 ? 'less' : 'more'}',
              style: TapeType.numeral(
                size: 28,
                weight: 500,
                color: palette.money,
              ),
            ),
          const SizedBox(height: TapeSpace.s2),
          for (final line in [
            idleWords(m.idleSecondsSaved),
            hardWords(m.hardStartsSaved),
          ])
            if (line != null)
              TapeText(
                line,
                style: TapeTextStyle.small,
                color: palette.inkBright,
              ),
          const SizedBox(height: TapeSpace.s3),
        ],
        const InsightNote(
          'Compared in rupees, never in minutes: a commute is not a race.',
        ),
      ],
    );
  }
}

class _TapeRow extends StatelessWidget {
  const _TapeRow({
    required this.label,
    required this.bright,
    required this.trip,
  });

  final String label;
  final bool bright;
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final cost = trip.cost;
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: TapeLabel(
            label,
            size: 10,
            color: bright ? palette.inkBright : palette.inkDim,
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 22,
            child: CustomPaint(
              painter: BarcodePainter(trip.blockBuckets, palette),
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            cost == null ? '—' : '₹${cost.round()}',
            textAlign: TextAlign.end,
            style: TapeType.numeral(
              size: 16,
              weight: 500,
              color: bright ? palette.money : palette.inkMid,
            ),
          ),
        ),
      ],
    );
  }
}

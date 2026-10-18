import 'package:flutter/widgets.dart';

import '../../../insights/cold_start.dart';
import '../../../trips/trip.dart';
import '../../design/components/insights/cold_start_chart.dart';
import '../../design/components/tape_label.dart';
import '../../design/theme/tape_theme.dart';
import '../review/review_page.dart' show ReviewPageState;
import 'insight_layout.dart';

/// Cold-start bill (DESIGN.md 7.14): what the first minutes after a cold start
/// cost over the warm engine, for one trip, and for the month.
class ColdPanel extends StatelessWidget {
  const ColdPanel({
    super.key,
    required this.trip,
    required this.cold,
    required this.month,
    required this.monthTrips,
  });

  /// The trip shown: the chosen one if it started cold, else the latest that did.
  final Trip? trip;

  /// Null when no trip started cold.
  final ColdStart? cold;

  /// The month's cold-start bill in rupees, and over how many trips.
  final double month;
  final int monthTrips;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final c = cold;
    return InsightPanel(
      chart: c == null
          ? const InsightEmpty(
              title: 'No cold start to bill yet',
              how:
                  'A cold start is a drive that begins with the coolant under 65 °C and runs warm for a few minutes after, with a fuel price set.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (trip != null)
                  TapeLabel(
                    ReviewPageState.formatWhen(trip!.startedAt),
                    size: 10,
                    color: palette.inkDim,
                  ),
                Expanded(child: ColdStartChart(cold: c)),
              ],
            ),
      facts: [
        if (c != null) ...[
          InsightFact(
            label: 'Cold running, this drive',
            value: '≈ ₹${c.extraRupees.round()}',
            note: 'over the warm cost, in ${c.coldKm.toStringAsFixed(1)} km',
            color: palette.money,
            size: 26,
          ),
          InsightFact(
            label: 'This month',
            value: '≈ ₹${month.round()}',
            note:
                'over $monthTrips ${monthTrips == 1 ? 'drive' : 'drives'} that started cold',
            size: 18,
          ),
        ],
        InsightNote(
          c == null
              ? 'Fuel the engine burns while it is cold is not wasted by anyone; this is just the bill for it.'
              : 'A cold engine runs rich until it warms, so a short drive is mostly cold running. Moving drives only; the cold idling is not counted.',
        ),
      ],
    );
  }
}

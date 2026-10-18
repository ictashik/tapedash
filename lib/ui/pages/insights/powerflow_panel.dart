import 'package:flutter/widgets.dart';

import '../../../insights/powerflow.dart';
import '../../../trips/trip.dart';
import '../../design/components/insights/powerflow_chart.dart';
import '../../design/components/tape_label.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../review/review_page.dart' show ReviewPageState;
import 'insight_layout.dart';

/// Powerflow (DESIGN.md 7.14): where the energy in a trip's fuel went, from the
/// fuel to the wheels and the heat, and from the wheels to the tyres, the air and
/// the brakes, with the trip's rupees following the same split.
class PowerflowPanel extends StatelessWidget {
  const PowerflowPanel({super.key, required this.trip, required this.flow});

  final Trip? trip;

  /// Null for a trip with too little fuel or driving to say.
  final Powerflow? flow;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final f = flow;
    final t = trip;
    final brakes = f?.rupees(f.brakeOfFuel);
    return InsightPanel(
      chart: f == null
          ? const InsightEmpty(
              title: 'Nothing to split yet',
              how:
                  'Powerflow needs a finished drive with fuel and speed, a few minutes long.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (t != null)
                  TapeLabel(
                    '${ReviewPageState.formatWhen(t.startedAt)} · '
                    '${t.distanceKm.toStringAsFixed(1)} km',
                    size: 10,
                    color: palette.inkDim,
                  ),
                Expanded(child: PowerflowChart(flow: f)),
              ],
            ),
      facts: [
        if (f != null) ...[
          InsightFact(
            label: 'To the wheels',
            value: '≈ ${(f.wheelShare * 100).round()}%',
            note: 'of the energy in the fuel',
          ),
          if (brakes != null && brakes >= 1)
            InsightFact(
              label: 'Heat in the brake discs',
              value: '≈ ₹${brakes.round()}',
              note: 'of this trip',
              color: palette.money,
            )
          else
            InsightFact(
              label: 'Through the brakes',
              value: '≈ ${(f.brakeOfFuel * 100).round()}%',
              note: 'of the fuel',
            ),
          const SizedBox(height: TapeSpace.s1),
        ],
        const InsightNote(
          'An estimate from speed and fuel alone, with no hills: it shows the '
          'shape of where a litre goes, not the last percent.',
        ),
      ],
    );
  }
}

import 'package:flutter/widgets.dart';

import '../../../insights/rest_voltage_log.dart';
import '../../../insights/voltage_trace.dart';
import '../../../trips/trip.dart';
import '../../design/components/insights/voltage_chart.dart';
import '../../design/components/tape_label.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../review/review_page.dart' show ReviewPageState;
import 'insight_layout.dart';

/// Current (DESIGN.md 7.14): is the battery charging, and what dents the voltage.
/// The module voltage of a drive inside its charging band, each dip with its
/// depth, and the battery's resting voltage over the weeks.
///
/// The car reports no battery current, so a load is known only by the dent it
/// makes; what made it is not claimed.
class CurrentPanel extends StatelessWidget {
  const CurrentPanel({
    super.key,
    required this.trip,
    required this.trace,
    required this.rest,
  });

  final Trip? trip;
  final VoltageTrace trace;
  final List<RestReading> rest;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final dips = trace.dips;
    final typicalDepth = dips.isEmpty
        ? 0.0
        : (dips.map((d) => d.depth).toList()..sort())[dips.length ~/ 2];
    final typicalSeconds = dips.isEmpty
        ? 0.0
        : (dips.map((d) => d.seconds).toList()..sort())[dips.length ~/ 2];
    final charging = trace.chargingShare >= 0.5;
    return InsightPanel(
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: trace.isEmpty
                ? const SizedBox.shrink()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        trace.median.toStringAsFixed(1),
                        style: TapeType.numeral(
                          size: 44,
                          weight: 500,
                          color: palette.accentCore,
                        ),
                      ),
                      const SizedBox(width: TapeSpace.s1),
                      TapeLabel('V', size: 16, color: palette.inkDim),
                      const SizedBox(width: TapeSpace.s3),
                      TapeLabel(
                        charging ? 'Charging' : 'On the battery',
                        size: 12,
                        color: charging ? palette.inkBright : palette.caution,
                      ),
                      const Spacer(),
                      if (trip != null)
                        TapeLabel(
                          ReviewPageState.formatWhen(trip!.startedAt),
                          size: 10,
                          color: palette.inkDim,
                        ),
                    ],
                  ),
          ),
          Expanded(child: VoltageChart(trace: trace)),
        ],
      ),
      facts: [
        InsightFact(
          label: 'Charging',
          value: trace.isEmpty
              ? '—'
              : '${(trace.chargingShare * 100).round()}%',
          note: 'of the drive at ${VoltageTrace.chargingVolts} V+',
        ),
        InsightFact(
          label: 'Dips',
          value: dips.isEmpty
              ? (trace.isEmpty ? '—' : 'None')
              : '${dips.length}',
          note: dips.isEmpty
              ? null
              : 'typically −${typicalDepth.toStringAsFixed(1)} V for '
                    '${typicalSeconds.round()} s',
        ),
        const TapeLabel('Resting, ignition on', size: 10),
        const SizedBox(height: 2),
        SizedBox(height: 28, child: RestTrend(readings: rest)),
        const SizedBox(height: 2),
        TapeText(
          rest.isEmpty
              ? 'None yet'
              : '${rest.last.volts.toStringAsFixed(2)} V · ${rest.length} '
                    '${rest.length == 1 ? 'reading' : 'readings'}',
          style: TapeTextStyle.caption,
          color: palette.inkMid,
        ),
        const SizedBox(height: TapeSpace.s2),
        InsightNote(
          rest.isEmpty
              ? 'Ignition on, a few seconds, then start: that is a reading. Weeks of them show a battery ageing.'
              : 'A dip is a load. A battery resting lower each week is ageing.',
        ),
      ],
    );
  }
}

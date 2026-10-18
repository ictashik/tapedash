import 'package:flutter/widgets.dart';

import '../../../core/number_format.dart';
import '../../../insights/power_curve.dart';
import '../../design/components/insights/power_curve_chart.dart';
import '../../design/theme/tape_theme.dart';
import 'insight_layout.dart';

/// Power curve (DESIGN.md 7.14): a dyno chart built from ordinary driving, with
/// no special run. Wheel power against revs, coloured by throttle; where the car
/// has never been, the chart says so.
class PowerPanel extends StatelessWidget {
  const PowerPanel({super.key, required this.curve});

  final PowerCurve curve;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final top = curve.highest;
    return InsightPanel(
      chart: curve.isEmpty
          ? const InsightEmpty(
              title: 'Nothing to chart yet',
              how:
                  'The curve builds itself from ordinary driving: every moment the '
                  'engine pulls is a dot. A few drives fill the middle of it.',
            )
          : PowerCurveChart(curve: curve),
      facts: [
        InsightFact(
          label: 'Highest seen',
          value: top == null ? '—' : '≈ ${top.kw.round()} kW',
          note: top == null ? null : 'at ${_rpm(top.rpm)} rpm',
          color: palette.inkBright,
          size: 24,
        ),
        InsightFact(
          label: 'Revs reached',
          value: curve.isEmpty ? '—' : _rpm(curve.coveredRpm),
          note: 'rpm, while pulling',
        ),
        const InsightNote(
          'Wheel power from speed and acceleration, an estimate. The edge is the '
          'most the car has shown, and rises as you use more of its range; it never '
          'asks you to rev.',
        ),
      ],
    );
  }

  /// Revs to the nearest 100, with a comma: 3,700.
  static String _rpm(double rpm) =>
      groupDigits('${(rpm / 100).round() * 100}', DigitGrouping.western);
}

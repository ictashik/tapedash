import 'package:flutter/widgets.dart';

import '../../../insights/gearbox.dart';
import '../../design/components/insights/gear_chart.dart';
import '../../design/components/tape_label.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import 'insight_layout.dart';

/// Gearbox, found (DESIGN.md 7.14): each gear is a straight line of rpm against
/// speed, and enough driving draws them with no setup. A CVT has no such lines and
/// shows a fan, which says so plainly.
class GearsPanel extends StatelessWidget {
  const GearsPanel({super.key, required this.gearbox});

  final Gearbox gearbox;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final usage = gearbox.usage();
    return InsightPanel(
      chart: gearbox.isEmpty
          ? const InsightEmpty(
              title: 'Nothing to plot yet',
              how:
                  'Every moment above 12 km/h is a dot of revs against speed. A few drives are enough for the gears to show.',
            )
          : GearChart(gearbox: gearbox),
      facts: [
        InsightFact(
          label: 'Gears found',
          value: gearbox.isEmpty
              ? '—'
              : gearbox.isFan
              ? 'None'
              : '${gearbox.gears}',
          note: gearbox.isFan
              ? 'The revs follow your foot, not a gear: this looks like a CVT.'
              : gearbox.isEmpty
              ? null
              : 'the ones your driving has used, by rpm for each km/h',
        ),
        for (final u in usage)
          Padding(
            padding: const EdgeInsets.only(bottom: TapeSpace.s1),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '${u.ratio.round()}',
                    style: TapeType.numeral(
                      size: 14,
                      weight: 500,
                      color: palette.accentCore,
                    ),
                  ),
                ),
                Expanded(
                  child: TapeText(
                    u.fromKmh.round() == u.toKmh.round()
                        ? '${u.fromKmh.round()} km/h'
                        : '${u.fromKmh.round()}–${u.toKmh.round()} km/h',
                    style: TapeTextStyle.caption,
                    color: palette.inkBright,
                  ),
                ),
                TapeLabel('${(u.share * 100).round()}%', size: 10),
              ],
            ),
          ),
        const SizedBox(height: TapeSpace.s2),
        const InsightNote(
          'No gear sensor: a gear is a ratio the revs keep. One never driven in is not shown, so gears are not numbered.',
        ),
      ],
    );
  }
}

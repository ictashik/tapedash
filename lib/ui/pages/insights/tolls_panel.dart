import 'package:flutter/widgets.dart';

import '../../../core/number_format.dart';
import '../../../insights/toll_map.dart';
import '../../design/components/insights/toll_map_chart.dart';
import '../../design/components/tape_label.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import 'insight_layout.dart';

/// The Toll Map (DESIGN.md 7.14): where the money spent standing still was spent.
/// Rings on the roads driven, sized by what each place cost, the dearest chosen to
/// begin with and any other one by a tap.
class TollsPanel extends StatefulWidget {
  const TollsPanel({super.key, required this.map, required this.since});

  final TollMap map;

  /// The first trip's day, for "since".
  final DateTime? since;

  @override
  State<TollsPanel> createState() => TollsPanelState();
}

class TollsPanelState extends State<TollsPanel> {
  int _selected = 0;

  /// The place chosen: 0 is the dearest.
  int get selected => _selected;

  /// "1 h 50 min", "12 min", "40 s".
  static String duration(double seconds) {
    final s = seconds.round();
    if (s < 90) return '$s s';
    final m = (s / 60).round();
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final rest = m % 60;
    return rest == 0 ? '$h h' : '$h h $rest min';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final map = widget.map;
    final spots = map.spots;
    final chosen = spots.isEmpty
        ? null
        : spots[_selected.clamp(0, spots.length - 1)];
    final since = widget.since;
    String money(double? rupees, double litres) => rupees == null
        ? '${litres.toStringAsFixed(1)} L'
        : '₹${groupDigits(rupees.round().toString(), DigitGrouping.indian)}';
    return InsightPanel(
      chart: spots.isEmpty
          ? const InsightEmpty(
              title: 'Nowhere yet',
              how:
                  'Stops with the engine running, with a GPS fix, are pinned to the road. Drive a few days and the places you wait the most show up.',
            )
          : TollMapChart(
              map: map,
              selected: _selected,
              onSelect: (i) => setState(() => _selected = i),
            ),
      facts: [
        if (chosen != null) ...[
          TapeLabel('Place ${_selected + 1} of ${spots.length}', size: 10),
          const SizedBox(height: 2),
          Text(
            money(chosen.rupees, chosen.litres),
            style: TapeType.numeral(
              size: 30,
              weight: 500,
              color: chosen.rupees == null ? palette.inkBright : palette.money,
            ),
          ),
          TapeText(
            '${duration(chosen.seconds)} standing still',
            style: TapeTextStyle.small,
            color: palette.inkBright,
          ),
          TapeText(
            '${chosen.stops} ${chosen.stops == 1 ? 'stop' : 'stops'}',
            style: TapeTextStyle.caption,
            color: palette.inkMid,
          ),
          const SizedBox(height: TapeSpace.s3),
          InsightFact(
            label: since == null
                ? 'All of them'
                : 'All of them, since ${since.day} ${_months[since.month - 1]}',
            value: money(
              map.totalRupees > 0 ? map.totalRupees : null,
              map.totalLitres,
            ),
            note: 'standing still',
            size: 18,
          ),
        ],
        InsightNote(
          spots.isEmpty
              ? 'Hollow rings are fuel burnt standing still.'
              : 'Tap a ring. Hollow, because fuel burnt standing still goes nowhere.',
        ),
      ],
    );
  }
}

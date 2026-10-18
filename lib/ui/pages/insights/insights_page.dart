import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../insights/insight_data.dart';
import '../../../insights/tank_reading.dart';
import '../../../trips/trip.dart';
import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/controls/tape_button.dart';
import '../../design/components/controls/tape_scroll_segmented.dart';
import '../../design/components/controls/tape_segmented.dart';
import '../../design/components/tape_label.dart';
import '../../design/icons/icons.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import 'tank_panel.dart';

/// The pages of Insights (DESIGN.md 7.14), in the order of the selector.
enum InsightTab {
  tank('Tank');

  const InsightTab(this.label);
  final String label;
}

/// Insights (DESIGN.md 7.14): what the car and the trips add up to, one picture at
/// a time. A scrolling selector across the top, one panel under it, and Close.
///
/// Parked only: it closes itself if the car starts to move. Real drives and the
/// demo are never mixed (CLAUDE.md 7.6), which [load] decides.
class InsightsPage extends StatefulWidget {
  const InsightsPage({
    super.key,
    required this.load,
    required this.tank,
    required this.mode,
    required this.width,
    required this.height,
    required this.onClose,
    this.initial = InsightTab.tank,
  });

  /// Reads the trips the panels draw from, when the page opens.
  final Future<InsightData> Function() load;

  /// The counted tank, given the trips to work the economy from.
  final TankReading? Function(Iterable<Trip> trips) tank;

  final ValueListenable<DrivingMode> mode;
  final double width;
  final double height;
  final VoidCallback onClose;
  final InsightTab initial;

  @override
  State<InsightsPage> createState() => InsightsPageState();
}

class InsightsPageState extends State<InsightsPage> {
  late InsightTab _tab = widget.initial;
  InsightData? _data;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    widget.mode.addListener(_onMode);
    _read();
  }

  @override
  void dispose() {
    widget.mode.removeListener(_onMode);
    super.dispose();
  }

  /// The tab now shown.
  InsightTab get tab => _tab;

  /// The trips read, or null while they are being read.
  InsightData? get data => _data;

  void showTab(InsightTab tab) => setState(() => _tab = tab);

  void _onMode() {
    if (widget.mode.value != DrivingMode.parked) widget.onClose();
  }

  Future<void> _read() async {
    final ticket = ++_ticket;
    final data = await widget.load();
    if (!mounted || ticket != _ticket) return;
    setState(() => _data = data);
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final margin = TapeSpace.margin(widget.height);
    final data = _data;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Padding(
        padding: EdgeInsets.all(margin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TapeScrollSegmented<InsightTab>(
                    segments: [
                      for (final t in InsightTab.values)
                        TapeSegment(t, t.label),
                    ],
                    value: _tab,
                    onChanged: showTab,
                  ),
                ),
                const SizedBox(width: TapeSpace.s2),
                TapeButton(
                  label: 'Close',
                  icon: TapeIcon.close,
                  compact: true,
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: TapeSpace.s3),
            Expanded(
              child: data == null
                  ? Center(
                      child: TapeLabel(
                        'Reading your drives',
                        color: palette.inkMid,
                      ),
                    )
                  : _panel(data),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(InsightData data) => switch (_tab) {
    InsightTab.tank => TankPanel(reading: widget.tank(data.trips)),
  };
}

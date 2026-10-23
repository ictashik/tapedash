import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../insights/ghost_commute.dart';
import '../../../insights/insight_data.dart';
import '../../../insights/rest_voltage_log.dart';
import '../../../insights/tank_reading.dart';
import '../../../insights/voltage_trace.dart';
import '../../../platform/image_sharer.dart';
import '../../../trips/trip.dart';
import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/controls/tape_button.dart';
import '../../design/components/controls/tape_scroll_segmented.dart';
import '../../design/components/controls/tape_segmented.dart';
import '../../design/components/tape_label.dart';
import '../../design/icons/icons.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import 'cold_panel.dart';
import 'current_panel.dart';
import 'gears_panel.dart';
import 'ghost_panel.dart';
import 'power_panel.dart';
import 'powerflow_panel.dart';
import 'tank_panel.dart';
import 'tolls_panel.dart';
import 'year_panel.dart';

/// The pages of Insights (DESIGN.md 7.14), in the order of the selector.
enum InsightTab {
  current('Current'),
  powerflow('Powerflow'),
  power('Power'),
  gears('Gears'),
  tank('Tank'),
  tolls('Tolls'),
  cold('Cold start'),
  ghost('Ghost'),
  year('Year');

  const InsightTab(this.label);
  final String label;
}

/// Insights (DESIGN.md 7.14): what the car and the trips add up to, one picture at
/// a time. A scrolling selector across the top, one panel under it, and Close.
///
/// Parked only: it closes itself if the car starts to move. Real drives and the
/// simulated trips are never mixed in, which [load] decides.
class InsightsPage extends StatefulWidget {
  const InsightsPage({
    super.key,
    required this.load,
    required this.tank,
    required this.mode,
    required this.width,
    required this.height,
    required this.onClose,
    required this.selected,
    required this.rest,
    required this.sharer,
    required this.now,
    this.initial = InsightTab.current,
  });

  /// Reads the trips the panels draw from, when the page opens.
  final Future<InsightData> Function() load;

  /// The counted tank, given the trips to work the economy from.
  final TankReading? Function(Iterable<Trip> trips) tank;

  /// The trip Review is showing, for the panels that are about one trip.
  final Trip? Function() selected;

  /// Hands a picture to the phone's share sheet (Year on Tape).
  final ImageSharer sharer;

  /// The time, for the year the poster opens on.
  final DateTime Function() now;

  /// The battery's resting voltage, reading by reading.
  final List<RestReading> Function() rest;

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

  /// The trip the per-trip panels are about: the one Review is on, if the data
  /// has it, else the latest.
  Trip? _trip(InsightData data) {
    final wanted = widget.selected();
    for (final t in data.trips) {
      if (wanted != null && t.id == wanted.id) return t;
    }
    return data.trips.isEmpty ? null : data.trips.first;
  }

  /// The sweet spot as "55–70", or null until the car has one.
  String? _sweetSpot(InsightData data) {
    final r = data.sweetSpot.range;
    return r == null ? null : '${r.from}–${r.to}';
  }

  /// The earlier drive of the chosen trip's route, or, if it has none, of the
  /// latest trip that has one.
  GhostMatch? _ghost(InsightData data, Trip? chosen) {
    final own = chosen == null ? null : data.ghostOf(chosen);
    if (own != null) return own;
    for (final t in data.trips) {
      final g = data.ghostOf(t);
      if (g != null) return g;
    }
    return null;
  }

  /// The cold start to show: the chosen trip's if it started cold, else the
  /// latest trip that did.
  Widget _cold(InsightData data, Trip? chosen) {
    Trip? shown = chosen;
    var cold = shown == null ? null : data.coldStartOf(shown);
    if (cold == null) {
      for (final t in data.trips) {
        final c = data.coldStartOf(t);
        if (c != null) {
          shown = t;
          cold = c;
          break;
        }
      }
    }
    final (month, n) = shown == null
        ? (0.0, 0)
        : data.coldMonth(shown.startedAt);
    return ColdPanel(
      trip: cold == null ? null : shown,
      cold: cold,
      month: month,
      monthTrips: n,
    );
  }

  Widget _panel(InsightData data) {
    final trip = _trip(data);
    return switch (_tab) {
      InsightTab.current => CurrentPanel(
        trip: trip,
        trace: trip == null
            ? VoltageTrace.from(const [])
            : data.voltageOf(trip),
        rest: widget.rest(),
      ),
      InsightTab.powerflow => PowerflowPanel(
        trip: trip,
        flow: trip == null ? null : data.powerflowOf(trip),
      ),
      InsightTab.power => PowerPanel(curve: data.powerCurve),
      InsightTab.gears => GearsPanel(gearbox: data.gearbox),
      InsightTab.tank => TankPanel(reading: widget.tank(data.trips)),
      InsightTab.cold => _cold(data, trip),
      InsightTab.ghost => GhostPanel(match: _ghost(data, trip)),
      InsightTab.year => YearPanel(
        // A fresh panel for a fresh snapshot: the years it offers are the data's.
        key: ValueKey(data),
        years: data.years,
        build: data.year,
        sweetSpot: _sweetSpot(data),
        initialYear: data.yearFor(widget.now()),
        sharer: widget.sharer,
      ),
      InsightTab.tolls => TollsPanel(
        map: data.tollMap,
        since: data.trips.isEmpty ? null : data.trips.last.startedAt,
      ),
    };
  }
}

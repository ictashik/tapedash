import 'package:flutter/widgets.dart';

import '../../design/components/rolling_numerals.dart';
import '../../design/components/shift_horizon.dart';
import '../../design/components/status_strip.dart';
import '../../design/components/telemetry_tile.dart';
import '../../design/motion/smoothing_pipeline.dart';
import '../../design/tokens/spacing.dart';
import 'drive_signals.dart';

/// The Telemetry cluster (DESIGN.md 7.3.4), the enthusiast layout: a 2x3
/// grid of telemetry tiles, the shift horizon and the shared status strip
/// on top. The one dense layout, opt-in, never the default.
///
/// The six tiles are chosen from DESIGN.md 7.3.4's candidate list as the
/// six that have a real source today: RPM, speed, throttle, calculated
/// load, coolant and module voltage (the last two arriving as real
/// `DriveSignals` bindings now -- `VehicleState.load`/`.voltage` have
/// always existed, the poller has always read them on their tiers; the
/// grid is just their first reader). MAP or MAF, intake air and instant
/// km/L are the same list's remaining candidates: km/L needs `fuel/`
/// (phase 4), and the grid is "chosen from" the list rather than obliged
/// to show all of it, so those stay out until a real screen wants them and
/// can say why -- absent, not faked (CLAUDE.md 1), like every cluster's
/// unfilled slot. No tile thresholds are passed either: the tinted
/// brackets (DESIGN.md 6.6) would need per-vehicle limits this project has
/// no real source for yet.
class TelemetryCluster extends StatelessWidget {
  const TelemetryCluster({
    super.key,
    required this.signals,
    required this.width,
    required this.height,
  });

  final DriveSignals signals;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final margin = TapeSpace.margin(height);
    final tileWidth = (width - 2 * margin - 2 * TapeSpace.s3) / 3;
    final top = height * TapeSpace.clearOfCaptionsShare;
    final bottom = height * TapeSpace.clearOfDockShare;
    final tileHeight = (height - top - bottom - TapeSpace.s3) / 2;

    Widget tile(String label, SmoothedSignal signal, NumeralFormat format) =>
        TelemetryTile(
          label: label,
          value: signal,
          format: format,
          width: tileWidth,
          height: tileHeight,
          history: signals.historyOf(signal),
        );

    Widget row(List<Widget> tiles) => Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: TapeSpace.s3),
          tiles[i],
        ],
      ],
    );

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // The shared horizon, as every cluster lays it out.
          Positioned(
            top: TapeSpace.s2,
            left: 0,
            right: 0,
            child: Center(
              child: ShiftHorizon(
                rpm: signals.rpm,
                width: width * 0.5,
                heightReference: height,
              ),
            ),
          ),
          Positioned(
            top: TapeSpace.s2,
            left: TapeSpace.s4,
            child: StatusStripLeft(
              adapter: signals.adapter,
              gpsHasFix: signals.gpsHasFix,
              parkedShare: signals.parkedShare,
            ),
          ),
          Positioned(
            top: TapeSpace.s2,
            right: TapeSpace.s4,
            child: StatusStripRight(
              demoMode: signals.demoMode,
              time: signals.wallClock,
              use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
              phoneHot: signals.phoneHot,
              parkedShare: signals.parkedShare,
            ),
          ),

          // The grid, in the centre zone between the shared horizon and
          // floor zones.
          Positioned(
            top: top,
            bottom: bottom,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: margin),
              child: Column(
                children: [
                  row([
                    tile(
                      'RPM',
                      signals.rpm,
                      const NumeralFormat(integerDigits: 4),
                    ),
                    tile(
                      'SPEED',
                      signals.speed,
                      const NumeralFormat(integerDigits: 3),
                    ),
                    tile(
                      'THROTTLE',
                      signals.throttle,
                      const NumeralFormat(integerDigits: 3),
                    ),
                  ]),
                  const SizedBox(height: TapeSpace.s3),
                  row([
                    tile(
                      'LOAD',
                      signals.load,
                      const NumeralFormat(integerDigits: 3),
                    ),
                    tile(
                      'COOLANT',
                      signals.coolant,
                      const NumeralFormat(integerDigits: 3),
                    ),
                    tile(
                      'VOLTS',
                      signals.voltage,
                      const NumeralFormat(integerDigits: 3, decimals: 1),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

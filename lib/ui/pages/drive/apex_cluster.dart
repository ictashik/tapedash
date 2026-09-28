import 'package:flutter/widgets.dart';

import '../../design/components/bar_gauge.dart';
import '../../design/components/centered_numeral.dart';
import '../../design/components/rolling_numerals.dart';
import '../../design/components/shift_horizon.dart';
import '../../design/components/status_strip.dart';
import '../../design/components/tach_arc.dart';
import '../../design/components/tape_label.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import 'drive_signals.dart';

/// The Apex cluster (DESIGN.md 7.3.1, Drive's default layout): the hero speed
/// inside the tach arc, the coolant gauge on the flank away from the driver,
/// the shift horizon and status strip on the horizon.
///
/// **What is not here yet, on purpose:** the driver-side flank's ₹ THIS TRIP
/// and ₹/KM, the coolant flank's instant km/L, the floor's eco bar and trip
/// distance/time. All five need `fuel/`, `money/` or `trips/` (CLAUDE.md 13's
/// phase 4), none of which exist yet, and CLAUDE.md 1 asks for honest
/// numbers over an invented one, so these slots are simply absent rather
/// than shown with a placeholder or a fake value. `DriveSignals`'s own doc
/// comment says the same for whoever reaches for one of them next.
class ApexCluster extends StatelessWidget {
  const ApexCluster({
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
    final theme = TapeTheme.of(context);
    final tachBox = TachArc.boxSideOf(height);
    final onDriverSideRight = theme.driverSide == DriverSide.right;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // Horizon: the shift horizon across the top, the status strip's
          // two flanks either side of it (DESIGN.md 6.9's "on either side").
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
            ),
          ),
          Positioned(
            top: TapeSpace.s2,
            right: TapeSpace.s4,
            child: StatusStripRight(
              time: signals.wallClock,
              use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
              phoneHot: signals.phoneHot,
            ),
          ),

          // Centre: the tach arc ringing the hero speed and its label.
          Center(
            child: SizedBox(
              width: tachBox,
              height: tachBox,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TachArc(rpm: signals.rpm, heightReference: height),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CenteredNumeral(
                        source: signals.speed,
                        format: const NumeralFormat(integerDigits: 3),
                        typicalIntegerDigits: 2,
                        size: TypeScale.forHeight(height).hero,
                        role: NumeralRole.bright,
                      ),
                      const SizedBox(height: 2),
                      const TapeLabel('KM/H'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // The flank away from the driver: the coolant gauge. (The
          // driver-side flank is the money readout's place, DESIGN.md 7.3 --
          // empty for now; see this class's own doc comment.)
          Positioned(
            top: 0,
            bottom: 0,
            left: onDriverSideRight ? TapeSpace.s6 : null,
            right: onDriverSideRight ? null : TapeSpace.s6,
            child: Center(
              child: BarGauge(
                value: signals.coolant,
                min: 0,
                max: 130,
                length: height * 0.4,
                label: 'COOLANT',
                vertical: true,
                normalBandMin: 80,
                normalBandMax: 100,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

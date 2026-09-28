import 'package:flutter/widgets.dart';

import '../../design/components/rolling_numerals.dart';
import '../../design/components/shift_horizon.dart';
import '../../design/components/status_strip.dart';
import '../../design/components/vertical_tape.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/tach.dart';
import '../../design/tokens/vertical_tape.dart';
import 'drive_signals.dart';

/// The Tape cluster (DESIGN.md 7.3.2), the brand layout: the speed tape on
/// the left and the RPM tape on the right, both with their trend vectors
/// (the tapes carry them themselves, DESIGN.md 6.3), on the shared horizon.
///
/// The shared zones (DESIGN.md 4.7's horizon and floor, DESIGN.md 7.3's
/// "all clusters share the horizon and floor") get the same horizon content
/// Apex has -- the shift horizon centred and the status strip's flanks --
/// with the tapes filling the centre zone between horizon and floor. The
/// flanks' exact positions follow `ApexCluster`'s, since the horizon is
/// shared chrome, not per-cluster layout.
///
/// **What is not here yet, on purpose:** the centre's instant km/L at
/// display size and the eco bar beneath it, and the floor's ₹ THIS TRIP
/// (DESIGN.md 7.3.2). All three need `fuel/`, `money/` or `trips/` (CLAUDE.md
/// 13's phase 4), so the centre is simply empty and the floor is simply
/// absent rather than faked (CLAUDE.md 1). The speed tape's tinted band
/// waits the same way: DESIGN.md 6.3 tints the band from "the user's speed
/// threshold", and the user-threshold setting that would feed it arrives
/// with the coach's thresholds (phase 5); the RPM tape's band is real now,
/// starting at the same redline the tach arc uses.
class TapeCluster extends StatelessWidget {
  const TapeCluster({
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
    final tapeWidth = width * TapeVerticalTape.widthShareOfW;
    final top = height * TapeSpace.horizonShare;
    final floor = height * TapeSpace.floorShare;
    final tapeHeight = height - top - floor;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // The shared horizon, exactly as Apex lays it out: the shift
          // horizon across the centre, the status strip's flanks either
          // side of it.
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
              time: signals.wallClock,
              use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
              phoneHot: signals.phoneHot,
              parkedShare: signals.parkedShare,
            ),
          ),

          // The tapes, in the centre zone between horizon and floor. The
          // speed tape's readout straddles its inner (right) edge, the RPM
          // tape's its inner (left) edge, both facing the centre the way
          // DESIGN.md 6.3 draws them.
          Positioned(
            top: top,
            left: 0,
            width: tapeWidth,
            height: tapeHeight,
            child: VerticalTape(
              value: signals.speed,
              halfWindow: 30,
              minorTickInterval: 5,
              majorTickInterval: 10,
              format: const NumeralFormat(integerDigits: 3),
              width: tapeWidth,
              height: tapeHeight,
              readoutSide: TapeReadoutSide.right,
            ),
          ),
          Positioned(
            top: top,
            right: 0,
            width: tapeWidth,
            height: tapeHeight,
            child: VerticalTape(
              value: signals.rpm,
              halfWindow: 2000,
              minorTickInterval: 250,
              majorTickInterval: 1000,
              format: const NumeralFormat(integerDigits: 4),
              width: tapeWidth,
              height: tapeHeight,
              readoutSide: TapeReadoutSide.left,
              thresholdValue: TapeTach.defaultRedlineRpm,
            ),
          ),

          // The centre's instant km/L and eco bar, and the floor's ₹ THIS
          // TRIP, are phase 4's; see this class's own doc comment.
        ],
      ),
    );
  }
}

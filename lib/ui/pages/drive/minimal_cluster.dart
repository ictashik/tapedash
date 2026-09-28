import 'package:flutter/widgets.dart';

import '../../design/components/centered_numeral.dart';
import '../../design/components/parked_scale.dart';
import '../../design/components/rolling_numerals.dart';
import '../../design/components/shift_horizon.dart';
import '../../design/components/status_strip.dart';
import '../../design/motion/smoothing_pipeline.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/tach.dart';
import '../../design/tokens/typography.dart';
import 'drive_signals.dart';

/// The Minimal cluster (DESIGN.md 7.3.3): the hero speed and a thin RPM
/// line under its digits, nothing else. Best at night, per the design.
///
/// The shared horizon (DESIGN.md 4.7's zones, DESIGN.md 7.3's "all clusters
/// share the horizon and floor") carries the same content Apex and Tape
/// give it -- the shift horizon centred and the status strip's flanks.
/// "Hero speed only" is read as the centre zone's content, not the
/// horizon's.
///
/// The parked choreography (DESIGN.md 7.2) reads the same parked share the
/// other clusters do: parked, the hero shrinks to primary size.
///
/// **What is not here yet, on purpose:** the driver-side corner's small
/// money readout (DESIGN.md 7.3.3), which needs `money/` (CLAUDE.md 13's
/// phase 4). Absent rather than faked (CLAUDE.md 1), like every cluster's
/// money slot.
class MinimalCluster extends StatelessWidget {
  const MinimalCluster({
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
    final type = TypeScale.forHeight(height);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // The shared horizon, as Apex and Tape lay it out.
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

          // The hero, in the centre zone between horizon and floor, with
          // the thin RPM line under its digits. Parked, the hero shrinks to
          // primary size on the parked share (DESIGN.md 7.2). (The
          // driver-side corner's money readout is phase 4's; see this
          // class's own doc comment.)
          Positioned(
            top: height * TapeSpace.horizonShare,
            bottom: height * TapeSpace.floorShare,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ParkedScale(
                    share: signals.parkedShare,
                    parkedScaleShare: type.primary / type.hero,
                    child: CenteredNumeral(
                      source: signals.speed,
                      format: const NumeralFormat(integerDigits: 3),
                      typicalIntegerDigits: 2,
                      size: type.hero,
                      role: NumeralRole.bright,
                    ),
                  ),
                  const SizedBox(height: TapeSpace.s2),
                  SizedBox(
                    width: extentShare * width,
                    height: RpmLinePainter.thickness,
                    child: CustomPaint(
                      painter: RpmLinePainter(
                        rpm: signals.rpm,
                        palette: TapeTheme.of(context).palette,
                        maxRpm: TapeTach.defaultMaxRpm,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The RPM line's full extent, as a share of the frame's width: modest,
  /// so it reads as part of the hero rather than a rival instrument.
  static const double extentShare = 0.25;
}

/// The thin RPM line under the hero's digits (DESIGN.md 7.3.3): centred
/// and symmetric, its length follows RPM from 0 at standstill to the full
/// extent at the tach's default max. Accent, the live-data colour.
class RpmLinePainter extends CustomPainter {
  RpmLinePainter({
    required this.rpm,
    required this.palette,
    required this.maxRpm,
  }) : super(repaint: rpm);

  /// The live RPM, already smoothed (`spring.needle`, as every signal
  /// `DriveSignals` exposes is).
  final SmoothedSignal rpm;
  final TapePalette palette;
  final double maxRpm;

  /// The line's thickness, in logical pixels.
  static const double thickness = 3;

  @override
  void paint(Canvas canvas, Size size) {
    if (!rpm.hasValue) return;
    final share = shareFor(rpm.value, maxRpm);
    if (share <= 0) return;
    final half = size.width * share / 2;
    canvas.drawLine(
      Offset(size.width / 2 - half, size.height / 2),
      Offset(size.width / 2 + half, size.height / 2),
      Paint()
        ..color = palette.accentCore
        ..strokeWidth = thickness,
    );
  }

  /// The line's length as a share of its extent, for [rpm] out of [maxRpm]:
  /// 0 at and below 0, rising to 1 at the max, so a value past the max
  /// cannot overrun the line. Exposed for a direct test.
  static double shareFor(double rpm, double maxRpm) =>
      maxRpm <= 0 ? 0.0 : (rpm / maxRpm).clamp(0.0, 1.0);

  @override
  bool shouldRepaint(RpmLinePainter old) =>
      old.palette != palette ||
      old.maxRpm != maxRpm ||
      !identical(old.rpm, rpm);
}

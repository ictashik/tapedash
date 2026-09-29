import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design/components/bar_gauge.dart';
import '../../design/components/centered_numeral.dart';
import '../../design/components/numeral_format.dart';
import '../../design/components/parked_scale.dart';
import '../../design/components/presence.dart';
import '../../design/components/shared_element_end.dart';
import '../../design/components/shift_horizon.dart';
import '../../design/components/status_strip.dart';
import '../../design/components/tach_arc.dart';
import '../../design/components/tape_label.dart';
import '../../design/motion/shared_elements.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/tach.dart';
import '../../design/tokens/typography.dart';
import '../strip/the_strip.dart';
import 'drive_signals.dart';

/// The Apex cluster (DESIGN.md 7.3.1, Drive's default layout): the hero speed
/// inside the tach arc, the coolant gauge on the flank away from the driver,
/// the shift horizon and status strip on the horizon.
///
/// The parked choreography (DESIGN.md 7.2) reads the one parked share the
/// signals carry: parked, the tach arc thins and dims to 60% (stagger 0) and
/// the hero shrinks to primary size (stagger 1, the spec's own order); in
/// motion the reverse runs inside the 300 ms the motion return allows.
///
/// **What is not here yet, on purpose:** the driver-side flank's ₹ THIS TRIP
/// and ₹/KM, the coolant flank's instant km/L, the floor's eco bar and trip
/// distance/time, and the flanks' unfolded detail panels (trip stats, fuel,
/// calibration) the Parked choreography asks for. All need `fuel/`, `money/`
/// or `trips/` (CLAUDE.md 13's phase 4), none of which exist yet, and
/// CLAUDE.md 1 asks for honest numbers over an invented one, so these slots
/// are simply absent rather than shown with a placeholder or a fake value.
/// `DriveSignals`'s own doc comment says the same for whoever reaches for
/// one of them next.
class ApexCluster extends StatelessWidget {
  const ApexCluster({
    super.key,
    required this.signals,
    required this.width,
    required this.height,
    this.heroSlotActive,
  });

  final DriveSignals signals;
  final double width;
  final double height;

  /// While not null, the shared-element registration only exists while this
  /// cluster is the nearest in the reel. Provided by [DrivePage].
  final ValueListenable<bool>? heroSlotActive;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final tachBox = TachArc.boxSideOf(height);
    final type = TypeScale.forHeight(height);
    final onDriverSideRight = theme.driverSide == DriverSide.right;
    final heroFade = SharedElementsScope.maybeOf(
      context,
    )?.ownShareOf(SharedElementIds.speed, SharedElementEndKind.from);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // Horizon: the shift horizon across the top, the status strip's
          // two flanks either side of it (DESIGN.md 6.9's "on either side").
          // Parked, the strip's glyphs gain their captions (DESIGN.md 6.9's
          // "text labels appear in Parked mode"), on the same parked share.
          Positioned(
            top: TapeSpace.s2,
            left: 0,
            right: 0,
            child: Center(
              child: ShiftHorizon(
                rpm: signals.rpm,
                width: width * 0.5,
                heightReference: height,
                drawShare: signals.horizonDraw,
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

          // Centre: the tach arc ringing the hero speed and its label. The
          // arc thins and dims first (stagger 0), the hero follows (stagger
          // 1), the order DESIGN.md 7.2 itself lists them in.
          // The arc's box is taller than the screen (radius 0.44H, then the
          // ticks and labels round it), so centred it clips its own top
          // labels; the opening at the bottom leaves room to sit it lower.
          Positioned(
            left: 0,
            right: 0,
            top: height * (0.5 + TapeTach.centreDropShare) - tachBox / 2,
            height: tachBox,
            child: Center(
              child: SizedBox(
                width: tachBox,
                height: tachBox,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TachArc(
                      rpm: signals.rpm,
                      heightReference: height,
                      parkedShare: signals.parkedShare,
                      litShare: signals.arcWave,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SharedElementEnd(
                          id: SharedElementIds.speed,
                          end: SharedElementEndKind.from,
                          page: TheStrip.homePage,
                          size: type.hero,
                          source: signals.speed,
                          format: const NumeralFormat(integerDigits: 3),
                          typicalIntegerDigits: 2,
                          role: NumeralRole.bright,
                          parkedShare: signals.parkedShare,
                          parkedScaleShare: type.primary / type.hero,
                          staggerIndex: 1,
                          active: heroSlotActive,
                          child: ParkedScale(
                            share: signals.parkedShare,
                            parkedScaleShare: type.primary / type.hero,
                            staggerIndex: 1,
                            child: CenteredNumeral(
                              source: signals.speed,
                              format: const NumeralFormat(integerDigits: 3),
                              typicalIntegerDigits: 2,
                              size: type.hero,
                              role: NumeralRole.bright,
                              presence: heroFade,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        // The numeral's own box is far taller than its ink (the
                        // detent and roll room), which left the unit near the
                        // floor, under the parked dock: it is drawn up to sit
                        // just under the digits, with no change to the layout.
                        Transform.translate(
                          offset: Offset(
                            0,
                            -(NumeralMetrics(type.hero).boxHeight -
                                        NumeralMetrics(type.hero).inkHeight) /
                                    2 +
                                height * TapeTach.unitGapShare,
                          ),
                          child: const TapeLabel('KM/H'),
                        ),
                      ],
                    ),
                  ],
                ),
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
            child: Presence(
              share: signals.flankAway,
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
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/widgets.dart';

import '../../design/components/centered_numeral.dart';
import '../../design/components/numeral_format.dart';
import '../../design/components/shared_element_end.dart';
import '../../design/components/tape_label.dart';
import '../../design/motion/shared_elements.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../drive/drive_signals.dart';
import '../strip/the_strip.dart';

/// The Money page (DESIGN.md 7.4) as it exists before phase 4.
///
/// The page's honest placeholder centre says what it is and what it waits for
/// (CLAUDE.md 1: never invent data), while the status-corner speed readout is
/// real -- the shared-element transition (DESIGN.md 7.1) lands the hero speed
/// here when the user swipes from Drive to Money. The centre's ₹ THIS TRIP
/// (display size) and the rest of the page's content arrive with `money/`
/// (phase 4).
class MoneyPage extends StatelessWidget {
  const MoneyPage({
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
    final palette = TapeTheme.of(context).palette;
    final toShare = SharedElementsScope.maybeOf(
      context,
    )?.ownShareOf(SharedElementIds.speed, SharedElementEndKind.to);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // The honest placeholder centre.
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TapeLabel('MONEY', size: 14),
                const SizedBox(height: TapeSpace.s2),
                TapeText(
                  'Arrives with the money engine.',
                  color: palette.inkMid,
                ),
              ],
            ),
          ),
          // The status-corner speed readout (DESIGN.md 7.1 shared-element
          // landing). Real data, registered as the to-end of the speed
          // flight.
          Positioned(
            top: TapeSpace.s4,
            right: TapeSpace.s4,
            child: SharedElementEnd(
              id: SharedElementIds.speed,
              end: SharedElementEndKind.to,
              page: TheStrip.moneyPage,
              size: type.secondary,
              source: signals.speed,
              format: const NumeralFormat(integerDigits: 3),
              typicalIntegerDigits: 2,
              role: NumeralRole.bright,
              child: CenteredNumeral(
                source: signals.speed,
                format: const NumeralFormat(integerDigits: 3),
                typicalIntegerDigits: 2,
                size: type.secondary,
                role: NumeralRole.bright,
                presence: toShare,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

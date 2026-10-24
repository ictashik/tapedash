import 'package:flutter/widgets.dart';

import '../../design/components/money.dart' show MoneyBlock;
import '../../design/components/numeral_format.dart';
import '../../design/components/tape_label.dart';
import '../../design/components/watch/money_ring.dart';
import '../../design/components/watch/watch_face.dart';
import '../../design/icons/icons.dart';
import '../../design/theme/tape_theme.dart';
import '../drive/drive_signals.dart';
import '../drive/money_slots.dart';
import '../money/money_figure.dart';
import '../money/money_signals.dart';

/// The watch's Money face (DESIGN.md 16.5): ₹ THIS TRIP at display size in the
/// core, with the money ring round the rim (every rupee a cell, printed clockwise
/// from 12 o'clock), ₹/km beneath, and what idling has cost.
///
/// With no price set the figure is litres, and a car that gives no fuel figure
/// says so (CLAUDE.md 1.6): nothing is invented to fill the ring.
class WatchMoneyFace extends StatelessWidget {
  const WatchMoneyFace({super.key, required this.signals, required this.face});

  final DriveSignals signals;
  final WatchFace face;

  @override
  Widget build(BuildContext context) {
    final money = signals.money;
    final type = face.type;
    if (money == null) return const SizedBox.shrink();
    final palette = TapeTheme.of(context).palette;
    return SizedBox.square(
      dimension: face.diameter,
      child: Stack(
        children: [
          Positioned.fill(
            child: MoneyRing(
              blocks: money.blocks,
              face: face,
              dimShare: signals.parkedShare,
            ),
          ),
          // The label over the figure.
          Positioned(
            left: 0,
            right: 0,
            top: face.heroY - type.display * 0.95,
            child: Center(
              child: ValueListenableBuilder<MoneyView>(
                valueListenable: money.view,
                builder: (context, view, _) => TapeLabel(switch (view) {
                  MoneyView.rupees => '₹ this trip',
                  MoneyView.litres => 'litres this trip',
                  MoneyView.unavailable => 'no fuel data',
                }, size: type.label),
              ),
            ),
          ),
          // The figure.
          Positioned(
            left: 0,
            right: 0,
            top: face.heroY - NumeralMetrics(type.display).boxHeight / 2,
            height: NumeralMetrics(type.display).boxHeight,
            child: Center(
              child: MoneyFigure(
                money: money,
                size: type.display,
                integerDigits: 5,
              ),
            ),
          ),
          // ₹/km, then the idle cost, each centred on its own line.
          _centred(
            y: face.diameter * 0.665,
            height: NumeralMetrics(type.secondary).boxHeight,
            child: ValueListenableBuilder<MoneyView>(
              valueListenable: money.view,
              builder: (context, view, _) => view == MoneyView.rupees
                  ? GatedNumeral(
                      available: money.costPerKmAvailable,
                      source: money.costPerKm,
                      format: rateFormat,
                      size: type.secondary,
                      prefix: '₹',
                      unit: '/KM',
                      role: NumeralRole.money,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          _centred(
            y: face.diameter * 0.765,
            height: NumeralMetrics(type.secondary * 0.8).boxHeight,
            child: ValueListenableBuilder<MoneyView>(
              valueListenable: money.view,
              builder: (context, view, _) => view == MoneyView.rupees
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TapeIconView(
                          TapeIcon.idle,
                          size: type.label,
                          color: palette.caution,
                        ),
                        SizedBox(width: type.label * 0.5),
                        LabeledNumeral(
                          source: money.idleCost,
                          format: const NumeralFormat(integerDigits: 4),
                          size: type.secondary * 0.8,
                          prefix: '₹',
                          role: NumeralRole.caution,
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          // What a cell stands for, once it is more than one rupee.
          Positioned(
            left: 0,
            right: 0,
            top: face.diameter * 0.915,
            child: Center(
              child: ValueListenableBuilder<List<MoneyBlock>>(
                valueListenable: money.blocks,
                builder: (context, blocks, _) {
                  final label = MoneyRingCells.of(blocks).scaleLabel;
                  return label == null
                      ? const SizedBox.shrink()
                      : TapeLabel(label, size: type.label);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [child] centred on the line [y] down the face, in a box [height] tall.
Widget _centred({
  required double y,
  required double height,
  required Widget child,
}) => Positioned(
  left: 0,
  right: 0,
  top: y - height / 2,
  height: height,
  child: Center(child: child),
);

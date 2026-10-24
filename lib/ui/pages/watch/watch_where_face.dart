import 'package:flutter/widgets.dart';

import '../../../money/spend_bucket.dart';
import '../../design/components/numeral_format.dart';
import '../../design/components/tape_label.dart';
import '../../design/components/watch/money_ring.dart';
import '../../design/components/watch/watch_face.dart';
import '../../design/motion/numeral_source.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../drive/drive_signals.dart';
import '../money/money_figure.dart' show LabeledNumeral;
import '../money/money_signals.dart';

/// WHERE IT WENT on the watch (DESIGN.md 16.5): the trip's four buckets as four
/// rows (swatch, name, ₹) inside the money ring, which is by now the trip's whole
/// barcode. Idling is the one the app calls avoidable and the others say what
/// happened (DESIGN.md 10). The figures are estimates and say so.
class WatchWhereFace extends StatelessWidget {
  const WatchWhereFace({super.key, required this.signals, required this.face});

  final DriveSignals signals;
  final WatchFace face;

  /// The rows' own names: short enough for the chord.
  static String shortName(SpendBucket b) => switch (b) {
    SpendBucket.normal => 'Normal',
    SpendBucket.idling => 'Idling',
    SpendBucket.hardAcceleration => 'Hard accel',
    SpendBucket.highSpeed => 'High speed',
  };

  @override
  Widget build(BuildContext context) {
    final money = signals.money;
    if (money == null) return const SizedBox.shrink();
    final type = face.type;
    final palette = TapeTheme.of(context).palette;
    final rowWidth = face.diameter * 0.68;
    return SizedBox.square(
      dimension: face.diameter,
      child: Stack(
        children: [
          Positioned.fill(
            child: MoneyRing(blocks: money.blocks, face: face),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: face.diameter * 0.255,
            child: Center(child: TapeLabel('Where it went', size: type.label)),
          ),
          ValueListenableBuilder<MoneyView>(
            valueListenable: money.view,
            builder: (context, view, _) => view != MoneyView.rupees
                ? Positioned(
                    left: 0,
                    right: 0,
                    top: face.heroY,
                    child: Center(
                      child: TapeLabel(
                        view == MoneyView.litres
                            ? 'set the price first'
                            : 'no fuel data',
                        size: type.label,
                        color: palette.inkMid,
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      for (final (i, b) in SpendBucket.values.indexed)
                        Positioned(
                          left: (face.diameter - rowWidth) / 2,
                          width: rowWidth,
                          top: face.diameter * (0.318 + 0.105 * i),
                          height: type.secondary * 1.2,
                          child: _Row(
                            bucket: b,
                            name: shortName(b),
                            cost: money.bucketCost[b]!,
                            size: type.secondary * 0.9,
                            label: type.label,
                            palette: palette,
                          ),
                        ),
                    ],
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: face.diameter * 0.775,
            child: Center(
              child: TapeLabel(
                '≈ estimates',
                size: type.label,
                color: palette.inkDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.bucket,
    required this.name,
    required this.cost,
    required this.size,
    required this.label,
    required this.palette,
  });

  final SpendBucket bucket;
  final String name;
  final NumeralSource cost;
  final double size;
  final double label;
  final TapePalette palette;

  @override
  Widget build(BuildContext context) {
    final (colour, hollow) = switch (bucket) {
      SpendBucket.normal => (palette.moneyDeep, false),
      SpendBucket.idling => (palette.caution, true),
      SpendBucket.hardAcceleration => (palette.critical, false),
      SpendBucket.highSpeed => (palette.accentDeep, false),
    };
    return Row(
      children: [
        SizedBox.square(
          dimension: label * 0.8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: hollow ? null : colour,
              border: hollow ? Border.all(color: colour, width: 1.4) : null,
            ),
          ),
        ),
        SizedBox(width: label * 0.6),
        Expanded(child: TapeLabel(name, size: label * 0.92)),
        LabeledNumeral(
          source: cost,
          format: const NumeralFormat(integerDigits: 4),
          size: size,
          prefix: '₹',
          role: NumeralRole.money,
        ),
      ],
    );
  }
}

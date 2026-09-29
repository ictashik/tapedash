import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../money/spend_bucket.dart';
import '../../design/components/rolling_numerals.dart';
import '../../design/components/tape_label.dart';
import '../../design/motion/numeral_source.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/strokes.dart';
import 'money_signals.dart';

/// The words for a bucket (DESIGN.md 10): idling is "avoidable"; the others say
/// what happened and never "wasted".
String bucketLabel(SpendBucket b) => switch (b) {
  SpendBucket.normal => 'Normal driving',
  SpendBucket.idling => 'Idling (avoidable)',
  SpendBucket.hardAcceleration => 'Hard acceleration',
  SpendBucket.highSpeed => 'High speed',
};

/// WHERE IT WENT (DESIGN.md 7.4, 7.5): a stacked bar of the four buckets and a
/// legend of rupees and percent. The styles are the Money Tape's, so the bar and
/// the tape read as the same thing: normal solid `money.deep`, idling a hollow
/// `caution` outline, hard acceleration solid `critical` with a notch, high speed
/// solid `accent.deep`.
class BucketBreakdown extends StatelessWidget {
  const BucketBreakdown({
    super.key,
    required this.money,
    required this.width,
    this.labelSize = 11,
    this.numeralSize = 18,
  });

  final MoneySignals money;
  final double width;
  final double labelSize;
  final double numeralSize;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TapeLabel('Where it went', size: labelSize),
          const SizedBox(height: TapeSpace.s2),
          SizedBox(
            width: width,
            height: 12,
            child: CustomPaint(
              painter: BucketBarPainter(
                shares: money.bucketPercent,
                palette: palette,
              ),
            ),
          ),
          const SizedBox(height: TapeSpace.s3),
          for (final b in SpendBucket.values) ...[
            _LegendRow(
              bucket: b,
              cost: money.bucketCost[b]!,
              percent: money.bucketPercent[b]!,
              palette: palette,
              labelSize: labelSize,
              numeralSize: numeralSize,
              width: width,
            ),
            const SizedBox(height: TapeSpace.s1),
          ],
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.bucket,
    required this.cost,
    required this.percent,
    required this.palette,
    required this.labelSize,
    required this.numeralSize,
    required this.width,
  });

  final SpendBucket bucket;
  final NumeralSource cost;
  final NumeralSource percent;
  final TapePalette palette;
  final double labelSize;
  final double numeralSize;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: numeralSize * 1.05,
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 10,
            child: CustomPaint(
              painter: BucketSwatchPainter(bucket: bucket, palette: palette),
            ),
          ),
          const SizedBox(width: TapeSpace.s2),
          Expanded(child: TapeLabel(bucketLabel(bucket), size: labelSize)),
          // The numerals' own boxes are far taller than their ink; the row is a
          // fixed height and lets them overflow, centred.
          SizedBox(
            width: numeralSize * 3.4,
            height: numeralSize,
            child: OverflowBox(
              maxHeight: NumeralMetrics(numeralSize).boxHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  RollingNumerals(
                    source: cost,
                    format: const NumeralFormat(
                      integerDigits: 4,
                      grouping: DigitGrouping.indian,
                    ),
                    size: numeralSize,
                    role: NumeralRole.money,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: numeralSize * 2.6,
            height: numeralSize,
            child: OverflowBox(
              maxHeight: NumeralMetrics(numeralSize * 0.8).boxHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  RollingNumerals(
                    source: percent,
                    format: const NumeralFormat(integerDigits: 3),
                    size: numeralSize * 0.8,
                    role: NumeralRole.mid,
                  ),
                  const SizedBox(width: 2),
                  TapeLabel('%', size: labelSize),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A block's own style as a small swatch, so the legend matches the tape.
class BucketSwatchPainter extends CustomPainter {
  BucketSwatchPainter({required this.bucket, required this.palette});

  final SpendBucket bucket;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) =>
      paintBucketBlock(canvas, Offset.zero & size, bucket, palette);

  @override
  bool shouldRepaint(BucketSwatchPainter old) =>
      old.bucket != bucket || old.palette != palette;
}

/// Paints one block of [bucket] in [rect]: the one place the four styles are
/// written down for the breakdown.
void paintBucketBlock(
  Canvas canvas,
  Rect rect,
  SpendBucket bucket,
  TapePalette palette,
) {
  switch (bucket) {
    case SpendBucket.normal:
      canvas.drawRect(rect, Paint()..color = palette.moneyDeep);
    case SpendBucket.idling:
      canvas.drawRect(
        rect.deflate(0.75),
        Paint()
          ..color = palette.caution
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    case SpendBucket.hardAcceleration:
      canvas.drawRect(rect, Paint()..color = palette.critical);
      // The notch: a corner cut out, so it is not told by colour alone.
      final n = rect.shortestSide * 0.4;
      canvas.drawPath(
        Path()
          ..moveTo(rect.right - n, rect.top)
          ..lineTo(rect.right, rect.top)
          ..lineTo(rect.right, rect.top + n)
          ..close(),
        Paint()..color = palette.canvas,
      );
    case SpendBucket.highSpeed:
      canvas.drawRect(rect, Paint()..color = palette.accentDeep);
  }
}

/// The stacked bar: each bucket's share of the fuel, side by side.
class BucketBarPainter extends CustomPainter {
  BucketBarPainter({required this.shares, required this.palette})
    : super(repaint: Listenable.merge(shares.values.toList()));

  final Map<SpendBucket, NumeralSource> shares;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    var total = 0.0;
    for (final s in shares.values) {
      total += s.value.clamp(0.0, 100.0);
    }
    // Nothing yet: an etched track, not an empty gap.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = palette.etchStrong
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = TapeStroke.fine,
    );
    if (total <= 0) return;
    var x = 0.0;
    for (final b in SpendBucket.values) {
      final w = size.width * shares[b]!.value.clamp(0.0, 100.0) / total;
      if (w >= 1) {
        paintBucketBlock(
          canvas,
          Rect.fromLTWH(x, 0, w - 1, size.height),
          b,
          palette,
        );
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(BucketBarPainter old) => old.palette != palette;
}

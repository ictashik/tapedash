import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../motion/smoothing_pipeline.dart';
import '../render/chamfer.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/bar_gauge.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'rolling_numerals.dart';
import 'tape_label.dart';

/// A horizontal or vertical bar gauge (DESIGN.md 6.5): a chamfered track, a
/// fill from `accent.deep` to `accent.core` at its leading edge, an etched
/// normal band, a bright leading-edge line, and the value in secondary
/// numerals with a label at the track's end.
///
/// The fill's position is a pure function of the smoothed value (DESIGN.md
/// 5.1): [value] should already be sprung with `spring.needle`, the same as
/// the tach arc's.
class BarGauge extends StatelessWidget {
  const BarGauge({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.length,
    required this.label,
    this.thickness = TapeBarGauge.defaultThickness,
    this.vertical = false,
    this.normalBandMin,
    this.normalBandMax,
    this.decimals = 0,
  });

  /// The live value, smoothed with `spring.needle`.
  final SmoothedSignal value;

  final double min;
  final double max;

  /// The track's length along its main axis, in logical pixels.
  final double length;

  final double thickness;

  /// True for a vertical gauge filling upward; false for horizontal, filling
  /// left to right.
  final bool vertical;

  /// The etched normal band (DESIGN.md 6.5: "e.g. coolant 80-100 C"), or null
  /// for a gauge with no normal range (DESIGN.md is silent on omitting the
  /// band; a gauge with nothing to compare against, such as throttle, has none).
  final double? normalBandMin;
  final double? normalBandMax;

  final String label;

  /// Decimals in the readout (DESIGN.md 6.5 shows whole degrees for coolant).
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    final track = SizedBox(
      width: vertical ? thickness : length,
      height: vertical ? length : thickness,
      child: CustomPaint(
        painter: BarGaugePainter(
          listenable: value,
          value: value,
          min: min,
          max: max,
          length: length,
          thickness: thickness,
          vertical: vertical,
          normalBandMin: normalBandMin,
          normalBandMax: normalBandMax,
          palette: palette,
        ),
      ),
    );
    final readout = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        RollingNumerals(
          source: value,
          format: NumeralFormat(
            integerDigits: max.abs().toStringAsFixed(0).length,
            decimals: decimals,
          ),
          size: TypeScale.forHeight(360).secondary,
          role: NumeralRole.bright,
        ),
        const SizedBox(width: TapeSpace.s1),
        TapeLabel(label, size: 10),
      ],
    );

    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          readout,
          const SizedBox(height: TapeSpace.s1),
          track,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        track,
        const SizedBox(width: TapeSpace.s2),
        readout,
      ],
    );
  }
}

class BarGaugePainter extends CustomPainter {
  BarGaugePainter({
    required Listenable listenable,
    required this.value,
    required this.min,
    required this.max,
    required this.length,
    required this.thickness,
    required this.vertical,
    required this.normalBandMin,
    required this.normalBandMax,
    required this.palette,
  }) : super(repaint: listenable);

  final SmoothedSignal value;
  final double min, max, length, thickness;
  final bool vertical;
  final double? normalBandMin, normalBandMax;
  final TapePalette palette;

  final Path _path = Path();

  double _shareOf(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final chamfer = thickness * TapeBarGauge.chamferShareOfThickness;

    Chamfer.polygonInto(_path, [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ], chamfer);
    canvas.drawPath(_path, Paint()..color = palette.track);

    final bandMin = normalBandMin;
    final bandMax = normalBandMax;
    if (bandMin != null && bandMax != null) {
      final from = _shareOf(bandMin);
      final to = _shareOf(bandMax);
      final bandRect = vertical
          ? Rect.fromLTRB(
              0,
              size.height * (1 - to),
              size.width,
              size.height * (1 - from),
            )
          : Rect.fromLTRB(size.width * from, 0, size.width * to, size.height);
      canvas.drawRect(
        bandRect,
        Paint()
          ..color = palette.etchStrong.withValues(
            alpha: TapeBarGauge.bandAlpha,
          ),
      );
    }

    if (!value.hasValue) return;
    final share = _shareOf(value.value);
    if (share <= 0) return;

    final inBand = bandMin == null || bandMax == null
        ? true
        : value.value >= bandMin && value.value <= bandMax;
    final belowBand = bandMin != null && value.value < bandMin;
    final fillEnd = vertical
        ? Rect.fromLTRB(0, size.height * (1 - share), size.width, size.height)
        : Rect.fromLTRB(0, 0, size.width * share, size.height);

    Chamfer.polygonInto(_path, [
      fillEnd.topLeft,
      fillEnd.topRight,
      fillEnd.bottomRight,
      fillEnd.bottomLeft,
    ], chamfer);
    canvas.save();
    canvas.clipPath(_path, doAntiAlias: false);
    final gradientColors = inBand
        ? [palette.accentDeep, palette.accentCore]
        : belowBand
        ? [palette.caution, palette.caution]
        : [palette.critical, palette.critical];
    final shader = ui.Gradient.linear(
      vertical ? Offset(0, size.height) : Offset.zero,
      vertical
          ? Offset(0, size.height * (1 - share))
          : Offset(size.width * share, 0),
      gradientColors,
    );
    canvas.drawRect(rect, Paint()..shader = shader);
    canvas.restore();

    final edgePaint = Paint()
      ..color = palette.inkBright
      ..strokeWidth = TapeBarGauge.edgeLineWidth;
    if (vertical) {
      final y = size.height * (1 - share);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), edgePaint);
    } else {
      final x = size.width * share;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), edgePaint);
    }
  }

  @override
  bool shouldRepaint(BarGaugePainter old) =>
      old.palette != palette ||
      old.min != min ||
      old.max != max ||
      old.normalBandMin != normalBandMin ||
      old.normalBandMax != normalBandMax ||
      // Not just old.value's *current number*: a caller that swaps in a new
      // SmoothedSignal object (a livery rebuild recreating its inputs, or a
      // test) needs a repaint even though the `repaint:` listenable of a
      // just-swapped-in object has not notified yet.
      !identical(old.value, value);
}

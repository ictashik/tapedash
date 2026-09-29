import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../motion/smoothing_pipeline.dart';
import '../render/chamfer.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/typography.dart';
import '../tokens/vertical_tape.dart';
import 'rolling_numerals.dart';

/// Which edge of the tape the readout box straddles -- the edge facing the
/// rest of the cluster (DESIGN.md 6.3's "inner edge").
enum TapeReadoutSide { left, right }

/// A vertical tape (DESIGN.md 6.3): the aircraft-style speed or RPM
/// instrument the product is named for. The current value stays fixed at
/// the tape's own vertical centre; the scale scrolls past it, a window
/// [halfWindow] wide either side, so higher values are higher on screen.
///
/// [value] should already be smoothed (`spring.needle`, DESIGN.md 5.3): the
/// trend vector reads its `velocity` directly, and needs no spring of its
/// own to look "springed" (DESIGN.md 6.3) -- it is already a continuous
/// function of an already-spring-smoothed value's own continuous velocity.
class VerticalTape extends StatelessWidget {
  const VerticalTape({
    super.key,
    required this.value,
    required this.halfWindow,
    required this.minorTickInterval,
    required this.majorTickInterval,
    required this.format,
    required this.width,
    required this.height,
    this.readoutSide = TapeReadoutSide.right,
    this.thresholdValue,
  });

  /// The live value, smoothed with `spring.needle`.
  final SmoothedSignal value;

  /// The visible window extends this far above and below the current value.
  final double halfWindow;

  /// Minor ticks appear on every multiple of this.
  final double minorTickInterval;

  /// Major (labelled) ticks appear on every multiple of this -- a multiple
  /// of [minorTickInterval], or every tick is treated as major.
  final double majorTickInterval;

  final NumeralFormat format;

  /// The strip's own width; DESIGN.md 6.3's 0.13 of a reference W is the
  /// caller's to apply before passing this in, the same as every other
  /// component's `width`/`heightReference` pair.
  final double width;
  final double height;

  final TapeReadoutSide readoutSide;

  /// Where a tinted band starts, running to the top of the window (a
  /// redline, or the user's speed threshold, DESIGN.md 6.3). Null for none.
  final double? thresholdValue;

  double get _boxHeight => height * 0.09;
  double get _boxWidth => width * 1.7;

  /// Screen y for [v], 0 at the top of [height]. Exposed so the mapping has
  /// a direct test, since sampling it back out of rendered pixels is the
  /// fragile way to check it.
  double yFor(double v, double current) =>
      height / 2 - (v - current) / halfWindow * (height / 2);

  /// The fade-to-void alpha multiplier for a tick at [y] (DESIGN.md 6.3's
  /// top/bottom 20%): 1 through the middle, falling to 0 at either edge.
  static double fadeAlphaFor(double y, double height) {
    final fadeHeight = height * TapeVerticalTape.fadeShare;
    if (y < fadeHeight) return (y / fadeHeight).clamp(0.0, 1.0);
    if (y > height - fadeHeight) {
      return ((height - y) / fadeHeight).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    final boxLeft = readoutSide == TapeReadoutSide.right
        ? width - _boxWidth / 2
        : -_boxWidth / 2;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none, // the readout box straddles the edge.
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: VerticalTapePainter(
                listenable: value,
                tape: this,
                palette: palette,
              ),
            ),
          ),
          Positioned(
            top: height / 2 - _boxHeight / 2,
            left: boxLeft,
            width: _boxWidth,
            height: _boxHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ReadoutBoxPainter(palette: palette),
                  ),
                ),
                // A numeral's own box (the detent and roll room) is taller than
                // this readout, and a tight parent would clamp it, moving the
                // digits down by half the difference: the box is let overflow,
                // centred, so the ink sits in the middle of the readout.
                Center(
                  child: OverflowBox(
                    minHeight: 0,
                    maxHeight: NumeralMetrics(
                      TypeScale.forHeight(height).secondary,
                    ).boxHeight,
                    child: RollingNumerals(
                      source: value,
                      format: format,
                      size: TypeScale.forHeight(height).secondary,
                      role: NumeralRole.bright,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadoutBoxPainter extends CustomPainter {
  _ReadoutBoxPainter({required this.palette});

  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Chamfer.all(Offset.zero & size, TapeVerticalTape.readoutChamfer),
      Paint()..color = palette.panel,
    );
    canvas.drawPath(
      Chamfer.all(Offset.zero & size, TapeVerticalTape.readoutChamfer),
      Paint()
        ..color = palette.accentCore
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.5 * palette.strokeScale,
    );
  }

  @override
  bool shouldRepaint(_ReadoutBoxPainter old) => old.palette != palette;
}

class VerticalTapePainter extends CustomPainter {
  VerticalTapePainter({
    required Listenable listenable,
    required this.tape,
    required this.palette,
  }) : super(repaint: listenable);

  final VerticalTape tape;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (!tape.value.hasValue) return;
    final current = tape.value.value;
    final top = current + tape.halfWindow;
    final bottom = current - tape.halfWindow;

    _paintThresholdBand(canvas, size, current);

    final firstTick =
        (bottom / tape.minorTickInterval).ceil() * tape.minorTickInterval;
    for (var v = firstTick; v <= top; v += tape.minorTickInterval) {
      final y = tape.yFor(v, current);
      final alpha = VerticalTape.fadeAlphaFor(y, size.height);
      if (alpha <= 0.01) continue;
      final majorRatio = v / tape.majorTickInterval;
      final isMajor = (majorRatio - majorRatio.round()).abs() < 1e-6;
      final tickLength =
          size.width *
          (isMajor
              ? TapeVerticalTape.majorTickShare
              : TapeVerticalTape.minorTickShare);
      final tickX = tape.readoutSide == TapeReadoutSide.right
          ? size.width - tickLength
          : 0.0;
      canvas.drawLine(
        Offset(tickX, y),
        Offset(tickX + tickLength, y),
        Paint()
          ..color = palette.etchStrong.withValues(
            alpha: palette.etchStrong.a * alpha,
          )
          ..strokeWidth = 1.5,
      );
      if (isMajor && v.round() != current.round()) {
        final label = TextPainter(
          text: TextSpan(
            text: v.round().toString(),
            style: TapeType.label(
              size: 10,
              color: palette.label.withValues(alpha: palette.label.a * alpha),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Kept inside the strip: a four-digit label ("2000") is wider than
        // the room a tick leaves it on a 640 lp screen, and ran off the edge.
        final labelX =
            (tape.readoutSide == TapeReadoutSide.right
                    ? size.width - tickLength - label.width - 3
                    : tickLength + 3)
                .clamp(0.0, math.max(0.0, size.width - label.width))
                .toDouble();
        label.paint(canvas, Offset(labelX, y - label.height / 2));
      }
    }

    _paintTrendVector(canvas, size, current);
  }

  void _paintThresholdBand(Canvas canvas, Size size, double current) {
    final threshold = tape.thresholdValue;
    if (threshold == null) return;
    final top = current + tape.halfWindow;
    if (threshold > top) return;
    final yTop = tape.yFor(top, current);
    final yThreshold = tape.yFor(
      threshold < current - tape.halfWindow
          ? current - tape.halfWindow
          : threshold,
      current,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, yTop, size.width, yThreshold),
      Paint()..color = palette.critical.withValues(alpha: 0.12),
    );
  }

  void _paintTrendVector(Canvas canvas, Size size, double current) {
    final velocity = tape.value.velocity;
    if (velocity.abs() < 1e-6) return;
    final predicted =
        current + velocity * TapeVerticalTape.trendLookaheadSeconds;
    final clamped = predicted.clamp(
      current - tape.halfWindow,
      current + tape.halfWindow,
    );
    final startY = size.height / 2;
    final endY = tape.yFor(clamped, current);
    final x = tape.readoutSide == TapeReadoutSide.right
        ? size.width - tape._boxWidth / 2
        : tape._boxWidth / 2;
    canvas.drawLine(
      Offset(x, startY),
      Offset(x, endY),
      Paint()
        ..color = palette.accentCore
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(VerticalTapePainter old) =>
      old.palette != palette ||
      old.tape.halfWindow != tape.halfWindow ||
      old.tape.thresholdValue != tape.thresholdValue ||
      old.tape.readoutSide != tape.readoutSide ||
      !identical(old.tape.value, tape.value);
}

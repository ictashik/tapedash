import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../motion/motion_clock.dart';
import '../motion/motion_scope.dart';
import '../motion/smoothing_pipeline.dart';
import '../motion/spring_value.dart';
import '../render/chamfer.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/money.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/typography.dart';
import 'rolling_numerals.dart';

/// How settled a fuel-cost estimate is (DESIGN.md 6.8, CLAUDE.md 8.5): the
/// confidence pips' own vocabulary, matching money/'s three levels exactly.
enum MoneyConfidence { uncalibrated, calibrating, calibrated }

/// The money readout (DESIGN.md 6.8): a rupee glyph at 55% of the digit
/// height, baseline-aligned with rolling digits, and three confidence pips.
class MoneyReadout extends StatelessWidget {
  const MoneyReadout({
    super.key,
    required this.value,
    required this.format,
    required this.confidence,
    this.approximate = false,
    this.size = 32,
  });

  /// The live ₹ amount, smoothed (`spring.gauge`).
  final SmoothedSignal value;

  /// Whole rupees in Motion mode, or one decimal for a ₹/km rate (DESIGN.md
  /// 6.8) -- the caller's choice of which to show, and when.
  final NumeralFormat format;

  final MoneyConfidence confidence;

  /// Prefixes "≈" (DESIGN.md 6.8: parked detail views only).
  final bool approximate;

  /// The digit size; the rupee glyph is [TapeMoney.rupeeShareOfDigitHeight]
  /// of it.
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (approximate)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text(
              '≈',
              style: TapeType.numeral(
                size: size * 0.5,
                weight: theme.livery.numeralWeight,
                color: palette.inkDim,
              ),
            ),
          ),
        Text(
          '₹',
          style: TapeType.numeral(
            size: size * TapeMoney.rupeeShareOfDigitHeight,
            weight: theme.livery.numeralWeight,
            color: palette.rupee,
          ),
        ),
        const SizedBox(width: 2),
        RollingNumerals(
          source: value,
          format: format,
          size: size,
          role: NumeralRole.money,
        ),
        const SizedBox(width: 6),
        _ConfidencePips(confidence: confidence, palette: palette),
      ],
    );
  }
}

class _ConfidencePips extends StatelessWidget {
  const _ConfidencePips({required this.confidence, required this.palette});

  final MoneyConfidence confidence;
  final TapePalette palette;

  int get _litCount => switch (confidence) {
    MoneyConfidence.uncalibrated => 1,
    MoneyConfidence.calibrating => 2,
    MoneyConfidence.calibrated => 3,
  };

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < TapeMoney.confidencePipCount; i++)
        Padding(
          padding: EdgeInsets.only(
            left: i == 0 ? 0 : TapeMoney.confidencePipGap,
          ),
          child: CustomPaint(
            size: const Size.square(TapeMoney.confidencePipSize),
            painter: _PipPainter(lit: i < _litCount, palette: palette),
          ),
        ),
    ],
  );
}

class _PipPainter extends CustomPainter {
  _PipPainter({required this.lit, required this.palette});

  final bool lit;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Chamfer.all(
      Offset.zero & size,
      TapeMoney.confidencePipChamfer,
    );
    if (lit) {
      canvas.drawPath(path, Paint()..color = palette.money);
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..color = palette.etchStrong
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_PipPainter old) =>
      old.lit != lit || old.palette != palette;
}

/// Which bucket a block of spend fell into (DESIGN.md 6.8, CLAUDE.md 8.7) --
/// this component's own presentational vocabulary, not money/'s attribution
/// types, which do not exist before Phase 4.
enum MoneyBucket { normal, idling, hardAcceleration, highSpeed }

/// One ₹1 block on the Money Tape.
@immutable
class MoneyBlock {
  const MoneyBlock(this.bucket);

  final MoneyBucket bucket;
}

/// The Money Tape (DESIGN.md 6.8, "signature"): a strip of ₹1 blocks, oldest
/// farthest from the print end, that builds a barcode of where a trip's
/// money went. Vertical by default (the Money page's driver-far flank); set
/// [vertical] false for the thin variant DESIGN.md 6.8 allows in the Drive
/// floor.
///
/// [blocks] grows by roughly one entry per rupee spent -- a rare, discrete
/// event even on a long trip, not a per-frame one -- so appending to it and
/// passing a new list is an ordinary rebuild (DESIGN.md 9.3 is about
/// continuously live values, which this is not); only the newest block's
/// flash and the stack's own settle are animated internally, on the motion
/// clock, independent of any rebuild.
///
/// **Not yet built:** DESIGN.md 6.8's compacting, where groups of blocks
/// merge into ₹5 and then ₹10 blocks with their own merge animation and a
/// "1 BLOCK = ₹5" scale label once the strip fills. The strip here simply
/// keeps growing. Flagged here and in the design review rather than
/// attempted half-done.
class MoneyTape extends StatefulWidget {
  const MoneyTape({
    super.key,
    required this.blocks,
    required this.length,
    this.thickness = 18,
    this.vertical = true,
  });

  final List<MoneyBlock> blocks;

  /// The strip's own long axis, in logical pixels.
  final double length;
  final double thickness;
  final bool vertical;

  @override
  State<MoneyTape> createState() => MoneyTapeState();
}

class MoneyTapeState extends State<MoneyTape> implements MotionDriven {
  late MotionClock _motion;
  SpringValue? _stack;
  int _lastCount = 0;
  Duration _newestBlockAt = Duration.zero;
  bool _flashAttached = false;
  final MoneyTapeRepaintPing repaint = MoneyTapeRepaintPing();

  static final _flashDuration = Duration(
    microseconds:
        ((TapeMotion.phosphorRiseSeconds + TapeMotion.phosphorDecaySeconds) *
                1e6)
            .round(),
  );

  /// The spring tracks total pixel length (block count x pitch), the same
  /// unit MoneyTapePainter's own targetTotalLength is in -- not a bare
  /// block count, which a first version of this retargeted it to, leaving
  /// the painter's `shift = stackValue - targetTotalLength` a units
  /// mismatch large enough to push nearly every block off-strip.
  double get _targetLength =>
      widget.blocks.length * (TapeMoney.blockLength + TapeMoney.blockGap);

  @override
  void initState() {
    super.initState();
    _lastCount = widget.blocks.length;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionScope.of(context);
    _stack ??= SpringValue(
      clock: _motion,
      spec: TapeSprings.gauge,
      initial: _targetLength,
    );
  }

  @override
  void didUpdateWidget(MoneyTape oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.blocks.length != _lastCount) {
      _lastCount = widget.blocks.length;
      _newestBlockAt = _motion.now;
      _stack!.retarget(_targetLength);
      if (!_flashAttached) {
        _flashAttached = true;
        _motion.attach(this);
      }
    }
  }

  @override
  bool advance(double dt, Duration time) {
    repaint.ping();
    if (time - _newestBlockAt >= _flashDuration) {
      _flashAttached = false;
      return false;
    }
    return true;
  }

  /// The newest block's flash alpha, 0 to 1: a rise then a decay (DESIGN.md
  /// 5.5), 0 once no block has ever arrived. Exposed for a direct test.
  double flashAlphaAt(Duration now) {
    if (widget.blocks.isEmpty) return 0;
    final age = (now - _newestBlockAt).inMicroseconds / 1e6;
    if (age < 0) return 0;
    if (age < TapeMotion.phosphorRiseSeconds) {
      return age / TapeMotion.phosphorRiseSeconds;
    }
    final decayAge = age - TapeMotion.phosphorRiseSeconds;
    if (decayAge >= TapeMotion.phosphorDecaySeconds) return 0;
    return 1 - decayAge / TapeMotion.phosphorDecaySeconds;
  }

  @override
  void dispose() {
    if (_flashAttached) _motion.detach(this);
    _stack?.dispose();
    repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return SizedBox(
      width: widget.vertical ? widget.thickness : widget.length,
      height: widget.vertical ? widget.length : widget.thickness,
      child: CustomPaint(
        painter: MoneyTapePainter(
          listenable: Listenable.merge([_stack!, repaint]),
          state: this,
          palette: palette,
        ),
      ),
    );
  }
}

class MoneyTapeRepaintPing extends ChangeNotifier {
  void ping() => notifyListeners();
}

class MoneyTapePainter extends CustomPainter {
  MoneyTapePainter({
    required Listenable listenable,
    required this.state,
    required this.palette,
  }) : super(repaint: listenable);

  final MoneyTapeState state;
  final TapePalette palette;

  static double get _pitch => TapeMoney.blockLength + TapeMoney.blockGap;

  @override
  void paint(Canvas canvas, Size size) {
    final blocks = state.widget.blocks;
    if (blocks.isEmpty) return;
    final vertical = state.widget.vertical;
    final long = vertical ? size.height : size.width;
    final thickness = vertical ? size.width : size.height;

    final targetTotalLength = blocks.length * _pitch;
    final stackValue = state._stack?.value ?? targetTotalLength;
    final shift = stackValue - targetTotalLength; // <= 0 while catching up.
    final flashAlpha = state.flashAlphaAt(state._motion.now);

    for (var i = 0; i < blocks.length; i++) {
      final fromPrintEnd = (blocks.length - 1 - i) * _pitch + shift;
      if (fromPrintEnd < -TapeMoney.blockLength) continue; // not born yet.
      final isNewest = i == blocks.length - 1;
      _paintBlock(
        canvas,
        blocks[i].bucket,
        fromPrintEnd,
        long,
        thickness,
        vertical,
        isNewest ? flashAlpha : 0,
      );
    }
  }

  void _paintBlock(
    Canvas canvas,
    MoneyBucket bucket,
    double fromPrintEnd,
    double long,
    double thickness,
    bool vertical,
    double flashAlpha,
  ) {
    // The print end is the strip's own start (vertical: bottom; horizontal:
    // left), so distance-from-print-end maps to a position measured back
    // from that edge.
    final near = vertical
        ? long - fromPrintEnd - TapeMoney.blockLength
        : fromPrintEnd;
    final rect = vertical
        ? Rect.fromLTWH(0, near, thickness, TapeMoney.blockLength)
        : Rect.fromLTWH(near, 0, TapeMoney.blockLength, thickness);
    if (vertical
        ? rect.bottom < 0 || rect.top > long
        : rect.right < 0 || rect.left > long) {
      return;
    }

    final (color, hollow, notch) = switch (bucket) {
      MoneyBucket.normal => (palette.moneyDeep, false, false),
      MoneyBucket.idling => (palette.caution, true, false),
      MoneyBucket.hardAcceleration => (palette.critical, false, true),
      MoneyBucket.highSpeed => (palette.accentDeep, false, false),
    };

    final path = notch ? _notchedRect(rect, vertical) : (Path()..addRect(rect));
    if (hollow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    } else {
      canvas.drawPath(path, Paint()..color = color);
    }

    if (flashAlpha > 0.01) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = palette.inkHot.withValues(alpha: flashAlpha)
          ..blendMode = ui.BlendMode.plus,
      );
    }
  }

  /// A block's rect with a small triangular notch cut into its outer long
  /// edge (DESIGN.md 6.8's hard-acceleration block).
  Path _notchedRect(Rect rect, bool vertical) {
    final notchDepth = (vertical ? rect.width : rect.height) * 0.35;
    final notchHalf = (vertical ? rect.height : rect.width) * 0.3;
    final path = Path()..addRect(rect);
    final centre = rect.center;
    final notch = Path();
    if (vertical) {
      notch
        ..moveTo(rect.right, centre.dy - notchHalf)
        ..lineTo(rect.right - notchDepth, centre.dy)
        ..lineTo(rect.right, centre.dy + notchHalf)
        ..close();
    } else {
      notch
        ..moveTo(centre.dx - notchHalf, rect.bottom)
        ..lineTo(centre.dx, rect.bottom - notchDepth)
        ..lineTo(centre.dx + notchHalf, rect.bottom)
        ..close();
    }
    return Path.combine(ui.PathOperation.difference, path, notch);
  }

  @override
  bool shouldRepaint(MoneyTapePainter old) =>
      old.palette != palette ||
      old.state.widget.vertical != state.widget.vertical ||
      old.state.widget.blocks.length != state.widget.blocks.length ||
      !identical(old.state.widget.blocks, state.widget.blocks);
}

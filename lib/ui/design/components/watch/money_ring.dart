import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../motion/motion_clock.dart';
import '../../motion/motion_scope.dart';
import '../../render/arc_geometry.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/motion_tokens.dart';
import '../../tokens/watch.dart';
import '../money.dart';
import 'watch_face.dart';

/// The ₹ blocks of a trip, packed into the money ring's cells (DESIGN.md 16.5).
///
/// The ring has [TapeWatch.moneyCells] cells. Each is ₹1 until the trip has spent
/// more than that, and then the blocks are packed into cells of ₹2, ₹5, ₹10 and
/// so on, the smallest that fits, so that a long trip still reads as one barcode
/// round the whole rim. A packed cell shows the bucket most of its rupees fell in.
@immutable
class MoneyRingCells {
  const MoneyRingCells._(this.scale, this.cells);

  /// How many rupees a cell stands for.
  final int scale;

  /// One bucket per cell, in the order they were spent.
  final List<MoneyBucket> cells;

  static const MoneyRingCells empty = MoneyRingCells._(1, []);

  /// Packs [blocks], one per rupee.
  factory MoneyRingCells.of(List<MoneyBlock> blocks) {
    if (blocks.isEmpty) return empty;
    var scale = TapeWatch.moneyScales.last;
    for (final s in TapeWatch.moneyScales) {
      if ((blocks.length / s).ceil() <= TapeWatch.moneyCells) {
        scale = s;
        break;
      }
    }
    final cells = <MoneyBucket>[];
    for (var start = 0; start < blocks.length; start += scale) {
      final end = start + scale < blocks.length ? start + scale : blocks.length;
      final counts = <MoneyBucket, int>{};
      for (var i = start; i < end; i++) {
        counts.update(blocks[i].bucket, (n) => n + 1, ifAbsent: () => 1);
      }
      // The commonest bucket; on a tie the one that is worth noticing.
      var best = MoneyBucket.normal;
      var bestCount = -1;
      for (final bucket in _byNotice) {
        final n = counts[bucket] ?? 0;
        if (n > bestCount) {
          best = bucket;
          bestCount = n;
        }
      }
      cells.add(best);
    }
    return MoneyRingCells._(scale, cells);
  }

  static const List<MoneyBucket> _byNotice = [
    MoneyBucket.hardAcceleration,
    MoneyBucket.idling,
    MoneyBucket.highSpeed,
    MoneyBucket.normal,
  ];

  /// What the opening says when cells stand for more than ₹1, or null at ₹1:
  /// "1 BLOCK = ₹5".
  String? get scaleLabel => scale == 1 ? null : '1 block = ₹$scale';
}

/// The Money Tape, wrapped round the watch's rim (DESIGN.md 6.8, 16.5): every ₹ of
/// the trip a cell, printed clockwise from 12 o'clock, in the buckets' styles (a
/// solid cell for normal, a **hollow** one for idling, a notched one for hard
/// acceleration, the accent for high speed). The ring that is not spent yet shows
/// as ghost cells, so the structure is always there.
///
/// It repaints when the blocks change, which is about once a rupee, and for the
/// newest cell's phosphor flash; it asks for no frames otherwise.
class MoneyRing extends StatefulWidget {
  const MoneyRing({
    super.key,
    required this.blocks,
    required this.face,
    this.dimShare,
  });

  final ValueListenable<List<MoneyBlock>> blocks;
  final WatchFace face;

  /// 0 for full strength, rising to 1 when the face is parked: the ring dims to
  /// the parked brightness as every ring does (DESIGN.md 7.2).
  final ValueListenable<double>? dimShare;

  @override
  State<MoneyRing> createState() => MoneyRingState();
}

class MoneyRingState extends State<MoneyRing> implements MotionDriven {
  late MotionClock _motion;
  final _ping = _RingPing();
  MoneyRingCells cells = MoneyRingCells.empty;
  int _lastCount = 0;
  Duration _newestAt = Duration.zero;
  bool _attached = false;

  static final Duration _flash = Duration(
    microseconds:
        ((TapeMotion.phosphorRiseSeconds + TapeMotion.phosphorDecaySeconds) *
                1e6)
            .round(),
  );

  @override
  void initState() {
    super.initState();
    _take();
    widget.blocks.addListener(_onBlocks);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionScope.of(context);
  }

  @override
  void didUpdateWidget(MoneyRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.blocks, widget.blocks)) {
      oldWidget.blocks.removeListener(_onBlocks);
      widget.blocks.addListener(_onBlocks);
      _take();
    }
  }

  @override
  void dispose() {
    widget.blocks.removeListener(_onBlocks);
    if (_attached) _motion.detach(this);
    _ping.dispose();
    super.dispose();
  }

  void _take() {
    cells = MoneyRingCells.of(widget.blocks.value);
    _lastCount = cells.cells.length;
  }

  void _onBlocks() {
    final before = _lastCount;
    _take();
    if (cells.cells.length > before && before > 0) {
      _newestAt = _motion.now;
      if (!_attached) {
        _attached = true;
        _motion.attach(this);
      }
    }
    _ping.ping();
  }

  @override
  bool advance(double dt, Duration time) {
    _ping.ping();
    if (time - _newestAt >= _flash) {
      _attached = false;
      return false;
    }
    return true;
  }

  /// The newest cell's flash, 0 to 1 (DESIGN.md 5.5's rise and decay).
  double flashAt(Duration now) {
    final age = (now - _newestAt).inMicroseconds / 1e6;
    if (age < 0) return 0;
    if (age < TapeMotion.phosphorRiseSeconds) {
      return age / TapeMotion.phosphorRiseSeconds;
    }
    final decay = age - TapeMotion.phosphorRiseSeconds;
    if (decay >= TapeMotion.phosphorDecaySeconds) return 0;
    return 1 - decay / TapeMotion.phosphorDecaySeconds;
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.face.diameter,
        child: CustomPaint(
          painter: MoneyRingPainter(
            state: this,
            palette: palette,
            repaint: Listenable.merge([_ping, ?widget.dimShare]),
          ),
        ),
      ),
    );
  }
}

class _RingPing extends ChangeNotifier {
  void ping() => notifyListeners();
}

class MoneyRingPainter extends CustomPainter {
  MoneyRingPainter({
    required this.state,
    required this.palette,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MoneyRingState state;
  final TapePalette palette;

  final Paint _fill = Paint()..style = ui.PaintingStyle.fill;
  final Paint _line = Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final Path _path = Path();

  /// The cell's angular start, in maths degrees: the ring starts at 12 o'clock
  /// (90) and runs clockwise, which is falling angle.
  static double startOf(int i) => 90 - i * slot;

  static double get slot => 360.0 / TapeWatch.moneyCells;

  @override
  void paint(Canvas canvas, Size size) {
    final face = state.widget.face;
    final centre = face.centre;
    final dim = 1 - (1 - 0.6) * (state.widget.dimShare?.value ?? 0).clamp(0, 1);
    final inner = face.rimInner;
    final outer = face.rimOuter;
    final fillSpan = slot * TapeWatch.moneyCellFill;
    final gap = (slot - fillSpan) / 2;
    final flash = state.flashAt(state._motion.now);
    final cells = state.cells.cells;

    for (var i = 0; i < TapeWatch.moneyCells; i++) {
      final a0 = startOf(i) - gap;
      final a1 = a0 - fillSpan;
      _path.reset();
      final corners = ArcGeometry.trapezoid(centre, inner, outer, a0, a1);
      _path.addPolygon(corners, true);
      if (i >= cells.length) {
        _fill.color = palette.track.withValues(alpha: palette.track.a * dim);
        canvas.drawPath(_path, _fill);
        continue;
      }
      final bucket = cells[i];
      final (color, hollow, notch) = switch (bucket) {
        MoneyBucket.normal => (palette.moneyDeep, false, false),
        MoneyBucket.idling => (palette.caution, true, false),
        MoneyBucket.hardAcceleration => (palette.critical, false, true),
        MoneyBucket.highSpeed => (palette.accentDeep, false, false),
      };
      final tone = color.withValues(alpha: color.a * dim);
      if (hollow) {
        _line.color = tone;
        canvas.drawPath(_path, _line);
      } else {
        _fill.color = tone;
        canvas.drawPath(_path, _fill);
      }
      if (notch) {
        // A small cut in the outer edge, in the canvas colour: the mark of
        // money that went on hard acceleration, at a glance.
        final mid = (a0 + a1) / 2;
        _path
          ..reset()
          ..moveTo(
            ArcGeometry.pointAt(centre, outer, a0).dx,
            ArcGeometry.pointAt(centre, outer, a0).dy,
          );
        final tip = ArcGeometry.pointAt(
          centre,
          outer - (outer - inner) * 0.4,
          mid,
        );
        _path
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(
            ArcGeometry.pointAt(centre, outer, a1).dx,
            ArcGeometry.pointAt(centre, outer, a1).dy,
          )
          ..close();
        _fill.color = palette.canvas;
        canvas.drawPath(_path, _fill);
      }
      if (flash > 0.01 && i == cells.length - 1) {
        _path
          ..reset()
          ..addPolygon(corners, true);
        _fill
          ..color = palette.inkHot.withValues(alpha: flash)
          ..blendMode = ui.BlendMode.plus;
        canvas.drawPath(_path, _fill);
        _fill.blendMode = ui.BlendMode.srcOver;
      }
    }
  }

  @override
  bool shouldRepaint(MoneyRingPainter old) =>
      old.palette != palette || !identical(old.state, state);
}

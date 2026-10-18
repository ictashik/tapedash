import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../insights/geo.dart';
import '../../../../insights/toll_map.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/strokes.dart';
import 'chart_kit.dart';

/// The Toll Map (DESIGN.md 6.18): the roads the car has driven, north up, and a
/// hollow `caution` ring wherever it stood with the engine running, as wide as what
/// the standing cost. Hollow, because money burned for nothing looks empty (DESIGN.md
/// 4.3). A tap on a ring chooses it.
class TollMapChart extends StatelessWidget {
  const TollMapChart({
    super.key,
    required this.map,
    required this.selected,
    required this.onSelect,
  });

  final TollMap map;
  final int? selected;
  final ValueChanged<int> onSelect;

  /// A tap this near a ring's centre chooses it, in lp.
  static const double tapReach = 30;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final at = TollMapPainter.positions(map, box.biggest);
          int? best;
          var gap = tapReach;
          for (var i = 0; i < at.length; i++) {
            final dist = (at[i] - d.localPosition).distance;
            if (dist <= gap) {
              gap = dist;
              best = i;
            }
          }
          if (best != null) onSelect(best);
        },
        child: CustomPaint(
          painter: TollMapPainter(
            map: map,
            selected: selected,
            palette: palette,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class TollMapPainter extends CustomPainter {
  TollMapPainter({
    required this.map,
    required this.selected,
    required this.palette,
  });

  final TollMap map;
  final int? selected;
  final TapePalette palette;

  static const double margin = 26;

  /// The ring of the dearest place, and of the cheapest drawn, in lp.
  static const double maxRadius = 24;
  static const double minRadius = 6;

  /// Where each spot is on a map of [size], in the order of [TollMap.spots].
  static List<Offset> positions(TollMap map, Size size) {
    final fit = map.fit();
    final k = fit.scale(size.width, size.height, margin);
    final c = size.center(Offset.zero);
    return [
      for (final s in map.spots)
        () {
          final (e, n) = fit.metres(s.at);
          return Offset(c.dx + e * k, c.dy - n * k);
        }(),
    ];
  }

  /// A ring's radius for a spot, from its share of the dearest place's money.
  static double radiusOf(TollMap map, int i) {
    final top = map.spots.first;
    double v(TollSpot s) => s.rupees ?? s.litres;
    final share = v(top) <= 0 ? 0.0 : v(map.spots[i]) / v(top);
    return minRadius + (maxRadius - minRadius) * math.sqrt(share);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fit = map.fit();
    final k = fit.scale(size.width, size.height, margin);
    final c = size.center(Offset.zero);
    Offset at(GeoPoint p) {
      final (e, n) = fit.metres(p);
      return Offset(c.dx + e * k, c.dy - n * k);
    }

    // The roads: every trip's line, faint, so that the ones driven most are the
    // brightest.
    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.fine
      ..strokeJoin = StrokeJoin.round
      // Faint enough that the road driven every day, laid over itself a hundred
      // times, is a line and not a white bar: the same total whatever the count.
      ..color = palette.etchStrong.withValues(
        alpha: (1 - math.pow(0.6, 1 / math.max(1, map.roads.length)))
            .clamp(0.03, 0.3)
            .toDouble(),
      );
    for (final r in map.roads) {
      final path = Path()..moveTo(at(r.first).dx, at(r.first).dy);
      for (final p in r.skip(1)) {
        path.lineTo(at(p).dx, at(p).dy);
      }
      canvas.drawPath(path, road);
    }

    if (map.spots.isEmpty) return;
    final pos = positions(map, size);
    // The cheapest first, so that the dearest ring is on top.
    for (var i = map.spots.length - 1; i >= 0; i--) {
      final r = radiusOf(map, i);
      final chosen = i == selected;
      canvas.drawCircle(
        pos[i],
        r,
        Paint()
          ..color = palette.caution.withValues(alpha: chosen ? 0.12 : 0.06),
      );
      canvas.drawCircle(
        pos[i],
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = palette.caution.withValues(alpha: chosen ? 1 : 0.75)
          ..strokeWidth = chosen ? TapeStroke.regular : TapeStroke.fine,
      );
      canvas.drawCircle(pos[i], 1.8, Paint()..color = palette.caution);
      ChartKit.numeral(
        canvas,
        '${i + 1}',
        pos[i] + Offset(r + 4, -r * 0.5),
        chosen ? palette.inkBright : palette.inkMid,
        size: 11,
      );
    }
    final sel = selected;
    if (sel != null && sel < pos.length) {
      ChartKit.dashed(
        canvas,
        pos[sel] + Offset(0, radiusOf(map, sel) + 4),
        pos[sel] + Offset(0, radiusOf(map, sel) + 14),
        palette.caution,
        dash: 2,
        gap: 2,
      );
    }
    ChartKit.label(
      canvas,
      'N',
      Offset(size.width - 10, 10),
      palette.inkDim,
      size: 11,
      align: ChartAlign.end,
    );
    ChartKit.glowLine(
      canvas,
      [Offset(size.width - 14, 24), Offset(size.width - 14, 40)],
      palette.inkDim,
      width: 1,
      halo: 0,
    );
  }

  @override
  bool shouldRepaint(TollMapPainter old) =>
      !identical(old.map, map) ||
      old.selected != selected ||
      old.palette != palette;
}

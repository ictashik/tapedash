import 'package:flutter/widgets.dart';

import '../../../../insights/geo.dart';
import '../../../../insights/toll_map.dart' show MapFit;
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/strokes.dart';
import 'chart_kit.dart';

/// Two drives of one route (DESIGN.md 6.18): this one in light, the earlier one
/// dashed behind it, both fitted to the panel together so that the places they
/// part company show.
class GhostRouteChart extends StatelessWidget {
  const GhostRouteChart({super.key, required this.now, required this.before});

  final List<GeoPoint> now;
  final List<GeoPoint> before;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: GhostRoutePainter(
      now: now,
      before: before,
      palette: TapeTheme.of(context).palette,
    ),
    size: Size.infinite,
  );
}

class GhostRoutePainter extends CustomPainter {
  GhostRoutePainter({
    required this.now,
    required this.before,
    required this.palette,
  });

  final List<GeoPoint> now;
  final List<GeoPoint> before;
  final TapePalette palette;

  static const double margin = 18;

  /// Both routes as points on a panel of [size], one fit for the two.
  static (List<Offset>, List<Offset>) layout(
    List<GeoPoint> now,
    List<GeoPoint> before,
    Size size,
  ) {
    final fit = MapFit([...now, ...before]);
    final k = fit.scale(size.width, size.height, margin);
    final c = size.center(Offset.zero);
    List<Offset> place(List<GeoPoint> r) => [
      for (final p in r)
        () {
          final (e, n) = fit.metres(p);
          return Offset(c.dx + e * k, c.dy - n * k);
        }(),
    ];
    return (place(now), place(before));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (now.length < 2) return;
    final (a, b) = layout(now, before, size);
    ChartKit.dashed(canvas, b.first, b.first, palette.inkMid, width: 0);
    // The earlier drive: dashed, in the mid ink.
    final path = Path()..moveTo(b.first.dx, b.first.dy);
    for (final p in b.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(
          m.extractPath(d, (d + 5).clamp(0, m.length)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = TapeStroke.fine
            ..color = palette.inkMid.withValues(alpha: 0.7),
        );
      }
    }
    // This one, in light.
    ChartKit.glowLine(canvas, a, palette.accentCore, width: 2.2);
    canvas.drawCircle(
      a.first,
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = palette.accentCore
        ..strokeWidth = TapeStroke.fine,
    );
    canvas.drawRect(
      Rect.fromCenter(center: a.last, width: 9, height: 9),
      Paint()..color = palette.accentCore,
    );
  }

  @override
  bool shouldRepaint(GhostRoutePainter old) =>
      !identical(old.now, now) ||
      !identical(old.before, before) ||
      old.palette != palette;
}

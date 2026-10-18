import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../insights/powerflow.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/strokes.dart';
import 'chart_kit.dart';

/// Where the energy in the fuel went (DESIGN.md 6.18): one river from the fuel,
/// splitting into the wheels, the engine standing still and the engine's heat, and
/// the wheels splitting again into tyres, air and brakes. Ribbons are as thick as
/// their share; idling is hollow, as it is on the Money Tape.
class PowerflowChart extends StatelessWidget {
  const PowerflowChart({super.key, required this.flow});

  final Powerflow flow;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: PowerflowPainter(
      flow: flow,
      palette: TapeTheme.of(context).palette,
    ),
    size: Size.infinite,
  );
}

/// Where each node of the river sits in a panel of a given size, so that the
/// painter and the test agree.
class PowerflowLayout {
  PowerflowLayout(Powerflow flow, Size size) {
    const nodeW = 8.0;
    const gap = 16.0;
    final top = 30.0;
    final avail = size.height - top - 8 - 2 * gap;
    final s = math.max(40.0, avail);
    fuelX = 0;
    // The last column leaves room for its labels on the right.
    endX = math.max(size.width * 0.5, size.width - 112);
    midX = endX * 0.46;
    fuel = Rect.fromLTWH(fuelX, top, nodeW, s);
    double h(double share) => math.max(3.0, share * s);
    final wheelsH = h(flow.wheelShare);
    final idleH = h(flow.idleShare);
    final heatH = h(flow.heatShare);
    wheels = Rect.fromLTWH(midX, top, nodeW, wheelsH);
    idle = Rect.fromLTWH(midX, wheels.bottom + gap, nodeW, idleH);
    heat = Rect.fromLTWH(midX, idle.bottom + gap, nodeW, heatH);
    // The wheels' three sinks, spaced so that their labels do not touch, and
    // centred on the wheels.
    final shares = [flow.tyreShare, flow.airShare, flow.brakeShare];
    final heights = [for (final sh in shares) math.max(3.0, sh * wheelsH)];
    const sinkGap = 28.0;
    var y = top;
    final rects = <Rect>[];
    for (final hh in heights) {
      rects.add(Rect.fromLTWH(endX, y, nodeW, hh));
      y += hh + sinkGap;
    }
    tyres = rects[0];
    air = rects[1];
    brakes = rects[2];
  }

  late final double fuelX;
  late final double midX;
  late final double endX;
  late final Rect fuel;
  late final Rect wheels;
  late final Rect idle;
  late final Rect heat;
  late final Rect tyres;
  late final Rect air;
  late final Rect brakes;
}

class PowerflowPainter extends CustomPainter {
  PowerflowPainter({required this.flow, required this.palette});

  final Powerflow flow;
  final TapePalette palette;

  /// A ribbon from the right edge of [from] (its [fromTop] to [fromTop] + [h])
  /// to the left edge of [to] (its own top, same thickness).
  static Path ribbon(double x0, double y0, double x1, double y1, double h) {
    final m = (x0 + x1) / 2;
    return Path()
      ..moveTo(x0, y0)
      ..cubicTo(m, y0, m, y1, x1, y1)
      ..lineTo(x1, y1 + h)
      ..cubicTo(m, y1 + h, m, y0 + h, x0, y0 + h)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final l = PowerflowLayout(flow, size);
    final nodeW = l.fuel.width;
    final s = l.fuel.height;

    void flowTo(
      Rect from,
      double fromOffset,
      Rect to,
      double thickness,
      Color color, {
      bool hollow = false,
    }) {
      final path = ribbon(
        from.right,
        from.top + fromOffset,
        to.left,
        to.top,
        thickness,
      );
      if (hollow) {
        canvas.drawPath(
          path,
          Paint()..color = palette.caution.withValues(alpha: 0.06),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = palette.caution.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = TapeStroke.fine,
        );
      } else {
        canvas.drawPath(path, Paint()..color = color);
      }
    }

    // Fuel to the wheels, the idling and the heat, stacked in the fuel node.
    var at = 0.0;
    final wheelsT = l.wheels.height;
    flowTo(
      l.fuel,
      at,
      l.wheels,
      wheelsT,
      palette.accentDeep.withValues(alpha: 0.45),
    );
    at += flow.wheelShare * s;
    flowTo(l.fuel, at, l.idle, l.idle.height, palette.caution, hollow: true);
    at += flow.idleShare * s;
    flowTo(
      l.fuel,
      at,
      l.heat,
      l.heat.height,
      palette.inkDim.withValues(alpha: 0.22),
    );

    // The wheels to the tyres, the air and the brakes.
    var off = 0.0;
    for (final (node, share, alpha) in [
      (l.tyres, flow.tyreShare, 0.22),
      (l.air, flow.airShare, 0.18),
      (l.brakes, flow.brakeShare, 0.34),
    ]) {
      final t = math.max(node.height, 0.0);
      flowTo(
        l.wheels,
        off,
        node,
        t,
        palette.accentCore.withValues(alpha: alpha),
      );
      off += share * l.wheels.height;
    }

    // The nodes.
    canvas.drawRect(l.fuel, Paint()..color = palette.inkMid);
    canvas.drawRect(l.wheels, Paint()..color = palette.accentDeep);
    canvas.drawRect(
      l.idle.deflate(0.8),
      Paint()
        ..color = palette.caution
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawRect(l.heat, Paint()..color = palette.inkDim);
    for (final n in [l.tyres, l.air, l.brakes]) {
      canvas.drawRect(n, Paint()..color = palette.accentCore);
    }

    // The words.
    String pct(double v) => '≈ ${(v * 100).round()}%';
    String rs(double share) {
      final r = flow.rupees(share);
      return r == null ? '' : ' · ₹${r.round()}';
    }

    ChartKit.label(
      canvas,
      'Fuel · ≈ ${flow.fuelKwh.toStringAsFixed(1)} kWh',
      Offset(l.fuel.left, l.fuel.top - 12),
      palette.inkBright,
      size: 10,
    );
    final mx = l.midX + nodeW + 8;
    final wheelsLabel = ChartKit.label(
      canvas,
      'Wheels',
      Offset(l.midX, l.wheels.top - 12),
      palette.accentCore,
      size: 10,
    );
    ChartKit.numeral(
      canvas,
      pct(flow.wheelShare),
      Offset(l.midX + wheelsLabel + 8, l.wheels.top - 12),
      palette.inkBright,
      size: 11,
    );
    // The idling label sits below the wheels' ribbons, not across them.
    final idleY = math.max(l.idle.center.dy, l.brakes.bottom + 18);
    ChartKit.label(
      canvas,
      'Idling',
      Offset(mx, idleY - 7),
      palette.caution,
      size: 10,
    );
    ChartKit.numeral(
      canvas,
      '${pct(flow.idleShare)}${rs(flow.idleShare)}',
      Offset(mx, idleY + 7),
      palette.inkMid,
      size: 11,
    );
    ChartKit.label(
      canvas,
      'Engine heat',
      Offset(mx, l.heat.center.dy - 6),
      palette.inkMid,
      size: 10,
    );
    ChartKit.numeral(
      canvas,
      pct(flow.heatShare),
      Offset(mx, l.heat.center.dy + 8),
      palette.inkMid,
      size: 11,
    );
    for (final (node, name, share, color) in [
      (l.tyres, 'Tyres', flow.tyreOfFuel, palette.inkBright),
      (l.air, 'Air', flow.airOfFuel, palette.inkBright),
      (l.brakes, 'Brakes', flow.brakeOfFuel, palette.accentCore),
    ]) {
      final x = node.right + 8;
      ChartKit.label(
        canvas,
        name,
        Offset(x, node.center.dy - 7),
        color,
        size: 10,
      );
      ChartKit.numeral(
        canvas,
        '${pct(share)}${rs(share)}',
        Offset(x, node.center.dy + 7),
        palette.inkMid,
        size: 11,
      );
    }
  }

  @override
  bool shouldRepaint(PowerflowPainter old) =>
      !identical(old.flow, flow) || old.palette != palette;
}

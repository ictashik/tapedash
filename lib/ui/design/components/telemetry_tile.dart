import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../motion/motion_clock.dart';
import '../motion/motion_scope.dart';
import '../motion/smoothing_pipeline.dart';
import '../render/chamfer.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/spacing.dart';
import '../tokens/strokes.dart';
import '../tokens/telemetry_tile.dart';
import '../tokens/typography.dart';
import 'rolling_numerals.dart';
import 'tape_label.dart';

/// A telemetry tile (DESIGN.md 6.6, the enthusiast cluster's dense layout): a
/// bracket frame, a label at the top-left, the rolling value at the top-right,
/// and a sparkline of the last 60 s (at 2 Hz) filling the lower 55%. Out-of-range
/// values tint the brackets caution or critical.
class TelemetryTile extends StatefulWidget {
  const TelemetryTile({
    super.key,
    required this.label,
    required this.value,
    required this.format,
    this.cautionBelow,
    this.criticalBelow,
    this.cautionAbove,
    this.criticalAbove,
    this.width = 160,
    this.height = 100,
  });

  final String label;

  /// The live value; also what the sparkline samples (DESIGN.md 5.3's
  /// `spring.gauge`, the same spring a numeral's own value uses).
  final SmoothedSignal value;
  final NumeralFormat format;

  /// Thresholds that tint the brackets (DESIGN.md 6.6). Any may be omitted.
  final double? cautionBelow;
  final double? criticalBelow;
  final double? cautionAbove;
  final double? criticalAbove;

  final double width;
  final double height;

  @override
  State<TelemetryTile> createState() => TelemetryTileState();
}

class TelemetryTileState extends State<TelemetryTile> implements MotionDriven {
  late MotionClock _motion;
  final Float32List _samples = Float32List(TapeTelemetryTile.sparklinePoints);
  int _head = 0;
  int _filled = 0;
  Duration? _lastSample;
  bool _attached = false;
  final TileRepaintPing repaint = TileRepaintPing();

  @override
  void initState() {
    super.initState();
    widget.value.addListener(_onValue);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionScope.of(context);
    _onValue();
  }

  @override
  void didUpdateWidget(TelemetryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value)) {
      oldWidget.value.removeListener(_onValue);
      widget.value.addListener(_onValue);
    }
    _onValue();
  }

  void _onValue() {
    if (widget.value.hasValue && !_attached) {
      _attached = true;
      _motion.attach(this);
    }
  }

  @override
  bool advance(double dt, Duration time) {
    final last = _lastSample;
    if (last == null || time - last >= TapeTelemetryTile.sampleInterval) {
      _lastSample = time;
      _samples[_head] = widget.value.value;
      _head = (_head + 1) % _samples.length;
      if (_filled < _samples.length) _filled++;
    }
    repaint.ping();
    return true;
  }

  /// The samples oldest-first, for tests and the painter.
  List<double> samplesOldestFirst() => [
    for (var i = 0; i < _filled; i++)
      _samples[(_head - _filled + i + _samples.length) % _samples.length],
  ];

  /// Where [v] currently stands: below/above a caution or critical threshold,
  /// or normal. Read fresh by the painter on every repaint (DESIGN.md 9.3:
  /// the widget itself never rebuilds for live data), not cached at build
  /// time — a value crossing a threshold between rebuilds would otherwise
  /// leave the brackets showing a zone that is no longer current.
  _Zone _zoneFor(double v) {
    if (widget.criticalBelow != null && v < widget.criticalBelow!) {
      return _Zone.critical;
    }
    if (widget.criticalAbove != null && v > widget.criticalAbove!) {
      return _Zone.critical;
    }
    if (widget.cautionBelow != null && v < widget.cautionBelow!) {
      return _Zone.caution;
    }
    if (widget.cautionAbove != null && v > widget.cautionAbove!) {
      return _Zone.caution;
    }
    return _Zone.normal;
  }

  @override
  void dispose() {
    widget.value.removeListener(_onValue);
    if (_attached) _motion.detach(this);
    repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: TelemetryTilePainter(
                listenable: Listenable.merge([widget.value, repaint]),
                state: this,
                palette: palette,
              ),
            ),
          ),
          Positioned(
            left: TapeSpace.s2,
            top: TapeSpace.s1,
            child: TapeLabel(widget.label, size: 10),
          ),
          Positioned(
            right: TapeSpace.s2,
            top: TapeSpace.s1,
            child: RollingNumerals(
              source: widget.value,
              format: widget.format,
              size: TypeScale.forHeight(360).secondary,
              role: NumeralRole.bright,
            ),
          ),
        ],
      ),
    );
  }
}

enum _Zone { normal, caution, critical }

/// A ping with no value attached, for the sampling clock's repaint trigger.
class TileRepaintPing extends ChangeNotifier {
  void ping() => notifyListeners();
}

class TelemetryTilePainter extends CustomPainter {
  TelemetryTilePainter({
    required Listenable listenable,
    required this.state,
    required this.palette,
  }) : super(repaint: listenable);

  final TelemetryTileState state;
  final TapePalette palette;

  final Path _path = Path();

  Color _bracketColor() {
    final value = state.widget.value;
    final zone = value.hasValue ? state._zoneFor(value.value) : _Zone.normal;
    return switch (zone) {
      _Zone.normal => palette.etchStrong,
      _Zone.caution => palette.caution,
      _Zone.critical => palette.critical,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    Chamfer.bracketsInto(
      _path,
      Offset.zero & size,
      TapeTelemetryTile.bracketArm,
    );
    canvas.drawPath(
      _path,
      Paint()
        ..color = _bracketColor()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = TapeStroke.fine * palette.strokeScale,
    );

    final samples = state.samplesOldestFirst();
    if (samples.length < 2) return;
    var min = samples.first;
    var max = samples.first;
    for (final s in samples) {
      if (s < min) min = s;
      if (s > max) max = s;
    }
    final span = (max - min).abs() < 1e-9 ? 1.0 : max - min;

    final top = size.height * (1 - TapeTelemetryTile.sparklineShare);
    final bottom = size.height;
    final left = TapeSpace.s1;
    final right = size.width - TapeSpace.s1;
    final dx = (right - left) / (TapeTelemetryTile.sparklinePoints - 1);

    double yOf(double v) => bottom - (v - min) / span * (bottom - top);
    double xOf(int i) =>
        left + dx * (i + (TapeTelemetryTile.sparklinePoints - samples.length));

    // min/max reference lines.
    final refPaint = Paint()
      ..color = palette.etchFaint
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, top), Offset(right, top), refPaint);
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), refPaint);

    final line = Path()..moveTo(xOf(0), yOf(samples[0]));
    for (var i = 1; i < samples.length; i++) {
      line.lineTo(xOf(i), yOf(samples[i]));
    }
    final fill = Path.from(line)
      ..lineTo(xOf(samples.length - 1), bottom)
      ..lineTo(xOf(0), bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = palette.accentCore.withValues(
          alpha: TapeTelemetryTile.fillAlpha,
        ),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = palette.accentCore
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = TapeTelemetryTile.lineWidth,
    );
  }

  @override
  bool shouldRepaint(TelemetryTilePainter old) =>
      old.palette != palette ||
      !identical(old.state.widget.value, state.widget.value);
}

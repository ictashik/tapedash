import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../coach/sample_events.dart';
import '../../../trips/trip.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/strokes.dart';

/// The telemetry scrubber (DESIGN.md 6.12): a full-width band with the speed trace
/// (accent) above and the throttle trace (`ink.mid`) below on one time axis, and
/// the trip's events marked on the axis. Drag anywhere to scrub: a vertical cursor
/// appears and [cursor] says which sample it is on. Double-tap puts the cursor
/// away.
///
/// (Pinch to zoom time, which DESIGN.md also asks for, is not built.)
///
/// The two traces are drawn from paths worked out once for a trip and a width; a
/// drag repaints the cursor alone and rebuilds nothing.
class TelemetryScrubber extends StatefulWidget {
  const TelemetryScrubber({
    super.key,
    required this.samples,
    required this.cursor,
    this.events = const [],
    this.lower,
    this.playhead,
  });

  /// Where a replay is, as a fractional sample (null when there is none): the line
  /// is drawn there, moving smoothly, and the [cursor] is left to say which whole
  /// sample it is nearest. Dragging still sets the [cursor].
  final ValueListenable<double?>? playhead;

  /// What the lower trace shows: null is the throttle, 0 to 100 %.
  final ScrubberTrace? lower;

  final List<TripSample> samples;

  /// The sample the cursor is on, or null with no cursor. The scrubber sets it.
  final ValueNotifier<int?> cursor;

  final List<SampleEvent> events;

  /// The sample at horizontal position [x] of a band [width] wide over
  /// [count] samples.
  static int sampleAt(double x, double width, int count) {
    if (count <= 1 || width <= 0) return 0;
    return (x / width * (count - 1)).round().clamp(0, count - 1);
  }

  @override
  State<TelemetryScrubber> createState() => _TelemetryScrubberState();
}

class _TelemetryScrubberState extends State<TelemetryScrubber> {
  double _width = 0;

  void _scrub(double x) {
    widget.cursor.value = TelemetryScrubber.sampleAt(
      x,
      _width,
      widget.samples.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _scrub(d.localPosition.dx),
          onHorizontalDragStart: (d) => _scrub(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => _scrub(d.localPosition.dx),
          onDoubleTap: () => widget.cursor.value = null,
          child: CustomPaint(
            size: Size(box.maxWidth, box.maxHeight),
            painter: ScrubberPainter(
              samples: widget.samples,
              events: widget.events,
              cursor: widget.cursor,
              palette: palette,
              lower: widget.lower,
              playhead: widget.playhead,
            ),
          ),
        );
      },
    );
  }
}

/// A trace for the scrubber's lower half other than the throttle: [value] of each
/// sample (null where the car did not say, which carries the last forward),
/// drawn between [min] and [max].
class ScrubberTrace {
  const ScrubberTrace({
    required this.value,
    required this.min,
    required this.max,
  });

  final double? Function(TripSample) value;
  final double min;
  final double max;

  /// The trace of [value] over the range the trip covered, but over at least
  /// [minSpan] (see `normaliseSpread`).
  factory ScrubberTrace.spread(
    List<TripSample> samples,
    double? Function(TripSample) value, {
    required double minSpan,
  }) {
    double? lo, hi;
    for (final s in samples) {
      final v = value(s);
      if (v == null) continue;
      lo = lo == null || v < lo ? v : lo;
      hi = hi == null || v > hi ? v : hi;
    }
    lo ??= 0;
    hi ??= minSpan;
    if (hi - lo < minSpan) {
      final mid = (lo + hi) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
    }
    return ScrubberTrace(value: value, min: lo, max: hi);
  }

  /// The largest value of [value] in [samples], rounded up to a multiple of
  /// [step] (at least one step).
  static double roundedMax(
    List<TripSample> samples,
    double Function(TripSample) value,
    double step,
  ) {
    var m = step;
    for (final s in samples) {
      final v = value(s);
      if (v > m) m = v;
    }
    return (m / step).ceil() * step;
  }
}

class ScrubberPainter extends CustomPainter {
  ScrubberPainter({
    required this.samples,
    required this.events,
    required this.cursor,
    required this.palette,
    this.lower,
    this.playhead,
  }) : super(repaint: Listenable.merge([cursor, ?playhead]));

  final ScrubberTrace? lower;
  final ValueListenable<double?>? playhead;

  final List<TripSample> samples;
  final List<SampleEvent> events;
  final ValueListenable<int?> cursor;
  final TapePalette palette;

  Size? _size;
  Path? _speed;
  Path? _throttle;

  /// The most speed the scale shows: what the trip reached, rounded up to 20.
  static double speedMax(List<TripSample> samples) {
    var m = 20.0;
    for (final s in samples) {
      if (s.speedKmh > m) m = s.speedKmh;
    }
    return (m / 20).ceil() * 20.0;
  }

  void _build(Size size) {
    if (_size == size) return;
    _size = size;
    final n = samples.length;
    final trace = size.height - 14; // the axis is the bottom 14 lp.
    final upper = Rect.fromLTWH(0, 2, size.width, trace * 0.6 - 2);
    final lower = Rect.fromLTWH(
      0,
      trace * 0.6 + 2,
      size.width,
      trace * 0.4 - 2,
    );
    final vMax = speedMax(samples);
    final sp = Path();
    final th = Path();
    final other = this.lower;
    double? carried;
    // Thinned to about a point a pixel: a long trip's trace needs no more.
    final step = n > size.width ? n / size.width : 1.0;
    for (var k = 0.0, first = true; k < n; k += step, first = false) {
      final i = k.floor().clamp(0, n - 1);
      final x = n <= 1 ? 0.0 : size.width * i / (n - 1);
      final sy =
          upper.bottom -
          upper.height * (samples[i].speedKmh / vMax).clamp(0.0, 1.0);
      final double share;
      if (other == null) {
        share = samples[i].throttle / 100;
      } else {
        carried = other.value(samples[i]) ?? carried;
        share = carried == null
            ? 0
            : (carried - other.min) / (other.max - other.min);
      }
      final ty = lower.bottom - lower.height * share.clamp(0.0, 1.0);
      if (first) {
        sp.moveTo(x, sy);
        th.moveTo(x, ty);
      } else {
        sp.lineTo(x, sy);
        th.lineTo(x, ty);
      }
    }
    _speed = sp;
    _throttle = th;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    _build(size);
    final n = samples.length;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    line
      ..strokeWidth = TapeStroke.regular
      ..color = palette.accentCore;
    canvas.drawPath(_speed!, line);
    line
      ..strokeWidth = TapeStroke.fine
      ..color = palette.inkMid;
    canvas.drawPath(_throttle!, line);

    // The time axis, with an event marker on it for each moment.
    final axisY = size.height - 7;
    line
      ..strokeWidth = TapeStroke.fine
      ..color = palette.etchStrong;
    canvas.drawLine(Offset(0, axisY), Offset(size.width, axisY), line);
    for (final e in events) {
      final x = size.width * e.index / (n - 1);
      final p = Offset(x, axisY);
      switch (e.type) {
        case SampleEventType.hardAcceleration:
          line.color = palette.critical;
          canvas.drawLine(
            p + const Offset(-3, 3),
            p + const Offset(0, -3),
            line,
          );
          canvas.drawLine(
            p + const Offset(0, -3),
            p + const Offset(3, 3),
            line,
          );
        case SampleEventType.hardBraking:
          line.color = palette.critical;
          canvas.drawLine(
            p + const Offset(-2, -3),
            p + const Offset(-2, 3),
            line,
          );
          canvas.drawLine(
            p + const Offset(2, -3),
            p + const Offset(2, 3),
            line,
          );
        case SampleEventType.longIdle:
          line.color = palette.caution;
          canvas.drawRect(
            Rect.fromCenter(center: p, width: 6, height: 6),
            line,
          );
      }
    }

    final c = playhead?.value ?? cursor.value;
    if (c != null) {
      final x = size.width * c / (n - 1);
      line
        ..strokeWidth = TapeStroke.regular
        ..color = palette.inkHot;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  @override
  bool shouldRepaint(ScrubberPainter old) =>
      old.lower != lower ||
      !identical(old.samples, samples) ||
      old.palette != palette ||
      !identical(old.playhead, playhead) ||
      !identical(old.events, events);
}

/// What the readouts show at the cursor (DESIGN.md 6.12): speed, rpm, throttle and
/// the ₹/km at that moment, or null where there is none to give.
class ScrubReadout {
  const ScrubReadout({
    required this.speedKmh,
    required this.rpm,
    required this.throttle,
    required this.costPerKm,
  });

  final double speedKmh;
  final double rpm;
  final double throttle;

  /// What each kilometre is costing at that moment: null below 5 km/h, with no
  /// price, or with no fuel figure.
  final double? costPerKm;

  static ScrubReadout at(
    List<TripSample> samples,
    int i,
    double? pricePerLitre,
  ) {
    final s = samples[i.clamp(0, samples.length - 1)];
    return ScrubReadout(
      speedKmh: s.speedKmh,
      rpm: s.rpm,
      throttle: s.throttle,
      costPerKm: pricePerLitre == null || s.speedKmh < 5
          ? null
          : s.litresPerHour * pricePerLitre / s.speedKmh,
    );
  }
}

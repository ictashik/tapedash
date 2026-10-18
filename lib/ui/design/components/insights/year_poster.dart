import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../../core/number_format.dart';
import '../../../../insights/year_on_tape.dart';
import '../../../../money/spend_bucket.dart';
import '../../theme/palette.dart';
import '../../theme/tape_theme.dart';
import 'chart_kit.dart';

/// Year on Tape (DESIGN.md 6.18): every trip of a year as a bar of a barcode, in
/// the order of the calendar, stacked by where its money went, with the year's
/// totals under it. It is the screen's picture and the picture that is saved and
/// shared, drawn by the same painter at 640 x 360 and scaled.
class YearPoster extends StatelessWidget {
  const YearPoster({super.key, required this.year, this.sweetSpot});

  final YearOnTape year;

  /// The car's sweet spot, as "55–70", for the last figure; null leaves it out.
  final String? sweetSpot;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: YearPosterPainter.width / YearPosterPainter.height,
    child: LayoutBuilder(
      builder: (context, box) => CustomPaint(
        painter: YearPosterPainter(
          year: year,
          palette: TapeTheme.of(context).palette,
          sweetSpot: sweetSpot,
          scale: box.maxWidth / YearPosterPainter.width,
        ),
        size: box.biggest,
      ),
    ),
  );
}

class YearPosterPainter extends CustomPainter {
  YearPosterPainter({
    required this.year,
    required this.palette,
    this.sweetSpot,
    this.scale = 1,
  });

  final YearOnTape year;
  final TapePalette palette;
  final String? sweetSpot;

  /// How many pixels a poster unit is: the poster is drawn on 640 x 360 units.
  final double scale;

  static const double width = 640;
  static const double height = 360;

  /// The bars' left and right, baseline and tallest height, in poster units.
  static const double _x0 = 32;
  static const double _x1 = 608;
  static const double _base = 252;
  static const double _tallest = 150;

  /// The month letters.
  static const String monthLetters = 'JFMAMJJASOND';

  /// The tallest bar is the 98th percentile of the trips, so that one trip to
  /// another city does not make every other bar a hair.
  static double barScale(YearOnTape y) {
    if (y.bars.isEmpty) return 1;
    final v = [for (final b in y.bars) b.value]..sort();
    return math.max(1, v[math.min(v.length - 1, (v.length * 0.98).floor())]);
  }

  /// Where in the year a trip falls, 0 to 1 (a leap year has its extra day).
  static double dayShare(DateTime at, int year) {
    final start = DateTime(year);
    final days = DateTime(year + 1).difference(start).inDays;
    return (at.difference(start).inHours / 24 / days).clamp(0.0, 1.0);
  }

  Color _bucket(int i) => switch (SpendBucket.values[i]) {
    SpendBucket.normal => palette.moneyDeep,
    SpendBucket.idling => palette.caution.withValues(alpha: 0.6),
    SpendBucket.hardAcceleration => palette.critical,
    SpendBucket.highSpeed => palette.accentDeep,
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    _paint(canvas);
    canvas.restore();
  }

  void _paint(Canvas canvas) {
    const rect = Rect.fromLTWH(0, 0, width, height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(width / 2, height * 0.45),
          width * 0.62,
          [palette.vignetteCentre, palette.canvas],
        ),
    );

    ChartKit.label(
      canvas,
      'TapeDash',
      const Offset(32, 30),
      palette.inkDim,
      size: 12,
    );
    ChartKit.numeral(
      canvas,
      '${year.year} on Tape'.toUpperCase(),
      const Offset(32, 62),
      palette.inkBright,
      size: 28,
    );
    ChartKit.label(
      canvas,
      'One bar a trip',
      const Offset(width - 32, 30),
      palette.inkDim,
      size: 11,
      align: ChartAlign.end,
    );
    ChartKit.label(
      canvas,
      year.priced ? 'Height is ₹' : 'Height is litres',
      const Offset(width - 32, 46),
      palette.inkDim,
      size: 11,
      align: ChartAlign.end,
    );

    // The bars: a trip is a slot of the calendar, and two on a day share it.
    final top = barScale(year);
    final slot = (_x1 - _x0) / 365;
    final byDay = <int, List<YearBar>>{};
    for (final b in year.bars) {
      final d = (dayShare(b.at, year.year) * 364).floor();
      byDay.putIfAbsent(d, () => []).add(b);
    }
    for (final e in byDay.entries) {
      final n = e.value.length;
      final w = math.max(0.7, slot * 0.78 / n);
      for (final (k, b) in e.value.indexed) {
        final x = _x0 + e.key * slot + k * (slot / n);
        var y = _base;
        final total = math.min(_tallest, b.value / top * _tallest);
        for (var i = 0; i < b.shares.length; i++) {
          final h = b.shares[i] * total;
          if (h <= 0) continue;
          canvas.drawRect(
            Rect.fromLTWH(x, y - h, w, h),
            Paint()..color = _bucket(i),
          );
          y -= h;
        }
      }
    }
    canvas.drawRect(
      const Rect.fromLTWH(_x0, _base, _x1 - _x0, 1),
      Paint()..color = palette.etchStrong,
    );

    // The months along the foot.
    for (var m = 0; m < 12; m++) {
      final x =
          _x0 + (_x1 - _x0) * dayShare(DateTime(year.year, m + 1), year.year);
      canvas.drawRect(
        Rect.fromLTWH(x, _base + 2, 1, 5),
        Paint()..color = palette.etch,
      );
      ChartKit.label(
        canvas,
        monthLetters[m],
        Offset(x + 3, _base + 16),
        palette.inkDim,
        size: 10,
      );
    }

    // The year's figures.
    canvas.drawRect(
      const Rect.fromLTWH(32, 288, width - 64, 1),
      Paint()..color = palette.etchFaint,
    );
    String money(double v) =>
        '${year.priced ? '₹' : ''}${groupDigits(v.round().toString(), year.priced ? DigitGrouping.indian : DigitGrouping.none)}${year.priced ? '' : ' L'}';
    final cells = <(String, String, Color)>[
      (
        'Trips',
        groupDigits('${year.trips}', DigitGrouping.indian),
        palette.inkBright,
      ),
      (
        'Km',
        groupDigits(year.km.round().toString(), DigitGrouping.indian),
        palette.inkBright,
      ),
      (year.priced ? 'Spent' : 'Fuel', '≈ ${money(year.spent)}', palette.money),
      (
        'Idling',
        '≈ ${money(year.idleSpent)} · ${(year.idleShare * 100).round()}%',
        palette.caution,
      ),
      if (sweetSpot != null)
        ('Sweet spot', '$sweetSpot km/h', palette.accentCore),
    ];
    final xs = sweetSpot == null
        ? const [32.0, 120.0, 224.0, 380.0]
        : const [32.0, 104.0, 192.0, 320.0, 480.0];
    for (final (i, c) in cells.indexed) {
      ChartKit.label(
        canvas,
        c.$1,
        Offset(xs[i], 306),
        palette.inkDim,
        size: 10,
      );
      ChartKit.numeral(
        canvas,
        c.$2,
        Offset(xs[i], 330),
        c.$3,
        size: i == 4 ? 14 : 17,
      );
    }
    ChartKit.label(
      canvas,
      'Estimates',
      const Offset(width - 32, 346),
      palette.inkDim.withValues(alpha: 0.7),
      size: 9,
      align: ChartAlign.end,
    );
  }

  @override
  bool shouldRepaint(YearPosterPainter old) =>
      !identical(old.year, year) ||
      old.palette != palette ||
      old.sweetSpot != sweetSpot ||
      old.scale != scale;

  /// The poster as a PNG, [scale] pixels to a unit: 3 is 1920 x 1080.
  static Future<Uint8List> toPng(
    YearOnTape year,
    TapePalette palette, {
    String? sweetSpot,
    double scale = 3,
  }) async {
    final recorder = ui.PictureRecorder();
    final size = Size(width * scale, height * scale);
    YearPosterPainter(
      year: year,
      palette: palette,
      sweetSpot: sweetSpot,
      scale: scale,
    ).paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data!.buffer.asUint8List();
  }
}

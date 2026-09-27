// The bar gauge (DESIGN.md 6.5): the fill position, the normal band, and the
// caution/critical colouring outside it.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/bar_gauge.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/vehicle/reading.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
  });

  tearDown(() {
    motion.dispose();
    kit.dispose();
  });

  SmoothedSignal signal(double v) {
    final s = SmoothedSignal(
      motion: motion,
      clock: clock,
      spring: TapeSprings.needle,
    );
    s.ingest(
      Reading(value: v, at: clock.monotonic(), receivedAt: clock.monotonic()),
    );
    addTearDown(s.dispose);
    return s;
  }

  Future<Uint32List> showAndCapture(
    WidgetTester tester,
    double value, {
    double min = 0,
    double max = 120,
    double? bandMin = 80,
    double? bandMax = 100,
    bool vertical = true,
  }) async {
    setWindow(tester, const Size(300, 400));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: Center(
          child: BarGauge(
            value: signal(value),
            min: min,
            max: max,
            length: 300,
            vertical: vertical,
            normalBandMin: bandMin,
            normalBandMax: bandMax,
            label: 'COOLANT °C',
          ),
        ),
      ),
    );
    motion.advance(const Duration(seconds: 1));
    await tester.pump();
    final image = await renderImage(tester);
    late ByteData data;
    await tester.runAsync(() async => data = (await image.toByteData())!);
    return Uint32List.fromList([
      for (var i = 0; i < image.width * image.height; i++)
        data.getUint32(i * 4),
    ]);
  }

  int count(Uint32List pixels, int rgba) =>
      pixels.where((p) => p == rgba).length;

  group('colour by zone (DESIGN.md 6.5)', () {
    testWidgets('in the normal band: an accent.deep to accent.core fill', (
      tester,
    ) async {
      final pixels = await showAndCapture(tester, 90);

      expect(count(pixels, 0x1296FFFF), greaterThan(5), reason: 'accent.deep');
      expect(count(pixels, 0x5CE1FFFF), greaterThan(5), reason: 'accent.core');
      expect(count(pixels, 0xFFB020FF), 0, reason: 'no caution');
      expect(count(pixels, 0xFF3355FF), 0, reason: 'no critical');
    });

    testWidgets('below the band: caution', (tester) async {
      final pixels = await showAndCapture(tester, 40);

      expect(count(pixels, 0xFFB020FF), greaterThan(50));
      expect(count(pixels, 0x5CE1FFFF), 0);
      expect(count(pixels, 0xFF3355FF), 0);
    });

    testWidgets('above the band: critical', (tester) async {
      final pixels = await showAndCapture(tester, 118);

      expect(count(pixels, 0xFF3355FF), greaterThan(50));
      expect(count(pixels, 0x5CE1FFFF), 0);
      expect(count(pixels, 0xFFB020FF), 0);
    });

    testWidgets('with no normal band given, any value in range is accent', (
      tester,
    ) async {
      final pixels = await showAndCapture(
        tester,
        40,
        bandMin: null,
        bandMax: null,
      );

      // A short fill shows only a thin strip of the gradient's exact end
      // colour (most pixels along its short height are an in-between blend),
      // so the positive check is for a blue-dominant (accent) fill pixel
      // rather than the one exact hex value; the negative checks (never
      // caution or critical) are the part that actually distinguishes "no
      // band" from the below/above-band paths.
      var blueDominant = 0;
      for (final p in pixels) {
        final r = (p >> 24) & 0xFF;
        final g = (p >> 16) & 0xFF;
        final b = (p >> 8) & 0xFF;
        if (b > 150 && b > r + 30 && b > g) blueDominant++;
      }
      expect(blueDominant, greaterThan(5));
      expect(count(pixels, 0xFFB020FF), 0, reason: 'no caution');
      expect(count(pixels, 0xFF3355FF), 0, reason: 'no critical');
    });
  });

  group('the fill (DESIGN.md 6.5)', () {
    testWidgets('draws nothing at the very minimum', (tester) async {
      final pixels = await showAndCapture(tester, 0);

      expect(count(pixels, 0x1296FFFF), 0);
      expect(count(pixels, 0xFFB020FF), 0);
    });

    testWidgets('clamps at the maximum rather than overflow the track', (
      tester,
    ) async {
      final pixels = await showAndCapture(tester, 500);

      // Should read as fully critical (past the band), not throw or vanish.
      expect(count(pixels, 0xFF3355FF), greaterThan(50));
    });

    testWidgets('grows as the value rises', (tester) async {
      final small = await showAndCapture(
        tester,
        20,
        bandMin: null,
        bandMax: null,
      );
      final big = await showAndCapture(
        tester,
        100,
        bandMin: null,
        bandMax: null,
      );

      expect(count(big, 0x5CE1FFFF), greaterThan(count(small, 0x5CE1FFFF)));
    });
  });

  group('cost', () {
    testWidgets(
      'repaints when a new SmoothedSignal object is given, not just a new value',
      (tester) async {
        // A regression test: shouldRepaint originally compared only the palette
        // and the band, so swapping in a freshly created signal (as a rebuild
        // that recreates its inputs would) kept showing the old paint until
        // that new object's own listenable happened to fire again.
        final a = await showAndCapture(tester, 40); // below band: caution
        final b = await showAndCapture(tester, 90); // in band: accent

        expect(count(a, 0xFFB020FF), greaterThan(50));
        expect(count(b, 0x5CE1FFFF), greaterThan(5));
        expect(
          count(b, 0xFFB020FF),
          0,
          reason: 'not still showing the first render',
        );
      },
    );
  });
}

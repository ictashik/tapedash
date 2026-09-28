// CenteredNumeral: it reports the typical-digit-count width to its own
// layout, and the numeral it wraps paints centred within that box -- not
// the full reservation, and not clipped when a value needs the overflow
// room. Written after two capture-shot bugs (the road view's hero speed,
// DESIGN.md 6.11; the Apex cluster's, DESIGN.md 7.3) and a real layout
// crash (an unbounded ambient height reaching OverflowBox) while building
// this component to fix both at the source.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/centered_numeral.dart';
import 'package:tapedash/ui/design/components/rolling_numerals.dart';
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
  late SmoothedSignal value;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    value = SmoothedSignal(
      motion: motion,
      clock: clock,
      spring: TapeSprings.gauge,
    );
  });

  tearDown(() {
    value.dispose();
    motion.dispose();
    kit.dispose();
  });

  void ingest(double v) {
    final now = clock.monotonic();
    value.ingest(Reading(value: v, at: now, receivedAt: now));
  }

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    Size window = const Size(600, 300),
  }) async {
    setWindow(tester, window);
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: Center(child: child),
      ),
    );
    await tester.pump();
  }

  group('layout', () {
    testWidgets(
      'reports the typical-digit-count width, not the full reservation',
      (tester) async {
        ingest(81);
        await show(
          tester,
          CenteredNumeral(
            source: value,
            format: const NumeralFormat(integerDigits: 3),
            typicalIntegerDigits: 2,
            size: 100,
          ),
        );

        final reported = tester.getSize(find.byType(CenteredNumeral));
        // typicalIntegerDigits (2) worth of width, not integerDigits' (3):
        // 2 x one digit's pitch, not 3 x.
        expect(reported.width, closeTo(2 * NumeralMetrics(100).pitch, 1));
      },
    );

    testWidgets('with no spare digits, is exactly a bare RollingNumerals', (
      tester,
    ) async {
      ingest(81);
      await show(
        tester,
        CenteredNumeral(
          source: value,
          format: const NumeralFormat(integerDigits: 2),
          typicalIntegerDigits: 2,
          size: 100,
        ),
      );
      final centred = tester.getSize(find.byType(CenteredNumeral));

      await show(
        tester,
        RollingNumerals(
          source: value,
          format: const NumeralFormat(integerDigits: 2),
          size: 100,
        ),
      );
      final bare = tester.getSize(find.byType(RollingNumerals));

      expect(centred, bare);
    });
  });

  group('drawing', () {
    Future<Uint32List> pixels(WidgetTester tester) async {
      final image = await renderImage(tester);
      late ByteData data;
      await tester.runAsync(() async => data = (await image.toByteData())!);
      return Uint32List.fromList([
        for (var i = 0; i < image.width * image.height; i++)
          data.getUint32(i * 4),
      ]);
    }

    testWidgets('a typical-digit-count value paints centred in its own box', (
      tester,
    ) async {
      ingest(81);
      await show(
        tester,
        CenteredNumeral(
          source: value,
          format: const NumeralFormat(integerDigits: 3),
          typicalIntegerDigits: 2,
          size: 80,
          role: NumeralRole.bright,
        ),
        window: const Size(400, 200),
      );

      final frame = await pixels(tester);
      final width = (400 * tester.view.devicePixelRatio).round();
      bool isBright(int p) {
        final r = (p >> 24) & 0xFF;
        final g = (p >> 16) & 0xFF;
        final b = (p >> 8) & 0xFF;
        return r > 180 && g > 180 && b > 180; // ink.bright, near-white.
      }

      var sumX = 0, count = 0;
      for (var i = 0; i < frame.length; i++) {
        if (isBright(frame[i])) {
          sumX += i % width;
          count++;
        }
      }
      expect(count, greaterThan(0), reason: 'nothing bright was drawn at all');
      final centroidX = sumX / count;
      final frameCentre = width / 2;
      // Within a few percent of the frame's own centre: the box itself is
      // centred by the harness's own Center, and the digits fill their
      // reported box closely enough that the visible ink's centroid should
      // land close to that box's -- and so the frame's -- own centre.
      expect(centroidX, closeTo(frameCentre, width * 0.05));
    });

    testWidgets('a value needing the overflow digit is not clipped', (
      tester,
    ) async {
      ingest(732); // uses all 3 reserved digits, 1 more than typical.
      await show(
        tester,
        CenteredNumeral(
          source: value,
          format: const NumeralFormat(integerDigits: 3),
          typicalIntegerDigits: 2,
          size: 80,
          role: NumeralRole.bright,
        ),
        window: const Size(400, 200),
      );

      final frame = await pixels(tester);
      final width = (400 * tester.view.devicePixelRatio).round();
      bool isBright(int p) {
        final r = (p >> 24) & 0xFF;
        final g = (p >> 16) & 0xFF;
        final b = (p >> 8) & 0xFF;
        return r > 180 && g > 180 && b > 180;
      }

      var minX = width, maxX = 0, count = 0;
      for (var i = 0; i < frame.length; i++) {
        if (isBright(frame[i])) {
          final x = i % width;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          count++;
        }
      }
      expect(count, greaterThan(0));
      // The actual claim: nothing was clipped away, so the ink drawn is
      // wider than the reported (2-digit) box at all -- the extra digit is
      // still fully there, spilling past the reported box's own width,
      // rather than being cut off at it. (Not a specific ratio: ink is
      // narrower than a digit's full advance/pitch, so a third digit adds
      // less extra width than a naive 3-pitches-vs-2 comparison would say.)
      final reported = tester.getSize(find.byType(CenteredNumeral));
      final reportedPx = reported.width * tester.view.devicePixelRatio;
      expect((maxX - minX).toDouble(), greaterThan(reportedPx));
    });
  });
}

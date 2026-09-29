// The vertical tape (DESIGN.md 6.3): the y-position mapping, the fade to
// void, and that it repaints live without a rebuild.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/numeral_format.dart';
import 'package:tapedash/ui/design/components/vertical_tape.dart';
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

  group('VerticalTape.yFor (DESIGN.md 6.3)', () {
    late ManualMotionClock motion;
    late FakeClock clock;
    late SmoothedSignal unused;
    late VerticalTape tape;

    setUp(() {
      motion = ManualMotionClock();
      clock = FakeClock();
      unused = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.needle,
      );
      tape = VerticalTape(
        value: unused,
        halfWindow: 30,
        minorTickInterval: 5,
        majorTickInterval: 10,
        format: const NumeralFormat(integerDigits: 3),
        width: 60,
        height: 360,
      );
    });

    tearDown(() {
      unused.dispose();
      motion.dispose();
    });

    test('the current value sits at the vertical centre', () {
      expect(tape.yFor(70, 70), 180);
    });

    test('a higher value is higher on screen (smaller y)', () {
      expect(tape.yFor(100, 70), lessThan(180));
      expect(tape.yFor(40, 70), greaterThan(180));
    });

    test('the top and bottom of the window are the strip\'s own edges', () {
      expect(tape.yFor(100, 70), 0); // current + halfWindow.
      expect(tape.yFor(40, 70), 360); // current - halfWindow.
    });
  });

  group('VerticalTape.fadeAlphaFor (DESIGN.md 6.3)', () {
    test('is full strength through the middle', () {
      expect(VerticalTape.fadeAlphaFor(180, 360), 1.0);
    });

    test('is 0 at the very top and bottom edges', () {
      expect(VerticalTape.fadeAlphaFor(0, 360), 0);
      expect(VerticalTape.fadeAlphaFor(360, 360), 0);
    });

    test('fades linearly within the top and bottom 20%', () {
      // fadeShare 0.2 of 360 = 72.
      expect(VerticalTape.fadeAlphaFor(36, 360), closeTo(0.5, 1e-9));
      expect(VerticalTape.fadeAlphaFor(360 - 36, 360), closeTo(0.5, 1e-9));
    });

    test('is exactly 1 right at the 20% line, not just past it', () {
      expect(VerticalTape.fadeAlphaFor(72, 360), 1.0);
      expect(VerticalTape.fadeAlphaFor(360 - 72, 360), 1.0);
    });
  });

  group('drawing', () {
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
        spring: TapeSprings.needle,
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

    void run(Duration duration) {
      var left = duration.inMicroseconds;
      const frame = 16667;
      while (left > 0) {
        final step = left < frame ? left : frame;
        motion.tick(step / 1e6);
        clock.advance(Duration(microseconds: step));
        left -= step;
      }
    }

    Future<void> show(
      WidgetTester tester, {
      double? threshold,
      TapeReadoutSide side = TapeReadoutSide.right,
    }) async {
      setWindow(tester, const Size(220, 360));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(
            child: VerticalTape(
              value: value,
              halfWindow: 2000,
              minorTickInterval: 250,
              majorTickInterval: 1000,
              format: const NumeralFormat(integerDigits: 4),
              width: 60,
              height: 360,
              readoutSide: side,
              thresholdValue: threshold,
            ),
          ),
        ),
      );
    }

    Future<Uint32List> pixels(WidgetTester tester) async {
      final image = await renderImage(tester);
      late ByteData data;
      await tester.runAsync(() async => data = (await image.toByteData())!);
      return Uint32List.fromList([
        for (var i = 0; i < image.width * image.height; i++)
          data.getUint32(i * 4),
      ]);
    }

    testWidgets('the readout digits sit in the middle of the readout box', (
      tester,
    ) async {
      ingest(2111);
      await show(tester);
      run(const Duration(seconds: 1));
      await tester.pump();
      final px = await pixels(tester);
      const w = 440; // 220 lp at 2x
      // The digits are ink.bright (near white); the box outline is accent and
      // the ticks are etch, so near-white pixels in the rows of the box are
      // the numerals.
      var top = 1 << 30, bottom = -1;
      for (var y = 0; y < 720; y++) {
        for (var x = 0; x < w; x++) {
          final p = px[y * w + x];
          if (((p >> 24) & 0xFF) > 200 &&
              ((p >> 16) & 0xFF) > 200 &&
              ((p >> 8) & 0xFF) > 200) {
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
      }
      expect(bottom, greaterThan(top));
      // Centred on the tape's own centre line (360 px), to within 6 px.
      expect((top + bottom) / 2, closeTo(360, 6));
    });

    testWidgets('draws nothing before a reading arrives (no crash)', (
      tester,
    ) async {
      await show(tester);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a threshold band is critical-tinted, and absent without one', (
      tester,
    ) async {
      await show(tester, threshold: 6500);
      ingest(6100);
      run(const Duration(seconds: 1));
      await tester.pump();
      final withBand = await pixels(tester);
      // palette.critical (0xFF3355FF) at 12% alpha, blended over the void:
      // not the solid literal, so check for critical's own red-dominant hue
      // rather than an exact composited hex, which depends on what's under it.
      bool reddish(int p) {
        final r = (p >> 24) & 0xFF;
        final g = (p >> 16) & 0xFF;
        final b = (p >> 8) & 0xFF;
        return r > 20 && r > g + 5 && r > b - 20 && b > g;
      }

      expect(withBand.where(reddish).length, greaterThan(20));

      await show(tester); // no threshold this time.
      ingest(6100);
      run(const Duration(seconds: 1));
      await tester.pump();
      final withoutBand = await pixels(tester);
      expect(withoutBand.where(reddish).length, 0);
    });

    testWidgets('the readout box moves to the requested side', (tester) async {
      // The centroid x of the box's own accent.core outline pixels (Ion's
      // 0x5CE1FFFF), the same robust-to-blur technique glow_cache_test.dart
      // uses, rather than predicting an exact column by hand.
      const accentCoreArgb = 0x5CE1FFFF;
      Future<double> centroidX(TapeReadoutSide side) async {
        await show(tester, side: side);
        ingest(3000);
        run(const Duration(seconds: 1));
        await tester.pump();
        final frame = await pixels(tester);
        final width = (220 * tester.view.devicePixelRatio).round();
        var sumX = 0, count = 0;
        for (var i = 0; i < frame.length; i++) {
          if (frame[i] == accentCoreArgb) {
            sumX += i % width;
            count++;
          }
        }
        expect(count, greaterThan(0), reason: 'no readout box drawn at all');
        return sumX / count;
      }

      final leftCentroid = await centroidX(TapeReadoutSide.left);
      final rightCentroid = await centroidX(TapeReadoutSide.right);
      expect(rightCentroid, greaterThan(leftCentroid));
    });

    testWidgets('responds to a live value with no rebuild needed', (
      tester,
    ) async {
      await show(tester);
      ingest(3000);
      run(const Duration(seconds: 1));
      await tester.pump();
      final atLow = await pixels(tester);

      ingest(6000);
      run(const Duration(seconds: 2));
      await tester.pump();
      final atHigh = await pixels(tester);

      expect(atLow, isNot(equals(atHigh)));
    });

    testWidgets('a swapped SmoothedSignal repaints, not just a new value', (
      tester,
    ) async {
      await show(tester);
      ingest(3000);
      run(const Duration(seconds: 1));
      await tester.pump();
      final before = await pixels(tester);

      final other = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.needle,
      );
      addTearDown(other.dispose);
      other.ingest(
        Reading(
          value: 6000,
          at: clock.monotonic(),
          receivedAt: clock.monotonic(),
        ),
      );

      setWindow(tester, const Size(220, 360));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(
            child: VerticalTape(
              value: other,
              halfWindow: 2000,
              minorTickInterval: 250,
              majorTickInterval: 1000,
              format: const NumeralFormat(integerDigits: 4),
              width: 60,
              height: 360,
            ),
          ),
        ),
      );
      run(const Duration(seconds: 2));
      await tester.pump();
      final after = await pixels(tester);

      expect(before, isNot(equals(after)));
    });
  });
}

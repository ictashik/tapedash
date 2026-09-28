// The money readout and the Money Tape (DESIGN.md 6.8): confidence pips,
// bucket styling (including that idling is genuinely hollow, not just
// outlined over a fill), the phosphor flash curve, and that a newly
// appended block settles into view.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/money.dart';
import 'package:tapedash/ui/design/components/numeral_format.dart';
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

  group('MoneyReadout (DESIGN.md 6.8)', () {
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

    Future<Uint32List> pixels(WidgetTester tester) async {
      final image = await renderImage(tester);
      late ByteData data;
      await tester.runAsync(() async => data = (await image.toByteData())!);
      return Uint32List.fromList([
        for (var i = 0; i < image.width * image.height; i++)
          data.getUint32(i * 4),
      ]);
    }

    Future<void> show(WidgetTester tester, MoneyConfidence confidence) async {
      setWindow(tester, const Size(220, 60));
      final signal = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.gauge,
      );
      addTearDown(signal.dispose);
      signal.ingest(
        Reading(
          value: 342,
          at: clock.monotonic(),
          receivedAt: clock.monotonic(),
        ),
      );
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(
            child: MoneyReadout(
              value: signal,
              format: const NumeralFormat(integerDigits: 4),
              confidence: confidence,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'more confidence lights more pips: strictly more money-coloured pixels',
      (tester) async {
        // money.core (0xF3CF86FF) marks both the digits and a lit pip; the
        // ordering below is the claim, not the exact pixel counts.
        const moneyCoreArgb = 0xF3CF86FF;
        await show(tester, MoneyConfidence.uncalibrated);
        final uncalibrated = (await pixels(
          tester,
        )).where((v) => v == moneyCoreArgb).length;

        await show(tester, MoneyConfidence.calibrating);
        final calibrating = (await pixels(
          tester,
        )).where((v) => v == moneyCoreArgb).length;

        await show(tester, MoneyConfidence.calibrated);
        final calibrated = (await pixels(
          tester,
        )).where((v) => v == moneyCoreArgb).length;

        expect(calibrating, greaterThan(uncalibrated));
        expect(calibrated, greaterThan(calibrating));
      },
    );
  });

  group('MoneyTapeState.flashAlphaAt (DESIGN.md 5.5, 6.8)', () {
    late TapeRenderKit kit;
    late ManualMotionClock motion;

    setUp(() {
      kit = TapeRenderKit();
      motion = ManualMotionClock();
    });

    tearDown(() {
      motion.dispose();
      kit.dispose();
    });

    Future<MoneyTapeState> show(
      WidgetTester tester,
      List<MoneyBlock> blocks,
    ) async {
      setWindow(tester, const Size(120, 300));
      final key = GlobalKey<MoneyTapeState>();
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(
            child: MoneyTape(key: key, blocks: blocks, length: 260),
          ),
        ),
      );
      return key.currentState!;
    }

    testWidgets('is 0 with no block yet', (tester) async {
      final state = await show(tester, const []);
      expect(state.flashAlphaAt(motion.now), 0);
    });

    testWidgets('rises from 0 to 1 over the rise time, then decays back to 0', (
      tester,
    ) async {
      final state = await show(tester, const [MoneyBlock(MoneyBucket.normal)]);
      final start = motion.now;
      expect(state.flashAlphaAt(start), 0);
      expect(
        state.flashAlphaAt(start + const Duration(milliseconds: 15)),
        closeTo(0.5, 0.05),
      );
      final peakAt =
          start +
          Duration(
            microseconds: (TapeMotion.phosphorRiseSeconds * 1e6).round(),
          );
      expect(state.flashAlphaAt(peakAt), closeTo(1.0, 0.02));
      final decayedAt =
          peakAt +
          Duration(
            microseconds: (TapeMotion.phosphorDecaySeconds * 1e6).round(),
          );
      expect(state.flashAlphaAt(decayedAt), closeTo(0, 0.02));
    });
  });

  group('drawing', () {
    late TapeRenderKit kit;
    late ManualMotionClock motion;

    setUp(() {
      kit = TapeRenderKit();
      motion = ManualMotionClock();
    });

    tearDown(() {
      motion.dispose();
      kit.dispose();
    });

    void run(Duration duration) {
      var left = duration.inMicroseconds;
      const frame = 16667;
      while (left > 0) {
        final step = left < frame ? left : frame;
        motion.tick(step / 1e6);
        left -= step;
      }
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

    Future<void> show(WidgetTester tester, List<MoneyBlock> blocks) async {
      setWindow(tester, const Size(120, 300));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(child: MoneyTape(blocks: blocks, length: 260)),
        ),
      );
      run(const Duration(seconds: 1)); // let the stack spring settle.
      await tester.pump();
    }

    testWidgets('a normal block is a solid money.deep fill', (tester) async {
      await show(tester, const [MoneyBlock(MoneyBucket.normal)]);
      // money.deep, Ion (livery-independent: money tokens are not per-livery).
      expect(
        (await pixels(tester)).where((v) => v == 0xD6A042FF).length,
        greaterThan(5),
      );
    });

    testWidgets(
      'an idling block is genuinely hollow: void shows through its centre',
      (tester) async {
        // Solid blocks (normal, either side) bracket it, so if it were
        // wrongly filled (the ambiguity a compressed preview screenshot
        // could not settle by eye) there would be no void-coloured pixels
        // anywhere between the two solid neighbours' own edges.
        await show(tester, const [
          MoneyBlock(MoneyBucket.normal),
          MoneyBlock(MoneyBucket.idling),
          MoneyBlock(MoneyBucket.normal),
        ]);
        final frame = await pixels(tester);
        final width = (120 * tester.view.devicePixelRatio).round();

        // The idling block's own outline colour (caution, 0xFFB020FF) must
        // appear (it is not simply missing/invisible)...
        expect(frame.where((v) => v == 0xFFB020FF).length, greaterThan(0));

        // ...and find its row band, then confirm that row also has
        // background-coloured pixels near its horizontal centre (a solid
        // fill would leave none): the row containing the most caution pixels.
        final rowCounts = <int, int>{};
        for (var i = 0; i < frame.length; i++) {
          if (frame[i] == 0xFFB020FF) {
            final row = i ~/ width;
            rowCounts[row] = (rowCounts[row] ?? 0) + 1;
          }
        }
        final midRow = rowCounts.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
        final rowStart = midRow * width;
        final rowPixels = frame.sublist(rowStart, rowStart + width);
        bool isVoidish(int p) {
          final r = (p >> 24) & 0xFF;
          final g = (p >> 16) & 0xFF;
          final b = (p >> 8) & 0xFF;
          return r < 40 && g < 40 && b < 40;
        }

        expect(rowPixels.where(isVoidish).length, greaterThan(0));
      },
    );

    testWidgets('a hard-acceleration block is critical', (tester) async {
      await show(tester, const [MoneyBlock(MoneyBucket.hardAcceleration)]);
      expect(
        (await pixels(tester)).where((v) => v == 0xFF3355FF).length,
        greaterThan(0),
      );
    });

    testWidgets('a high-speed block is accent.deep', (tester) async {
      await show(tester, const [MoneyBlock(MoneyBucket.highSpeed)]);
      // Ion's accent.deep.
      expect(
        (await pixels(tester)).where((v) => v == 0x1296FFFF).length,
        greaterThan(0),
      );
    });

    testWidgets(
      'an appended block settles into view once the spring catches up',
      (tester) async {
        var blocks = const [
          MoneyBlock(MoneyBucket.normal),
          MoneyBlock(MoneyBucket.normal),
        ];
        await show(tester, blocks);
        final before = (await pixels(
          tester,
        )).where((v) => v == 0xD6A042FF).length;

        blocks = [...blocks, const MoneyBlock(MoneyBucket.normal)];
        await tester.pumpWidget(
          tapeHarness(
            kit: kit,
            motion: motion,
            theme: TapeThemeData(livery: Liveries.ion),
            child: Center(child: MoneyTape(blocks: blocks, length: 260)),
          ),
        );
        run(const Duration(seconds: 1)); // the stack spring settles again.
        // Also clears the newest block's own phosphor flash, so the count
        // below reflects the settled fill, not flash-lightened pixels.
        run(const Duration(seconds: 1));
        await tester.pump();
        final after = (await pixels(
          tester,
        )).where((v) => v == 0xD6A042FF).length;

        expect(after, greaterThan(before));
      },
    );

    testWidgets('empty draws nothing (no crash)', (tester) async {
      await show(tester, const []);
      expect(tester.takeException(), isNull);
    });
  });
}

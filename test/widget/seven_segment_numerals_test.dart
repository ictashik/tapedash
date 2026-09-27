// The VFD numerals (DESIGN.md 6.17): segments with ghosts at 7%, each with its own
// phosphor, so a change of digit crossfades segment by segment.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/rolling_numerals.dart';
import 'package:tapedash/ui/design/components/seven_segment_numerals.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/render/seven_segment.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';

import '../design/support/harness.dart';
import '../design/support/numbers.dart';

void main() {
  setUpAll(loadTapeFonts);

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

  final vfd = TapeThemeData(livery: Liveries.vfd);
  const format3 = NumeralFormat(integerDigits: 3);

  Future<void> show(
    WidgetTester tester,
    ManualNumber n, {
    NumeralFormat format = format3,
    TapeThemeData? theme,
    double halo = 0,
    double size = 60,
  }) => tester.pumpWidget(
    tapeHarness(
      kit: kit,
      motion: motion,
      theme: theme ?? vfd,
      child: Align(
        alignment: Alignment.topLeft,
        child: RollingNumerals(
          source: n,
          format: format,
          size: size,
          halo: halo,
        ),
      ),
    ),
  );

  RenderSevenSegmentNumerals render(WidgetTester tester) => tester
      .renderObject<RenderSevenSegmentNumerals>(find.byType(RollingNumerals));

  List<Segment> lit(int mask) => [
    for (final s in Segment.values)
      if (SegmentMask.lit(mask, s)) s,
  ];

  group('the livery', () {
    testWidgets(
      'VFD uses the seven-segment renderer, and the others use Saira',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(87);
        addTearDown(n.dispose);

        await show(tester, n);
        expect(find.byType(SevenSegmentNumerals), findsOneWidget);
        expect(find.byType(SairaNumerals), findsNothing);

        for (final livery in [Liveries.ion, Liveries.ember, Liveries.mono]) {
          await show(tester, n, theme: TapeThemeData(livery: livery));
          expect(
            find.byType(SairaNumerals),
            findsOneWidget,
            reason: livery.name,
          );
          expect(
            find.byType(SevenSegmentNumerals),
            findsNothing,
            reason: livery.name,
          );
        }
      },
    );
  });

  group('the digits', () {
    testWidgets(
      'light the segments of each digit, and a leading zero is dark',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(87);
        addTearDown(n.dispose);
        await show(tester, n);

        final masks = render(tester).masks;

        expect(lit(masks[0]), lit(SegmentMask.digit(7)));
        expect(lit(masks[1]), lit(SegmentMask.digit(8)));
        expect(
          masks[2],
          SegmentMask.blank,
          reason: 'no leading zero: a ghost 8 only',
        );
      },
    );

    testWidgets(
      'a zero is lit when it is not leading, and the ones digit is always lit',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(100);
        addTearDown(n.dispose);
        await show(tester, n);

        expect(render(tester).masks, [
          SegmentMask.digit(0),
          SegmentMask.digit(0),
          SegmentMask.digit(1),
        ]);

        n.value = 0;
        await tester.pump();
        expect(render(tester).masks, [
          SegmentMask.digit(0),
          SegmentMask.blank,
          SegmentMask.blank,
        ]);
      },
    );

    testWidgets(
      'decimals are shown with a point, and the units digit is lit even at 0.5',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(0.5);
        addTearDown(n.dispose);
        await show(
          tester,
          n,
          format: const NumeralFormat(integerDigits: 2, decimals: 1),
        );

        expect(render(tester).masks, [
          SegmentMask.digit(5),
          SegmentMask.digit(0),
          SegmentMask.blank,
        ]);
      },
    );

    testWidgets('a value rounds to its digit: 87.6 shows 88', (tester) async {
      setWindow(tester, const Size(640, 360));
      final n = ManualNumber(87.6);
      addTearDown(n.dispose);
      await show(tester, n);

      expect(render(tester).masks.take(2), [
        SegmentMask.digit(8),
        SegmentMask.digit(8),
      ]);
    });

    testWidgets('a value too big shows nines, and NaN shows nothing wrong', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = ManualNumber(5000);
      addTearDown(n.dispose);
      await show(tester, n);
      expect(render(tester).masks, [
        SegmentMask.digit(9),
        SegmentMask.digit(9),
        SegmentMask.digit(9),
      ]);

      n.value = double.nan;
      await tester.pump();
      expect(render(tester).masks.first, SegmentMask.digit(0));
    });

    testWidgets(
      'a digit stays anchored: the ones digit is at the same place for 7, 77 and 107',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(7);
        addTearDown(n.dispose);
        await show(tester, n);
        final x = render(tester).columnX(0);

        for (final v in [77.0, 107.0, 999.0]) {
          n.value = v;
          await tester.pump();
          expect(render(tester).columnX(0), x, reason: '$v');
        }
      },
    );
  });

  group('phosphor (DESIGN.md 5.5)', () {
    testWidgets(
      'a segment that goes off decays with a time constant of 180 ms',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(8);
        addTearDown(n.dispose);
        await show(tester, n);
        motion.advance(const Duration(seconds: 1));
        expect(render(tester).segmentLevel(0, Segment.e), 1);

        n.value = 9; // 8 lights every segment, 9 not the lower left
        await tester.pump();
        motion.advance(const Duration(milliseconds: 180));

        final level = render(tester).segmentLevel(0, Segment.e);
        expect(level, closeTo(math.exp(-1), math.exp(-1) * 0.06));
        expect(
          render(tester).segmentLevel(0, Segment.a),
          1,
          reason: 'the segments that stay lit do not blink',
        );
      },
    );

    testWidgets('a segment that comes on rises with a time constant of 30 ms', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = ManualNumber(9);
      addTearDown(n.dispose);
      await show(tester, n);
      motion.advance(const Duration(seconds: 1));

      n.value = 8;
      await tester.pump();
      motion.advance(const Duration(milliseconds: 30));

      final level = render(tester).segmentLevel(0, Segment.e);
      expect(level, closeTo(1 - math.exp(-1), 0.06));
    });

    testWidgets(
      'digits crossfade segment by segment: mid-change, the old and new both glow',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(1); // bc
        addTearDown(n.dispose);
        await show(tester, n);
        motion.advance(const Duration(seconds: 1));

        n.value = 2; // abdeg
        await tester.pump();
        motion.advance(const Duration(milliseconds: 40));
        final r = render(tester);

        expect(
          r.segmentLevel(0, Segment.c),
          inExclusiveRange(0.5, 0.95),
          reason: 'the old digit is fading',
        );
        expect(
          r.segmentLevel(0, Segment.a),
          inExclusiveRange(0.5, 0.95),
          reason: 'the new is arriving',
        );
        expect(
          r.segmentLevel(0, Segment.b),
          1,
          reason: 'the shared segment stays',
        );
      },
    );

    testWidgets('it comes to rest, and then asks the clock for nothing', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = ManualNumber(8);
      addTearDown(n.dispose);
      await show(tester, n);
      n.value = 1;
      await tester.pump();
      expect(motion.attachedCount, greaterThan(0));

      motion.advance(const Duration(seconds: 3));

      expect(motion.attachedCount, 0);
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

    testWidgets(
      'lit segments are the accent, and the unlit ones are ghosts at 7%',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(87);
        addTearDown(n.dispose);
        await show(tester, n);
        motion.advance(const Duration(seconds: 1));
        await tester.pump();

        final all = await pixels(tester);
        final accent = all.where((p) => p == 0x6BF7DCFF).length;
        // A ghost is the accent at 7% over the void: dim but not void.
        final ghosts = all.where((p) {
          final r = (p >> 24) & 0xFF;
          final g = (p >> 16) & 0xFF;
          return g > 0x0C && g < 0x40 && r < 0x20 && p != 0x050607FF;
        }).length;

        expect(accent, greaterThan(300), reason: 'the lit digits');
        expect(
          ghosts,
          greaterThan(300),
          reason: 'the ghost 8 of the leading zero, and the dark segments',
        );
      },
    );

    testWidgets('with no value it draws nothing, not even ghosts', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = ManualNumber(87, has: false);
      addTearDown(n.dispose);
      await show(tester, n);

      final all = await pixels(tester);

      expect(all.every((p) => p == 0x050607FF), isTrue);
    });

    testWidgets('a stale value fades to the stale colour', (tester) async {
      setWindow(tester, const Size(640, 360));
      final n = ManualNumber(88);
      addTearDown(n.dispose);
      await show(tester, n);
      motion.advance(const Duration(seconds: 1));
      n.staleness = 1;
      await tester.pump();

      final all = await pixels(tester);

      expect(all.where((p) => p == 0x7A838FFF).length, greaterThan(300));
      expect(all.where((p) => p == 0x6BF7DCFF).length, 0);
    });

    testWidgets(
      'a halo adds light, Daylight removes it, and it is 30% by design',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(88);
        addTearDown(n.dispose);

        Future<int> lit(TapeThemeData theme, double halo) async {
          await show(tester, n, theme: theme, halo: halo);
          motion.advance(const Duration(seconds: 1));
          await tester.pump();
          return (await pixels(tester)).where((p) => p != 0x050607FF).length;
        }

        final plain = await lit(vfd, 0);
        final glowing = await lit(vfd, 1);
        final daylight = await lit(
          TapeThemeData(livery: Liveries.vfd, mode: TapeMode.daylight),
          1,
        );

        expect(glowing, greaterThan(plain * 1.1));
        expect(daylight, lessThan(glowing));
      },
    );
  });

  group('layout', () {
    testWidgets(
      'the box is fixed for its digits and is as tall as the Saira box',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(1);
        addTearDown(n.dispose);
        await show(tester, n);
        final before = tester.getSize(find.byType(RollingNumerals));

        n.value = 888;
        await tester.pump();

        expect(tester.getSize(find.byType(RollingNumerals)), before);
        expect(before.height, closeTo(NumeralMetrics(60).boxHeight, 1e-9));
      },
    );

    testWidgets(
      'digits are one advance apart, from the ones column leftwards',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(1);
        addTearDown(n.dispose);
        await show(tester, n);
        final r = render(tester);

        final step = r.columnX(0) - r.columnX(1);
        expect(r.columnX(1) - r.columnX(2), closeTo(step, 1e-9));
        expect(r.columnX(2), 0);
        expect(step, greaterThan(60 * 0.4));
      },
    );

    testWidgets(
      'the baseline is the same as the Saira readout, so the faces swap in a Row',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(1);
        addTearDown(n.dispose);
        await show(tester, n);

        expect(
          render(
            tester,
          ).computeDistanceToActualBaseline(TextBaseline.alphabetic),
          closeTo(NumeralMetrics(60).baseline, 1e-9),
        );
      },
    );
  });

  group('repainting', () {
    testWidgets('it repaints from its source and lets go of it when removed', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = ManualNumber(1);
      addTearDown(n.dispose);
      await show(tester, n);
      expect(n.isListened, isTrue);
      expect(render(tester).isRepaintBoundary, isTrue);

      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: vfd,
          child: const SizedBox(),
        ),
      );

      expect(n.isListened, isFalse);
      expect(
        motion.attachedCount,
        0,
        reason: 'the phosphor bank let go of the clock',
      );
    });
  });
}

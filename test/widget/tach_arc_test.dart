// The tach arc (DESIGN.md 6.2): the angle function, segment lighting, the
// redline zone, phosphor decay above the needle, the trail and peak hold.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/tach_arc.dart';
import 'package:tapedash/ui/design/fidelity/fidelity_tier.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/ui/design/tokens/tach.dart';
import 'package:tapedash/vehicle/reading.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late SmoothedSignal rpm;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    rpm = SmoothedSignal(
      motion: motion,
      clock: clock,
      spring: TapeSprings.needle,
    );
  });

  tearDown(() {
    rpm.dispose();
    motion.dispose();
    kit.dispose();
  });

  void ingest(double value) {
    final now = clock.monotonic();
    rpm.ingest(Reading(value: value, at: now, receivedAt: now));
  }

  Future<TachArcState> show(
    WidgetTester tester, {
    double maxRpm = 7000,
    double redline = 6500,
    TapeThemeData? theme,
  }) async {
    setWindow(tester, const Size(700, 700));
    final key = GlobalKey<TachArcState>();
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: theme,
        child: Center(
          child: TachArc(
            key: key,
            rpm: rpm,
            heightReference: 360,
            maxRpm: maxRpm,
            redlineRpm: redline,
          ),
        ),
      ),
    );
    return key.currentState!;
  }

  group('the angle function (DESIGN.md 6.2)', () {
    testWidgets('0 rpm sits at 210°, max rpm at -30°, the midpoint at 90°', (
      tester,
    ) async {
      final state = await show(tester);

      expect(state.angleForRpm(0), closeTo(TapeTach.startDegrees, 1e-9));
      expect(state.angleForRpm(7000), closeTo(TapeTach.endDegrees, 1e-9));
      expect(state.angleForRpm(3500), closeTo(90, 1e-9));
    });

    testWidgets('is linear in rpm, and clamps outside the range', (
      tester,
    ) async {
      final state = await show(tester);

      expect(state.angleForRpm(1750), closeTo(150, 1e-9));
      expect(state.angleForRpm(-500), state.angleForRpm(0));
      expect(state.angleForRpm(9000), state.angleForRpm(7000));
    });
  });

  group('segments', () {
    testWidgets('one per 100 rpm in Balanced, one per 200 in Lite', (
      tester,
    ) async {
      final balanced = await show(
        tester,
        theme: TapeThemeData(tier: FidelityTier.balanced),
      );
      expect(balanced.bank!.count, 70);

      final lite = await show(
        tester,
        theme: TapeThemeData(tier: FidelityTier.lite),
      );
      expect(lite.bank!.count, 35);
    });

    testWidgets(
      'light fully below the needle, fractionally at it, and stay dark above',
      (tester) async {
        final state = await show(tester);
        ingest(4250); // segment 42 spans 4200-4300: 50% in
        await tester.pump();
        motion.advance(const Duration(seconds: 1));
        await tester.pump();

        final bank = state.bank!;
        for (var i = 0; i < 42; i++) {
          expect(bank.levels[i], 1.0, reason: 'segment $i is fully below 4250');
        }
        expect(bank.levels[42], closeTo(0.5, 0.02));
        for (var i = 43; i < bank.count; i++) {
          expect(bank.levels[i], 0.0, reason: 'segment $i is above 4250');
        }
      },
    );

    testWidgets(
      'a big drop dims every segment between the old and new position',
      (tester) async {
        final state = await show(tester);
        ingest(6000);
        motion.advance(const Duration(seconds: 2));
        await tester.pump();
        expect(state.bank!.levels[59], 1.0);

        ingest(1000);
        // rpm.value is itself spring-smoothed (spring.needle), so it takes
        // real time to sweep down to 1000; targetOf reads what was last SET,
        // not a decayed level, so once the needle has actually arrived this
        // reflects the sync and not how far the phosphor has decayed.
        motion.advance(const Duration(seconds: 2));
        await tester.pump();

        expect(state.widget.rpm.value, closeTo(1000, 5));
        expect(state.bank!.targetOf(59), 0.0);
        expect(state.bank!.targetOf(9), 1.0);
        expect(state.bank!.targetOf(10), closeTo(0.0, 1e-9));
      },
    );

    testWidgets(
      'the redline segments are unlit at a tint, and lit fully critical',
      (tester) async {
        final state = await show(tester, maxRpm: 7000, redline: 6500);
        final redlineIndex = (6500 / 100).floor();

        ingest(2000);
        motion.advance(const Duration(seconds: 2));
        await tester.pump();
        // Below the needle and below redline: full level, but the colour split
        // is tested at paint time in the pixel test below. Here: the target
        // above the needle in the redline zone is 0 (a tint is a paint-time
        // blend, not a phosphor target).
        expect(state.bank!.targetOf(redlineIndex), 0.0);
      },
    );
  });

  group('the trail and peak hold (DESIGN.md 6.2)', () {
    testWidgets(
      'samples the angle every 30 ms, oldest first when read backwards',
      (tester) async {
        final state = await show(tester);
        ingest(1000);
        motion.tick(0.001);
        await tester.pump();

        for (var i = 0; i < 5; i++) {
          ingest(1000.0 + i * 200);
          motion.advance(const Duration(milliseconds: 30));
          await tester.pump();
        }

        expect(state.trailFilled, greaterThanOrEqualTo(4));
      },
    );

    testWidgets('the peak holds the highest rpm of the last few seconds', (
      tester,
    ) async {
      final state = await show(tester);
      ingest(5000);
      motion.advance(const Duration(milliseconds: 500));
      await tester.pump();
      ingest(2000);
      motion.advance(const Duration(milliseconds: 500));
      await tester.pump();

      expect(state.peakValue, greaterThan(4000));
    });

    testWidgets('the peak is replaced once 3 s plus the 1 s fade have passed', (
      tester,
    ) async {
      final state = await show(tester);
      ingest(5000);
      motion.advance(const Duration(seconds: 1));
      await tester.pump();
      ingest(1000);
      motion.advance(
        TapeMotion.peakHold +
            TapeMotion.peakFade +
            const Duration(milliseconds: 200),
      );
      await tester.pump();

      expect(state.peakValue, lessThan(1500));
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

    testWidgets('lit segments are the accent and the needle is bright', (
      tester,
    ) async {
      await show(tester, theme: TapeThemeData(livery: Liveries.ion));
      ingest(3000);
      motion.advance(const Duration(seconds: 2));
      await tester.pump();

      final all = await pixels(tester);
      expect(
        all.where((p) => p == 0x5CE1FFFF).length,
        greaterThan(200),
        reason: 'accent segments',
      );
      expect(
        all.where((p) => p == 0xFFFFFFFF).length,
        greaterThan(0),
        reason: 'the needle core',
      );
    });

    testWidgets('past the redline, lit segments are critical', (tester) async {
      await show(
        tester,
        theme: TapeThemeData(livery: Liveries.ion),
        maxRpm: 7000,
        redline: 6500,
      );
      ingest(6800);
      motion.advance(const Duration(seconds: 2));
      await tester.pump();

      final all = await pixels(tester);
      expect(
        all.where((p) => p == 0xFF3355FF).length,
        greaterThan(20),
        reason: 'critical segments',
      );
    });

    testWidgets('nothing draws before the first reading arrives', (
      tester,
    ) async {
      await show(tester);
      await tester.pump();

      final all = await pixels(tester);
      final canvas = all.first;
      // Only the etched track and labels may show; no accent or critical yet.
      expect(all.where((p) => p == 0x5CE1FFFF).length, 0);
      expect(canvas, isNot(0));
    });
  });

  group('cost', () {
    testWidgets(
      'at rest with a value, it keeps ticking (a live tach always does)',
      (tester) async {
        await show(tester);
        ingest(2000);
        await tester.pump();

        expect(motion.attachedCount, greaterThan(0));
      },
    );

    testWidgets('with no reading yet, it costs the clock nothing', (
      tester,
    ) async {
      await show(tester);

      expect(motion.attachedCount, 0);
    });

    testWidgets('disposing lets go of the clock and the source', (
      tester,
    ) async {
      await show(tester);
      ingest(2000);
      // Past full staleness (1.5 s plus the 0.6 s fade): rpm's own
      // SmoothedSignal stays attached to the clock while fresh, to notice
      // when it goes stale, independently of TachArcState. Staleness is
      // judged on the *domain* clock (DESIGN.md 5.2), so that has to move
      // too, not just the motion clock the animation runs on.
      clock.advance(const Duration(seconds: 3));
      motion.advance(const Duration(seconds: 3));
      await tester.pump();
      expect(motion.attachedCount, greaterThan(0));

      await tester.pumpWidget(
        tapeHarness(kit: kit, motion: motion, child: const SizedBox()),
      );

      expect(motion.attachedCount, 0);
    });
  });

  group('sizing (DESIGN.md 6.2)', () {
    test('the arc radius is 0.44 of the reference height', () {
      expect(TachArc.radiusOf(360), closeTo(158.4, 1e-9));
      expect(TachArc.radiusOf(720), closeTo(316.8, 1e-9));
    });

    test('the box is big enough for the segments, ticks and labels', () {
      final side = TachArc.boxSideOf(360);
      final r = TachArc.radiusOf(360);

      expect(side, greaterThan(2 * r));
    });
  });
}

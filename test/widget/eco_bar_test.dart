// The eco bar (DESIGN.md 6.7): shareFor's math, the colour ramp at its named
// stops, and that the puck responds to a live value with no rebuild needed.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/eco_bar.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/vehicle/reading.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  group('shareFor (DESIGN.md 6.7)', () {
    // shareFor(value) is pure: it never reads instantValue. A throwaway
    // signal (never ingested into) satisfies the widget's required
    // parameter without standing for anything in these tests.
    late ManualMotionClock motion;
    late FakeClock clock;
    late SmoothedSignal unused;

    setUp(() {
      motion = ManualMotionClock();
      clock = FakeClock();
      unused = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.gauge,
      );
    });

    tearDown(() {
      unused.dispose();
      motion.dispose();
    });

    test('is 0 at the average', () {
      final bar = EcoBar(
        instantValue: unused,
        average: 16,
        width: 640,
        heightReference: 360,
      );
      expect(bar.shareFor(16), 0);
    });

    test('is 1 at the top of the travel band, and clamps beyond it', () {
      final bar = EcoBar(
        instantValue: unused,
        average: 16,
        width: 640,
        heightReference: 360,
      );
      // travel = average * 0.5 = 8, so 24 is the top of the band.
      expect(bar.shareFor(24), 1);
      expect(bar.shareFor(40), 1);
    });

    test('is -1 at the bottom of the travel band, and clamps beyond it', () {
      final bar = EcoBar(
        instantValue: unused,
        average: 16,
        width: 640,
        heightReference: 360,
      );
      expect(bar.shareFor(8), -1);
      expect(bar.shareFor(0), -1);
    });

    test('is proportional in between', () {
      final bar = EcoBar(
        instantValue: unused,
        average: 16,
        width: 640,
        heightReference: 360,
      );
      expect(bar.shareFor(20), closeTo(0.5, 1e-9));
      expect(bar.shareFor(12), closeTo(-0.5, 1e-9));
    });

    test('is 0 with no average yet, rather than guessing one', () {
      final noAverage = EcoBar(
        instantValue: unused,
        average: null,
        width: 640,
        heightReference: 360,
      );
      expect(noAverage.shareFor(22), 0);
      expect(noAverage.shareFor(0), 0);
    });

    test(
      'is 0 with a zero or negative average, rather than dividing by it',
      () {
        final zero = EcoBar(
          instantValue: unused,
          average: 0,
          width: 640,
          heightReference: 360,
        );
        expect(zero.shareFor(5), 0);
      },
    );
  });

  group('EcoBarPainter.colorFor (DESIGN.md 6.7)', () {
    final palette = TapePalette(livery: Liveries.ion);

    test('is ink.bright exactly at the centre', () {
      expect(EcoBarPainter.colorFor(0, palette), palette.inkBright);
    });

    test('is accent.core at and past the accent stop', () {
      expect(EcoBarPainter.colorFor(1, palette), palette.accentCore);
      expect(EcoBarPainter.colorFor(1, palette), palette.accentCore);
    });

    test('is caution exactly at the caution stop', () {
      expect(EcoBarPainter.colorFor(-0.5, palette), palette.caution);
    });

    test('is critical at and past the critical stop', () {
      expect(EcoBarPainter.colorFor(-1, palette), palette.critical);
      expect(EcoBarPainter.colorFor(-1, palette), palette.critical);
    });

    test('ramps monotonically from centre to accent, not just at the ends', () {
      final mid = EcoBarPainter.colorFor(0.5, palette);
      expect(mid, isNot(palette.inkBright));
      expect(mid, isNot(palette.accentCore));
    });

    test(
      'ramps monotonically from caution to critical, not just at the ends',
      () {
        final mid = EcoBarPainter.colorFor(-0.75, palette);
        expect(mid, isNot(palette.caution));
        expect(mid, isNot(palette.critical));
      },
    );
  });

  group('drawing (DESIGN.md 6.7)', () {
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

    Future<void> show(WidgetTester tester, {double average = 16}) async {
      setWindow(tester, const Size(640, 100));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(
            child: EcoBar(
              instantValue: value,
              average: average,
              width: 640,
              heightReference: 360,
            ),
          ),
        ),
      );
    }

    // The same two literals bar_gauge_test.dart uses for the Ion livery's
    // accent.core and critical, each a solid fill used nowhere else in the
    // component (the halo is always accent.glow-tinted, never these), so
    // their presence or absence is a clean fingerprint for the puck itself
    // without having to predict its exact screen column: the bar is only
    // 0.36 of the 640-wide harness, centred, which is easy to get wrong by
    // hand (an earlier draft of this test did).
    const accentCoreArgb = 0x5CE1FFFF;
    const criticalArgb = 0xFF3355FF;

    Future<Uint32List> pixels(WidgetTester tester) async {
      final image = await renderImage(tester);
      // toByteData() resolves through a platform-channel callback, which
      // flutter_test's fake-async zone only pumps inside runAsync (the same
      // rule toImage() itself follows) — outside it this hangs until the
      // framework's 10-minute timeout instead of failing fast.
      late ByteData data;
      await tester.runAsync(() async => data = (await image.toByteData())!);
      return Uint32List.fromList([
        for (var i = 0; i < image.width * image.height; i++)
          data.getUint32(i * 4),
      ]);
    }

    testWidgets('draws nothing for the puck before a reading arrives', (
      tester,
    ) async {
      await show(tester);
      await tester.pump();
      // No crash, and no accent/critical colour anywhere: only the track and
      // the centre notch, both neutral.
      final p = await pixels(tester);
      expect(p.where((v) => v == accentCoreArgb).length, 0);
      expect(p.where((v) => v == criticalArgb).length, 0);
    });

    testWidgets('responds to the value live: a rebuild is not required', (
      tester,
    ) async {
      // The same shape of regression as the telemetry tile's brackets: the
      // painter must read instantValue.value fresh in paint(), not cache a
      // share or colour computed at build time (DESIGN.md 9.3). If it were
      // cached, ingesting a second value into the same signal object would
      // move neither fingerprint colour below.
      await show(tester);
      ingest(0); // at or below the bottom of the travel band: critical.
      run(const Duration(seconds: 2));
      await tester.pump();
      final atBottom = await pixels(tester);
      expect(atBottom.where((v) => v == criticalArgb).length, greaterThan(5));
      expect(atBottom.where((v) => v == accentCoreArgb).length, 0);

      ingest(24); // at or above the top of the band: accent.core.
      run(const Duration(seconds: 2)); // let spring.gauge settle.
      await tester.pump();
      final atTop = await pixels(tester);
      expect(atTop.where((v) => v == accentCoreArgb).length, greaterThan(5));
      expect(atTop.where((v) => v == criticalArgb).length, 0);
    });

    testWidgets('a swapped SmoothedSignal repaints, not just a new value', (
      tester,
    ) async {
      // The shouldRepaint-identity regression already hit in the tach arc,
      // the shift horizon and the bar gauge: didUpdateWidget reuses the
      // render object, so a swapped live-data object must be compared by
      // identity, not assumed equal because its *current* value has not
      // changed yet.
      await show(tester, average: 16);
      ingest(0); // critical.
      run(const Duration(seconds: 2));
      await tester.pump();

      final other = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.gauge,
      );
      addTearDown(other.dispose);
      other.ingest(
        Reading(
          value: 24,
          at: clock.monotonic(),
          receivedAt: clock.monotonic(),
        ),
      ); // accent.core.

      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(
            child: EcoBar(
              instantValue: other,
              average: 16,
              width: 640,
              heightReference: 360,
            ),
          ),
        ),
      );
      run(const Duration(seconds: 2));
      await tester.pump();

      final p = await pixels(tester);
      expect(p.where((v) => v == accentCoreArgb).length, greaterThan(5));
      expect(p.where((v) => v == criticalArgb).length, 0);
    });
  });
}

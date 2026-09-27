// Alerts (DESIGN.md 6.10): AlertHysteresis's debouncing, the slot glyph's
// sizing by level, the critical bracket's pulse and cost, and the caution
// horizon line.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/alerts.dart';
import 'package:tapedash/ui/design/components/bar_gauge.dart';
import 'package:tapedash/ui/design/icons/icons.dart';
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

  group('AlertHysteresis (DESIGN.md 6.10)', () {
    test('stays none until a raw caution reading has held for raiseAfter', () {
      final h = AlertHysteresis(
        raiseAfter: const Duration(seconds: 2),
        fallAfter: const Duration(seconds: 5),
      );
      expect(
        h.update(AlertLevel.caution, const Duration(seconds: 0)),
        AlertLevel.none,
      );
      expect(
        h.update(AlertLevel.caution, const Duration(seconds: 1)),
        AlertLevel.none,
      );
      expect(
        h.update(AlertLevel.caution, const Duration(seconds: 2)),
        AlertLevel.caution,
      );
    });

    test(
      'a blip that reverts before raiseAfter never raises the stable level',
      () {
        final h = AlertHysteresis(
          raiseAfter: const Duration(seconds: 2),
          fallAfter: const Duration(seconds: 5),
        );
        h.update(AlertLevel.caution, const Duration(seconds: 0));
        h.update(AlertLevel.caution, const Duration(milliseconds: 1500));
        // Reverts to none before the 2 s raise threshold.
        expect(
          h.update(AlertLevel.none, const Duration(seconds: 1600)),
          AlertLevel.none,
        );
        // ...and even once 2 s have passed since the original blip, none is
        // still the raw reading, so it never raises.
        expect(
          h.update(AlertLevel.none, const Duration(seconds: 3)),
          AlertLevel.none,
        );
      },
    );

    test(
      'falling is slower than rising: critical holds through a dip to caution',
      () {
        final h = AlertHysteresis(
          raiseAfter: const Duration(seconds: 2),
          fallAfter: const Duration(seconds: 5),
        );
        h.update(AlertLevel.critical, const Duration(seconds: 0));
        expect(
          h.update(AlertLevel.critical, const Duration(seconds: 2)),
          AlertLevel.critical,
        );

        // Dips to caution; critical must hold until fallAfter (5 s), not
        // raiseAfter (2 s).
        expect(
          h.update(AlertLevel.caution, const Duration(seconds: 3)),
          AlertLevel.critical,
        );
        expect(
          h.update(AlertLevel.caution, const Duration(seconds: 7)),
          AlertLevel.critical,
        );
        expect(
          h.update(AlertLevel.caution, const Duration(seconds: 8)),
          AlertLevel.caution,
        );
      },
    );

    test('a raw value switching target mid-debounce restarts the timer', () {
      final h = AlertHysteresis(
        raiseAfter: const Duration(seconds: 2),
        fallAfter: const Duration(seconds: 5),
      );
      h.update(AlertLevel.caution, const Duration(seconds: 0));
      // Before caution commits, the reading jumps straight to critical.
      h.update(AlertLevel.critical, const Duration(seconds: 1));
      // 2 s after the ORIGINAL caution reading, but only 1 s after the
      // switch to critical: critical must not have committed yet.
      expect(
        h.update(AlertLevel.critical, const Duration(seconds: 2)),
        AlertLevel.none,
      );
      expect(
        h.update(AlertLevel.critical, const Duration(seconds: 3)),
        AlertLevel.critical,
      );
    });

    test('a direct none-to-critical jump uses raiseAfter, not fallAfter', () {
      final h = AlertHysteresis(
        raiseAfter: const Duration(seconds: 2),
        fallAfter: const Duration(seconds: 5),
      );
      h.update(AlertLevel.critical, const Duration(seconds: 0));
      expect(
        h.update(AlertLevel.critical, const Duration(seconds: 1)),
        AlertLevel.none,
      );
      expect(
        h.update(AlertLevel.critical, const Duration(seconds: 2)),
        AlertLevel.critical,
      );
    });

    test('level defaults to none, and matches the last update', () {
      final h = AlertHysteresis();
      expect(h.level, AlertLevel.none);
    });
  });

  group('drawing', () {
    late TapeRenderKit kit;
    late ManualMotionClock motion;
    late FakeClock clock;

    setUp(() {
      kit = TapeRenderKit();
      motion = ManualMotionClock();
      clock = FakeClock()..advance(const Duration(seconds: 100));
    });

    SmoothedSignal fixedSignal(double value) {
      final s = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.needle,
      );
      s.ingest(
        Reading(
          value: value,
          at: clock.monotonic(),
          receivedAt: clock.monotonic(),
        ),
      );
      addTearDown(s.dispose);
      return s;
    }

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

    Future<void> show(WidgetTester tester, Widget child, {Size? window}) async {
      setWindow(tester, window ?? const Size(200, 200));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(child: child),
        ),
      );
    }

    group('AlertSlot', () {
      testWidgets('none draws nothing: zero size', (tester) async {
        await show(
          tester,
          const AlertSlot(level: AlertLevel.none, icon: TapeIcon.coolant),
        );
        await tester.pump();
        expect(tester.getSize(find.byType(AlertSlot)), Size.zero);
      });

      testWidgets('critical is larger than caution', (tester) async {
        await show(
          tester,
          const AlertSlot(level: AlertLevel.caution, icon: TapeIcon.coolant),
        );
        await tester.pump();
        final cautionSize = tester.getSize(find.byType(AlertSlot));

        await show(
          tester,
          const AlertSlot(level: AlertLevel.critical, icon: TapeIcon.coolant),
        );
        await tester.pump();
        final criticalSize = tester.getSize(find.byType(AlertSlot));

        expect(criticalSize.width, greaterThan(cautionSize.width));
      });
    });

    group('CriticalAlertFrame', () {
      const criticalArgb = 0xFF3355FF;

      Widget gauge() => BarGauge(
        value: fixedSignal(50),
        min: 0,
        max: 100,
        length: 100,
        label: 'X',
      );

      testWidgets('draws no bracket at all when inactive', (tester) async {
        await show(tester, CriticalAlertFrame(active: false, child: gauge()));
        await tester.pump();
        expect(
          (await pixels(tester)).where((v) => v == criticalArgb).length,
          0,
        );
      });

      testWidgets('draws a critical bracket when active', (tester) async {
        await show(tester, CriticalAlertFrame(active: true, child: gauge()));
        motion.advance(const Duration(milliseconds: 250)); // near peak alpha.
        await tester.pump();
        expect(
          (await pixels(tester)).where((v) => v == criticalArgb).length,
          greaterThan(0),
        );
      });

      testWidgets('costs the motion clock nothing while inactive', (
        tester,
      ) async {
        // A plain, non-live child, not gauge(): motion.attachedCount is a
        // shared counter, and a BarGauge's own SmoothedSignal legitimately
        // attaches regardless of the alert frame wrapping it, which would
        // otherwise be counted as if it were the frame's own attachment.
        await show(
          tester,
          const CriticalAlertFrame(
            active: false,
            child: SizedBox.square(dimension: 40),
          ),
        );
        await tester.pump();
        expect(motion.attachedCount, 0);
      });

      testWidgets('attaches while active, and detaches once it is not', (
        tester,
      ) async {
        final key = GlobalKey();
        const child = SizedBox.square(dimension: 40);
        await show(
          tester,
          CriticalAlertFrame(key: key, active: true, child: child),
        );
        await tester.pump();
        expect(motion.attachedCount, greaterThan(0));

        await show(
          tester,
          CriticalAlertFrame(key: key, active: false, child: child),
        );
        await tester.pump();
        expect(motion.attachedCount, 0);
      });
    });

    group('CriticalAlertFrameState.pulseAlphaAt (DESIGN.md 6.10)', () {
      // Exposed as a public static on the State (the same reasoning as the
      // status strip's own pulseAlphaAt): a direct test of the waveform,
      // rather than sampling anti-aliased stroke alpha back out of pixels.
      test('is 1 Hz: one full cycle every 1 s', () {
        final a = CriticalAlertFrameState.pulseAlphaAt(0);
        final b = CriticalAlertFrameState.pulseAlphaAt(1);
        expect(a, closeTo(b, 1e-9));
      });

      test(
        'reaches its max a quarter cycle in, and its min three quarters in',
        () {
          expect(
            CriticalAlertFrameState.pulseAlphaAt(0.25),
            closeTo(1.0, 1e-9),
          );
          expect(
            CriticalAlertFrameState.pulseAlphaAt(0.75),
            closeTo(0.5, 1e-9),
          );
        },
      );

      test('never leaves its 0.5-1.0 band', () {
        for (var t = 0.0; t < 2; t += 0.05) {
          final a = CriticalAlertFrameState.pulseAlphaAt(t);
          expect(a, greaterThanOrEqualTo(0.5 - 1e-9));
          expect(a, lessThanOrEqualTo(1.0 + 1e-9));
        }
      });

      test('stays well under the 3 Hz flash ceiling (DESIGN.md 11)', () {
        expect(TapeMotion.maxFlashHz, greaterThan(1));
      });
    });

    group('CautionHorizonLine', () {
      testWidgets('inactive draws no caution pixels', (tester) async {
        await show(
          tester,
          const CautionHorizonLine(active: false, width: 160),
          window: const Size(200, 20),
        );
        await tester.pump();
        expect((await pixels(tester)).where((v) => v == 0xFFB020FF).length, 0);
      });

      testWidgets('active draws a caution line the given width', (
        tester,
      ) async {
        await show(
          tester,
          const CautionHorizonLine(active: true, width: 160),
          window: const Size(200, 20),
        );
        await tester.pump();
        expect(
          (await pixels(tester)).where((v) => v == 0xFFB020FF).length,
          greaterThan(50),
        );
      });
    });
  });
}

// The shift horizon (DESIGN.md 6.4): the fill window, the colour steps, the
// flash at the shift point, and the CVT breathing mode.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/shift_horizon.dart';
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

  /// Advances both clocks together, so a signal that should go stale does.
  void settle([Duration duration = const Duration(seconds: 2)]) {
    clock.advance(duration);
    motion.advance(duration);
  }

  Future<ShiftHorizonState> show(
    WidgetTester tester, {
    double shiftRpm = 6500,
    double maxRpm = 7000,
    bool shiftLightEnabled = true,
    TapeThemeData? theme,
  }) async {
    setWindow(tester, const Size(640, 100));
    final key = GlobalKey<ShiftHorizonState>();
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: theme,
        // Align, not a bare child: a tight-constraint parent would stretch the
        // SizedBox to fill it, which no real caller does (DESIGN.md 4.7's
        // Horizon zone gives it just its own thin strip).
        child: Align(
          alignment: Alignment.topCenter,
          child: ShiftHorizon(
            key: key,
            rpm: rpm,
            width: 640,
            heightReference: 360,
            shiftRpm: shiftRpm,
            maxRpm: maxRpm,
            shiftLightEnabled: shiftLightEnabled,
          ),
        ),
      ),
    );
    return key.currentState!;
  }

  group('the fill window (DESIGN.md 6.4)', () {
    testWidgets('starts filling 1,500 rpm below the shift point', (
      tester,
    ) async {
      final state = await show(tester);
      ingest(4999); // shift 6500 - 1500 = 5000: just below the start
      settle();
      await tester.pump();

      expect(state.fillProgress(), 0);
    });

    testWidgets('is fully lit at the shift point', (tester) async {
      final state = await show(tester);
      ingest(6500);
      settle();
      await tester.pump();

      expect(state.fillProgress(), 1);
      expect(state.bank!.targetOf(0), 1.0);
      expect(state.bank!.targetOf(47), 1.0);
    });

    testWidgets('fills from the outer edges inward, converging at the centre', (
      tester,
    ) async {
      final state = await show(tester);
      ingest(
        5750,
      ); // half way through the 1500 rpm window: 12 of 24 lit per side
      settle();
      await tester.pump();

      final bank = state.bank!;
      // The painter maps bank index i to the position perSide-1-i on the left
      // (and perSide+i on the right), so the two ends of the array sit at the
      // centre and the two middle indices are the outer edges.
      expect(bank.levels[23], 1.0, reason: 'outermost, left');
      expect(bank.levels[24], 1.0, reason: 'outermost, right');
      expect(bank.levels[0], 0.0, reason: 'innermost, left');
      expect(bank.levels[47], 0.0, reason: 'innermost, right');
    });

    testWidgets('never lights below where the window starts', (tester) async {
      final state = await show(tester);
      ingest(1000);
      settle();
      await tester.pump();

      for (final level in state.bank!.levels) {
        expect(level, 0);
      }
    });
  });

  group('colour by position (DESIGN.md 6.4)', () {
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
      'the outer 60% is accent, the next 25% caution, the last 15% critical',
      (tester) async {
        await show(tester, theme: TapeThemeData(livery: Liveries.ion));
        ingest(6500); // fully lit: every segment shows its position colour
        settle();
        await tester.pump();

        final all = await pixels(tester);
        expect(
          all.where((p) => p == 0x5CE1FFFF).length,
          greaterThan(20),
          reason: 'accent',
        );
        expect(
          all.where((p) => p == 0xFFB020FF).length,
          greaterThan(5),
          reason: 'caution',
        );
        expect(
          all.where((p) => p == 0xFF3355FF).length,
          greaterThan(5),
          reason: 'critical',
        );
      },
    );
  });

  group('the flash at the shift point (DESIGN.md 6.4, 11)', () {
    testWidgets('flashes at exactly 3 Hz: on and off within one cycle', (
      tester,
    ) async {
      final state = await show(tester);
      ingest(6600); // at or above the shift point
      settle();
      await tester.pump();
      expect(state.atOrAboveShift, isTrue);

      final onFrames = <bool>[];
      // A 3 Hz square wave has a period of 1/3 s; sample across two periods.
      for (var i = 0; i < 40; i++) {
        motion.tick(1 / 120);
        onFrames.add(
          (motion.now.inMicroseconds / 1e6 * TapeShiftHorizon.flashHz * 2)
              .floor()
              .isEven,
        );
      }

      expect(onFrames, contains(true));
      expect(onFrames, contains(false));
    });

    test(
      'the flash rate is exactly the cap DESIGN.md 11 allows, never faster',
      () {
        expect(TapeShiftHorizon.flashHz, TapeMotion.maxFlashHz);
      },
    );

    testWidgets(
      'below the shift point there is no flash: level is level, not on/off',
      (tester) async {
        final state = await show(tester);
        ingest(5750);
        settle();
        await tester.pump();

        expect(state.atOrAboveShift, isFalse);
      },
    );
  });

  group(
    'a CVT or automatic profile: breathing, not a shift light (DESIGN.md 6.4)',
    () {
      testWidgets('never lights a segment', (tester) async {
        final state = await show(tester, shiftLightEnabled: false);
        ingest(6600);
        settle();
        await tester.pump();

        expect(state.bank, isNull);
      });

      testWidgets('costs the clock nothing: it repaints from rpm alone', (
        tester,
      ) async {
        // Before any reading: nothing has a reason to be on the clock yet.
        await show(tester, shiftLightEnabled: false);

        expect(motion.attachedCount, 0);
      });

      testWidgets('never attaches itself, even once rpm has a value', (
        tester,
      ) async {
        await show(tester, shiftLightEnabled: false);
        ingest(4000);
        await tester.pump();

        // rpm's own SmoothedSignal stays on the clock while fresh regardless
        // (to notice staleness), which alone accounts for exactly one: if the
        // horizon added its own attachment too, this would be 2.
        expect(motion.attachedCount, 1);
      });

      testWidgets('at idle, a point 150 lp from centre is still background', (
        tester,
      ) async {
        final v = await _breathingBrightnessAt(
          tester,
          kit: kit,
          motion: motion,
          clock: clock,
          rpmValue: 800,
          dxFromCentre: 150,
        );

        expect(v, 18, reason: 'the void token, R+G+B = 5+6+7');
      });

      test('the reach grows monotonically from idle to redline', () {
        // The mapping itself (DESIGN.md 6.4: "width follows rpm"), checked
        // directly rather than by sampling it back out of rendered pixels,
        // which this component's test found is the fragile way to check it.
        expect(
          ShiftHorizonPainter.widthShareFor(0, 7000),
          TapeShiftHorizon.breathingMinShare,
        );
        expect(
          ShiftHorizonPainter.widthShareFor(7000, 7000),
          TapeShiftHorizon.breathingMaxShare,
        );
        expect(
          ShiftHorizonPainter.widthShareFor(3500, 7000),
          closeTo(
            (TapeShiftHorizon.breathingMinShare +
                    TapeShiftHorizon.breathingMaxShare) /
                2,
            1e-9,
          ),
        );

        var last = -1.0;
        for (var rpm = 0.0; rpm <= 7000; rpm += 350) {
          final share = ShiftHorizonPainter.widthShareFor(rpm, 7000);
          expect(share, greaterThan(last));
          last = share;
        }
      });

      test(
        'clamps outside the range, and a zero max rpm is never a divide by zero',
        () {
          expect(
            ShiftHorizonPainter.widthShareFor(-500, 7000),
            ShiftHorizonPainter.widthShareFor(0, 7000),
          );
          expect(
            ShiftHorizonPainter.widthShareFor(9000, 7000),
            ShiftHorizonPainter.widthShareFor(7000, 7000),
          );
          expect(
            ShiftHorizonPainter.widthShareFor(1000, 0),
            TapeShiftHorizon.breathingMinShare,
          );
        },
      );
    },
  );

  group('cost, on a manual profile', () {
    testWidgets('keeps ticking while it has a value', (tester) async {
      await show(tester);
      ingest(5500);
      await tester.pump();

      expect(motion.attachedCount, greaterThan(0));
    });

    testWidgets('with no reading yet, costs the clock nothing', (tester) async {
      await show(tester);

      expect(motion.attachedCount, 0);
    });

    testWidgets('disposing lets go of the clock', (tester) async {
      await show(tester);
      ingest(5500);
      settle(const Duration(seconds: 3));
      await tester.pump();
      expect(motion.attachedCount, greaterThan(0));

      await tester.pumpWidget(
        tapeHarness(kit: kit, motion: motion, child: const SizedBox()),
      );

      expect(motion.attachedCount, 0);
    });
  });
}

/// The brightness (R+G+B, since the flattened canvas is opaque and the glow
/// shows as added colour, not alpha) at [dxFromCentre] logical pixels from the
/// horizon's centre, for a single rpm value shown in a fresh widget tree of
/// its own (not two `pumpWidget` calls sharing one `testWidgets`, which this
/// component's test found does not reliably re-capture between calls).
Future<int> _breathingBrightnessAt(
  WidgetTester tester, {
  required TapeRenderKit kit,
  required ManualMotionClock motion,
  required FakeClock clock,
  required double rpmValue,
  required int dxFromCentre,
}) async {
  final rpm = SmoothedSignal(
    motion: motion,
    clock: clock,
    spring: TapeSprings.needle,
  );
  addTearDown(rpm.dispose);
  rpm.ingest(
    Reading(
      value: rpmValue,
      at: clock.monotonic(),
      receivedAt: clock.monotonic(),
    ),
  );
  setWindow(tester, const Size(640, 100));
  await tester.pumpWidget(
    tapeHarness(
      kit: kit,
      motion: motion,
      child: Align(
        alignment: Alignment.topCenter,
        child: ShiftHorizon(
          rpm: rpm,
          width: 640,
          heightReference: 360,
          shiftLightEnabled: false,
        ),
      ),
    ),
  );
  await tester.pump();
  final image = await renderImage(tester);
  late ByteData data;
  await tester.runAsync(() async => data = (await image.toByteData())!);
  final dpr = tester.view.devicePixelRatio;
  final x = (image.width / 2 + dxFromCentre * dpr).round().clamp(
    0,
    image.width - 1,
  );
  // Sampled inside the band's own small height (DESIGN.md 6.4: 0.018H), not
  // the whole captured window it sits at the top of.
  const heightReference = 360.0;
  final bandHeight = 0.018 * heightReference;
  final y = (bandHeight / 2 * dpr).round().clamp(0, image.height - 1);
  final offset = (y * image.width + x) * 4;
  return data.getUint8(offset) +
      data.getUint8(offset + 1) +
      data.getUint8(offset + 2);
}

// Specimen captures: numerals in every livery and mode, and a strip through a
// roll. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/rolling_numerals.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/vehicle/reading.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;

  setUpAll(loadTapeFonts);

  for (final livery in Liveries.all) {
    testWidgets('specimen ${livery.name}', (tester) async {
      setWindow(tester, const Size(640, 360));
      final kit = TapeRenderKit();
      addTearDown(kit.dispose);
      final motion = ManualMotionClock();
      addTearDown(motion.dispose);
      final clock = FakeClock()..advance(const Duration(seconds: 100));

      SmoothedSignal signal(double v) {
        final s = SmoothedSignal(
          motion: motion,
          clock: clock,
          spring: TapeSprings.gauge,
        );
        s.ingest(
          Reading(
            value: v,
            at: clock.monotonic(),
            receivedAt: clock.monotonic(),
          ),
        );
        addTearDown(s.dispose);
        return s;
      }

      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: livery),
          child: TapeBackdrop(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  RollingNumerals(
                    source: signal(87),
                    format: const NumeralFormat(integerDigits: 3),
                    size: 100,
                    halo: 0.3,
                  ),
                  const SizedBox(width: 20),
                  RollingNumerals(
                    source: signal(14.6),
                    format: const NumeralFormat(integerDigits: 2, decimals: 1),
                    size: 50,
                    role: NumeralRole.money,
                    halo: 0.3,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      motion.advance(const Duration(milliseconds: 600));
      await tester.pump();
      await capturePng(tester, 'specimen-${livery.name.toLowerCase()}');
    }, skip: !enabled);
  }

  testWidgets('a roll', (tester) async {
    setWindow(tester, const Size(640, 360));
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    final motion = ManualMotionClock();
    addTearDown(motion.dispose);
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    SmoothedSignal signal(double v) {
      final s = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.gauge,
      );
      s.ingest(
        Reading(value: v, at: clock.monotonic(), receivedAt: clock.monotonic()),
      );
      addTearDown(s.dispose);
      return s;
    }

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                for (final v in [3.0, 3.35, 3.5, 3.65, 4.0, 9.5, 19.5])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: RollingNumerals(
                      source: signal(v),
                      format: const NumeralFormat(integerDigits: 2),
                      size: 46,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await capturePng(tester, 'roll-strip');
  }, skip: !enabled);

  testWidgets('modes', (tester) async {
    setWindow(tester, const Size(640, 360));
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    final motion = ManualMotionClock();
    addTearDown(motion.dispose);
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    SmoothedSignal signal(double v) {
      final s = SmoothedSignal(
        motion: motion,
        clock: clock,
        spring: TapeSprings.gauge,
      );
      s.ingest(
        Reading(value: v, at: clock.monotonic(), receivedAt: clock.monotonic()),
      );
      addTearDown(s.dispose);
      return s;
    }

    for (final mode in TapeMode.values) {
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ember, mode: mode),
          child: TapeBackdrop(
            child: Center(
              child: RollingNumerals(
                source: signal(87),
                format: const NumeralFormat(integerDigits: 3),
                size: 120,
                halo: 0.3,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await capturePng(tester, 'ember-${mode.name}');
    }
  }, skip: !enabled);
}

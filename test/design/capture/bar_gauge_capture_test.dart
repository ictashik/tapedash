// A first look at the bar gauge. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/bar_gauge.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/vehicle/reading.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('coolant at a few temperatures', (tester) async {
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
        spring: TapeSprings.needle,
      );
      s.ingest(
        Reading(value: v, at: clock.monotonic(), receivedAt: clock.monotonic()),
      );
      addTearDown(s.dispose);
      return s;
    }

    Future<void> shot(String name, double celsius) async {
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: TapeBackdrop(
            child: Center(
              child: BarGauge(
                value: signal(celsius),
                min: 0,
                max: 120,
                length: 300,
                vertical: true,
                normalBandMin: 80,
                normalBandMax: 100,
                label: 'COOLANT °C',
              ),
            ),
          ),
        ),
      );
      motion.advance(const Duration(seconds: 1));
      await tester.pump();
      await capturePng(tester, name);
    }

    await shot('bar-cold', 40);
    await shot('bar-normal', 90);
    await shot('bar-hot', 118);
  }, skip: !enabled);
}

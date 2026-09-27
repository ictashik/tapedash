// A first look at the telemetry tile. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/numeral_format.dart';
import 'package:tapedash/ui/design/components/telemetry_tile.dart';
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

  testWidgets('a sweep of samples', (tester) async {
    setWindow(tester, const Size(640, 360));
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    final motion = ManualMotionClock();
    addTearDown(motion.dispose);
    final clock = FakeClock()..advance(const Duration(seconds: 100));

    final rpm = SmoothedSignal(
      motion: motion,
      clock: clock,
      spring: TapeSprings.gauge,
    );
    addTearDown(rpm.dispose);

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: Center(
            child: TelemetryTile(
              label: 'RPM',
              value: rpm,
              format: const NumeralFormat(integerDigits: 4),
              cautionAbove: 5500,
              criticalAbove: 6500,
              width: 220,
              height: 140,
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 40; i++) {
      final v = 1500 + 2500 * (1 - (i - 20).abs() / 20);
      rpm.ingest(
        Reading(value: v, at: clock.monotonic(), receivedAt: clock.monotonic()),
      );
      motion.advance(const Duration(milliseconds: 500));
      clock.advance(const Duration(milliseconds: 500));
      await tester.pump();
    }
    await capturePng(tester, 'tile-sweep');

    // Push it into caution.
    for (var i = 0; i < 5; i++) {
      rpm.ingest(
        Reading(
          value: 5800,
          at: clock.monotonic(),
          receivedAt: clock.monotonic(),
        ),
      );
      motion.advance(const Duration(milliseconds: 500));
      clock.advance(const Duration(milliseconds: 500));
      await tester.pump();
    }
    await capturePng(tester, 'tile-caution');
  }, skip: !enabled);
}

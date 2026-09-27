// A first look at the tach arc. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/rolling_numerals.dart';
import 'package:tapedash/ui/design/components/tach_arc.dart';
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

  testWidgets('tach at a few revs', (tester) async {
    setWindow(tester, const Size(640, 500));
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

    final rpm = signal(0);
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                TachArc(rpm: rpm, heightReference: 360),
                RollingNumerals(
                  source: signal(0),
                  format: const NumeralFormat(integerDigits: 3),
                  size: 100,
                  halo: 0.3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    rpm.ingest(
      Reading(
        value: 4200,
        at: clock.monotonic(),
        receivedAt: clock.monotonic(),
      ),
    );
    motion.advance(const Duration(milliseconds: 500));
    await tester.pump();
    await capturePng(tester, 'tach-4200');

    rpm.ingest(
      Reading(
        value: 6800,
        at: clock.monotonic(),
        receivedAt: clock.monotonic(),
      ),
    );
    motion.advance(const Duration(milliseconds: 120));
    await tester.pump();
    await capturePng(tester, 'tach-redline-inflight');

    motion.advance(const Duration(seconds: 2));
    await tester.pump();
    await capturePng(tester, 'tach-redline-settled');
  }, skip: !enabled);
}

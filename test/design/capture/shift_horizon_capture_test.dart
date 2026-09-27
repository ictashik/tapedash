// A first look at the shift horizon. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/shift_horizon.dart';
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

  testWidgets('shift horizon at a few revs', (tester) async {
    setWindow(tester, const Size(640, 100));
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    final motion = ManualMotionClock();
    addTearDown(motion.dispose);
    final clock = FakeClock()..advance(const Duration(seconds: 100));

    final rpm = SmoothedSignal(
      motion: motion,
      clock: clock,
      spring: TapeSprings.needle,
    );
    addTearDown(rpm.dispose);
    void ingest(double v) => rpm.ingest(
      Reading(value: v, at: clock.monotonic(), receivedAt: clock.monotonic()),
    );

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: Align(
            alignment: Alignment.topCenter,
            child: ShiftHorizon(rpm: rpm, width: 640, heightReference: 360),
          ),
        ),
      ),
    );
    ingest(5000);
    motion.advance(const Duration(seconds: 1));
    await tester.pump();
    await capturePng(tester, 'shift-5000');

    ingest(6200);
    motion.advance(const Duration(seconds: 1));
    await tester.pump();
    await capturePng(tester, 'shift-6200');

    ingest(6600);
    motion.advance(const Duration(milliseconds: 200));
    await tester.pump();
    await capturePng(tester, 'shift-flash');
  }, skip: !enabled);

  testWidgets('breathing (CVT)', (tester) async {
    setWindow(tester, const Size(640, 100));
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    final motion = ManualMotionClock();
    addTearDown(motion.dispose);
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    final rpm = SmoothedSignal(
      motion: motion,
      clock: clock,
      spring: TapeSprings.needle,
    );
    addTearDown(rpm.dispose);
    rpm.ingest(
      Reading(
        value: 4000,
        at: clock.monotonic(),
        receivedAt: clock.monotonic(),
      ),
    );

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
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
      ),
    );
    motion.advance(const Duration(seconds: 1));
    await tester.pump();
    await capturePng(tester, 'shift-breathing');
  }, skip: !enabled);
}

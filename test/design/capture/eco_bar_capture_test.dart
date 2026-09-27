// A first look at the eco bar. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/eco_bar.dart';
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

  Future<void> shot(WidgetTester tester, String name, double value) async {
    setWindow(tester, const Size(640, 100));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    final signal = SmoothedSignal(
      motion: motion,
      clock: clock,
      spring: TapeSprings.gauge,
    );
    signal.ingest(
      Reading(
        value: value,
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
          child: Center(
            child: EcoBar(
              key: ValueKey(name),
              instantValue: signal,
              average: 16,
              width: 640,
              heightReference: 360,
            ),
          ),
        ),
      ),
    );
    motion.advance(const Duration(seconds: 1));
    await tester.pump();
    await capturePng(tester, name);
    signal.dispose();
    motion.dispose();
    kit.dispose();
  }

  testWidgets('efficient, average, thirsty', (tester) async {
    await shot(tester, 'eco-efficient', 22);
    await shot(tester, 'eco-average', 16);
    await shot(tester, 'eco-thirsty', 9);
  }, skip: !enabled);
}

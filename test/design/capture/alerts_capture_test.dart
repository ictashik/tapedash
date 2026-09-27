// A first look at alerts. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/alerts.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/bar_gauge.dart';
import 'package:tapedash/ui/design/icons/icons.dart';
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

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget Function() build, {
    Size window = const Size(300, 200),
  }) async {
    setWindow(tester, window);
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(child: Center(child: build())),
      ),
    );
    await tester.pump();
    await capturePng(tester, name);
    motion.dispose();
    kit.dispose();
  }

  testWidgets('alert slot: caution and critical', (tester) async {
    await shot(
      tester,
      'alert-slot-caution',
      () => const AlertSlot(level: AlertLevel.caution, icon: TapeIcon.coolant),
    );
    await shot(
      tester,
      'alert-slot-critical',
      () => const AlertSlot(level: AlertLevel.critical, icon: TapeIcon.coolant),
    );
  }, skip: !enabled);

  testWidgets('critical bracket around a bar gauge', (tester) async {
    setWindow(tester, const Size(300, 200));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    final signal = SmoothedSignal(
      motion: motion,
      clock: clock,
      spring: TapeSprings.needle,
    );
    signal.ingest(
      Reading(value: 118, at: clock.monotonic(), receivedAt: clock.monotonic()),
    );

    Widget gauge() => BarGauge(
      value: signal,
      min: 40,
      max: 130,
      length: 160,
      label: 'COOLANT',
      normalBandMin: 80,
      normalBandMax: 100,
    );

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: Center(
            child: CriticalAlertFrame(active: true, child: gauge()),
          ),
        ),
      ),
    );
    motion.advance(const Duration(seconds: 1));
    // Land near the pulse's peak (a quarter cycle in, DESIGN.md 6.10's 1 Hz).
    motion.advance(const Duration(milliseconds: 250));
    await tester.pump();
    await capturePng(tester, 'alert-frame-active');

    signal.dispose();
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);

  testWidgets('caution horizon line', (tester) async {
    await shot(
      tester,
      'alert-horizon-line',
      () => const CautionHorizonLine(active: true, width: 260),
      window: const Size(300, 40),
    );
  }, skip: !enabled);
}
